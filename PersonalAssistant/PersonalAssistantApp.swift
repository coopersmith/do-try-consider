import SwiftUI

@main
struct PersonalAssistantApp: App {
    @State private var settingsViewModel = SettingsViewModel()
    @State private var notificationService = NotificationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settingsViewModel)
                .environment(notificationService)
                .tint(AppTheme.accent)
                .task {
                    await notificationService.requestPermission()
                }
        }
    }
}
