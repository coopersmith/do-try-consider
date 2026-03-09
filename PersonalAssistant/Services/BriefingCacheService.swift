import Foundation

struct CachedBriefing: Codable {
    let briefing: Briefing
    let cachedAt: Date
    let briefingDate: String
    let briefingPeriod: String // "morning" or "evening"
}

final class BriefingCacheService: Sendable {
    static let shared = BriefingCacheService()

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.cooperliskasmith.DoTryConsider", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("briefing_cache.json")
    }()

    private init() {}

    func save(_ briefing: Briefing) {
        let dateStr = DateFormatting.isoDateOnly(Date())
        let period = briefing.type == .morning ? "morning" : "evening"
        let cached = CachedBriefing(
            briefing: briefing,
            cachedAt: Date(),
            briefingDate: dateStr,
            briefingPeriod: period
        )
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache write failure is non-critical
        }
    }

    func load() -> CachedBriefing? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedBriefing.self, from: data) else {
            return nil
        }
        return cached
    }

    func isStale(_ cached: CachedBriefing) -> Bool {
        let now = Date()
        let todayStr = DateFormatting.isoDateOnly(now)

        // Different day — always stale
        if cached.briefingDate != todayStr { return true }

        // Different time period (morning vs evening)
        let hour = Calendar.current.component(.hour, from: now)
        let currentPeriod = hour < 16 ? "morning" : "evening"
        if cached.briefingPeriod != currentPeriod { return true }

        // Older than 2 hours
        let age = now.timeIntervalSince(cached.cachedAt)
        if age > 2 * 60 * 60 { return true }

        return false
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
