import Foundation

@Observable
@MainActor
final class MeetingListViewModel {
    // MARK: - Meeting Filter

    enum MeetingFilter: String, CaseIterable {
        case hasNotes = "Have Notes"
        case all = "All Meetings"
    }

    var meetings: [CalendarMeetingItem] = []
    var isLoading = false
    var error: String?
    var searchText = ""
    var meetingFilter: MeetingFilter = .all
    var permissionStatus: CalendarPermissionStatus = .notDetermined
    var showCalendarChooser = false
    var showAllUpcoming = false

    private let calendarService = CalendarService.shared
    private let noteMatching = NoteMatchingService.shared
    private let upcomingPreviewCount = 3

    // MARK: - Notes Count

    /// Number of meetings that have a matched Granola note.
    var notesCount: Int {
        meetings.filter { $0.hasGranolaNote }.count
    }

    // MARK: - Filtered Base

    private var filtered: [CalendarMeetingItem] {
        var result = meetings

        // Apply notes filter
        if meetingFilter == .hasNotes {
            result = result.filter { $0.hasGranolaNote }
        }

        // Apply search filter
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.title.lowercased().contains(query)
            || $0.calendarName.lowercased().contains(query)
            || ($0.location?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Upcoming

    /// Future events (startDate >= now), sorted soonest-first.
    var upcomingMeetings: [CalendarMeetingItem] {
        let now = Date()
        return filtered
            .filter { $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
    }

    var visibleUpcomingMeetings: [CalendarMeetingItem] {
        showAllUpcoming ? upcomingMeetings : Array(upcomingMeetings.prefix(upcomingPreviewCount))
    }

    var hasMoreUpcoming: Bool {
        upcomingMeetings.count > upcomingPreviewCount
    }

    // MARK: - Past (grouped, reverse-chronological)

    var pastGroupedMeetings: [(String, [CalendarMeetingItem])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [String: [CalendarMeetingItem]] = [:]
        let order = ["Today", "Yesterday", "This Week", "Earlier"]

        let pastEvents = filtered
            .filter { $0.startDate < now }
            .sorted { $0.startDate > $1.startDate } // most recent first

        for meeting in pastEvents {
            let date = meeting.startDate
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

    var isEmpty: Bool {
        upcomingMeetings.isEmpty && pastGroupedMeetings.isEmpty
    }

    // MARK: - Permission

    func checkPermission() {
        permissionStatus = calendarService.permissionStatus
    }

    func requestCalendarAccess() async {
        let granted = await calendarService.requestAccess()
        permissionStatus = granted ? .authorized : .denied
        if granted {
            showCalendarChooser = true
        }
    }

    func onCalendarChooserDone(_ ids: Set<String>) {
        calendarService.setSelectedCalendarIDs(ids)
        showCalendarChooser = false
        Task { await loadMeetings() }
    }

    func onCalendarChooserCancel() {
        showCalendarChooser = false
        Task { await loadMeetings() }
    }

    // MARK: - Loading

    func loadMeetings() async {
        guard permissionStatus == .authorized else {
            checkPermission()
            return
        }

        isLoading = true
        error = nil

        let calendar = Calendar.current
        let now = Date()
        let past = calendar.date(byAdding: .day, value: -30, to: now)!
        let future = calendar.date(byAdding: .day, value: 14, to: now)!

        var events = calendarService.fetchEvents(from: past, to: future)

        // Match Granola notes (best-effort)
        events = await noteMatching.matchNotes(to: events)

        meetings = events
        isLoading = false
    }
}
