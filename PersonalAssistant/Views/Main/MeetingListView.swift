import SwiftUI

struct MeetingListView: View {
    @State private var viewModel = MeetingListViewModel()
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.permissionStatus {
                case .notDetermined:
                    permissionPrompt
                case .denied, .restricted:
                    permissionDenied
                case .authorized:
                    authorizedContent
                }
            }
            .background(AppTheme.adaptiveBackground)
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Meetings")
                        .font(AppTheme.subheadlineFont)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .task {
                viewModel.checkPermission()
                if viewModel.permissionStatus == .authorized && viewModel.meetings.isEmpty {
                    await viewModel.loadMeetings()
                }
            }
            #if canImport(EventKitUI)
            .sheet(isPresented: $viewModel.showCalendarChooser) {
                CalendarChooserView(
                    eventStore: CalendarService.shared.eventStore,
                    selectedCalendarIDs: CalendarService.shared.selectedCalendarIDs,
                    onDone: { ids in
                        viewModel.onCalendarChooserDone(ids)
                    },
                    onCancel: {
                        viewModel.onCalendarChooserCancel()
                    }
                )
            }
            #endif
        }
    }

    // MARK: - Permission Prompt

    private var permissionPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.badgeCalendar)

            Text("Calendar Access")
                .font(AppTheme.titleFont)

            Text("Allow access to your calendar to see your meetings here.")
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.requestCalendarAccess() }
            } label: {
                Label("Allow Calendar Access", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Permission Denied

    private var permissionDenied: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Calendar Access Denied")
                .font(AppTheme.titleFont)

            Text("Open Settings to grant calendar access.")
                .font(AppTheme.subheadlineFont)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            #if os(iOS)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Filter", selection: $viewModel.meetingFilter) {
                ForEach(MeetingListViewModel.MeetingFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Group {
                if viewModel.isLoading && viewModel.meetings.isEmpty {
                    LoadingIndicator("Loading meetings...")
                } else if let error = viewModel.error, viewModel.meetings.isEmpty {
                    ErrorStateView(error) {
                        Task { await viewModel.loadMeetings() }
                    }
                } else if viewModel.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: viewModel.meetingFilter == .hasNotes ? "No Meeting Notes" : "No Meetings",
                        message: viewModel.meetingFilter == .hasNotes
                            ? "No meetings with Granola notes found."
                            : viewModel.meetings.isEmpty
                                ? "No calendar events found."
                                : "No meetings match your search."
                    )
                } else {
                    meetingList
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search meetings")
        .refreshable {
            await viewModel.loadMeetings()
        }
    }

    // MARK: - Meeting List

    private var meetingList: some View {
        List {
            // Coming Up section
            if !viewModel.upcomingMeetings.isEmpty {
                Section {
                    ForEach(viewModel.visibleUpcomingMeetings) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRowView(meeting: meeting)
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    }

                    if viewModel.hasMoreUpcoming && !viewModel.showAllUpcoming {
                        Button {
                            withAnimation { viewModel.showAllUpcoming = true }
                        } label: {
                            HStack {
                                Text("Show \(viewModel.upcomingMeetings.count - viewModel.visibleUpcomingMeetings.count) More")
                                    .font(AppTheme.subheadlineFont)
                                Image(systemName: "chevron.down")
                                    .font(AppTheme.captionFont)
                            }
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    }
                } header: {
                    sectionHeader("Coming Up", accent: true)
                }
            }

            // Past sections (reverse-chronological)
            ForEach(viewModel.pastGroupedMeetings, id: \.0) { label, meetings in
                Section {
                    ForEach(meetings) { meeting in
                        NavigationLink(value: meeting) {
                            MeetingRowView(meeting: meeting)
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    }
                } header: {
                    sectionHeader(label, accent: false)
                }
            }
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .contentMargins(.bottom, 80, for: .scrollContent)
        .navigationDestination(for: CalendarMeetingItem.self) { meeting in
            CalendarEventDetailView(meeting: meeting)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ label: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            if accent {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 6, height: 6)
            }
            Text(label.uppercased())
                .font(AppTheme.captionFont)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundStyle(accent ? AppTheme.accent : AppTheme.textSecondary)
        }
    }
}
