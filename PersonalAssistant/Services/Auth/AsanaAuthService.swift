import CryptoKit
import Foundation
import UIKit
import WebKit

@Observable
final class AsanaAuthService: NSObject {
    static let shared = AsanaAuthService()

    // MARK: - Configuration
    // Register your app at https://app.asana.com/0/developer-console
    // Set redirect URI to: https://localhost/oauth-callback
    private let clientID = "1213289525288309"
    private let clientSecret = "816602782b952dbe93a2fc11eee51142"
    private let redirectURI = "https://localhost/oauth-callback"
    private let authorizeURL = "https://app.asana.com/-/oauth_authorize"
    private let tokenURL = "https://app.asana.com/-/oauth_token"

    private(set) var isAuthenticating = false

    private var codeVerifier: String?

    private override init() {
        super.init()
    }

    // MARK: - OAuth2 + PKCE Flow

    @MainActor
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

        // Present OAuth web view and wait for redirect
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let oauthVC = OAuthWebViewController(
                authURL: authURL,
                redirectHost: "localhost",
                redirectPath: "/oauth-callback"
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: AsanaAuthError.noCallbackURL)
                    return
                }
                continuation.resume(returning: url)
            }

            let navController = UINavigationController(rootViewController: oauthVC)
            navController.modalPresentationStyle = .formSheet

            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
                let window = scene.windows.first(where: { $0.isKeyWindow }),
                let rootVC = window.rootViewController else {
                continuation.resume(throwing: AsanaAuthError.sessionStartFailed)
                return
            }

            // Find the topmost presented view controller
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(navController, animated: true)
        }

        // Extract authorization code from callback
        guard let code = extractCode(from: callbackURL) else {
            throw AsanaAuthError.noAuthorizationCode
        }

        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, verifier: verifier)
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

// MARK: - OAuth Web View Controller

private final class OAuthWebViewController: UIViewController, WKNavigationDelegate {
    private let authURL: URL
    private let redirectHost: String
    private let redirectPath: String
    private var completion: ((URL?, Error?) -> Void)?
    private var webView: WKWebView!

    init(authURL: URL, redirectHost: String, redirectPath: String, completion: @escaping (URL?, Error?) -> Void) {
        self.authURL = authURL
        self.redirectHost = redirectHost
        self.redirectPath = redirectPath
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Sign in with Asana"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

        webView.load(URLRequest(url: authURL))
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) {
            self.completion?(nil, AsanaAuthError.sessionStartFailed)
            self.completion = nil
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              url.host == redirectHost,
              url.path == redirectPath else {
            decisionHandler(.allow)
            return
        }

        // Intercept the localhost redirect — extract the auth code
        decisionHandler(.cancel)
        dismiss(animated: true) {
            self.completion?(url, nil)
            self.completion = nil
        }
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
