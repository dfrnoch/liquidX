public import Foundation

public enum XAPIError: Error, Hashable, Sendable, LocalizedError {
    case cancelled
    case unauthorized
    case authorization(String)
    case rateLimited(resetsAt: Date?)
    case forbidden(String)
    case notFound
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            String(localized: "Sign-in was cancelled.")
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.")
        case .authorization(let message):
            message
        case .rateLimited(let resetsAt):
            if let resetsAt {
                String(localized: "X's rate limit was reached. Try again \(resetsAt.formatted(.relative(presentation: .named))).")
            } else {
                String(localized: "X's rate limit was reached. Try again in a few minutes.")
            }
        case .forbidden(let message):
            message
        case .notFound:
            String(localized: "This content isn't available.")
        case .server(let status, let message):
            message ?? String(localized: "X returned an error (\(status)).")
        case .transport(let message):
            message
        case .decoding(let what):
            String(localized: "Couldn't read X's response (\(what)).")
        }
    }
}

/// Which slice of a timeline to load.
public enum PageRequest: Hashable, Sendable {
    /// The newest page. With `since`, only posts newer than that ID.
    case newest(since: String?)
    /// The page after a previous page's `nextCursor`.
    case older(cursor: String)
}

public struct TimelinePage: Hashable, Sendable, Codable {
    public var items: [XTimelineItem]
    public var nextCursor: String?
    /// `true` when a `since` request filled a whole page: there may be a gap
    /// between this page and what is already on screen.
    public var mayHaveGap: Bool

    public init(items: [XTimelineItem], nextCursor: String?, mayHaveGap: Bool = false) {
        self.items = items
        self.nextCursor = nextCursor
        self.mayHaveGap = mayHaveGap
    }
}

public enum HomeFeed: String, Hashable, Sendable, Codable, CaseIterable {
    /// X's ranked "For you" timeline (x.com web session only).
    case forYou
    /// Reverse-chronological posts from accounts you follow.
    case following
}

public struct HomeFilter: Hashable, Sendable, Codable {
    public var hideReplies: Bool
    public var hideReposts: Bool
    public var feed: HomeFeed

    public init(hideReplies: Bool = false, hideReposts: Bool = false, feed: HomeFeed = .following) {
        self.hideReplies = hideReplies
        self.hideReposts = hideReposts
        self.feed = feed
    }
}

/// Search result tabs, named after x.com's `SearchTimeline` products.
public enum SearchKind: String, Hashable, Sendable, CaseIterable {
    case top = "Top"
    case latest = "Latest"
    case people = "People"
    case media = "Media"
}

public struct UserPage: Hashable, Sendable {
    public var users: [XUser]
    public var nextCursor: String?

    public init(users: [XUser], nextCursor: String?) {
        self.users = users
        self.nextCursor = nextCursor
    }
}

/// Typeahead results while typing a search.
public struct SearchSuggestions: Hashable, Sendable {
    public var users: [XUser]
    public var topics: [String]

    public init(users: [XUser] = [], topics: [String] = []) {
        self.users = users
        self.topics = topics
    }

    public var isEmpty: Bool { users.isEmpty && topics.isEmpty }
}

/// How LiquidX talks to X.
public enum ConnectionKind: String, Sendable {
    case officialAPI
    case webSession
    case demo
}

/// Everything the interface needs from X. `XClient` talks to the real API;
/// `DemoService` serves bundled sample data so the app can be explored (and
/// screenshotted, and tested) without an X developer account.
public protocol XService: Sendable {
    var isDemo: Bool { get }
    var connection: ConnectionKind { get }
    /// Feeds the home timeline can show; the first is the default.
    var homeFeeds: [HomeFeed] { get }

    func me() async throws -> XUser
    func homeTimeline(_ page: PageRequest, filter: HomeFilter) async throws -> TimelinePage
    func posts(of userID: String, _ page: PageRequest, includeReplies: Bool) async throws -> TimelinePage
    func mentions(_ page: PageRequest) async throws -> TimelinePage
    func bookmarks(_ page: PageRequest) async throws -> TimelinePage
    /// Search result tabs this connection supports, in display order.
    var searchKinds: [SearchKind] { get }
    func search(_ query: String, kind: SearchKind, _ page: PageRequest) async throws -> TimelinePage
    func searchUsers(_ query: String, _ page: PageRequest) async throws -> UserPage
    func searchSuggestions(_ query: String) async throws -> SearchSuggestions
    func replies(to post: XPost) async throws -> [XTimelineItem]
    func post(id: String) async throws -> XPost
    func user(username: String) async throws -> XUser
    func trends() async throws -> [XTrend]
    /// The post's text in `language` (a code such as "en"), sent again each
    /// time more of it arrives. nil when the connection can't translate, as
    /// the official API can't; the interface then translates on the device.
    func translation(of post: XPost, into language: String) -> AsyncThrowingStream<AttributedString, any Error>?

    func setLiked(_ liked: Bool, postID: String) async throws
    func setReposted(_ reposted: Bool, postID: String) async throws
    func setBookmarked(_ bookmarked: Bool, postID: String) async throws
    func setFollowing(_ following: Bool, userID: String) async throws
    func createPost(text: String, replyingTo: String?) async throws -> XPost

    func signOut() async
}

extension XService {
    public var connection: ConnectionKind { isDemo ? .demo : .officialAPI }
    public var homeFeeds: [HomeFeed] { [.following] }
    public var searchKinds: [SearchKind] { [.latest] }

    public func search(_ query: String, _ page: PageRequest) async throws -> TimelinePage {
        try await search(query, kind: .latest, page)
    }

    public func searchUsers(_ query: String, _ page: PageRequest) async throws -> UserPage {
        UserPage(users: [], nextCursor: nil)
    }

    public func searchSuggestions(_ query: String) async throws -> SearchSuggestions {
        SearchSuggestions()
    }

    public func translation(of post: XPost, into language: String) -> AsyncThrowingStream<AttributedString, any Error>? {
        nil
    }
}
