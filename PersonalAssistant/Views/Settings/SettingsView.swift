import SwiftUI

struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @Environment(NotificationService.self) private var notifications

    var body: some View {
        NavigationStack {
            List {
                // Accounts Section
                Section("Accounts") {
                    NavigationLink {
                        AsanaAccountView()
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundStyle(.orange)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Asana")
                                    .font(AppTheme.subheadlineFont)
                                Text(viewModel.isAsanaConnected ? "Connected" : "Not connected")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(viewModel.isAsanaConnected ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(AppTheme.badgeCalendar)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Calendar")
                                    .font(AppTheme.subheadlineFont)
                                Text(viewModel.calendarStatusText)
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(viewModel.isCalendarAuthorized ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    NavigationLink {
                        GranolaSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundStyle(AppTheme.badgeGranola)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Granola")
                                    .font(AppTheme.subheadlineFont)
                                Text(viewModel.isGranolaConfigured ? "Configured" : "Not configured")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(viewModel.isGranolaConfigured ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    NavigationLink {
                        MeetingNotesSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.indigo)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Meeting Notes")
                                    .font(AppTheme.subheadlineFont)
                                Text(viewModel.isMeetingNotesConfigured ? "Configured" : "Not configured")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(viewModel.isMeetingNotesConfigured ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    NavigationLink {
                        ClaudeSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Claude AI")
                                    .font(AppTheme.subheadlineFont)
                                Text(viewModel.isClaudeConfigured ? "Configured" : "Not configured")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(viewModel.isClaudeConfigured ? AppTheme.urgencyGreen : AppTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                }

                // Notifications Section
                NotificationSettingsSection()

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            }
            .insetGroupedListStyle()
            .warmListBackground()
            .navigationTitle("Settings")
            .onAppear { viewModel.refreshMeetingNotesStatus() }
        }
    }
}

struct NotificationSettingsSection: View {
    @Environment(NotificationService.self) private var notifications

    var body: some View {
        @Bindable var notifs = notifications

        Section("Notifications") {
            Toggle("Morning Briefing", isOn: $notifs.isMorningBriefingEnabled)
                .tint(AppTheme.accent)
                .listRowBackground(AppTheme.adaptiveCard)

            if notifications.isMorningBriefingEnabled {
                HStack {
                    Text("Time")
                    Spacer()
                    Text(formatTime(notifications.morningBriefingTime))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.adaptiveCard)
            }

            Toggle("Evening Recap", isOn: $notifs.isEveningRecapEnabled)
                .tint(AppTheme.accent)
                .listRowBackground(AppTheme.adaptiveCard)

            if notifications.isEveningRecapEnabled {
                HStack {
                    Text("Time")
                    Spacer()
                    Text(formatTime(notifications.eveningRecapTime))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.adaptiveCard)
            }

            if !notifications.isPermissionGranted {
                Button("Enable Notifications") {
                    Task { await notifications.requestPermission() }
                }
                .tint(AppTheme.accent)
                .listRowBackground(AppTheme.adaptiveCard)
            }
        }
    }

    private func formatTime(_ components: DateComponents) -> String {
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }
}
