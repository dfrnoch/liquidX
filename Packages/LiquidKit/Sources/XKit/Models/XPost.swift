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
    public var quoted: XQuotedPost?
    public var card: XLinkCard?

    public init(
        id: String,
        author: XUser,
        createdAt: Date,
        text: AttributedString,
        media: [XMedia] = [],
        metrics: Metrics = Metrics(),
        conversationID: String? = nil,
        replyingTo: [String] = [],
        quoted: XQuotedPost? = nil,
        card: XLinkCard? = nil
    ) {
        self.id = id
        self.author = author
        self.createdAt = createdAt
        self.text = text
        self.media = media
        self.metrics = metrics
        self.conversationID = conversationID
        self.replyingTo = replyingTo
        self.quoted = quoted
        self.card = card
    }

    public var url: URL {
        URL(string: "https://x.com/\(author.username)/status/\(id)")!
    }

    public var plainText: String { String(text.characters) }
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
