import Foundation

@Observable
@MainActor
final class BriefingViewModel {
    var briefing: Briefing?
    var isLoading = false
    var isRefreshing = false
    var isCacheStale = false
    var lastCachedAt: Date?
    var error: String?

    private let briefingService = BriefingService()
    private let cache = BriefingCacheService.shared

    var currentBriefingType: Briefing.BriefingType {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 16 ? .morning : .evening
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }

    var lastUpdatedText: String? {
        guard let cachedAt = lastCachedAt else { return nil }
        let minutes = Int(-cachedAt.timeIntervalSinceNow / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        return "Updated \(hours)h ago"
    }

    var unifiedSections: [UnifiedBriefingSection] {
        guard let briefing = briefing else { return [] }

        var sections: [UnifiedBriefingSection] = []

        // Greeting — AI progress card as body text
        let progressText = briefing.aiSummaryCards.first(where: { $0.category == .progress })?.content
        sections.append(UnifiedBriefingSection(key: .greeting, aiText: progressText, items: []))

        // Needs Your Attention — overdue/actions AI text + overdue/due-today/still-open data items
        let attentionCards = briefing.aiSummaryCards.filter { $0.category == .overdue || $0.category == .actions || $0.category == .priorities }
        let attentionText = attentionCards.isEmpty ? nil : attentionCards.map(\.content).joined(separator: "\n\n")
        let attentionItems = briefing.sections
            .filter { ["Overdue", "Due Today", "Still Open"].contains($0.title) }
            .flatMap(\.items)
        if attentionText != nil || !attentionItems.isEmpty {
            sections.append(UnifiedBriefingSection(key: .attention, aiText: attentionText, items: attentionItems))
        }

        // Completed Today — evening only, data section
        let completedItems = briefing.sections.first(where: { $0.title == "Completed Today" })?.items ?? []
        if !completedItems.isEmpty {
            sections.append(UnifiedBriefingSection(key: .completedToday, aiText: nil, items: completedItems))
        }

        // Today's Meetings — AI meeting insights + calendar data items
        let meetingsText = briefing.aiSummaryCards.first(where: { $0.category == .meetings })?.content
        let meetingItems = briefing.sections.first(where: { $0.title == "Today's Meetings" })?.items ?? []
        if meetingsText != nil || !meetingItems.isEmpty {
            sections.append(UnifiedBriefingSection(key: .meetings, aiText: meetingsText, items: meetingItems))
        }

        // Coming This Week — AI upcoming card + data items
        let upcomingText = briefing.aiSummaryCards.first(where: { $0.category == .upcoming })?.content
        let upcomingItems = briefing.sections.first(where: { $0.title == "Coming This Week" })?.items ?? []
        if upcomingText != nil || !upcomingItems.isEmpty {
            sections.append(UnifiedBriefingSection(key: .comingThisWeek, aiText: upcomingText, items: upcomingItems))
        }

        // Fallback: if no parsed AI cards, show raw summary in greeting
        if briefing.aiSummaryCards.isEmpty, let summary = briefing.aiSummary, sections.count == 1 {
            sections[0] = UnifiedBriefingSection(key: .greeting, aiText: summary, items: [])
        }

        return sections
    }

    func loadBriefing() async {
        guard !isLoading else { return }

        // Try loading from disk cache first
        if briefing == nil, let cached = cache.load() {
            briefing = cached.briefing
            lastCachedAt = cached.cachedAt
            isCacheStale = cache.isStale(cached)

            // If cache is fresh, we're done
            if !isCacheStale { return }

            // Cache is stale — refresh in background without showing loading skeleton
            await refreshInBackground()
            return
        }

        // No cache — full loading with skeleton
        isLoading = true
        error = nil

        do {
            let result = try await briefingService.generateBriefing(type: currentBriefingType)
            briefing = result
            lastCachedAt = Date()
            isCacheStale = false
            cache.save(result)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        // Keep existing briefing visible while refreshing
        await refreshInBackground()
    }

    func forceRefresh() async {
        await refreshInBackground()
    }

    private func refreshInBackground() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        do {
            let result = try await briefingService.generateBriefing(type: currentBriefingType)
            briefing = result
            lastCachedAt = Date()
            isCacheStale = false
            cache.save(result)
            error = nil
        } catch {
            // If we already have cached data, don't overwrite with error
            if briefing == nil {
                self.error = error.localizedDescription
            }
        }

        isRefreshing = false
    }
}
