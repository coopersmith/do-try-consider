import SwiftUI

struct MeetingListView: View {
    @State private var viewModel = MeetingListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.meetings.isEmpty {
                    LoadingIndicator("Loading meetings...")
                } else if let error = viewModel.error, viewModel.meetings.isEmpty {
                    ErrorStateView(error) {
                        Task { await viewModel.loadMeetings() }
                    }
                } else if viewModel.filteredMeetings.isEmpty {
                    EmptyStateView(
                        icon: "person.2",
                        title: "No Meetings",
                        message: viewModel.meetings.isEmpty
                            ? "Configure Granola or local notes in Settings to see meetings."
                            : "No meetings match your search."
                    )
                } else {
                    meetingList
                }
            }
            .navigationTitle("Meetings")
            .searchable(text: $viewModel.searchText, prompt: "Search meetings")
            .refreshable {
                await viewModel.loadMeetings()
            }
            .task {
                if viewModel.meetings.isEmpty {
                    await viewModel.loadMeetings()
                }
            }
        }
    }

    private var meetingList: some View {
        List {
            ForEach(viewModel.groupedMeetings, id: \.0) { label, meetings in
                Section(label) {
                    ForEach(meetings) { meeting in
                        NavigationLink(value: meeting.id) {
                            MeetingRowView(meeting: meeting)
                        }
                    }
                }
            }
        }
        .insetGroupedListStyle()
        .navigationDestination(for: String.self) { meetingID in
            MeetingDetailView(meetingID: meetingID)
        }
    }
}
