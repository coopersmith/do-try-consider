#if canImport(EventKitUI)
import EventKit
import EventKitUI
import SwiftUI

struct CalendarChooserView: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let selectedCalendarIDs: Set<String>
    let onDone: (Set<String>) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let chooser = EKCalendarChooser(
            selectionStyle: .multiple,
            displayStyle: .allCalendars,
            entityType: .event,
            eventStore: eventStore
        )
        chooser.delegate = context.coordinator
        chooser.showsDoneButton = true
        chooser.showsCancelButton = true

        // Pre-select calendars from saved selection
        let allCalendars = eventStore.calendars(for: .event)
        chooser.selectedCalendars = Set(
            allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        )

        let nav = UINavigationController(rootViewController: chooser)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone, onCancel: onCancel)
    }

    class Coordinator: NSObject, EKCalendarChooserDelegate {
        let onDone: (Set<String>) -> Void
        let onCancel: () -> Void

        init(onDone: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
            self.onDone = onDone
            self.onCancel = onCancel
        }

        func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser) {
            let ids = Set(calendarChooser.selectedCalendars.map { $0.calendarIdentifier })
            onDone(ids)
        }

        func calendarChooserDidCancel(_ calendarChooser: EKCalendarChooser) {
            onCancel()
        }
    }
}
#endif
