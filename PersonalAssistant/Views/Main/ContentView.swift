import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var chatViewModel = ChatViewModel()
    @State private var isChatPresented = false

    private let tabs: [(icon: String, label: String)] = [
        ("sun.max.fill", "Briefing"),
        ("checklist", "Tasks"),
        ("person.2.fill", "Meetings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case 0: BriefingView()
                case 1: TaskListView()
                case 2: MeetingListView()
                default: BriefingView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80)

            // Custom bottom bar
            HStack(spacing: 12) {
                // Nav pill — left
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTab = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 20, weight: .medium))
                                Text(tab.label)
                                    .font(AppTheme.caption2Font)
                            }
                            .foregroundStyle(selectedTab == index ? AppTheme.accent : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(AppTheme.adaptiveCard)
                        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 2)
                )

                // Chat action button — right
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    isChatPresented = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.accent)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 10, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .background(AppTheme.adaptiveBackground)
        .sheet(isPresented: $isChatPresented) {
            ChatOverlayView(viewModel: chatViewModel)
        }
    }
}
