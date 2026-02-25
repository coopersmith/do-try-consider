import Foundation

@Observable
@MainActor
final class SettingsViewModel {
    // Asana (multi-account)
    var isAsanaConnected: Bool { TokenManager.shared.isAsanaAuthenticated }

    struct AsanaAccountInfo: Identifiable {
        let id: String  // userGID
        let user: AsanaUser
        let workspaces: [AsanaWorkspace]
    }
    var asanaAccountInfos: [AsanaAccountInfo] = []

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

    var asanaStatusText: String {
        let count = tokenManager.asanaAccounts.count
        if count == 0 { return "Not connected" }
        if count == 1 { return "Connected" }
        return "\(count) accounts connected"
    }

    func authenticateWithAsana() async {
        isSavingAsana = true
        asanaError = nil

        do {
            let response = try await AsanaAuthService.shared.authenticate()

            // Fetch user info using a temporary token approach:
            // Store temporarily so getCurrentUser can work, then properly add
            // We need the user info before we can properly store the account.
            // Use the token directly to fetch user info.
            let user = try await fetchUserWithToken(response.accessToken)

            // Check for duplicate
            if tokenManager.asanaAccounts.contains(where: { $0.userGID == user.gid }) {
                // Update existing account tokens
                try tokenManager.addAsanaAccount(response, user: user)
                asanaError = nil
            } else {
                try tokenManager.addAsanaAccount(response, user: user)
            }

            await loadAsanaInfo()
        } catch {
            asanaError = error.localizedDescription
        }

        isSavingAsana = false
    }

    func disconnectAsanaAccount(id: String) {
        try? tokenManager.removeAsanaAccount(id: id)
        asanaAccountInfos.removeAll { $0.id == id }
    }

    func disconnectAllAsana() {
        try? tokenManager.clearAsanaTokens()
        asanaAccountInfos = []
    }

    func loadAsanaInfo() async {
        guard isAsanaConnected else { return }

        var infos: [AsanaAccountInfo] = []

        for account in tokenManager.asanaAccounts {
            do {
                // Handle migration placeholder
                if account.userGID == "migrated" {
                    let user = try await asana.getCurrentUser(accountID: account.userGID)
                    try tokenManager.updateMigratedAccount(user: user)
                    let workspaces = try await asana.getWorkspaces(accountID: user.gid)
                    infos.append(AsanaAccountInfo(id: user.gid, user: user, workspaces: workspaces))
                } else {
                    let user = try await asana.getCurrentUser(accountID: account.userGID)
                    let workspaces = try await asana.getWorkspaces(accountID: account.userGID)
                    infos.append(AsanaAccountInfo(id: account.userGID, user: user, workspaces: workspaces))
                }
            } catch {
                asanaError = error.localizedDescription
            }
        }

        asanaAccountInfos = infos
    }

    /// Fetch user info directly using a bearer token (for initial auth before account is stored)
    private func fetchUserWithToken(_ token: String) async throws -> AsanaUser {
        let url = URL(string: "https://app.asana.com/api/1.0/users/me?opt_fields=name,email,photo,workspaces")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AsanaResponse<AsanaUser>.self, from: data)
        return response.data
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
