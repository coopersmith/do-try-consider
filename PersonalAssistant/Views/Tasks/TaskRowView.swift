import SwiftUI

struct TaskRowView: View {
    let task: AsanaTask

    var body: some View {
        HStack(spacing: 12) {
            // Completion indicator
            Image(systemName: task.completed == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.completed == true ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                // Task name
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(task.completed == true)
                    .foregroundStyle(task.completed == true ? .secondary : .primary)

                HStack(spacing: 8) {
                    // Due date
                    if let dueDate = task.dueDate {
                        Label(dueDateText(dueDate), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(dueDateColor(dueDate))
                    }

                    // Project name
                    if let project = task.projects?.first, let projectName = project.name {
                        Text(projectName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Workspace badge
            if let workspace = task.workspace {
                WorkspaceBadge(text: workspace.displayName, color: workspaceColor(workspace))
            }
        }
        .padding(.vertical, 2)
    }

    private func dueDateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return DateFormatting.shortDate(date)
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        if task.completed == true { return .secondary }
        if date < Calendar.current.startOfDay(for: Date()) { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }

    private func workspaceColor(_ workspace: AsanaWorkspace) -> Color {
        // Generate a stable color from workspace name
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .cyan, .mint]
        let index = abs(workspace.displayName.hashValue) % colors.count
        return colors[index]
    }
}
