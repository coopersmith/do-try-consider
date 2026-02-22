import SwiftUI

struct BriefingView: View {
    @State private var viewModel = BriefingViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    if viewModel.isLoading && viewModel.briefing == nil {
                        briefingLoadingView
                    } else if let error = viewModel.error, viewModel.briefing == nil {
                        ErrorStateView(error) {
                            Task { await viewModel.loadBriefing() }
                        }
                    } else if let briefing = viewModel.briefing {
                        briefingContent(briefing)
                    }
                }
                .padding()
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
        }
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: Briefing) -> some View {
        // Greeting
        Text(viewModel.greeting)
            .font(AppTheme.largeTitleFont)
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

        // AI Summary Cards — one per category
        if !briefing.aiSummaryCards.isEmpty {
            ForEach(briefing.aiSummaryCards) { card in
                BriefingSummaryCardView(card: card)
            }
        } else if let summary = briefing.aiSummary {
            // Fallback: single card if parsing yielded nothing
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Summary", systemImage: "sparkles")
                    .font(AppTheme.captionFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)

                MarkdownTextView(text: summary)
                    .font(AppTheme.subheadlineFont)
            }
            .padding(AppTheme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard)
                    .fill(AppTheme.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard)
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
            )
        }

        // Sections
        ForEach(briefing.sections) { section in
            BriefingSectionView(section: section)
        }
    }

    // MARK: - Loading

    private var briefingLoadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerView()
                        .frame(width: 120, height: 20)
                    ShimmerView()
                        .frame(height: 60)
                    ShimmerView()
                        .frame(height: 40)
                }
                .padding(AppTheme.cardPadding)
                .background(AppTheme.adaptiveCard)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard))
            }
        }
    }
}

// MARK: - AI Summary Card View

struct BriefingSummaryCardView: View {
    let card: BriefingSummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subtle category label
            Label(card.category.rawValue, systemImage: card.category.icon)
                .font(AppTheme.captionFont)
                .fontWeight(.semibold)
                .foregroundStyle(card.category.accentColor)

            // Card content
            MarkdownTextView(text: card.content)
                .font(AppTheme.subheadlineFont)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard)
                .fill(AppTheme.adaptiveCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusCard)
                .stroke(card.category.accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Section View

struct BriefingSectionView: View {
    let section: BriefingSection

    var body: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                Label(section.title, systemImage: section.icon)
                    .font(AppTheme.sectionHeaderFont)

                // Items
                ForEach(section.items) { item in
                    BriefingItemRow(item: item)
                }
            }
        }
    }
}

// MARK: - Item Row

struct BriefingItemRow: View {
    let item: BriefingItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Urgency indicator
            Circle()
                .fill(urgencyColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AppTheme.subheadlineFont)
                    .fontWeight(item.urgency == .critical ? .semibold : .regular)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            if let badge = item.badge {
                WorkspaceBadge(text: badge.text, color: badgeSwiftUIColor(badge.color))
            }
        }
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
