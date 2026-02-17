import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BriefingView()
                .tabItem {
                    Label("Briefing", systemImage: "sun.max.fill")
                }
                .tag(0)

            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(1)

            MeetingListView()
                .tabItem {
                    Label("Meetings", systemImage: "person.2.fill")
                }
                .tag(2)

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
    }
}
