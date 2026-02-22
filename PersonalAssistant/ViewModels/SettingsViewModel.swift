import Foundation

@Observable
@MainActor
final class SettingsViewModel {
    // Asana
    var isAsanaConnected: Bool { TokenManager.shared.isAsanaAuthenticated }
    var asanaUser: AsanaUser?
    var asanaWorkspaces: [AsanaWorkspace] = []
    var asanaToken: String = ""
    var isSavingAsana = false
    var asanaError: String?

    // Granola
    var granolaAPIKey: String = ""
    var isGranolaConfigured: Bool {
        (try? TokenManager.shared.getGranolaAPIKey()) != nil
    }
    var granolaError: String?

    // Claude
    var claudeAPIKey: String = ""
    var isClaudeConfigured: Bool {
        (try? TokenManager.shared.getClaudeAPIKey()) != nil
    }
    var claudeError: String?
    var selectedModel: ClaudeAPIClient.Model = .haiku

    // Calendar
    var isCalendarAuthorized: Bool {
        CalendarService.shared.permissionStatus == .authorized
    }
    var selectedCalendarCount: Int {
        CalendarService.shared.selectedCalendarIDs.count
    }
    var calendarStatusText: String {
        guard isCalendarAuthorized else { return "Not configured" }
        if selectedCalendarCount == 0 { return "No calendars selected" }
        return "\(selectedCalendarCount) calendar\(selectedCalendarCount == 1 ? "" : "s") selected"
    }

    // Meeting Notes (local Obsidian)
    var isMeetingNotesConfigured: Bool = false
    var meetingNotesFolderName: String?
    var meetingNotesFileCount: Int = 0
    var meetingNotesError: String?

    private let tokenManager = TokenManager.shared
    private let asana = AsanaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared

    // MARK: - Asana

    func saveAsanaToken() async {
        let token = asanaToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isSavingAsana = true
        asanaError = nil

        do {
            try tokenManager.storeAsanaToken(token)
            asanaToken = "" // Clear from memory

            // Verify by fetching user info
            asanaUser = try await asana.getCurrentUser()
            asanaWorkspaces = try await asana.getWorkspaces()
        } catch {
            try? tokenManager.clearAsanaTokens()
            asanaError = "Invalid token: \(error.localizedDescription)"
        }

        isSavingAsana = false
    }

    func disconnectAsana() {
        try? tokenManager.clearAsanaTokens()
        asanaUser = nil
        asanaWorkspaces = []
    }

    func loadAsanaInfo() async {
        guard isAsanaConnected else { return }
        do {
            asanaUser = try await asana.getCurrentUser()
            asanaWorkspaces = try await asana.getWorkspaces()
        } catch {
            asanaError = error.localizedDescription
        }
    }

    // MARK: - Granola

    func saveGranolaAPIKey() {
        granolaError = nil
        do {
            if granolaAPIKey.isEmpty {
                try tokenManager.clearGranolaAPIKey()
            } else {
                try tokenManager.storeGranolaAPIKey(granolaAPIKey)
            }
            granolaAPIKey = "" // Clear from memory
        } catch {
            granolaError = error.localizedDescription
        }
    }

    func clearGranolaAPIKey() {
        try? tokenManager.clearGranolaAPIKey()
        granolaAPIKey = ""
    }

    // MARK: - Claude

    func saveClaudeAPIKey() {
        claudeError = nil
        do {
            if claudeAPIKey.isEmpty {
                try tokenManager.clearClaudeAPIKey()
            } else {
                try tokenManager.storeClaudeAPIKey(claudeAPIKey)
            }
            claudeAPIKey = "" // Clear from memory
        } catch {
            claudeError = error.localizedDescription
        }
    }

    func clearClaudeAPIKey() {
        try? tokenManager.clearClaudeAPIKey()
        claudeAPIKey = ""
    }

    // MARK: - Meeting Notes

    func refreshMeetingNotesStatus() {
        isMeetingNotesConfigured = meetingNotes.isConfigured
        meetingNotesFolderName = meetingNotes.folderName
        meetingNotesFileCount = meetingNotes.fileCount()
    }

    func selectMeetingNotesFolder(url: URL) {
        meetingNotesError = nil
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            try meetingNotes.setFolder(url: url)
            refreshMeetingNotesStatus()
        } catch {
            meetingNotesError = error.localizedDescription
        }
    }

    func clearMeetingNotesFolder() {
        meetingNotes.clearFolder()
        meetingNotesError = nil
        refreshMeetingNotesStatus()
    }
}
