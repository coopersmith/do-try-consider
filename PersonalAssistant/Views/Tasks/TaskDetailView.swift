import SwiftUI

struct TaskDetailView: View {
    let taskID: String

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
                            .foregroundStyle(task.completed == true ? .green : .secondary)
                            .font(.title2)

                        Text(task.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    if let workspace = task.workspace {
                        WorkspaceBadge(text: workspace.displayName, color: .blue)
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    // Due date — tappable
                    if let dueDate = task.dueDate {
                        Button {
                            selectedDate = dueDate
                            showDatePicker = true
                        } label: {
                            HStack {
                                Label("Due Date", systemImage: "calendar")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                Text(DateFormatting.fullDate(dueDate))
                                    .font(.subheadline)
                                    .foregroundStyle(task.isOverdue ? .red : .primary)

                                Spacer()

                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
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

                // Notes
                if let notes = task.notes, !notes.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)

                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

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
                    .disabled(isCompleting)
                }
            }
            .padding()
        }
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            if isLoadingComments {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading comments...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if comments.isEmpty {
                Text("No comments yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Color.accentColor)
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
            task = try await asana.getTask(id: taskID)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func completeTask() async {
        isCompleting = true
        do {
            task = try await asana.completeTask(id: taskID)
        } catch {
            self.error = error.localizedDescription
        }
        isCompleting = false
    }

    private func loadComments() async {
        isLoadingComments = true
        do {
            comments = try await asana.getTaskComments(taskID: taskID)
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
            let newComment = try await asana.addTaskComment(taskID: taskID, text: text)
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
            task = try await asana.updateTask(id: taskID, fields: ["due_on": dateString])
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
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let date = story.createdDate {
                    Text(DateFormatting.relative(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(story.text ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.systemGray6Color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor ?? .primary)
        }
    }
}
