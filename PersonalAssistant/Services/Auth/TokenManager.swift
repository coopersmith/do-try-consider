import Foundation

@Observable
final class TokenManager {
    static let shared = TokenManager()

    private(set) var asanaAccounts: [AsanaAccount] = []
    var isAsanaAuthenticated: Bool { !asanaAccounts.isEmpty }

    private let keychain = KeychainService.shared

    private init() {
        loadStoredTokens()
    }

    // MARK: - Asana Multi-Account

    func addAsanaAccount(_ response: AsanaTokenResponse, user: AsanaUser) throws {
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn)).timeIntervalSince1970

        let account = AsanaAccount(
            userGID: user.gid,
            userName: user.name,
            userEmail: user.email,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            tokenExpiresAt: expiresAt
        )

        // Update existing or append new
        if let index = asanaAccounts.firstIndex(where: { $0.userGID == user.gid }) {
            asanaAccounts[index] = account
        } else {
            asanaAccounts.append(account)
        }

        try persistAccounts()
    }

    func getValidToken(for accountID: String) async throws -> String {
        guard let index = asanaAccounts.firstIndex(where: { $0.userGID == accountID }) else {
            throw TokenError.noToken
        }

        let account = asanaAccounts[index]

        // No expiry info — return as-is
        guard let expiresAt = account.tokenExpiresAt else {
            return account.accessToken
        }

        // Token still valid (with 60s buffer)
        let expiryDate = Date(timeIntervalSince1970: expiresAt)
        if expiryDate.timeIntervalSinceNow > 60 {
            return account.accessToken
        }

        // Token expired — refresh
        guard let refreshToken = account.refreshToken else {
            throw TokenError.noToken
        }

        let response = try await AsanaAuthService.shared.refreshToken(refreshToken)
        let newExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn)).timeIntervalSince1970

        asanaAccounts[index].accessToken = response.accessToken
        if let newRefresh = response.refreshToken {
            asanaAccounts[index].refreshToken = newRefresh
        }
        asanaAccounts[index].tokenExpiresAt = newExpiresAt

        try persistAccounts()
        return response.accessToken
    }

    func removeAsanaAccount(id: String) throws {
        asanaAccounts.removeAll { $0.userGID == id }
        try persistAccounts()
    }

    func clearAsanaTokens() throws {
        asanaAccounts = []
        try keychain.delete(key: .asanaAccounts)
        // Clean up legacy keys if present
        try? keychain.delete(key: .asanaAccessToken)
        try? keychain.delete(key: .asanaRefreshToken)
        try? keychain.delete(key: .asanaTokenExpiry)
    }

    /// Update the migrated placeholder account with real user info
    func updateMigratedAccount(user: AsanaUser) throws {
        if let index = asanaAccounts.firstIndex(where: { $0.userGID == "migrated" }) {
            let old = asanaAccounts[index]
            asanaAccounts[index] = AsanaAccount(
                userGID: user.gid,
                userName: user.name,
                userEmail: user.email,
                accessToken: old.accessToken,
                refreshToken: old.refreshToken,
                tokenExpiresAt: old.tokenExpiresAt
            )
            try persistAccounts()
        }
    }

    // MARK: - Granola API Key

    func storeGranolaAPIKey(_ key: String) throws {
        try keychain.save(key, for: .granolaAPIKey)
    }

    func getGranolaAPIKey() throws -> String? {
        try keychain.loadString(for: .granolaAPIKey)
    }

    func clearGranolaAPIKey() throws {
        try keychain.delete(key: .granolaAPIKey)
    }

    // MARK: - Claude API Key

    func storeClaudeAPIKey(_ key: String) throws {
        try keychain.save(key, for: .claudeAPIKey)
    }

    func getClaudeAPIKey() throws -> String? {
        try keychain.loadString(for: .claudeAPIKey)
    }

    func clearClaudeAPIKey() throws {
        try keychain.delete(key: .claudeAPIKey)
    }

    // MARK: - Private

    private func persistAccounts() throws {
        let data = try JSONEncoder().encode(asanaAccounts)
        try keychain.save(data, for: .asanaAccounts)
    }

    private func loadStoredTokens() {
        do {
            // Try new multi-account format first
            if let data = try keychain.loadData(for: .asanaAccounts),
               let accounts = try? JSONDecoder().decode([AsanaAccount].self, from: data),
               !accounts.isEmpty {
                asanaAccounts = accounts
                return
            }

            // Migration: check legacy single-account keys
            if let accessToken = try keychain.loadString(for: .asanaAccessToken) {
                let refreshToken = try? keychain.loadString(for: .asanaRefreshToken)
                var expiresAt: TimeInterval?
                if let expiryString = try keychain.loadString(for: .asanaTokenExpiry),
                   let interval = Double(expiryString) {
                    expiresAt = interval
                }

                let migrated = AsanaAccount(
                    userGID: "migrated",
                    userName: "Asana User",
                    userEmail: nil,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    tokenExpiresAt: expiresAt
                )

                asanaAccounts = [migrated]
                try persistAccounts()

                // Clean up legacy keys
                try? keychain.delete(key: .asanaAccessToken)
                try? keychain.delete(key: .asanaRefreshToken)
                try? keychain.delete(key: .asanaTokenExpiry)
            }
        } catch {
            asanaAccounts = []
        }
    }
}

enum TokenError: LocalizedError {
    case noToken

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token available. Please sign in with Asana in Settings."
        }
    }
}
