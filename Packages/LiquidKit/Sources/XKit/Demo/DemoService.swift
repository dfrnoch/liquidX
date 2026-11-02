public import Foundation

/// Offline `XService` with fictional accounts and posts. Used by "Try the demo",
/// by screenshots, and by UI tests. Images are `demo://` URLs that the interface
/// renders procedurally, so the demo never touches the network.
public actor DemoService: XService {
    public nonisolated let isDemo = true

    private let latency: Duration
    private var home: [XTimelineItem]
    private var liked: Set<String> = []
    private var reposted: Set<String> = []
    private var bookmarked: Set<String> = []
    private var following: Set<String>
    private var nextID = 9_000
    /// Posts that "arrive" one by one on refresh, so the demo feels alive.
    private var arrivals: [XPost]

    public init(latency: Duration = .milliseconds(350), now: Date = .now) {
        self.latency = latency
        home = DemoData.timeline(now: now)
        arrivals = DemoData.arrivals(now: now)
        following = Set(DemoData.people.prefix(6).map(\.id))
    }

    private func pause() async throws {
        try await Task.sleep(for: latency)
    }

    private func paginate(_ items: [XTimelineItem], _ page: PageRequest, size: Int = 12) -> TimelinePage {
        switch page {
        case .newest(let since?):
            let index = items.firstIndex { $0.id == since } ?? items.count
            return TimelinePage(items: Array(items.prefix(index)), nextCursor: nil)
        case .newest(nil):
            return TimelinePage(items: Array(items.prefix(size)), nextCursor: items.count > size ? "\(size)" : nil)
        case .older(let cursor):
            let start = min(Int(cursor) ?? items.count, items.count)
            let end = min(start + size, items.count)
            return TimelinePage(items: Array(items[start..<end]), nextCursor: end < items.count ? "\(end)" : nil)
        }
    }

    public func me() async throws -> XUser { DemoData.me }

    public func homeTimeline(_ page: PageRequest, filter: HomeFilter) async throws -> TimelinePage {
        try await pause()
        if case .newest(.some) = page, !arrivals.isEmpty {
            var post = arrivals.removeFirst()
            post.createdAt = .now
            home.insert(XTimelineItem(post), at: 0)
        }
        let items = home.filter { item in
            !(filter.hideReposts && item.repostedBy != nil) && !(filter.hideReplies && !item.post.replyingTo.isEmpty)
        }
        return paginate(items, page)
    }

    public func posts(of userID: String, _ page: PageRequest, includeReplies: Bool) async throws -> TimelinePage {
        try await pause()
        let items = home
            .filter { ($0.repostedBy?.id ?? $0.post.author.id) == userID }
            .filter { includeReplies || $0.post.replyingTo.isEmpty }
        return paginate(items, page)
    }

    public func mentions(_ page: PageRequest) async throws -> TimelinePage {
        try await pause()
        return paginate(DemoData.mentions(now: .now), page)
    }

    public func bookmarks(_ page: PageRequest) async throws -> TimelinePage {
        try await pause()
        return paginate(home.filter { bookmarked.contains($0.post.id) }, page)
    }

    public func search(_ query: String, _ page: PageRequest) async throws -> TimelinePage {
        try await pause()
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = home.filter { item in
            item.repostedBy == nil && (
                item.post.plainText.lowercased().contains(needle)
                    || item.post.author.name.lowercased().contains(needle)
                    || item.post.author.username.lowercased().contains(needle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))
            )
        }
        return paginate(items, page)
    }

    public func replies(to post: XPost) async throws -> [XTimelineItem] {
        try await pause()
        return DemoData.replies(to: post)
    }

    public func post(id: String) async throws -> XPost {
        guard let item = home.first(where: { $0.post.id == id }) else { throw XAPIError.notFound }
        return item.post
    }

    public func user(username: String) async throws -> XUser {
        try await pause()
        let all = [DemoData.me] + DemoData.people
        guard var user = all.first(where: { $0.username.caseInsensitiveCompare(username) == .orderedSame }) else {
            throw XAPIError.notFound
        }
        if user.id != DemoData.me.id { user.isFollowedByMe = following.contains(user.id) }
        return user
    }

    public func trends() async throws -> [XTrend] {
        try await pause()
        return DemoData.trends
    }

    public func setLiked(_ liked: Bool, postID: String) async throws {
        try await pause()
        if liked { self.liked.insert(postID) } else { self.liked.remove(postID) }
    }

    public func setReposted(_ reposted: Bool, postID: String) async throws {
        try await pause()
        if reposted { self.reposted.insert(postID) } else { self.reposted.remove(postID) }
    }

    public func setBookmarked(_ bookmarked: Bool, postID: String) async throws {
        try await pause()
        if bookmarked { self.bookmarked.insert(postID) } else { self.bookmarked.remove(postID) }
    }

    public func setFollowing(_ following: Bool, userID: String) async throws {
        try await pause()
        if following { self.following.insert(userID) } else { self.following.remove(userID) }
    }

    public func createPost(text: String, replyingTo: String?) async throws -> XPost {
        try await pause()
        nextID += 1
        let post = XPost(
            id: "demo-\(nextID)",
            author: DemoData.me,
            createdAt: .now,
            text: RichText.make(text),
            replyingTo: replyingTo.flatMap { id in home.first { $0.post.id == id }?.post.author.username }.map { [$0] } ?? []
        )
        if replyingTo == nil { home.insert(XTimelineItem(post), at: 0) }
        return post
    }

    public func signOut() async {}
}
