import Foundation

@Observable
@MainActor
final class MeetingListViewModel {
    var meetings: [GranolaNoteListItem] = []
    var isLoading = false
    var error: String?
    var searchText = ""

    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let tokenManager = TokenManager.shared

    // MARK: - Computed Properties

    var filteredMeetings: [GranolaNoteListItem] {
        let sorted = meetings.sorted { $0.createdAt > $1.createdAt }
        guard !searchText.isEmpty else { return sorted }
        let query = searchText.lowercased()
        return sorted.filter { $0.displayTitle.lowercased().contains(query) }
    }

    var groupedMeetings: [(String, [GranolaNoteListItem])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [String: [GranolaNoteListItem]] = [:]
        let order = ["Today", "Yesterday", "This Week", "Earlier"]

        for meeting in filteredMeetings {
            guard let date = parseISO8601(meeting.createdAt) else {
                groups["Earlier", default: []].append(meeting)
                continue
            }
            if calendar.isDateInToday(date) {
                groups["Today", default: []].append(meeting)
            } else if calendar.isDateInYesterday(date) {
                groups["Yesterday", default: []].append(meeting)
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                groups["This Week", default: []].append(meeting)
            } else {
                groups["Earlier", default: []].append(meeting)
            }
        }

        return order.compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }

    var isSourceConfigured: Bool {
        meetingNotes.isConfigured || ((try? tokenManager.getGranolaAPIKey()) != nil)
    }

    // MARK: - Loading

    func loadMeetings() async {
        guard isSourceConfigured else {
            error = "Configure meeting notes in Settings to see your meetings."
            return
        }

        isLoading = true
        error = nil

        do {
            if meetingNotes.isConfigured {
                meetings = try await meetingNotes.getRecentNotes(days: 30)
            } else {
                meetings = try await granola.getRecentNotes(days: 30)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
