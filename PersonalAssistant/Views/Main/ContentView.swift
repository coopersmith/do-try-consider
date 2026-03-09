import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var briefingViewModel = BriefingViewModel()
    @State private var chatViewModel = ChatViewModel()
    @State private var isChatPresented = false

    private let tabs: [(icon: String, label: String)] = [
        ("sun.max.fill", "Briefing"),
        ("checklist", "Tasks"),
        ("person.2.fill", "Meetings"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: BriefingView(viewModel: briefingViewModel)
                case 1: TaskListView()
                case 2: MeetingListView()
                default: BriefingView(viewModel: briefingViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        AppTheme.adaptiveBackground.opacity(0),
                        AppTheme.adaptiveBackground.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .background(AppTheme.adaptiveBackground.opacity(0.5))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $isChatPresented) {
            ChatOverlayView(viewModel: chatViewModel)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Nav pill
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
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 2)
            )

            // Chat action button
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
    }
}
