import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var chatViewModel = ChatViewModel()
    @State private var isChatPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
            }
            .tint(AppTheme.accent)

            FloatingChatButton {
                isChatPresented = true
            }
        }
        .sheet(isPresented: $isChatPresented) {
            ChatOverlayView(viewModel: chatViewModel)
        }
    }
}
