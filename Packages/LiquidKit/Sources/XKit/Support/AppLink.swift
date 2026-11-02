public import Foundation

/// In-app destinations encoded as `liquidx://` URLs, so links inside rendered
/// post text (mentions, hashtags) can be routed by an `OpenURLAction`.
public enum AppLink: Hashable, Sendable {
    case user(String)
    case search(String)

    public static let scheme = "liquidx"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .user(let username):
            components.host = "user"
            components.path = "/\(username)"
        case .search(let query):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "user":
            let name = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !name.isEmpty else { return nil }
            self = .user(name)
        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
            guard let query, !query.isEmpty else { return nil }
            self = .search(query)
        default:
            return nil
        }
    }

    /// Recognizes x.com / twitter.com profile links so they open in the app too.
    public init?(webURL url: URL) {
        guard let host = url.host()?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host)
        else { return nil }
        let parts = url.path().split(separator: "/")
        guard parts.count == 1 else { return nil }
        let name = String(parts[0])
        let reserved: Set<String> = ["home", "explore", "search", "i", "settings", "messages", "notifications", "compose"]
        guard !reserved.contains(name.lowercased()), name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        self = .user(name)
    }
}
