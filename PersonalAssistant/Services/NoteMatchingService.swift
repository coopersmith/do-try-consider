import Foundation

@MainActor
final class NoteMatchingService {
    static let shared = NoteMatchingService()

    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let tokenManager = TokenManager.shared

    // Cache: [matchKey: (noteID, noteTitle)]
    private var lookup: [String: (noteID: String, title: String)] = [:]
    private var lastBuildDate: Date?
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes

    private init() {}

    // MARK: - Public API

    /// Populates granolaNoteID and granolaNoteTitle on matching calendar events.
    /// Uses the SAME note source that detail views use (local notes first, then Granola API).
    func matchNotes(to events: [CalendarMeetingItem]) async -> [CalendarMeetingItem] {
        await refreshLookupIfNeeded()

        guard !lookup.isEmpty else { return events }

        return events.map { event in
            var mutable = event
            let key = matchKey(title: event.title, date: event.startDate)
            if let match = lookup[key] {
                mutable.granolaNoteID = match.noteID
                mutable.granolaNoteTitle = match.title
            }
            return mutable
        }
    }

    func invalidateCache() {
        lookup = [:]
        lastBuildDate = nil
    }

    // MARK: - Internal

    private func refreshLookupIfNeeded() async {
        if let lastBuild = lastBuildDate, Date().timeIntervalSince(lastBuild) < cacheDuration {
            return
        }
        await buildLookup()
    }

    private func buildLookup() async {
        let useLocalNotes = meetingNotes.isConfigured
        let hasGranolaKey = (try? tokenManager.getGranolaAPIKey()) != nil

        guard useLocalNotes || hasGranolaKey else {
            lookup = [:]
            lastBuildDate = Date()
            return
        }

        do {
            var newLookup: [String: (noteID: String, title: String)] = [:]

            if useLocalNotes {
                try await buildFromLocalNotes(into: &newLookup)
            } else {
                try await buildFromGranolaAPI(into: &newLookup)
            }

            lookup = newLookup
            lastBuildDate = Date()
        } catch {
            if lastBuildDate == nil {
                lastBuildDate = Date()
            }
        }
    }

    // MARK: - Local Notes Source

    private func buildFromLocalNotes(into lookup: inout [String: (noteID: String, title: String)]) async throws {
        let notes = try await meetingNotes.getRecentNotes(days: 37)

        for note in notes {
            let entry = (noteID: note.id, title: note.displayTitle)
            let key = matchKey(title: note.displayTitle, isoDate: note.createdAt)
            lookup[key] = entry
        }
    }

    // MARK: - Granola API Source

    private func buildFromGranolaAPI(into lookup: inout [String: (noteID: String, title: String)]) async throws {
        let notes = try await granola.getRecentNotes(days: 37)

        for note in notes {
            let entry = (noteID: note.id, title: note.displayTitle)

            do {
                let detail = try await granola.getNote(id: note.id)

                if let calEvent = detail.calendarEvent {
                    if let eventTitle = calEvent.eventTitle,
                       let startTime = calEvent.scheduledStartTime {
                        let primaryKey = matchKey(title: eventTitle, isoDate: startTime)
                        lookup[primaryKey] = entry
                    }

                    if let startTime = calEvent.scheduledStartTime {
                        let secondaryKey = matchKey(title: detail.displayTitle, isoDate: startTime)
                        if lookup[secondaryKey] == nil {
                            lookup[secondaryKey] = entry
                        }
                    }
                }

                let tertiaryKey = matchKey(title: detail.displayTitle, isoDate: detail.createdAt)
                if lookup[tertiaryKey] == nil {
                    lookup[tertiaryKey] = entry
                }
            } catch {
                let fallbackKey = matchKey(title: note.displayTitle, isoDate: note.createdAt)
                if lookup[fallbackKey] == nil {
                    lookup[fallbackKey] = entry
                }
            }
        }
    }

    // MARK: - Key Building

    private func matchKey(title: String, date: Date) -> String {
        let dateString = Self.dayFormatter.string(from: date)
        return "\(normalizeTitle(title))|\(dateString)"
    }

    private func matchKey(title: String, isoDate: String) -> String {
        let dateString: String
        if let date = Self.parseISO8601(isoDate) {
            dateString = Self.dayFormatter.string(from: date)
        } else {
            dateString = String(isoDate.prefix(10))
        }
        return "\(normalizeTitle(title))|\(dateString)"
    }

    private func normalizeTitle(_ title: String) -> String {
        var result = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading "YYYY-MM-DD " date prefix (Granola Obsidian export format)
        if result.count > 11,
           result[result.index(result.startIndex, offsetBy: 4)] == "-",
           result[result.index(result.startIndex, offsetBy: 7)] == "-",
           result[result.index(result.startIndex, offsetBy: 10)] == " " {
            let digits = result.prefix(4) + result.dropFirst(5).prefix(2) + result.dropFirst(8).prefix(2)
            if digits.allSatisfy(\.isNumber) {
                result = String(result.dropFirst(11))
            }
        }

        return result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Date Helpers

    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt
    }()

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
