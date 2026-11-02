public import Foundation
import CryptoKit

/// OAuth 2.0 Authorization Code flow with PKCE, as a *public* client: LiquidX
/// ships no client secret. Every user (or fork) brings the Client ID of an app
/// registered at developer.x.com with type "Native App".
public struct OAuthConfiguration: Hashable, Sendable {
    public static let callbackScheme = AppLink.scheme
    public static let redirectURI = URL(string: "\(callbackScheme)://oauth-callback")!
    public static let authorizeURL = URL(string: "https://x.com/i/oauth2/authorize")!
    public static let tokenURL = URL(string: "https://api.x.com/2/oauth2/token")!
    public static let revokeURL = URL(string: "https://api.x.com/2/oauth2/revoke")!

    public static let scopes = [
        "tweet.read", "tweet.write", "users.read",
        "like.read", "like.write",
        "follows.read", "follows.write",
        "bookmark.read", "bookmark.write",
        "offline.access",
    ]

    public var clientID: String

    public init(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct OAuthTokens: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var scope: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    func isExpired(leeway: TimeInterval = 60, now: Date = .now) -> Bool {
        expiresAt.addingTimeInterval(-leeway) <= now
    }
}

/// One in-flight authorization: the browser URL plus the secrets needed to
/// validate the callback and redeem the code.
public struct AuthorizationRequest: Sendable {
    public let url: URL
    public let state: String
    let verifier: String
    let configuration: OAuthConfiguration

    public init(configuration: OAuthConfiguration) {
        self.configuration = configuration
        verifier = PKCE.makeVerifier()
        state = PKCE.makeVerifier(length: 32)
        var components = URLComponents(url: OAuthConfiguration.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConfiguration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: OAuthConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        url = components.url!
    }

    /// Validates the redirect and returns the authorization code.
    public func code(from callback: URL) throws(XAPIError) -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? .cancelled : .authorization(value("error_description") ?? error)
        }
        guard value("state") == state else { throw .authorization("The sign-in response did not match this request.") }
        guard let code = value("code"), !code.isEmpty else { throw .authorization("X did not return an authorization code.") }
        return code
    }
}

enum PKCE {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func makeVerifier(length: Int = 64) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Token endpoint calls. Public clients send `client_id` in the form body.
enum TokenEndpoint {
    private struct Response: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Double?
        var scope: String?
    }

    static func redeem(code: String, for request: AuthorizationRequest, session: URLSession) async throws(XAPIError) -> OAuthTokens {
        try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConfiguration.redirectURI.absoluteString,
            "code_verifier": request.verifier,
            "client_id": request.configuration.clientID,
        ], session: session)
    }

    static func refresh(_ refreshToken: String, clientID: String, session: URLSession) async throws(XAPIError) -> OAuthTokens {
        try await post([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ], session: session)
    }

    static func revoke(_ token: String, clientID: String, session: URLSession) async {
        var request = URLRequest(url: OAuthConfiguration.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["token": token, "token_type_hint": "access_token", "client_id": clientID])
        _ = try? await session.data(for: request)
    }

    private static func post(_ fields: [String: String], session: URLSession) async throws(XAPIError) -> OAuthTokens {
        var request = URLRequest(url: OAuthConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Problem: Decodable { var error: String?; var error_description: String? }
            let problem = try? JSONDecoder().decode(Problem.self, from: data)
            if problem?.error == "invalid_grant" || problem?.error == "invalid_request" && fields["grant_type"] == "refresh_token" {
                throw .unauthorized
            }
            throw .authorization(problem?.error_description ?? problem?.error ?? "Token request failed (\(status)).")
        }
        guard let body = try? JSONDecoder().decode(Response.self, from: data) else {
            throw .decoding("token response")
        }
        return OAuthTokens(
            accessToken: body.access_token,
            refreshToken: body.refresh_token ?? fields["refresh_token"],
            expiresAt: Date.now.addingTimeInterval(body.expires_in ?? 7_200),
            scope: body.scope
        )
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}
