import Foundation

@Observable
final class TokenManager {
    static let shared = TokenManager()

    private(set) var isAsanaAuthenticated = false
    private(set) var asanaAccessToken: String?

    private let keychain = KeychainService.shared

    private init() {
        loadStoredTokens()
    }

    // MARK: - Asana Token (Personal Access Token)

    func storeAsanaToken(_ token: String) throws {
        try keychain.save(token, for: .asanaAccessToken)
        asanaAccessToken = token
        isAsanaAuthenticated = true
    }

    func getValidAsanaToken() async throws -> String {
        guard let token = asanaAccessToken else {
            throw TokenError.noToken
        }
        return token
    }

    func clearAsanaTokens() throws {
        try keychain.delete(key: .asanaAccessToken)
        asanaAccessToken = nil
        isAsanaAuthenticated = false
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

    private func loadStoredTokens() {
        do {
            asanaAccessToken = try keychain.loadString(for: .asanaAccessToken)
            isAsanaAuthenticated = asanaAccessToken != nil
        } catch {
            isAsanaAuthenticated = false
        }
    }
}

enum TokenError: LocalizedError {
    case noToken

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token available. Please add your Asana token in Settings."
        }
    }
}
