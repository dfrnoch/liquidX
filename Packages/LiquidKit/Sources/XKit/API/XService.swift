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

public struct HomeFilter: Hashable, Sendable, Codable {
    public var hideReplies: Bool
    public var hideReposts: Bool

    public init(hideReplies: Bool = false, hideReposts: Bool = false) {
        self.hideReplies = hideReplies
        self.hideReposts = hideReposts
    }
}

/// Everything the interface needs from X. `XClient` talks to the real API;
/// `DemoService` serves bundled sample data so the app can be explored (and
/// screenshotted, and tested) without an X developer account.
public protocol XService: Sendable {
    var isDemo: Bool { get }

    func me() async throws -> XUser
    func homeTimeline(_ page: PageRequest, filter: HomeFilter) async throws -> TimelinePage
    func posts(of userID: String, _ page: PageRequest, includeReplies: Bool) async throws -> TimelinePage
    func mentions(_ page: PageRequest) async throws -> TimelinePage
    func bookmarks(_ page: PageRequest) async throws -> TimelinePage
    func search(_ query: String, _ page: PageRequest) async throws -> TimelinePage
    func replies(to post: XPost) async throws -> [XTimelineItem]
    func post(id: String) async throws -> XPost
    func user(username: String) async throws -> XUser
    func trends() async throws -> [XTrend]

    func setLiked(_ liked: Bool, postID: String) async throws
    func setReposted(_ reposted: Bool, postID: String) async throws
    func setBookmarked(_ bookmarked: Bool, postID: String) async throws
    func setFollowing(_ following: Bool, userID: String) async throws
    func createPost(text: String, replyingTo: String?) async throws -> XPost

    func signOut() async
}
