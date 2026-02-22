import Foundation

@MainActor
final class NoteMatchingService {
    static let shared = NoteMatchingService()

    private let granola = GranolaAPIClient.shared
    private let tokenManager = TokenManager.shared

    // Cache: [calendarEventId: (noteID, noteTitle)]
    private var lookup: [String: (noteID: String, title: String)] = [:]
    private var lastBuildDate: Date?
    private let cacheDuration: TimeInterval = 5 * 60 // 5 minutes

    private init() {}

    // MARK: - Public API

    /// Populates granolaNoteID and granolaNoteTitle on matching calendar events.
    /// Fails silently — calendar events always show, badges are best-effort.
    func matchNotes(to events: [CalendarMeetingItem]) async -> [CalendarMeetingItem] {
        await refreshLookupIfNeeded()

        guard !lookup.isEmpty else { return events }

        return events.map { event in
            var mutable = event
            if let match = lookup[event.id] {
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
            return // Cache is fresh
        }
        await buildLookup()
    }

    private func buildLookup() async {
        guard (try? tokenManager.getGranolaAPIKey()) != nil else {
            lookup = [:]
            lastBuildDate = Date()
            return
        }

        do {
            // Fetch notes from the last 37 days to cover the typical calendar window
            let notes = try await granola.getRecentNotes(days: 37)
            var newLookup: [String: (noteID: String, title: String)] = [:]

            // Fetch detail for each note to extract calendarEventId
            for note in notes {
                do {
                    let detail = try await granola.getNote(id: note.id)
                    if let calendarEventId = detail.calendarEvent?.calendarEventId,
                       !calendarEventId.isEmpty {
                        newLookup[calendarEventId] = (noteID: note.id, title: note.displayTitle)
                    }
                } catch {
                    // Skip notes that fail to load — best effort
                    continue
                }
            }

            lookup = newLookup
            lastBuildDate = Date()
        } catch {
            // Fail silently — keep stale cache or empty
            if lastBuildDate == nil {
                lastBuildDate = Date()
            }
        }
    }
}
