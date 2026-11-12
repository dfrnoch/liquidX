import Foundation
import XKit

/// One paginated timeline (home, a profile, mentions, bookmarks, search).
///
/// Refreshing asks only for posts newer than the newest one on screen; when that
/// fills a whole page there may be a gap, so the list is replaced instead of
/// prepended. Older pages load as the user nears the end.
@Observable
final class FeedStore {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    typealias Fetch = @Sendable (PageRequest) async throws -> TimelinePage

    private(set) var items: [XTimelineItem] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var reachedEnd = false
    /// Non-fatal failure of a refresh or next page while content is shown.
    var transientError: String?
    /// Posts added above the reader by a background refresh and not yet seen.
    private(set) var unseenCount = 0

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let cache: FeedCache?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private(set) var lastRefresh: Date?

    /// Reads the cache right away, so the first frame shows the last timeline.
    convenience init(cache: FeedCache? = nil, fetch: @escaping Fetch) {
        self.init(cache: cache, restored: cache?.load(), fetch: fetch)
    }

    /// `restored` is the cache's page, already decoded (off the main actor).
    init(cache: FeedCache?, restored: TimelinePage?, fetch: @escaping Fetch) {
        self.fetch = fetch
        self.cache = cache
        if let restored, !restored.items.isEmpty {
            items = restored.items
            nextCursor = restored.nextCursor
            phase = .loaded
        }
    }

    var isEmpty: Bool { items.isEmpty }

    func loadIfNeeded() async {
        switch phase {
        case .idle: await loadFirstPage()
        case .loaded where lastRefresh == nil: await refresh()
        default: break
        }
    }

    func reload() async {
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        phase = .loading
        do {
            let page = try await fetch(.newest(since: nil))
            items = Self.deduplicated(page.items)
            nextCursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            unseenCount = 0
            phase = .loaded
            lastRefresh = .now
            persist()
        } catch is CancellationError {
            phase = items.isEmpty ? .idle : .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Pull-to-refresh. Coalesces concurrent calls.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        guard !items.isEmpty else { return await loadFirstPage() }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        do {
            let page = try await fetch(.newest(since: items.first?.id))
            lastRefresh = .now
            transientError = nil
            if page.mayHaveGap {
                items = Self.deduplicated(page.items)
                nextCursor = page.nextCursor
                reachedEnd = page.nextCursor == nil
            } else {
                // Posts already on screen stay where they are: a ranked feed
                // can serve them again, and they shouldn't jump back to the top.
                let known = Set(items.map(\.id))
                let fresh = Self.deduplicated(page.items.filter { !known.contains($0.id) })
                if !fresh.isEmpty {
                    items = fresh + items
                    unseenCount += fresh.count
                }
            }
            persist()
        } catch is CancellationError {
        } catch {
            transientError = error.localizedDescription
        }
    }

    /// Refreshes when the feed is older than `interval` (returning to the app).
    func refreshIfStale(after interval: TimeInterval) async {
        guard phase == .loaded, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) >= interval else { return }
        await refresh()
    }

    func markSeen() {
        if unseenCount != 0 { unseenCount = 0 }
    }

    /// Authors of the unseen posts, for the "new posts" pill.
    var unseenAuthors: [XUser] {
        var seen = Set<String>()
        return items.prefix(unseenCount)
            .map { $0.repostedBy ?? $0.post.author }
            .filter { seen.insert($0.id).inserted }
            .prefix(3)
            .map { $0 }
    }

    func loadMoreIfNeeded(after item: XTimelineItem) {
        guard !isLoadingMore, !reachedEnd, nextCursor != nil else { return }
        guard let index = items.lastIndex(where: { $0.id == item.id }), index >= items.count - 6 else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(.older(cursor: cursor))
            items = Self.deduplicated(items + page.items)
            nextCursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            transientError = nil
        } catch is CancellationError {
        } catch {
            transientError = error.localizedDescription
        }
    }

    func insert(_ post: XPost) {
        items.insert(XTimelineItem(post), at: 0)
        persist()
    }

    func remove(postID: String) {
        items.removeAll { $0.post.id == postID }
    }

    private func persist() {
        guard let cache else { return }
        let snapshot = TimelinePage(items: Array(items.prefix(80)), nextCursor: items.count > 80 ? nil : nextCursor)
        Task.detached(priority: .utility) { cache.save(snapshot) }
    }

    private static func deduplicated(_ items: [XTimelineItem]) -> [XTimelineItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

/// Last home timeline on disk, so launch shows content instantly and the first
/// refresh only asks X for what is new.
struct FeedCache: Sendable {
    let url: URL

    init(name: String) {
        let directory = URL.cachesDirectory.appending(path: "LiquidXFeeds", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "\(name).json")
    }

    nonisolated func load() -> TimelinePage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TimelinePage.self, from: data)
    }

    nonisolated func save(_ page: TimelinePage) {
        guard let data = try? JSONEncoder().encode(page) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        let directory = URL.cachesDirectory.appending(path: "LiquidXFeeds", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
    }
}
