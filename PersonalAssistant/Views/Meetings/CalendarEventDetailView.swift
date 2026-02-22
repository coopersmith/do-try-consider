import SwiftUI

struct CalendarEventDetailView: View {
    let meeting: CalendarMeetingItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(meeting.title)
                        .font(AppTheme.title3Font)

                    WorkspaceBadge(
                        text: meeting.calendarName,
                        color: Color(hex: meeting.calendarColorHex)
                    )
                }

                Divider()

                // Metadata
                WarmCard {
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataRow(
                            icon: "calendar",
                            label: "Date",
                            value: DateFormatting.fullDate(meeting.startDate)
                        )

                        if meeting.isAllDay {
                            MetadataRow(icon: "clock", label: "Time", value: "All Day")
                        } else {
                            MetadataRow(
                                icon: "clock",
                                label: "Time",
                                value: "\(DateFormatting.time(meeting.startDate)) – \(DateFormatting.time(meeting.endDate))"
                            )
                        }

                        if let location = meeting.location, !location.isEmpty {
                            MetadataRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                        }

                        if !meeting.attendees.isEmpty {
                            MetadataRow(
                                icon: "person.2",
                                label: "Attendees",
                                value: "\(meeting.attendees.count) people"
                            )
                        }
                    }
                }

                // Attendees
                if !meeting.attendees.isEmpty {
                    attendeesSection
                }

                // Notes
                if let notes = meeting.notes, !notes.isEmpty {
                    WarmCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Event Notes")
                                .font(AppTheme.sectionHeaderFont)
                            Text(notes)
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .warmScrollBackground()
        .background(AppTheme.adaptiveBackground)
        .navigationTitle("Event Details")
        .inlineNavigationBarTitle()
    }

    // MARK: - Attendees

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(AppTheme.sectionHeaderFont)

            ForEach(meeting.attendees.indices, id: \.self) { index in
                let attendee = meeting.attendees[index]
                HStack(spacing: 8) {
                    Image(systemName: attendee.isOrganizer ? "person.circle.fill" : "person.circle")
                        .foregroundStyle(attendee.isOrganizer ? AppTheme.accent : AppTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(attendee.displayName)
                                .font(AppTheme.subheadlineFont)
                            if attendee.isOrganizer {
                                Text("Organizer")
                                    .font(AppTheme.caption2Font)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        if let email = attendee.email, attendee.name != nil {
                            Text(email)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
