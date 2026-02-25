import Foundation

@Observable
@MainActor
final class ChatService {
    private let claude = ClaudeAPIClient.shared
    private let asana = AsanaAPIClient.shared
    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let tokenManager = TokenManager.shared

    private(set) var isProcessing = false

    // Cached context
    private var cachedTasks: [AsanaTask] = []
    private var cachedMeetings: [GranolaNoteListItem] = []
    private var cachedWorkspaces: [AsanaWorkspace] = []
    private var lastContextRefresh: Date?
    private let contextRefreshInterval: TimeInterval = 300 // 5 minutes

    // Account mapping for multi-account support
    private var taskAccountMap: [String: String] = [:]      // taskGID → accountID
    private var workspaceAccountMap: [String: String] = [:]  // workspaceGID → accountID

    // MARK: - System Prompt

    private var systemPrompt: String {
        """
        You are a personal assistant helping manage tasks and meetings. You have access to the user's Asana tasks and Granola meeting notes.

        Current date and time: \(DateFormatting.fullDate(Date())) \(DateFormatting.time(Date()))

        Be concise, actionable, and helpful. When referring to tasks or meetings, be specific about names and dates.

        When the user asks to create a task, use the create_asana_task tool. If there are multiple workspaces, ask the user which workspace to use before calling the tool, and pass the workspace_id.
        When the user says they've completed a task, use the complete_asana_task tool.
        When asked about upcoming or overdue tasks, use the get_tasks_due tool.
        When asked about meetings or discussions, ALWAYS use the search_meeting_notes tool. The meeting titles listed in CONTEXT below are only titles — you do NOT have access to the content of any meeting unless you call the tool.
        When asked to change a due date, rename, or update task notes, use the update_asana_task tool.
        When asked about comments on a task, use the get_task_comments tool.
        When asked to add a comment to a task, use the add_task_comment tool.

        CONTEXT:
        \(contextSummary)
        """
    }

    private var contextSummary: String {
        var summary = ""

        if !cachedWorkspaces.isEmpty {
            summary += "Connected Asana workspaces:\n"
            for ws in cachedWorkspaces {
                let accountName = tokenManager.asanaAccounts.first(where: { $0.userGID == workspaceAccountMap[ws.gid] })?.userName ?? "Unknown"
                summary += "- [\(ws.gid)] \(ws.displayName) (account: \(accountName))\n"
            }
            summary += "\n"
        }

        let overdue = cachedTasks.filter { $0.isOverdue }
        let dueToday = cachedTasks.filter { $0.isDueToday }
        let incomplete = cachedTasks.filter { $0.completed != true }

        if !overdue.isEmpty {
            summary += "OVERDUE TASKS:\n"
            for task in overdue {
                summary += "- [\(task.gid)] \(task.name) (due: \(task.dueOn ?? "?"))\n"
            }
            summary += "\n"
        }

        if !dueToday.isEmpty {
            summary += "DUE TODAY:\n"
            for task in dueToday {
                summary += "- [\(task.gid)] \(task.name)\n"
            }
            summary += "\n"
        }

        if !incomplete.isEmpty {
            let upcoming = incomplete.filter { !$0.isOverdue && !$0.isDueToday }.prefix(10)
            if !upcoming.isEmpty {
                summary += "UPCOMING TASKS:\n"
                for task in upcoming {
                    summary += "- [\(task.gid)] \(task.name) (due: \(task.dueOn ?? "no date"))\n"
                }
                summary += "\n"
            }
        }

        if !cachedMeetings.isEmpty {
            summary += "RECENT MEETINGS (titles only — use search_meeting_notes tool to read content):\n"
            for meeting in cachedMeetings.prefix(5) {
                summary += "- \(meeting.displayTitle) (\(meeting.createdAt))\n"
            }
        }

        if summary.isEmpty {
            summary = "No task or meeting data available. The user may need to connect their accounts in Settings."
        }

        return summary
    }

    // MARK: - Refresh Context

    func refreshContext() async {
        guard shouldRefreshContext else { return }

        // Fetch tasks and meetings in parallel
        async let tasksResult = fetchAllTasks()
        async let meetingsResult = fetchMeetings()
        async let workspacesResult = fetchWorkspaces()

        cachedTasks = (try? await tasksResult) ?? cachedTasks
        cachedMeetings = (try? await meetingsResult) ?? cachedMeetings
        cachedWorkspaces = (try? await workspacesResult) ?? cachedWorkspaces
        lastContextRefresh = Date()
    }

    private var shouldRefreshContext: Bool {
        guard let last = lastContextRefresh else { return true }
        return Date().timeIntervalSince(last) > contextRefreshInterval
    }

    private func fetchAllTasks() async throws -> [AsanaTask] {
        guard tokenManager.isAsanaAuthenticated else { return [] }
        var allTasks: [AsanaTask] = []
        var newTaskMap: [String: String] = [:]

        for account in tokenManager.asanaAccounts {
            let workspaces = try await asana.getWorkspaces(accountID: account.userGID)
            for workspace in workspaces {
                let tasks = try await asana.getMyTasks(workspaceID: workspace.gid, completedSince: Date(), accountID: account.userGID)
                for task in tasks {
                    newTaskMap[task.gid] = account.userGID
                }
                allTasks.append(contentsOf: tasks)
            }
        }

        taskAccountMap = newTaskMap
        return allTasks
    }

    private func fetchMeetings() async throws -> [GranolaNoteListItem] {
        if meetingNotes.isConfigured {
            return try await meetingNotes.getRecentNotes(days: 7)
        }
        return try await granola.getRecentNotes(days: 7)
    }

    private func fetchWorkspaces() async throws -> [AsanaWorkspace] {
        guard tokenManager.isAsanaAuthenticated else { return [] }
        var allWorkspaces: [AsanaWorkspace] = []
        var newMap: [String: String] = [:]

        for account in tokenManager.asanaAccounts {
            let workspaces = try await asana.getWorkspaces(accountID: account.userGID)
            for ws in workspaces {
                newMap[ws.gid] = account.userGID
            }
            allWorkspaces.append(contentsOf: workspaces)
        }

        workspaceAccountMap = newMap
        return allWorkspaces
    }

    // MARK: - Send Message

    func sendMessage(
        _ userMessage: String,
        conversationHistory: [ChatMessage],
        onTextDelta: @escaping (String) -> Void,
        onToolCall: @escaping (String, String, [String: Any]) -> Void
    ) async throws -> ClaudeAPIClient.StopReason {
        isProcessing = true
        defer { isProcessing = false }

        await refreshContext()

        // Build Claude messages from conversation history
        var claudeMessages: [ClaudeMessage] = []

        for msg in conversationHistory.suffix(20) {
            switch msg.role {
            case .user:
                claudeMessages.append(ClaudeMessage(role: "user", content: .text(msg.content)))
            case .assistant:
                claudeMessages.append(ClaudeMessage(role: "assistant", content: .text(msg.content)))
            case .system:
                break
            }
        }

        // Add current user message
        claudeMessages.append(ClaudeMessage(role: "user", content: .text(userMessage)))

        let stopReasonBox = StopReasonBox()

        try await claude.streamMessage(
            messages: claudeMessages,
            systemPrompt: systemPrompt,
            tools: ClaudeAPIClient.tools,
            onText: { text in
                Task { @MainActor in
                    onTextDelta(text)
                }
            },
            onToolUse: { id, name, input in
                Task { @MainActor in
                    onToolCall(id, name, input)
                }
            },
            onComplete: { reason in
                stopReasonBox.reason = reason
            }
        )

        return stopReasonBox.reason
    }

    // MARK: - Execute Tool

    func executeTool(name: String, input: [String: Any]) async throws -> String {
        switch name {
        case "create_asana_task":
            return try await executeCreateTask(input)
        case "complete_asana_task":
            return try await executeCompleteTask(input)
        case "get_tasks_due":
            return try await executeGetTasksDue(input)
        case "search_meeting_notes":
            return try await executeSearchMeetings(input)
        case "update_asana_task":
            return try await executeUpdateTask(input)
        case "get_task_comments":
            return try await executeGetTaskComments(input)
        case "add_task_comment":
            return try await executeAddTaskComment(input)
        default:
            return "Unknown tool: \(name)"
        }
    }

    private func executeCreateTask(_ input: [String: Any]) async throws -> String {
        guard let name = input["name"] as? String else {
            return "Error: Task name is required."
        }

        let workspace: AsanaWorkspace
        let accountID: String

        if let wsID = input["workspace_id"] as? String {
            // Explicit workspace specified
            guard let acctID = workspaceAccountMap[wsID],
                  let ws = cachedWorkspaces.first(where: { $0.gid == wsID }) else {
                return "Error: Workspace ID '\(wsID)' not found. Available workspaces: \(cachedWorkspaces.map { "[\($0.gid)] \($0.displayName)" }.joined(separator: ", "))"
            }
            workspace = ws
            accountID = acctID
        } else if cachedWorkspaces.count > 1 {
            // Multiple workspaces — ask the user to pick
            let listing = cachedWorkspaces.map { ws in
                let acctName = tokenManager.asanaAccounts.first(where: { $0.userGID == workspaceAccountMap[ws.gid] })?.userName ?? "Unknown"
                return "- [\(ws.gid)] \(ws.displayName) (account: \(acctName))"
            }.joined(separator: "\n")
            return "Multiple workspaces available. Please ask the user which workspace to create the task in:\n\(listing)"
        } else {
            // Single workspace — use it
            guard let (ws, acctID) = firstWorkspaceAndAccount() else {
                return "Error: No Asana workspace available."
            }
            workspace = ws
            accountID = acctID
        }

        let task = AsanaTaskCreate(
            name: name,
            notes: input["notes"] as? String,
            dueOn: input["due_on"] as? String,
            projects: nil,
            workspace: workspace.gid,
            assignee: "me"
        )

        let created = try await asana.createTask(task, accountID: accountID)
        // Add to cached tasks and map
        cachedTasks.append(created)
        taskAccountMap[created.gid] = accountID

        return "Task created: \"\(created.name)\" in \(workspace.displayName) (ID: \(created.gid))\(created.dueOn.map { ", due: \($0)" } ?? "")"
    }

    private func executeCompleteTask(_ input: [String: Any]) async throws -> String {
        guard let taskID = input["task_id"] as? String else {
            return "Error: Task ID is required."
        }

        guard let accountID = taskAccountMap[taskID] ?? tokenManager.asanaAccounts.first?.userGID else {
            return "Error: Could not determine which account owns this task."
        }

        let completed = try await asana.completeTask(id: taskID, accountID: accountID)
        // Update cached task in-place
        if let idx = cachedTasks.firstIndex(where: { $0.gid == taskID }) {
            cachedTasks[idx] = completed
        }

        return "Task completed: \"\(completed.name)\""
    }

    private func executeGetTasksDue(_ input: [String: Any]) async throws -> String {
        let range = input["date_range"] as? String ?? "today"

        let tasks: [AsanaTask]
        switch range {
        case "today":
            tasks = cachedTasks.filter { $0.isDueToday }
        case "overdue":
            tasks = cachedTasks.filter { $0.isOverdue }
        case "this_week":
            let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
            tasks = cachedTasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate <= endOfWeek && task.completed != true
            }
        default:
            tasks = cachedTasks.filter { $0.completed != true }
        }

        if tasks.isEmpty {
            return "No tasks found for range: \(range)"
        }

        var result = "Tasks (\(range)):\n"
        for task in tasks {
            let project = task.projects?.first?.name ?? "No project"
            result += "- [\(task.gid)] \(task.name) (due: \(task.dueOn ?? "no date")) [\(project)]\n"
        }
        return result
    }

    private func executeUpdateTask(_ input: [String: Any]) async throws -> String {
        guard let taskID = input["task_id"] as? String else {
            return "Error: Task ID is required."
        }

        guard let accountID = taskAccountMap[taskID] ?? tokenManager.asanaAccounts.first?.userGID else {
            return "Error: Could not determine which account owns this task."
        }

        var fields: [String: Any] = [:]
        if let dueOn = input["due_on"] as? String {
            fields["due_on"] = dueOn
        }
        if let name = input["name"] as? String {
            fields["name"] = name
        }
        if let notes = input["notes"] as? String {
            fields["notes"] = notes
        }

        guard !fields.isEmpty else {
            return "Error: At least one field (due_on, name, or notes) must be provided."
        }

        let updated = try await asana.updateTask(id: taskID, fields: fields, accountID: accountID)
        // Update cached task in-place
        if let idx = cachedTasks.firstIndex(where: { $0.gid == taskID }) {
            cachedTasks[idx] = updated
        }

        var changes: [String] = []
        if let dueOn = fields["due_on"] as? String { changes.append("due date → \(dueOn)") }
        if let name = fields["name"] as? String { changes.append("name → \"\(name)\"") }
        if fields["notes"] != nil { changes.append("notes updated") }

        return "Task updated: \"\(updated.name)\" (\(changes.joined(separator: ", ")))"
    }

    private func executeGetTaskComments(_ input: [String: Any]) async throws -> String {
        guard let taskID = input["task_id"] as? String else {
            return "Error: Task ID is required."
        }

        guard let accountID = taskAccountMap[taskID] ?? tokenManager.asanaAccounts.first?.userGID else {
            return "Error: Could not determine which account owns this task."
        }

        let comments = try await asana.getTaskComments(taskID: taskID, accountID: accountID)

        if comments.isEmpty {
            return "No comments on this task."
        }

        var result = "Comments (\(comments.count)):\n"
        for comment in comments {
            let author = comment.createdBy?.name ?? "Unknown"
            let date = comment.createdDate.map { DateFormatting.shortDate($0) } ?? ""
            let text = comment.text ?? ""
            result += "\n[\(author) — \(date)]\n\(text)\n"
        }
        return result
    }

    private func executeAddTaskComment(_ input: [String: Any]) async throws -> String {
        guard let taskID = input["task_id"] as? String else {
            return "Error: Task ID is required."
        }
        guard let text = input["text"] as? String else {
            return "Error: Comment text is required."
        }

        guard let accountID = taskAccountMap[taskID] ?? tokenManager.asanaAccounts.first?.userGID else {
            return "Error: Could not determine which account owns this task."
        }

        let story = try await asana.addTaskComment(taskID: taskID, text: text, accountID: accountID)
        return "Comment posted on task (ID: \(story.gid)): \"\(text.prefix(100))\""
    }

    // MARK: - Helpers

    private func firstWorkspaceAndAccount() -> (AsanaWorkspace, String)? {
        for (wsGID, accountID) in workspaceAccountMap {
            if let ws = cachedWorkspaces.first(where: { $0.gid == wsGID }) {
                return (ws, accountID)
            }
        }
        return nil
    }

    // Thread-safe box for capturing stop reason from @Sendable closure
    private final class StopReasonBox: @unchecked Sendable {
        var reason: ClaudeAPIClient.StopReason = .endTurn
    }

    private func executeSearchMeetings(_ input: [String: Any]) async throws -> String {
        let query = input["query"] as? String ?? ""
        print("executeSearchMeetings: query='\(query)'")

        let notes: [GranolaNoteListItem]
        if query.isEmpty {
            notes = cachedMeetings
        } else if meetingNotes.isConfigured {
            notes = try await meetingNotes.searchNotes(query: query)
        } else {
            notes = try await granola.searchNotes(query: query)
        }

        if notes.isEmpty {
            return "No meeting notes found matching: \(query)"
        }

        var result = "Meeting notes:\n"
        for note in notes.prefix(5) {
            result += "\n## \(note.displayTitle) (\(note.createdAt))\n"

            do {
                let detail: GranolaNoteDetail
                if meetingNotes.isConfigured {
                    detail = try await meetingNotes.getNote(id: note.id)
                } else {
                    detail = try await granola.getNoteWithTranscript(id: note.id)
                }

                if let attendees = detail.attendees, !attendees.isEmpty {
                    result += "Attendees: \(attendees.map(\.displayName).joined(separator: ", "))\n"
                }
                if let summary = detail.summaryMarkdown ?? detail.summaryText, !summary.isEmpty {
                    result += "\(String(summary.prefix(2000)))\n"
                } else if let transcript = detail.transcript, !transcript.isEmpty {
                    let text = transcript.map(\.text).joined(separator: " ")
                    result += "\(String(text.prefix(2000)))\n"
                } else {
                    result += "(No content found for this meeting)\n"
                }
            } catch {
                print("Failed to fetch detail for note \(note.id): \(error)")
                result += "(Error reading note: \(error.localizedDescription))\n"
            }
        }
        return result
    }
}
