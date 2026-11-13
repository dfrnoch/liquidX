public import Foundation

/// A single post. Text is pre-rendered into an `AttributedString` once, when the
/// post is built, so rows never parse entities while scrolling.
public struct XPost: Identifiable, Hashable, Sendable, Codable {
    public struct Metrics: Hashable, Sendable, Codable {
        public var replies: Int
        public var reposts: Int
        public var likes: Int
        public var quotes: Int
        public var bookmarks: Int
        public var views: Int?

        public init(replies: Int = 0, reposts: Int = 0, likes: Int = 0, quotes: Int = 0, bookmarks: Int = 0, views: Int? = nil) {
            self.replies = replies
            self.reposts = reposts
            self.likes = likes
            self.quotes = quotes
            self.bookmarks = bookmarks
            self.views = views
        }
    }

    public var id: String
    public var author: XUser
    public var createdAt: Date
    public var text: AttributedString
    public var media: [XMedia]
    public var metrics: Metrics
    public var conversationID: String?
    /// Usernames this post replies to (without "@").
    public var replyingTo: [String]
    /// The post this one replies to.
    public var replyToID: String?
    public var quoted: XQuotedPost?
    public var card: XLinkCard?
    /// The signed-in account's own engagement, when the source reports it
    /// (the x.com web API does; the official v2 timeline does not).
    public var viewer: ViewerState?
    /// The language X detected for the text (`lang`), e.g. "it". X uses "und"
    /// and codes such as "qme" (media links only) for text in no language.
    public var language: String?

    public init(
        id: String,
        author: XUser,
        createdAt: Date,
        text: AttributedString,
        media: [XMedia] = [],
        metrics: Metrics = Metrics(),
        conversationID: String? = nil,
        replyingTo: [String] = [],
        replyToID: String? = nil,
        quoted: XQuotedPost? = nil,
        card: XLinkCard? = nil,
        viewer: ViewerState? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.author = author
        self.createdAt = createdAt
        self.text = text
        self.media = media
        self.metrics = metrics
        self.conversationID = conversationID
        self.replyingTo = replyingTo
        self.replyToID = replyToID
        self.quoted = quoted
        self.card = card
        self.viewer = viewer
        self.language = language
    }

    public var url: URL {
        URL(string: "https://x.com/\(author.username)/status/\(id)")!
    }

    public var plainText: String { String(text.characters) }

    /// X's language as a `Locale.Language`, or nil when the text has none.
    public var spokenLanguage: Locale.Language? {
        guard var code = language?.lowercased(), !code.isEmpty else { return nil }
        // "und", "zxx" and the like, plus X's own "qam", "qct", "qht", "qme", "qst".
        if ["und", "zxx", "art", "mis", "mul"].contains(code) || (code.count == 3 && code.hasPrefix("q")) { return nil }
        // Twitter kept a few retired ISO codes.
        code = ["in": "id", "iw": "he", "ji": "yi"][code] ?? code
        return Locale.Language(identifier: code)
    }

    /// Whether to offer a translation to someone reading in `reader`, as X does
    /// when a post's language isn't the reader's.
    public func isTranslatable(for reader: Locale.Language) -> Bool {
        guard !text.characters.isEmpty, let language = spokenLanguage?.languageCode else { return false }
        return language != reader.languageCode
    }
}

public struct ViewerState: Hashable, Sendable, Codable {
    public var liked: Bool
    public var reposted: Bool
    public var bookmarked: Bool

    public init(liked: Bool = false, reposted: Bool = false, bookmarked: Bool = false) {
        self.liked = liked
        self.reposted = reposted
        self.bookmarked = bookmarked
    }
}

/// A quoted post, one level deep (X does not render quotes of quotes inline).
public struct XQuotedPost: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var author: XUser
    public var createdAt: Date
    public var text: AttributedString
    public var media: [XMedia]

    public init(id: String, author: XUser, createdAt: Date, text: AttributedString, media: [XMedia] = []) {
        self.id = id
        self.author = author
        self.createdAt = createdAt
        self.text = text
        self.media = media
    }
}

/// Preview for the first external link in a post, from the API's URL unwinding.
public struct XLinkCard: Hashable, Sendable, Codable {
    public var url: URL
    public var host: String
    public var title: String
    public var summary: String?
    public var imageURL: URL?

    public init(url: URL, host: String, title: String, summary: String? = nil, imageURL: URL? = nil) {
        self.url = url
        self.host = host
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
    }
}

/// One row of a timeline. A repost keeps its own identity (`id`) so the same
/// post reposted by two people produces two distinct rows.
public struct XTimelineItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var post: XPost
    public var repostedBy: XUser?

    public init(id: String, post: XPost, repostedBy: XUser? = nil) {
        self.id = id
        self.post = post
        self.repostedBy = repostedBy
    }

    public init(_ post: XPost) {
        self.init(id: post.id, post: post)
    }
}

/// Which rows of a list are joined into a thread: a reply placed right after
/// the post it answers (as x.com sends conversations) continues it.
public struct ThreadLinks: Sendable {
    /// Rows followed by a reply to them.
    public private(set) var continuesBelow: Set<String> = []
    /// Replies right after the post they answer.
    public private(set) var continuesAbove: Set<String> = []

    public init(_ items: [XTimelineItem]) {
        for (parent, reply) in zip(items, items.dropFirst())
        where reply.repostedBy == nil && reply.post.replyToID == parent.post.id {
            continuesBelow.insert(parent.id)
            continuesAbove.insert(reply.id)
        }
    }
}

public struct XTrend: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public var name: String
    public var category: String?
    public var postCount: Int?

    public init(name: String, category: String? = nil, postCount: Int? = nil) {
        self.name = name
        self.category = category
        self.postCount = postCount
    }
}
