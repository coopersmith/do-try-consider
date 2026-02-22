import SwiftUI

struct CalendarSettingsView: View {
    @State private var permissionStatus: CalendarPermissionStatus = .notDetermined
    @State private var showingChooser = false

    private let calendarService = CalendarService.shared

    var body: some View {
        List {
            // Hero section
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.badgeCalendar)

                    Text("Apple Calendar")
                        .font(AppTheme.titleFont)

                    Text("Your calendar events appear in the Meetings tab. Choose which calendars to include.")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(AppTheme.adaptiveCard)
            }

            // Permission section
            Section("Calendar Access") {
                #if canImport(EventKit)
                switch permissionStatus {
                case .notDetermined:
                    Button {
                        Task {
                            let granted = await calendarService.requestAccess()
                            permissionStatus = granted ? .authorized : .denied
                            if granted {
                                showingChooser = true
                            }
                        }
                    } label: {
                        Label("Grant Calendar Access", systemImage: "calendar.badge.plus")
                    }
                    .tint(AppTheme.accent)
                    .listRowBackground(AppTheme.adaptiveCard)

                case .authorized:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.urgencyGreen)
                        Text("Calendar access granted")
                            .font(AppTheme.subheadlineFont)
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                case .denied:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calendar access was denied.")
                            .font(AppTheme.subheadlineFont)
                        #if os(iOS)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                        }
                        .tint(AppTheme.accent)
                        #else
                        Text("Grant access in System Settings > Privacy & Security > Calendars.")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textSecondary)
                        #endif
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                case .restricted:
                    Text("Calendar access is restricted on this device.")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(AppTheme.adaptiveCard)
                }
                #else
                Text("Calendar is not available on this platform.")
                    .font(AppTheme.subheadlineFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.adaptiveCard)
                #endif
            }

            // Calendar selection (only when authorized)
            if permissionStatus == .authorized {
                Section("Selected Calendars") {
                    let count = calendarService.selectedCalendarIDs.count
                    HStack {
                        Text(count > 0 ? "\(count) calendar\(count == 1 ? "" : "s") selected" : "No calendars selected")
                            .font(AppTheme.subheadlineFont)
                            .foregroundStyle(count > 0 ? AppTheme.textPrimary : AppTheme.textSecondary)
                        Spacer()
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    Button {
                        showingChooser = true
                    } label: {
                        Label("Choose Calendars", systemImage: "calendar.badge.checkmark")
                    }
                    .tint(AppTheme.accent)
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            }
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationTitle("Calendar")
        .inlineNavigationBarTitle()
        .onAppear {
            permissionStatus = calendarService.permissionStatus
        }
        #if canImport(EventKitUI)
        .sheet(isPresented: $showingChooser) {
            CalendarChooserView(
                eventStore: calendarService.eventStore,
                selectedCalendarIDs: calendarService.selectedCalendarIDs,
                onDone: { ids in
                    calendarService.setSelectedCalendarIDs(ids)
                    showingChooser = false
                },
                onCancel: {
                    showingChooser = false
                }
            )
        }
        #endif
    }
}
