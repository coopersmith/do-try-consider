#if canImport(EventKit)
import EventKit
#endif
import Foundation

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let selectedCalendarsKey = "CalendarService.selectedCalendarIDs"

    #if canImport(EventKit)
    let eventStore = EKEventStore()
    #endif

    private init() {}

    // MARK: - Permission

    var permissionStatus: CalendarPermissionStatus {
        #if canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
        #else
        return .denied
        #endif
    }

    func requestAccess() async -> Bool {
        #if canImport(EventKit)
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Calendar Selection

    var selectedCalendarIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: selectedCalendarsKey) ?? []
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: selectedCalendarsKey)
        }
    }

    var hasCalendarSelection: Bool {
        UserDefaults.standard.stringArray(forKey: selectedCalendarsKey) != nil
    }

    func setSelectedCalendarIDs(_ ids: Set<String>) {
        selectedCalendarIDs = ids
    }

    // MARK: - Fetching Events

    func fetchEvents(from startDate: Date, to endDate: Date) -> [CalendarMeetingItem] {
        #if canImport(EventKit)
        guard permissionStatus == .authorized else { return [] }

        let selected = selectedCalendarIDs
        guard !selected.isEmpty else { return [] }

        let calendars = eventStore.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)

        return events.map { mapEvent($0) }
        #else
        return []
        #endif
    }

    func fetchEvent(identifier: String) -> CalendarMeetingItem? {
        #if canImport(EventKit)
        guard permissionStatus == .authorized else { return nil }
        guard let event = eventStore.event(withIdentifier: identifier) else { return nil }
        return mapEvent(event)
        #else
        return nil
        #endif
    }

    // MARK: - Private Helpers

    #if canImport(EventKit)
    private func mapEvent(_ event: EKEvent) -> CalendarMeetingItem {
        let attendees: [CalendarAttendee] = (event.attendees ?? []).map { participant in
            CalendarAttendee(
                name: participant.name,
                email: extractEmail(from: participant),
                isOrganizer: participant.isCurrentUser && event.organizer == participant
            )
        }

        return CalendarMeetingItem(
            id: event.eventIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            attendees: attendees,
            calendarName: event.calendar.title,
            calendarColorHex: cgColorToHex(event.calendar.cgColor)
        )
    }

    private func extractEmail(from participant: EKParticipant) -> String? {
        let urlString = participant.url.absoluteString
        if urlString.lowercased().hasPrefix("mailto:") {
            return String(urlString.dropFirst("mailto:".count))
        }
        return nil
    }
    #endif

    private func cgColorToHex(_ cgColor: CGColor) -> UInt {
        guard let components = cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        )?.components, components.count >= 3 else {
            return 0x3478F6 // fallback blue
        }
        let r = UInt(components[0] * 255)
        let g = UInt(components[1] * 255)
        let b = UInt(components[2] * 255)
        return (r << 16) | (g << 8) | b
    }
}
