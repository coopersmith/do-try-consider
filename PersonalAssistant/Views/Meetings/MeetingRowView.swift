import SwiftUI

struct MeetingRowView: View {
    let meeting: GranolaNoteListItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.purple)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if meeting.id.hasPrefix("local-") {
                    WorkspaceBadge(text: "Local", color: .teal)
                } else {
                    WorkspaceBadge(text: "Granola", color: .purple)
                }
            }

            Spacer()

            if let date = parseDate(meeting.createdAt) {
                Text(DateFormatting.relative(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
