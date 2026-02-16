import SwiftUI

struct BriefingView: View {
    @State private var viewModel = BriefingViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
            .navigationTitle(viewModel.currentBriefingType.title)
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
        // Header
        VStack(spacing: 4) {
            Text(DateFormatting.fullDate(briefing.generatedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(briefing.type.subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)

        // AI Summary Card
        if let summary = briefing.aiSummary {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                MarkdownTextView(text: summary)
                    .font(.subheadline)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
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
                .padding()
                .background(Color.systemGray6Color)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Section View

struct BriefingSectionView: View {
    let section: BriefingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Label(section.title, systemImage: section.icon)
                .font(.headline)

            // Items
            ForEach(section.items) { item in
                BriefingItemRow(item: item)
            }
        }
        .padding()
        .background(Color.systemGray6Color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .font(.subheadline)
                    .fontWeight(item.urgency == .critical ? .semibold : .regular)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func badgeSwiftUIColor(_ color: BriefingItem.BadgeInfo.BadgeColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}
