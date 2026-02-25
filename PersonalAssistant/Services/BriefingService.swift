import Foundation

@Observable
@MainActor
final class BriefingService {
    private let asana = AsanaAPIClient.shared
    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let claude = ClaudeAPIClient.shared
    private let tokenManager = TokenManager.shared
    private let calendarService = CalendarService.shared
    private let noteMatching = NoteMatchingService.shared

    func generateBriefing(type: Briefing.BriefingType) async throws -> Briefing {
        var briefing = Briefing(type: type)

        // Fetch data in parallel
        let data = try await fetchBriefingData(type: type)

        let hasClaude = (try? tokenManager.getClaudeAPIKey()) != nil

        // Run emoji assignment and AI summary in parallel (both only need raw data)
        async let emojiResult: [String: String] = hasClaude ? assignEmojis(from: data) : [:]
        async let summaryResult: String? = hasClaude ? (try? generateAISummary(data: data, type: type)) : nil

        let emojiMap = await emojiResult
        briefing.sections = buildSections(from: data, type: type, emojiMap: emojiMap, taskAccountMap: data.taskAccountMap)
        briefing.isLoading = false

        if let summary = await summaryResult {
            briefing.aiSummary = summary
            briefing.aiSummaryCards = BriefingSummaryCard.parse(from: summary)
        }

        return briefing
    }

    // MARK: - Data Fetching

    private func fetchBriefingData(type: Briefing.BriefingType) async throws -> BriefingData {
        var allTasksDueToday: [AsanaTask] = []
        var allOverdueTasks: [AsanaTask] = []
        var allUpcomingTasks: [AsanaTask] = []
        var allCompletedToday: [AsanaTask] = []
        var workspaces: [AsanaWorkspace] = []
        var accountMap: [String: String] = [:]

        // Fetch Asana data across all accounts
        for account in tokenManager.asanaAccounts {
            let accountID = account.userGID
            let accountWorkspaces = (try? await asana.getWorkspaces(accountID: accountID)) ?? []
            workspaces.append(contentsOf: accountWorkspaces)

            for workspace in accountWorkspaces {
                async let overdue = asana.getOverdueTasks(workspaceID: workspace.gid, accountID: accountID)
                async let completed = asana.getTasksCompletedToday(workspaceID: workspace.gid, accountID: accountID)
                async let myTasks = asana.getMyTasks(workspaceID: workspace.gid, completedSince: Date(), accountID: accountID)

                let overdueResult = (try? await overdue) ?? []
                let completedResult = (try? await completed) ?? []
                let tasksResult = (try? await myTasks) ?? []

                for task in overdueResult + completedResult + tasksResult {
                    accountMap[task.gid] = accountID
                }

                allOverdueTasks.append(contentsOf: overdueResult)
                allCompletedToday.append(contentsOf: completedResult)

                let dueToday = tasksResult.filter { $0.isDueToday }
                allTasksDueToday.append(contentsOf: dueToday)

                let upcoming = tasksResult.filter { task in
                    guard let dueDate = task.dueDate, task.completed != true else { return false }
                    let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                    return dueDate > Date() && dueDate <= nextWeek && !task.isDueToday
                }
                allUpcomingTasks.append(contentsOf: upcoming)
            }
        }

        // Fetch calendar events for today
        var calendarEvents: [CalendarMeetingItem] = []
        var meetingDetails: [GranolaNoteDetail] = []

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

        if calendarService.permissionStatus == .authorized {
            calendarEvents = calendarService.fetchEvents(from: todayStart, to: todayEnd)
            calendarEvents = await noteMatching.matchNotes(to: calendarEvents)

            // Fetch Granola details for matched events (for AI context)
            for event in calendarEvents where event.hasGranolaNote {
                if let noteID = event.granolaNoteID,
                   let detail = try? await granola.getNote(id: noteID) {
                    meetingDetails.append(detail)
                }
            }
        }

        return BriefingData(
            tasksDueToday: allTasksDueToday,
            overdueTasks: allOverdueTasks,
            upcomingTasks: allUpcomingTasks,
            completedToday: allCompletedToday,
            calendarEvents: calendarEvents,
            meetingDetails: meetingDetails,
            workspaces: workspaces,
            taskAccountMap: accountMap
        )
    }

    // MARK: - Emoji Assignment (Claude-powered)

    private func assignEmojis(from data: BriefingData) async -> [String: String] {
        let allTasks: [(gid: String, name: String, project: String?, section: String)] =
            data.overdueTasks.map { ($0.gid, $0.name, $0.projects?.first?.name, "overdue") } +
            data.tasksDueToday.map { ($0.gid, $0.name, $0.projects?.first?.name, "due today") } +
            data.upcomingTasks.map { ($0.gid, $0.name, $0.projects?.first?.name, "upcoming") } +
            data.completedToday.map { ($0.gid, $0.name, $0.projects?.first?.name, "completed") }

        guard !allTasks.isEmpty else { return [:] }

        var taskList = ""
        for task in allTasks {
            let project = task.project ?? "No project"
            taskList += "- \(task.gid): \"\(task.name)\" [\(project)] (\(task.section))\n"
        }

        let prompt = """
        Assign exactly one emoji to each task. Think about what the task is actually about — the subject matter, not just keywords.

        Context clues:
        - "Henry" is a labrador retriever dog — use dog-related emojis
        - For completed tasks, use a celebratory or achievement emoji that still relates to the task content
        - Be literal and specific: toilets → 🚽, groceries → 🛒, cooking → 🍳, etc.
        - Use the project name as context for ambiguous task names

        Tasks:
        \(taskList)
        Return ONLY a JSON object mapping task ID to emoji, nothing else. Example: {"123": "🐕", "456": "🚽"}
        """

        do {
            let messages = [ClaudeMessage(role: "user", content: .text(prompt))]
            let response = try await claude.sendMessage(
                messages: messages,
                systemPrompt: "You assign emojis to tasks. Return only valid JSON. No markdown, no explanation."
            )

            // Parse JSON response — strip markdown fences if present
            var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonString.hasPrefix("```") {
                jsonString = jsonString
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let jsonData = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                return dict
            }
        } catch {
            // Fall through to empty map — buildSections uses fallback
        }

        return [:]
    }

    private static let fallbackEmojis = ["📋", "📌", "💡", "🎯", "⚡", "🔧", "📦", "✨"]

    private func fallbackEmoji(for taskGID: String) -> String {
        let index = abs(taskGID.hashValue) % Self.fallbackEmojis.count
        return Self.fallbackEmojis[index]
    }

    // MARK: - Section Building

    private func buildSections(from data: BriefingData, type: Briefing.BriefingType, emojiMap: [String: String] = [:], taskAccountMap: [String: String] = [:]) -> [BriefingSection] {
        var sections: [BriefingSection] = []

        switch type {
        case .morning:
            // Overdue tasks
            if !data.overdueTasks.isEmpty {
                sections.append(BriefingSection(
                    title: "Overdue",
                    icon: "exclamationmark.triangle.fill",
                    items: data.overdueTasks.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: "Due: \(task.dueOn ?? "unknown")",
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .red)
                            },
                            urgency: .critical,
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

            // Due today
            if !data.tasksDueToday.isEmpty {
                sections.append(BriefingSection(
                    title: "Due Today",
                    icon: "calendar.badge.exclamationmark",
                    items: data.tasksDueToday.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: task.projects?.first?.name,
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .blue)
                            },
                            urgency: .warning,
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

            // Today's meetings (from calendar)
            if !data.calendarEvents.isEmpty {
                sections.append(BriefingSection(
                    title: "Today's Meetings",
                    icon: "calendar",
                    items: data.calendarEvents.prefix(5).map { event in
                        let timeText = event.isAllDay ? "All Day" : DateFormatting.time(event.startDate)
                        return BriefingItem(
                            title: event.title,
                            subtitle: timeText,
                            badge: BriefingItem.BadgeInfo(text: "Calendar", color: .blue)
                        )
                    }
                ))
            }

            // Upcoming this week
            if !data.upcomingTasks.isEmpty {
                sections.append(BriefingSection(
                    title: "Coming This Week",
                    icon: "calendar",
                    items: data.upcomingTasks.prefix(5).map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: task.dueDate.map { DateFormatting.shortDate($0) },
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

        case .evening:
            // Overdue tasks (also relevant in evening)
            if !data.overdueTasks.isEmpty {
                sections.append(BriefingSection(
                    title: "Overdue",
                    icon: "exclamationmark.triangle.fill",
                    items: data.overdueTasks.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: "Due: \(task.dueOn ?? "unknown")",
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .red)
                            },
                            urgency: .critical,
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

            // Completed today
            if !data.completedToday.isEmpty {
                sections.append(BriefingSection(
                    title: "Completed Today",
                    icon: "checkmark.circle.fill",
                    items: data.completedToday.map { task in
                        BriefingItem(
                            title: task.name,
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .green)
                            },
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

            // Still open from today
            let stillOpen = data.tasksDueToday.filter { $0.completed != true }
            if !stillOpen.isEmpty {
                sections.append(BriefingSection(
                    title: "Still Open",
                    icon: "circle",
                    items: stillOpen.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: "Was due today",
                            urgency: .warning,
                            taskGID: task.gid,
                            accountID: taskAccountMap[task.gid],
                            emoji: emojiMap[task.gid] ?? fallbackEmoji(for: task.gid)
                        )
                    }
                ))
            }

            // Meetings attended (from calendar)
            if !data.calendarEvents.isEmpty {
                sections.append(BriefingSection(
                    title: "Today's Meetings",
                    icon: "calendar",
                    items: data.calendarEvents.map { event in
                        let timeText = event.isAllDay ? "All Day" : DateFormatting.time(event.startDate)
                        let noteSuffix = event.hasGranolaNote ? " (has notes)" : ""
                        return BriefingItem(
                            title: event.title,
                            subtitle: timeText + noteSuffix
                        )
                    }
                ))
            }
        }

        return sections
    }

    // MARK: - AI Summary

    private func generateAISummary(data: BriefingData, type: Briefing.BriefingType) async throws -> String {
        let prompt: String
        switch type {
        case .morning:
            prompt = """
            Generate a morning briefing organized into categories. Use EXACTLY these markdown headings (include only categories that have relevant content):

            ### Priorities
            1-2 sentences on what to focus on today and why. Do NOT list individual task names — those are shown separately as tappable cards.

            ### Overdue Alert
            Only if there are overdue tasks. A brief sentence on the urgency or impact. Do NOT list individual task names.

            ### Meeting Insights
            Only if there are meetings today. Key prep notes or what to expect. Do NOT list individual meeting names.

            ### Action Items
            A brief sentence about suggested next steps or approach. Do NOT list individual task names — the app already shows them as interactive cards.

            IMPORTANT: Never list or repeat individual task or meeting names. The app displays those as tappable cards below your text. Your job is to add insight, context, and prioritization guidance — not to enumerate items.

            Keep each section to 1-2 sentences. Be concise and actionable.
            """
        case .evening:
            prompt = """
            Generate an evening recap organized into categories. Use EXACTLY these markdown headings (include only categories that have relevant content):

            ### Progress
            1-2 sentences celebrating what was accomplished today. Do NOT list individual task names — those are shown separately as tappable cards.

            ### Overdue Alert
            Only if tasks were due today but not completed. A brief constructive sentence about the impact. Do NOT list individual task names.

            ### Meeting Insights
            Only if there were meetings. Key outcomes or decisions in 1-2 sentences. Do NOT list individual meeting names.

            ### Action Items
            A brief sentence about suggested follow-ups or approach for tomorrow. Do NOT list individual task names.

            ### Looking Ahead
            Brief note on what's coming tomorrow/this week.

            IMPORTANT: Never list or repeat individual task or meeting names. The app displays those as tappable cards below your text. Your job is to add insight, encouragement, and context — not to enumerate items.

            Keep each section to 1-2 sentences. Be encouraging and constructive.
            """
        }

        let messages = [ClaudeMessage(role: "user", content: .text(prompt))]
        let systemPrompt = "You are a personal assistant generating a \(type == .morning ? "morning" : "evening") briefing. Be concise, helpful, and actionable.\n\nDATA:\n\(data.contextForClaude)"

        return try await claude.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt
        )
    }
}
