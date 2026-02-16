import Foundation

// MARK: - Notes List Response

struct GranolaNotesResponse: Codable {
    let notes: [GranolaNoteListItem]
    let hasMore: Bool?
    let cursor: String?
}

// MARK: - Note (List Item)

struct GranolaNoteListItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let owner: GranolaOwner?
    let createdAt: String
    let updatedAt: String?

    static func == (lhs: GranolaNoteListItem, rhs: GranolaNoteListItem) -> Bool {
        lhs.id == rhs.id
    }

    enum CodingKeys: String, CodingKey {
        case id, title, owner
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String { title ?? "Untitled" }
}

// MARK: - Owner

struct GranolaOwner: Codable {
    let name: String?
    let email: String?
}

// MARK: - Note Detail

struct GranolaNoteDetail: Codable, Identifiable {
    let id: String
    let title: String?
    let owner: GranolaOwner?
    let createdAt: String
    let updatedAt: String?
    let calendarEvent: GranolaCalendarEvent?
    let attendees: [GranolaAttendee]?
    let folderMembership: [GranolaFolder]?
    let summaryText: String?
    let summaryMarkdown: String?
    let transcript: [GranolaTranscriptSegment]?

    enum CodingKeys: String, CodingKey {
        case id, title, owner, attendees, transcript
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case calendarEvent = "calendar_event"
        case folderMembership = "folder_membership"
        case summaryText = "summary_text"
        case summaryMarkdown = "summary_markdown"
    }

    var displayTitle: String { title ?? "Untitled" }

    var summary: String? { summaryText }
}

// MARK: - Calendar Event

struct GranolaCalendarEvent: Codable {
    let eventTitle: String?
    let invitees: [GranolaInvitee]?
    let organiser: String?
    let calendarEventId: String?
    let scheduledStartTime: String?
    let scheduledEndTime: String?

    enum CodingKeys: String, CodingKey {
        case invitees, organiser
        case eventTitle = "event_title"
        case calendarEventId = "calendar_event_id"
        case scheduledStartTime = "scheduled_start_time"
        case scheduledEndTime = "scheduled_end_time"
    }
}

struct GranolaInvitee: Codable {
    let email: String?
}

// MARK: - Folder

struct GranolaFolder: Codable, Identifiable {
    let id: String
    let name: String?
}

// MARK: - Attendee

struct GranolaAttendee: Codable {
    let name: String?
    let email: String?

    var displayName: String {
        name ?? email ?? "Unknown"
    }
}

// MARK: - Transcript Segment

struct GranolaTranscriptSegment: Codable {
    let speaker: GranolaSpeaker?
    let text: String
    let startTime: String?
    let endTime: String?

    enum CodingKeys: String, CodingKey {
        case speaker, text
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct GranolaSpeaker: Codable {
    let source: String?
}
