import SwiftUI

struct MeetingRowView: View {
    let meeting: CalendarMeetingItem

    var body: some View {
        HStack(spacing: 0) {
            // Time column
            VStack(spacing: 2) {
                if meeting.isAllDay {
                    Text("All")
                        .font(AppTheme.captionFont)
                        .fontWeight(.medium)
                    Text("Day")
                        .font(AppTheme.caption2Font)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text(DateFormatting.time(meeting.startDate))
                        .font(AppTheme.captionFont)
                        .fontWeight(.medium)
                    Text(DateFormatting.time(meeting.endDate))
                        .font(AppTheme.caption2Font)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(width: 50)

            // Calendar color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: meeting.calendarColorHex))
                .frame(width: 4)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)

            // Title + badges
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(AppTheme.subheadlineFont)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if meeting.hasGranolaNote {
                        WorkspaceBadge(text: "Notes", color: AppTheme.badgeGranola)
                    }

                    if let location = meeting.location, !location.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                            Text(location)
                                .lineLimit(1)
                        }
                        .font(AppTheme.caption2Font)
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
