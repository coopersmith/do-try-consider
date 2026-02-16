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
                                    .font(.subheadline)
                                Text(viewModel.isAsanaConnected ? "Connected" : "Not connected")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.isAsanaConnected ? .green : .secondary)
                            }
                        }
                    }

                    NavigationLink {
                        GranolaSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundStyle(.purple)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Granola")
                                    .font(.subheadline)
                                Text(viewModel.isGranolaConfigured ? "Configured" : "Not configured")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.isGranolaConfigured ? .green : .secondary)
                            }
                        }
                    }

                    NavigationLink {
                        MeetingNotesSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.indigo)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Meeting Notes")
                                    .font(.subheadline)
                                Text(viewModel.isMeetingNotesConfigured ? "Configured" : "Not configured")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.isMeetingNotesConfigured ? .green : .secondary)
                            }
                        }
                    }

                    NavigationLink {
                        ClaudeSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading) {
                                Text("Claude AI")
                                    .font(.subheadline)
                                Text(viewModel.isClaudeConfigured ? "Configured" : "Not configured")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.isClaudeConfigured ? .green : .secondary)
                            }
                        }
                    }
                }

                // Notifications Section
                NotificationSettingsSection()

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
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

            if notifications.isMorningBriefingEnabled {
                HStack {
                    Text("Time")
                    Spacer()
                    Text(formatTime(notifications.morningBriefingTime))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Evening Recap", isOn: $notifs.isEveningRecapEnabled)

            if notifications.isEveningRecapEnabled {
                HStack {
                    Text("Time")
                    Spacer()
                    Text(formatTime(notifications.eveningRecapTime))
                        .foregroundStyle(.secondary)
                }
            }

            if !notifications.isPermissionGranted {
                Button("Enable Notifications") {
                    Task { await notifications.requestPermission() }
                }
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
