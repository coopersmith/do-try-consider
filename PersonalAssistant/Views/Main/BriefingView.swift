import SwiftUI

struct BriefingView: View {
    @State private var viewModel = BriefingViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 36) {
                    if viewModel.isLoading && viewModel.briefing == nil {
                        briefingLoadingView
                    } else if let error = viewModel.error, viewModel.briefing == nil {
                        ErrorStateView(error) {
                            Task { await viewModel.loadBriefing() }
                        }
                    } else if viewModel.briefing != nil {
                        briefingContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .warmScrollBackground()
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(DateFormatting.fullDate(Date()))
                        .font(AppTheme.subheadlineFont)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                if viewModel.briefing == nil {
                    await viewModel.loadBriefing()
                }
            }
            .navigationDestination(for: TaskDestination.self) { dest in
                TaskDetailView(taskID: dest.taskID, accountID: dest.accountID)
            }
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private var briefingContent: some View {
        let sections = viewModel.unifiedSections

        if sections.isEmpty {
            emptyStateView
        } else {
            ForEach(sections) { section in
                switch section.key {
                case .greeting:
                    greetingSection(aiText: section.aiText)
                default:
                    standardSection(section)
                }
            }
        }
    }

    // MARK: - Greeting Section

    private func greetingSection(aiText: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.greeting)
                .font(AppTheme.largeTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            if let text = aiText {
                MarkdownTextView(text: text)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Standard Section (title + AI text + cards)

    private func standardSection(_ section: UnifiedBriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.key.displayTitle)
                .font(AppTheme.largeTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            if let text = section.aiText {
                MarkdownTextView(text: text)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(4)
            }

            ForEach(section.items) { item in
                if let taskGID = item.taskGID, let accountID = item.accountID {
                    NavigationLink(value: TaskDestination(taskID: taskGID, accountID: accountID)) {
                        BriefingTaskCardView(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    BriefingItemCardView(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.greeting)
                .font(AppTheme.largeTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            Text(viewModel.currentBriefingType == .morning
                 ? "No tasks or meetings found for today."
                 : "No activity recorded today.")
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textSecondary)

            Text("Connect your accounts in Settings to see your data here.")
                .font(AppTheme.captionFont)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading

    private var briefingLoadingView: some View {
        VStack(alignment: .leading, spacing: 36) {
            // Greeting shimmer
            VStack(alignment: .leading, spacing: 14) {
                ShimmerView()
                    .frame(width: 200, height: 32)
                ShimmerView()
                    .frame(height: 48)
            }

            // Section shimmers
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 16) {
                    ShimmerView()
                        .frame(width: 180, height: 28)
                    ShimmerView()
                        .frame(height: 40)
                    // Card-shaped shimmers
                    ForEach(0..<2, id: \.self) { _ in
                        ShimmerView()
                            .frame(height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard))
                    }
                }
            }
        }
    }
}

// MARK: - Task Card View (tappable, with emoji)

struct BriefingTaskCardView: View {
    let item: BriefingItem

    var body: some View {
        HStack(spacing: 12) {
            // Emoji
            if let emoji = item.emoji {
                Text(emoji)
                    .font(.title2)
            }

            // Title + subtitle + badge
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.bodyFont)
                    .fontWeight(item.urgency == .critical ? .semibold : .medium)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                // Project badge
                if let badge = item.badge {
                    WorkspaceBadge(text: badge.text, color: badgeSwiftUIColor(badge.color))
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.adaptiveCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard)
                .stroke(urgencyBorderColor, lineWidth: item.urgency == .normal ? 0 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var urgencyBorderColor: Color {
        switch item.urgency {
        case .normal: return .clear
        case .warning: return AppTheme.urgencyOrange.opacity(0.4)
        case .critical: return AppTheme.urgencyRed.opacity(0.4)
        }
    }

    private func badgeSwiftUIColor(_ color: BriefingItem.BadgeInfo.BadgeColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return AppTheme.urgencyGreen
        case .orange: return AppTheme.urgencyOrange
        case .red: return AppTheme.urgencyRed
        case .purple: return AppTheme.badgeGranola
        case .gray: return AppTheme.textSecondary
        }
    }
}

// MARK: - Item Card View (non-tappable, for calendar events / empty states)

struct BriefingItemCardView: View {
    let item: BriefingItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Urgency dot
            Circle()
                .fill(urgencyColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            // Title + subtitle + badge
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.bodyFont)
                    .fontWeight(item.urgency == .critical ? .semibold : .regular)
                    .foregroundStyle(AppTheme.textPrimary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                // Project badge
                if let badge = item.badge {
                    WorkspaceBadge(text: badge.text, color: badgeSwiftUIColor(badge.color))
                }
            }

            Spacer()
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.adaptiveCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var urgencyColor: Color {
        switch item.urgency {
        case .normal: return AppTheme.urgencyGreen
        case .warning: return AppTheme.urgencyOrange
        case .critical: return AppTheme.urgencyRed
        }
    }

    private func badgeSwiftUIColor(_ color: BriefingItem.BadgeInfo.BadgeColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return AppTheme.urgencyGreen
        case .orange: return AppTheme.urgencyOrange
        case .red: return AppTheme.urgencyRed
        case .purple: return AppTheme.badgeGranola
        case .gray: return AppTheme.textSecondary
        }
    }
}
