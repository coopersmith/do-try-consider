import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let accountID: String

    @State private var task: AsanaTask?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isCompleting = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var isUpdatingDate = false
    @State private var comments: [AsanaStory] = []
    @State private var isLoadingComments = false
    @State private var commentText = ""
    @State private var isPostingComment = false

    private let asana = AsanaAPIClient.shared

    var body: some View {
        Group {
            if isLoading {
                LoadingIndicator("Loading task...")
            } else if let error {
                ErrorStateView(error) {
                    Task { await loadTask() }
                }
            } else if let task {
                taskContent(task)
            }
        }
        .background(AppTheme.adaptiveBackground)
        .navigationTitle("Task Details")
        .inlineNavigationBarTitle()
        .task {
            await loadTask()
            await loadComments()
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    @ViewBuilder
    private func taskContent(_ task: AsanaTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title + status
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: task.completed == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.completed == true ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            .font(.title2)

                        Text(task.name)
                            .font(AppTheme.title3Font)
                    }

                    if let workspace = task.workspace {
                        WorkspaceBadge(text: workspace.displayName, color: .blue)
                    }
                }

                Divider()

                // Metadata
                WarmCard {
                    VStack(alignment: .leading, spacing: 12) {
                        // Due date — tappable
                        if let dueDate = task.dueDate {
                            Button {
                                selectedDate = dueDate
                                showDatePicker = true
                            } label: {
                                HStack {
                                    Label("Due Date", systemImage: "calendar")
                                        .font(AppTheme.subheadlineFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(width: 120, alignment: .leading)

                                    Text(DateFormatting.fullDate(dueDate))
                                        .font(AppTheme.subheadlineFont)
                                        .foregroundStyle(task.isOverdue ? AppTheme.urgencyRed : .primary)

                                    Spacer()

                                    Image(systemName: "pencil")
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                selectedDate = Date()
                                showDatePicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Add Due Date")
                                }
                                .font(AppTheme.subheadlineFont)
                                .foregroundStyle(AppTheme.accent)
                            }
                        }

                        // Assignee
                        if let assignee = task.assignee {
                            MetadataRow(
                                icon: "person",
                                label: "Assignee",
                                value: assignee.name
                            )
                        }

                        if let project = task.projects?.first, let projectName = project.name {
                            MetadataRow(
                                icon: "folder",
                                label: "Project",
                                value: projectName
                            )
                        }

                        if let createdAt = task.createdAt,
                           let date = DateFormatting.dateFromISO(createdAt) {
                            MetadataRow(
                                icon: "clock",
                                label: "Created",
                                value: DateFormatting.relative(date)
                            )
                        }
                    }
                }

                // Notes
                if let notes = task.notes, !notes.isEmpty {
                    WarmCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(AppTheme.sectionHeaderFont)

                            Text(notes)
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                // Comments section
                commentsSection

                Spacer(minLength: 40)

                // Actions
                if task.completed != true {
                    Button {
                        Task { await completeTask() }
                    } label: {
                        HStack {
                            if isCompleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Mark as Complete")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(isCompleting)
                }
            }
            .padding()
        }
        .warmScrollBackground()
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(AppTheme.sectionHeaderFont)

            if isLoadingComments {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading comments...")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else if comments.isEmpty {
                Text("No comments yet")
                    .font(AppTheme.subheadlineFont)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(comments) { comment in
                    CommentRow(story: comment)
                }
            }

            // New comment input
            HStack(spacing: 8) {
                TextField("Add a comment...", text: $commentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task { await postComment() }
                } label: {
                    if isPostingComment {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : AppTheme.accent)
                    }
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingComment)
            }
        }
    }

    // MARK: - Date Picker Sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Due Date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)

                if isUpdatingDate {
                    ProgressView("Updating...")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Change Due Date")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await updateDueDate() }
                    }
                    .disabled(isUpdatingDate)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadTask() async {
        isLoading = true
        error = nil

        do {
            task = try await asana.getTask(id: taskID, accountID: accountID)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func completeTask() async {
        isCompleting = true
        do {
            task = try await asana.completeTask(id: taskID, accountID: accountID)
        } catch {
            self.error = error.localizedDescription
        }
        isCompleting = false
    }

    private func loadComments() async {
        isLoadingComments = true
        do {
            comments = try await asana.getTaskComments(taskID: taskID, accountID: accountID)
        } catch {
            print("Failed to load comments: \(error)")
        }
        isLoadingComments = false
    }

    private func postComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isPostingComment = true
        do {
            let newComment = try await asana.addTaskComment(taskID: taskID, text: text, accountID: accountID)
            comments.append(newComment)
            commentText = ""
        } catch {
            self.error = error.localizedDescription
        }
        isPostingComment = false
    }

    private func updateDueDate() async {
        isUpdatingDate = true
        do {
            let dateString = DateFormatting.isoDateOnly(selectedDate)
            task = try await asana.updateTask(id: taskID, fields: ["due_on": dateString], accountID: accountID)
            showDatePicker = false
        } catch {
            self.error = error.localizedDescription
        }
        isUpdatingDate = false
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    let story: AsanaStory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(story.createdBy?.name ?? "Unknown")
                    .font(AppTheme.subheadlineFont)
                    .fontWeight(.medium)

                Spacer()

                if let date = story.createdDate {
                    Text(DateFormatting.relative(date))
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Text(story.text ?? "")
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(10)
        .background(AppTheme.adaptiveSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(valueColor ?? .primary)
        }
    }
}
