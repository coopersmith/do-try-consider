import AuthenticationServices
import CryptoKit
import Foundation

@Observable
final class AsanaAuthService: NSObject {
    static let shared = AsanaAuthService()

    // MARK: - Configuration
    // Register your app at https://app.asana.com/0/developer-console
    // Set redirect URI to: personalassistant://oauth-callback
    private let clientID = "1213289525288309"
    private let clientSecret = "816602782b952dbe93a2fc11eee51142"
    private let redirectURI = "https://localhost/oauth-callback"
    private let authorizeURL = "https://app.asana.com/-/oauth_authorize"
    private let tokenURL = "https://app.asana.com/-/oauth_token"

    private(set) var isAuthenticating = false

    private var authContinuation: CheckedContinuation<URL, Error>?
    private var codeVerifier: String?

    private override init() {
        super.init()
    }

    // MARK: - OAuth2 + PKCE Flow

    func authenticate() async throws -> AsanaTokenResponse {
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Generate PKCE challenge
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        // Build authorization URL
        let state = UUID().uuidString
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "default"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let authURL = components.url!

        // Present auth session
        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            authContinuation = continuation

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "https"
            ) { [weak self] url, error in
                if let error {
                    self?.authContinuation?.resume(throwing: error)
                    self?.authContinuation = nil
                    return
                }
                guard let url else {
                    self?.authContinuation?.resume(throwing: AsanaAuthError.noCallbackURL)
                    self?.authContinuation = nil
                    return
                }
                self?.authContinuation?.resume(returning: url)
                self?.authContinuation = nil
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                continuation.resume(throwing: AsanaAuthError.sessionStartFailed)
                authContinuation = nil
            }
        }

        // Extract authorization code from callback
        guard let code = extractCode(from: callbackURL) else {
            throw AsanaAuthError.noAuthorizationCode
        }

        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    func handleCallback(url: URL) {
        // This is called by the app delegate for custom URL scheme handling
        // ASWebAuthenticationSession handles its own callbacks, but this
        // serves as a fallback for deep linking
    }

    func refreshToken(_ refreshToken: String) async throws -> AsanaTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AsanaAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(AsanaTokenResponse.self, from: data)
    }

    // MARK: - Private Methods

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> AsanaTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "code": code,
            "code_verifier": verifier,
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AsanaAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(AsanaTokenResponse.self, from: data)
    }

    private func extractCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AsanaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        if let window = scene?.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return UIWindow(windowScene: scene!)
        #else
        return NSWindow()
        #endif
    }
}

// MARK: - Base64URL Encoding

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Errors

enum AsanaAuthError: LocalizedError {
    case noCallbackURL
    case sessionStartFailed
    case noAuthorizationCode
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .noCallbackURL: return "No callback URL received from Asana."
        case .sessionStartFailed: return "Failed to start authentication session."
        case .noAuthorizationCode: return "No authorization code found in callback."
        case .tokenExchangeFailed: return "Failed to exchange authorization code for tokens."
        }
    }
}
