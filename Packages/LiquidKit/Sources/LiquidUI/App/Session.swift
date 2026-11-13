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
    let translations: TranslationStore

    var section: AppSection = .home
    private(set) var routers: [AppSection: Router] = [:]

    var homeFilter: HomeFilter {
        didSet { if homeFilter != oldValue { rebuildHome() } }
    }
    private(set) var home: FeedStore
    /// Home stores by filter, so switching feeds back and forth keeps each
    /// one's posts instead of rebuilding and reloading it.
    @ObservationIgnored private var homeStores: [HomeFilter: FeedStore] = [:]
    let mentions: FeedStore
    let bookmarks: FeedStore
    private(set) var unreadMentions = 0

    var composer: ComposerContext?
    /// The floating glass composer (new posts and quick replies).
    var quickComposer: QuickComposeContext?
    var isShowingSettings = false
    var mediaViewer: MediaViewerContext?
    var toast: Toast?
    var searchText = ""
    /// Bumped when a search is submitted from outside the Search screen.
    private(set) var searchSubmissions = 0
    /// Most recent first; kept on this device only.
    private(set) var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: "LiquidX.recentSearches") ?? []
    var trends: [XTrend] = []
    /// Bumped when the current section is selected again at its root.
    private(set) var scrollToTopTicks: [AppSection: Int] = [:]
    /// Minimum age of a feed before returning to the app refreshes it.
    @ObservationIgnored var autoRefreshInterval: TimeInterval = 120

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let onSignOut: () -> Void

    init(service: any XService, me: XUser, onSignOut: @escaping () -> Void) {
        self.service = service
        self.me = me
        self.onSignOut = onSignOut
        let filter = HomeFilter(feed: service.homeFeeds.first ?? .following)
        homeFilter = filter
        home = Self.makeHome(service: service, me: me, filter: filter)
        mentions = FeedStore { page in try await service.mentions(page) }
        bookmarks = FeedStore { page in try await service.bookmarks(page) }
        engagement = EngagementStore(service: service)
        translations = TranslationStore(service: service)
        engagement.session = self
        translations.session = self
        for section in AppSection.allCases { routers[section] = Router() }
        homeStores[filter] = home
    }

    private static func makeHome(service: any XService, me: XUser, filter: HomeFilter) -> FeedStore {
        FeedStore(cache: homeCache(service: service, me: me, filter: filter)) { page in
            try await service.homeTimeline(page, filter: filter)
        }
    }

    private static func homeCache(service: any XService, me: XUser, filter: HomeFilter) -> FeedCache? {
        let unfiltered = !filter.hideReplies && !filter.hideReposts
        return service.isDemo || !unfiltered ? nil : FeedCache(name: "home-\(me.id)-\(filter.feed.rawValue)")
    }

    /// Builds the other home feeds' stores with their caches decoded off the
    /// main actor. Decoding while switching feeds stalled the picker.
    private func preloadHomeFeeds() async {
        let service = service
        for feed in service.homeFeeds {
            let filter = HomeFilter(hideReplies: homeFilter.hideReplies, hideReposts: homeFilter.hideReposts, feed: feed)
            guard homeStores[filter] == nil else { continue }
            let cache = Self.homeCache(service: service, me: me, filter: filter)
            let restored = await Task.detached(priority: .utility) { cache?.load() }.value
            guard homeStores[filter] == nil else { continue }
            homeStores[filter] = FeedStore(cache: cache, restored: restored) { page in
                try await service.homeTimeline(page, filter: filter)
            }
        }
    }

    private func rebuildHome() {
        if let store = homeStores[homeFilter] {
            home = store
        } else {
            home = Self.makeHome(service: service, me: me, filter: homeFilter)
            homeStores[homeFilter] = home
        }
    }

    func router(for section: AppSection) -> Router {
        routers[section]!
    }

    var currentRouter: Router { router(for: section) }

    /// Selecting the current section again pops it to its root, like UIKit tabs.
    func select(_ section: AppSection) {
        if section == self.section {
            if currentRouter.path.isEmpty {
                scrollToTopTicks[section, default: 0] += 1
            } else {
                currentRouter.popToRoot()
            }
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
        async let feeds: Void = preloadHomeFeeds()
        _ = await (mentions, trends, feeds)
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

    func submitSearch(_ text: String) {
        searchText = text
        searchSubmissions += 1
        select(.search)
    }

    func rememberSearch(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: "LiquidX.recentSearches")
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "LiquidX.recentSearches")
    }

    func reloadTrends() async {
        await loadTrends()
    }

    private func loadTrends() async {
        trends = (try? await service.trends()) ?? []
    }

    // MARK: - Actions

    /// New posts and replies open the floating glass composer; quotes need the
    /// full composer to show the quoted post.
    func compose(replyingTo post: XPost? = nil, quoting: XPost? = nil) {
        if let quoting {
            openFullComposer(quoting: quoting)
        } else {
            withAnimation(.snappy(duration: 0.35)) { quickComposer = QuickComposeContext(replyingTo: post) }
        }
    }

    func openFullComposer(replyingTo post: XPost? = nil, quoting: XPost? = nil, draft: String = "") {
        quickComposer = nil
        composer = ComposerContext(replyingTo: post, quoting: quoting, initialText: draft)
    }

    func didPost(_ post: XPost, replyingTo: XPost?) {
        if replyingTo == nil { home.insert(post) }
        if let replyingTo { engagement.state(for: replyingTo).replies += 1 }
        show(Toast(message: replyingTo == nil ? "Your post was sent." : "Your reply was sent.", symbol: "checkmark.circle.fill"))
    }

    func showMedia(_ media: [XMedia], index: Int, post: XPost) {
        mediaViewer = MediaViewerContext(media: media, index: index, post: post)
    }

    func save(_ media: [XMedia]) {
        // Videos take a moment to download; say something is happening.
        if media.contains(where: { $0.kind != .photo }) {
            show(Toast(message: "Saving…", symbol: "arrow.down.circle"))
        }
        Task {
            do {
                try await MediaSaver.save(media)
                show(Toast(message: MediaSaver.savedMessage, symbol: "checkmark.circle.fill"))
            } catch {
                report(error)
            }
        }
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

struct QuickComposeContext: Identifiable {
    let id = UUID()
    var replyingTo: XPost?
}

struct ComposerContext: Identifiable {
    let id = UUID()
    var replyingTo: XPost?
    var quoting: XPost?
    /// Draft carried over from the inline reply bar.
    var initialText = ""
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

    init(_ metrics: XPost.Metrics, viewer: ViewerState?) {
        liked = viewer?.liked ?? false
        reposted = viewer?.reposted ?? false
        bookmarked = viewer?.bookmarked ?? false
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
        let state = PostEngagement(post.metrics, viewer: post.viewer)
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
