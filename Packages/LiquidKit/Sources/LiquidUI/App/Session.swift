import SwiftUI
import XKit

/// Everything that belongs to one signed-in account (or the demo): the service,
/// the account itself, long-lived feeds, per-section navigation and transient
/// presentation state (composer, media viewer, toasts).
@Observable
final class Session {
    let service: any XService
    var me: XUser
    let engagement: EngagementStore

    var section: AppSection = .home
    private(set) var routers: [AppSection: Router] = [:]

    var homeFilter: HomeFilter {
        didSet { if homeFilter != oldValue { rebuildHome() } }
    }
    private(set) var home: FeedStore
    let mentions: FeedStore
    let bookmarks: FeedStore
    private(set) var unreadMentions = 0

    var composer: ComposerContext?
    var isShowingSettings = false
    var mediaViewer: MediaViewerContext?
    var toast: Toast?
    var searchText = ""
    var trends: [XTrend] = []

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let onSignOut: () -> Void

    init(service: any XService, me: XUser, onSignOut: @escaping () -> Void) {
        self.service = service
        self.me = me
        self.onSignOut = onSignOut
        homeFilter = HomeFilter()
        home = Self.makeHome(service: service, me: me, filter: HomeFilter())
        mentions = FeedStore { page in try await service.mentions(page) }
        bookmarks = FeedStore { page in try await service.bookmarks(page) }
        engagement = EngagementStore(service: service)
        engagement.session = self
        for section in AppSection.allCases { routers[section] = Router() }
    }

    private static func makeHome(service: any XService, me: XUser, filter: HomeFilter) -> FeedStore {
        let cache = service.isDemo || filter != HomeFilter() ? nil : FeedCache(name: "home-\(me.id)")
        return FeedStore(cache: cache) { page in try await service.homeTimeline(page, filter: filter) }
    }

    private func rebuildHome() {
        home = Self.makeHome(service: service, me: me, filter: homeFilter)
    }

    func router(for section: AppSection) -> Router {
        routers[section]!
    }

    var currentRouter: Router { router(for: section) }

    /// Selecting the current section again pops it to its root, like UIKit tabs.
    func select(_ section: AppSection) {
        if section == self.section {
            currentRouter.popToRoot()
        } else {
            self.section = section
        }
        if section == .notifications { unreadMentions = 0 }
    }

    func open(_ route: Route) {
        currentRouter.push(route)
    }

    // MARK: - Startup work

    func start() async {
        async let mentions: Void = refreshMentionBadge()
        async let trends: Void = loadTrends()
        _ = await (mentions, trends)
    }

    private func refreshMentionBadge() async {
        let before = Set(mentions.items.map(\.id))
        await mentions.loadIfNeeded()
        if before.isEmpty {
            let seen = UserDefaults.standard.string(forKey: "LiquidX.lastSeenMention.\(me.id)")
            unreadMentions = mentions.items.prefix { $0.id != seen }.count
        }
        if let newest = mentions.items.first?.id, section == .notifications {
            UserDefaults.standard.set(newest, forKey: "LiquidX.lastSeenMention.\(me.id)")
        }
    }

    func markMentionsSeen() {
        unreadMentions = 0
        if let newest = mentions.items.first?.id {
            UserDefaults.standard.set(newest, forKey: "LiquidX.lastSeenMention.\(me.id)")
        }
    }

    private func loadTrends() async {
        trends = (try? await service.trends()) ?? []
    }

    // MARK: - Actions

    func compose(replyingTo post: XPost? = nil, quoting: XPost? = nil) {
        composer = ComposerContext(replyingTo: post, quoting: quoting)
    }

    func didPost(_ post: XPost, replyingTo: XPost?) {
        if replyingTo == nil { home.insert(post) }
        if let replyingTo { engagement.state(for: replyingTo).replies += 1 }
        show(Toast(message: replyingTo == nil ? "Your post was sent." : "Your reply was sent.", symbol: "checkmark.circle.fill"))
    }

    func showMedia(_ media: [XMedia], index: Int, post: XPost) {
        mediaViewer = MediaViewerContext(media: media, index: index, post: post)
    }

    func show(_ toast: Toast) {
        withAnimation(.snappy) { self.toast = toast }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self.toast = nil }
        }
    }

    func report(_ error: any Error) {
        if case XAPIError.unauthorized = error {
            signOut()
            return
        }
        show(Toast(message: LocalizedStringKey(error.localizedDescription), symbol: "exclamationmark.triangle.fill", isError: true))
    }

    func signOut() {
        onSignOut()
    }
}

struct ComposerContext: Identifiable {
    let id = UUID()
    var replyingTo: XPost?
    var quoting: XPost?
}

struct MediaViewerContext: Identifiable {
    let id = UUID()
    var media: [XMedia]
    var index: Int
    var post: XPost
}

struct Toast: Identifiable {
    let id = UUID()
    var message: LocalizedStringKey
    var symbol: String
    var isError = false
}

/// Per-post interaction state (liked, reposted, bookmarked, counts). One
/// observable object per post, so a like re-renders only that row.
@Observable
final class PostEngagement {
    var liked = false
    var reposted = false
    var bookmarked = false
    var likes: Int
    var reposts: Int
    var replies: Int
    var bookmarks: Int

    init(_ metrics: XPost.Metrics) {
        likes = metrics.likes
        reposts = metrics.reposts
        replies = metrics.replies
        bookmarks = metrics.bookmarks
    }
}

final class EngagementStore {
    private let service: any XService
    private var states: [String: PostEngagement] = [:]
    weak var session: Session?

    init(service: any XService) {
        self.service = service
    }

    func state(for post: XPost) -> PostEngagement {
        if let state = states[post.id] { return state }
        let state = PostEngagement(post.metrics)
        states[post.id] = state
        return state
    }

    func toggleLike(_ post: XPost) {
        let state = state(for: post)
        state.liked.toggle()
        state.likes += state.liked ? 1 : -1
        let liked = state.liked
        perform({ try await $0.setLiked(liked, postID: post.id) }) {
            state.liked.toggle()
            state.likes += state.liked ? 1 : -1
        }
    }

    func toggleRepost(_ post: XPost) {
        let state = state(for: post)
        state.reposted.toggle()
        state.reposts += state.reposted ? 1 : -1
        let reposted = state.reposted
        perform({ try await $0.setReposted(reposted, postID: post.id) }) {
            state.reposted.toggle()
            state.reposts += state.reposted ? 1 : -1
        }
    }

    func toggleBookmark(_ post: XPost) {
        let state = state(for: post)
        state.bookmarked.toggle()
        state.bookmarks += state.bookmarked ? 1 : -1
        let bookmarked = state.bookmarked
        if !bookmarked { session?.bookmarks.remove(postID: post.id) }
        session?.show(Toast(message: bookmarked ? "Added to Bookmarks" : "Removed from Bookmarks", symbol: bookmarked ? "bookmark.fill" : "bookmark.slash"))
        perform({ try await $0.setBookmarked(bookmarked, postID: post.id) }) {
            state.bookmarked.toggle()
            state.bookmarks += state.bookmarked ? 1 : -1
        }
    }

    /// Optimistic update: the UI already changed; undo it if X refuses.
    private func perform(_ action: @escaping @Sendable (any XService) async throws -> Void, rollback: @escaping () -> Void) {
        let service = service
        Task {
            do {
                try await action(service)
            } catch {
                withAnimation { rollback() }
                session?.report(error)
            }
        }
    }
}
