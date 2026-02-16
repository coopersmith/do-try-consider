import Foundation

@Observable
@MainActor
final class BriefingViewModel {
    var briefing: Briefing?
    var isLoading = false
    var error: String?

    private let briefingService = BriefingService()

    var currentBriefingType: Briefing.BriefingType {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 16 ? .morning : .evening
    }

    func loadBriefing() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            briefing = try await briefingService.generateBriefing(type: currentBriefingType)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        briefing = nil
        await loadBriefing()
    }
}
