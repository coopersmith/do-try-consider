import Foundation

// MARK: - Calendar Meeting Item

struct CalendarMeetingItem: Identifiable, Hashable {
    let id: String // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let attendees: [CalendarAttendee]
    let calendarName: String
    let calendarColorHex: UInt

    // Granola note match (populated by NoteMatchingService)
    var granolaNoteID: String?
    var granolaNoteTitle: String?

    var hasGranolaNote: Bool { granolaNoteID != nil }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CalendarMeetingItem, rhs: CalendarMeetingItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Calendar Attendee

struct CalendarAttendee: Hashable {
    let name: String?
    let email: String?
    let isOrganizer: Bool

    var displayName: String {
        name ?? email ?? "Unknown"
    }
}

// MARK: - Calendar Permission Status

enum CalendarPermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

