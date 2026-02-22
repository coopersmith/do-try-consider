import SwiftUI

struct TaskRowView: View {
    let task: AsanaTask

    var body: some View {
        HStack(spacing: 12) {
            // Completion indicator
            Image(systemName: task.completed == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.completed == true ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                // Task name
                Text(task.name)
                    .font(AppTheme.subheadlineFont)
                    .fontWeight(.medium)
                    .strikethrough(task.completed == true)
                    .foregroundStyle(task.completed == true ? AppTheme.textSecondary : .primary)
                    .lineLimit(2)

                // Project badge
                if let project = task.projects?.first, let projectName = project.name {
                    WorkspaceBadge(text: projectName, color: projectColor(projectName))
                }
            }

            Spacer()

            // Due date
            if let dueDate = task.dueDate {
                Text(dueDateText(dueDate))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(dueDateColor(dueDate))
            }
        }
        .padding(.vertical, 2)
    }

    private static let compactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private func dueDateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tmrw"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yday"
        } else {
            return Self.compactDateFormatter.string(from: date)
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        if task.completed == true { return AppTheme.textSecondary }
        if date < Calendar.current.startOfDay(for: Date()) { return AppTheme.urgencyRed }
        if Calendar.current.isDateInToday(date) { return AppTheme.urgencyOrange }
        return AppTheme.textSecondary
    }

    private func projectColor(_ name: String) -> Color {
        let colors: [Color] = [.blue, AppTheme.badgeGranola, .indigo, AppTheme.badgeLocal, .cyan, .mint]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}
