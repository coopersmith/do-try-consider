import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

@Observable
@MainActor
final class NotificationService {
    private(set) var isPermissionGranted = false

    var morningBriefingTime: DateComponents {
        get {
            let hour = UserDefaults.standard.integer(forKey: "morningBriefingHour")
            let minute = UserDefaults.standard.integer(forKey: "morningBriefingMinute")
            return DateComponents(hour: hour == 0 ? 8 : hour, minute: minute)
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: "morningBriefingHour")
            UserDefaults.standard.set(newValue.minute, forKey: "morningBriefingMinute")
            scheduleDailyNotifications()
        }
    }

    var eveningRecapTime: DateComponents {
        get {
            let hour = UserDefaults.standard.integer(forKey: "eveningRecapHour")
            let minute = UserDefaults.standard.integer(forKey: "eveningRecapMinute")
            return DateComponents(hour: hour == 0 ? 18 : hour, minute: minute)
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: "eveningRecapHour")
            UserDefaults.standard.set(newValue.minute, forKey: "eveningRecapMinute")
            scheduleDailyNotifications()
        }
    }

    var isMorningBriefingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "morningBriefingEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "morningBriefingEnabled")
            scheduleDailyNotifications()
        }
    }

    var isEveningRecapEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "eveningRecapEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "eveningRecapEnabled")
            scheduleDailyNotifications()
        }
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isPermissionGranted = granted

            if granted {
                scheduleDailyNotifications()
                #if os(iOS)
                registerBackgroundTasks()
                #endif
            }
        } catch {
            isPermissionGranted = false
        }
    }

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule Notifications

    func scheduleDailyNotifications() {
        let center = UNUserNotificationCenter.current()

        // Remove existing scheduled notifications
        center.removePendingNotificationRequests(
            withIdentifiers: ["morning-briefing", "evening-recap"]
        )

        // Morning briefing
        if isMorningBriefingEnabled {
            let morningContent = UNMutableNotificationContent()
            morningContent.title = "Good Morning"
            morningContent.body = "Your daily briefing is ready. Tap to see your tasks and meetings."
            morningContent.sound = .default
            morningContent.categoryIdentifier = "BRIEFING"

            let morningTrigger = UNCalendarNotificationTrigger(
                dateMatching: morningBriefingTime,
                repeats: true
            )

            let morningRequest = UNNotificationRequest(
                identifier: "morning-briefing",
                content: morningContent,
                trigger: morningTrigger
            )

            center.add(morningRequest)
        }

        // Evening recap
        if isEveningRecapEnabled {
            let eveningContent = UNMutableNotificationContent()
            eveningContent.title = "Evening Recap"
            eveningContent.body = "See how your day went and plan for tomorrow."
            eveningContent.sound = .default
            eveningContent.categoryIdentifier = "BRIEFING"

            let eveningTrigger = UNCalendarNotificationTrigger(
                dateMatching: eveningRecapTime,
                repeats: true
            )

            let eveningRequest = UNNotificationRequest(
                identifier: "evening-recap",
                content: eveningContent,
                trigger: eveningTrigger
            )

            center.add(eveningRequest)
        }
    }

    // MARK: - Overdue Task Notifications

    func scheduleOverdueAlert(for task: AsanaTask) {
        guard let dueDate = task.dueDate else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task Overdue"
        content.body = "\"\(task.name)\" was due \(DateFormatting.relative(dueDate))"
        content.sound = .default
        content.categoryIdentifier = "TASK"
        content.userInfo = ["taskID": task.gid]

        // Trigger at 9 AM the day after due date
        var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        components.day = (components.day ?? 0) + 1
        components.hour = 9

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "overdue-\(task.gid)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Background Tasks

    #if os(iOS)
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.personalassistant.briefing-refresh",
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }

        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.personalassistant.briefing-refresh"
        )
        request.earliestBeginDate = Calendar.current.date(
            byAdding: .hour, value: 1, to: Date()
        )

        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleBackgroundRefresh()

        let backgroundTask = Task {
            // Pre-fetch data for next briefing
            // This keeps the app responsive when opened
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            backgroundTask.cancel()
        }
    }
    #endif
}
