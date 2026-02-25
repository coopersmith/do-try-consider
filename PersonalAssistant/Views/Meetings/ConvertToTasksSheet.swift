import SwiftUI

struct ConvertToTasksSheet: View {
    let meetingTitle: String
    let noteContent: String

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .extracting
    @State private var actionItems: [ActionItem] = []
    @State private var extractionError: String?
    @State private var createdCount = 0
    @State private var isCreating = false
    @State private var availableWorkspaces: [WorkspaceChoice] = []
    @State private var selectedWorkspaceIndex: Int = 0

    private let claude = ClaudeAPIClient.shared
    private let asana = AsanaAPIClient.shared
    private let tokenManager = TokenManager.shared

    enum Phase {
        case extracting
        case reviewing
        case complete
    }

    struct WorkspaceChoice: Identifiable {
        let id: String  // workspace GID
        let workspace: AsanaWorkspace
        let accountID: String
        let accountName: String

        var displayName: String {
            "\(workspace.displayName) (\(accountName))"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .extracting:
                    extractingView
                case .reviewing:
                    reviewingView
                case .complete:
                    completeView
                }
            }
            .background(AppTheme.adaptiveBackground)
            .navigationTitle("Convert to Tasks")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            await extractActionItems()
            await loadWorkspaces()
        }
    }

    // MARK: - Extracting

    private var extractingView: some View {
        VStack(spacing: 16) {
            if let extractionError {
                ErrorStateView(extractionError) {
                    Task { await extractActionItems() }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Extracting action items...")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Using Claude to analyze your meeting notes")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reviewing

    private var reviewingView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach($actionItems) { $item in
                        ActionItemRow(item: $item)
                    }
                } header: {
                    Text("Action items from \"\(meetingTitle)\"")
                        .font(AppTheme.captionFont)
                }

                // Workspace picker (only when multiple available)
                if availableWorkspaces.count > 1 {
                    Section {
                        Picker("Create in", selection: $selectedWorkspaceIndex) {
                            ForEach(Array(availableWorkspaces.enumerated()), id: \.offset) { index, choice in
                                Text(choice.displayName).tag(index)
                            }
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    } header: {
                        Text("Workspace")
                            .font(AppTheme.captionFont)
                    }
                }
            }
            .insetGroupedListStyle()
            .warmListBackground()

            // Bottom bar
            VStack(spacing: 12) {
                Divider()
                HStack {
                    Text("\(selectedCount) of \(actionItems.count) selected")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Button {
                        Task { await createTasks() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20, height: 20)
                        } else {
                            Text("Create Tasks")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(selectedCount == 0 || isCreating || availableWorkspaces.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(AppTheme.adaptiveCard)
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.urgencyGreen)

            Text("Tasks Created")
                .font(AppTheme.titleFont)

            Text("Created \(createdCount) task\(createdCount == 1 ? "" : "s") in Asana.")
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(AppTheme.textSecondary)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var selectedCount: Int {
        actionItems.filter(\.isSelected).count
    }

    // MARK: - Load Workspaces

    private func loadWorkspaces() async {
        var choices: [WorkspaceChoice] = []
        for account in tokenManager.asanaAccounts {
            let workspaces = (try? await asana.getWorkspaces(accountID: account.userGID)) ?? []
            for ws in workspaces {
                choices.append(WorkspaceChoice(
                    id: ws.gid,
                    workspace: ws,
                    accountID: account.userGID,
                    accountName: account.userName
                ))
            }
        }
        availableWorkspaces = choices
    }

    // MARK: - Extraction

    private func extractActionItems() async {
        extractionError = nil
        phase = .extracting

        let truncated = String(noteContent.prefix(10000))

        let systemPrompt = """
        Extract action items from the following meeting notes. \
        Return ONLY a JSON array of objects with these fields: \
        "name" (string, the task title), \
        "notes" (string or null, brief context), \
        "due_date" (string in YYYY-MM-DD format or null). \
        Do not include any other text, markdown fences, or explanation. \
        Return an empty array [] if no action items are found.
        """

        let userMessage = "Meeting: \"\(meetingTitle)\"\n\nNotes:\n\(truncated)"

        do {
            let messages = [ClaudeMessage(role: "user", content: .text(userMessage))]
            let response = try await claude.sendMessage(
                messages: messages,
                systemPrompt: systemPrompt,
                model: .haiku
            )

            let cleaned = stripMarkdownFences(response)

            guard let data = cleaned.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                extractionError = "Could not parse action items from Claude's response."
                return
            }

            if parsed.isEmpty {
                extractionError = "No action items found in the meeting notes."
                return
            }

            actionItems = parsed.map { dict in
                ActionItem(
                    name: dict["name"] as? String ?? "Untitled",
                    notes: dict["notes"] as? String,
                    dueDate: dict["due_date"] as? String
                )
            }

            phase = .reviewing
        } catch {
            extractionError = error.localizedDescription
        }
    }

    private func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove ```json ... ``` or ``` ... ```
        if result.hasPrefix("```") {
            // Drop first line
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Task Creation

    private func createTasks() async {
        guard selectedWorkspaceIndex < availableWorkspaces.count else {
            extractionError = "No workspace selected."
            return
        }

        isCreating = true
        let selectedItems = actionItems.filter(\.isSelected)
        let choice = availableWorkspaces[selectedWorkspaceIndex]

        do {
            var created = 0
            for item in selectedItems {
                let provenance = "Source: \(meetingTitle) meeting notes"
                let taskNotes: String
                if let notes = item.notes, !notes.isEmpty {
                    taskNotes = "\(notes)\n\n\(provenance)"
                } else {
                    taskNotes = provenance
                }

                let task = AsanaTaskCreate(
                    name: item.name,
                    notes: taskNotes,
                    dueOn: item.dueDate,
                    projects: nil,
                    workspace: choice.workspace.gid,
                    assignee: "me"
                )

                _ = try await asana.createTask(task, accountID: choice.accountID)
                created += 1
            }

            createdCount = created
            phase = .complete
        } catch {
            extractionError = error.localizedDescription
            phase = .reviewing
        }

        isCreating = false
    }
}

// MARK: - Action Item Model

struct ActionItem: Identifiable {
    let id = UUID()
    let name: String
    let notes: String?
    let dueDate: String?
    var isSelected = true
}

// MARK: - Action Item Row

private struct ActionItemRow: View {
    @Binding var item: ActionItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                item.isSelected.toggle()
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isSelected ? AppTheme.accent : AppTheme.textSecondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AppTheme.subheadlineFont)
                    .fontWeight(.medium)
                    .strikethrough(!item.isSelected)
                    .foregroundStyle(item.isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)

                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if let due = item.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(due)
                    }
                    .font(AppTheme.caption2Font)
                    .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(AppTheme.adaptiveCard)
    }
}
