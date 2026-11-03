import SwiftUI
import XKit

/// Search tab root. Idle: recent searches and trends. While typing:
/// suggested topics and accounts. Submitted: results in Top / Latest /
/// People / Media tabs.
struct SearchScreen: View {
    @Environment(Session.self) private var session
    @Environment(\.palette) private var palette
    @State private var submitted: String?
    @State private var suggestions = SearchSuggestions()
    #if os(macOS)
    @FocusState private var isFieldFocused: Bool
    /// Height of the inline field's bar; the dropdown opens just below it.
    @State private var fieldBarHeight: CGFloat = 0
    #endif

    var body: some View {
        @Bindable var session = session
        Group {
            if let submitted {
                SearchResultsPane(query: submitted)
                    .id(submitted)
            } else {
                SearchIdleView { submit($0) }
            }
        }
        .background(palette.canvas)
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $session.searchText, prompt: "Search X")
        .searchSuggestions {
            SuggestionRows(text: session.searchText, suggestions: suggestions) { submit($0) }
        }
        .onSubmit(of: .search) { submit(session.searchText) }
        #else
        // One search field on the Mac: inline at the top of the column (the
        // trends column hides its own while Search is open).
        .safeAreaInset(edge: .top, spacing: 0) {
            MacSearchField(text: $session.searchText, isFocused: $isFieldFocused) { submit(session.searchText) }
                .readableWidth()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldBarHeight = $0 }
        }
        .overlay(alignment: .top) {
            if showsDropdown {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SuggestionRows(text: session.searchText, suggestions: suggestions) { submit($0) }
                    }
                    .padding(.vertical, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                .readableWidth()
                .padding(.horizontal, 16)
                // The overlay spans the field's inset too; start below the field.
                .padding(.top, max(0, fieldBarHeight - 4))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: showsDropdown)
        .toolbar {
            // Results pages bring their own Refresh button.
            if submitted == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await session.reloadTrends() }
                    }
                }
            }
        }
        #endif
        .task(id: session.searchText) {
            // Debounced typeahead.
            let text = session.searchText
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                suggestions = SearchSuggestions()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            if let result = try? await session.service.searchSuggestions(text), !Task.isCancelled {
                suggestions = result
            }
        }
        .onChange(of: session.searchText) { _, text in
            if text.isEmpty { submitted = nil }
        }
        .onChange(of: session.searchSubmissions) { submit(session.searchText) }
        .onAppear {
            // The Mac's search field in the trends column hands its query over.
            if !session.searchText.isEmpty, submitted != session.searchText { submit(session.searchText) }
        }
    }

    #if os(macOS)
    private var showsDropdown: Bool {
        guard isFieldFocused else { return false }
        let text = session.searchText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return !session.recentSearches.isEmpty }
        return text != submitted
    }
    #endif

    private func submit(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        session.searchText = query
        session.rememberSearch(query)
        submitted = query
        #if os(macOS)
        isFieldFocused = false
        #endif
    }
}

/// Suggestions shown while typing (or recent searches for an empty field).
private struct SuggestionRows: View {
    let text: String
    let suggestions: SearchSuggestions
    let submit: (String) -> Void

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            ForEach(session.recentSearches, id: \.self) { query in
                row(symbol: "clock.arrow.circlepath", title: query) { submit(query) }
            }
        } else {
            row(symbol: "magnifyingglass", title: "Search for \"\(text)\"") { submit(text) }
            ForEach(suggestions.topics, id: \.self) { topic in
                row(symbol: "magnifyingglass", title: topic) { submit(topic) }
            }
            ForEach(suggestions.users) { user in
                Button {
                    router.push(.profile(user))
                } label: {
                    HStack(spacing: 12) {
                        Avatar(user: user, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(user.name).font(.headline).lineLimit(1)
                                VerifiedBadge(verification: user.verification, size: 14)
                            }
                            Text(user.handle).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverPointer()
            }
        }
    }

    private func row(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPointer()
    }
}

/// Recent searches and trends, shown before searching.
private struct SearchIdleView: View {
    let submit: (String) -> Void

    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !session.recentSearches.isEmpty {
                    HStack {
                        Text("Recent").font(.title3.weight(.heavy))
                        Spacer()
                        Button("Clear") { withAnimation { session.clearRecentSearches() } }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .hoverPointer()
                    }
                    .padding(16)
                    ForEach(session.recentSearches, id: \.self) { query in
                        Button { submit(query) } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverPointer()
                    }
                }
                if !session.trends.isEmpty {
                    Text("What's happening")
                        .font(.title3.weight(.heavy))
                        .padding(16)
                    ForEach(session.trends) { trend in
                        TrendRow(trend: trend)
                            .rowSeparator()
                    }
                }
                if session.recentSearches.isEmpty && session.trends.isEmpty {
                    ContentUnavailableView("Search X", systemImage: "magnifyingglass", description: Text("Find posts, people and topics."))
                        .padding(.top, 40)
                }
            }
            .readableWidth()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// A pushed search (hashtag tap, "from:" search on a profile).
struct SearchResultsView: View {
    let query: String

    @Environment(\.palette) private var palette

    var body: some View {
        SearchResultsPane(query: query)
            .background(palette.canvas)
            .navigationTitle(query)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// Keeps one store per tab, so switching tabs back and forth doesn't reload.
@Observable
private final class SearchModel {
    var kind: SearchKind?
    @ObservationIgnored private var feeds: [SearchKind: FeedStore] = [:]
    @ObservationIgnored private var people: UserListStore?

    func feed(for kind: SearchKind, query: String, service: any XService) -> FeedStore {
        if let store = feeds[kind] { return store }
        let store = FeedStore { page in try await service.search(query, kind: kind, page) }
        feeds[kind] = store
        return store
    }

    func people(query: String, service: any XService) -> UserListStore {
        if let people { return people }
        let store = UserListStore { page in try await service.searchUsers(query, page) }
        people = store
        return store
    }
}

private struct SearchResultsPane: View {
    let query: String

    @Environment(Session.self) private var session
    @State private var model = SearchModel()

    private var kinds: [SearchKind] { session.service.searchKinds }

    var body: some View {
        let kind = model.kind ?? kinds.first ?? .latest
        Group {
            switch kind {
            case .people:
                UserListScreen(store: model.people(query: query, service: session.service))
            case .media:
                MediaResultsScreen(store: model.feed(for: .media, query: query, service: session.service))
            case .top, .latest:
                FeedScreen(
                    store: model.feed(for: kind, query: query, service: session.service),
                    emptyTitle: "No results for \"\(query)\"",
                    emptySymbol: "magnifyingglass",
                    emptyMessage: "Try searching for something else."
                ) {
                    if let username {
                        NavigationLink(value: Route.user(username)) {
                            Label("Go to @\(username)", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .rowSeparator()
                    }
                }
            }
        }
        .id(kind)
        .safeAreaInset(edge: .top, spacing: 0) {
            if kinds.count > 1 {
                SegmentedPicker(
                    selection: Binding(get: { kind }, set: { model.kind = $0 }),
                    options: kinds.map { ($0, $0.title) }
                )
                .readableWidth()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var username: String? {
        let trimmed = query.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !trimmed.isEmpty, trimmed.count <= 15, !query.contains(" "), !query.hasPrefix("#"), !query.contains(":"),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return trimmed
    }
}

extension SearchKind {
    var title: LocalizedStringKey {
        switch self {
        case .top: "Top"
        case .latest: "Latest"
        case .people: "People"
        case .media: "Media"
        }
    }
}

/// Media search results as a three-column grid.
private struct MediaResultsScreen: View {
    let store: FeedStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                MediaGridTiles(store: store)
            }
            .readableWidth()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await store.refresh() }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
            }
        }
        #endif
    }
}

/// A paginated list of accounts (people search).
@Observable
final class UserListStore {
    typealias Fetch = @Sendable (PageRequest) async throws -> UserPage

    private(set) var users: [XUser] = []
    private(set) var phase: FeedStore.Phase = .idle
    private(set) var isLoadingMore = false
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let fetch: Fetch

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        phase = .loading
        do {
            let page = try await fetch(.newest(since: nil))
            users = page.users
            nextCursor = page.nextCursor
            phase = .loaded
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func loadMore(after user: XUser) async {
        guard !isLoadingMore, let cursor = nextCursor, users.last?.id == user.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await fetch(.older(cursor: cursor)) else { return }
        let known = Set(users.map(\.id))
        users += page.users.filter { !known.contains($0.id) }
        nextCursor = page.nextCursor
    }
}

private struct UserListScreen: View {
    let store: UserListStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch store.phase {
                case .idle, .loading:
                    PlaceholderRows(count: 5)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't load people", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await store.reload() } }
                            .buttonStyle(.glassProminent)
                    }
                    .padding(.top, 40)
                case .loaded where store.users.isEmpty:
                    ContentUnavailableView("No people found", systemImage: "person.2", description: Text("Try a different name or handle."))
                        .padding(.top, 40)
                case .loaded:
                    ForEach(store.users) { user in
                        UserRow(user: user)
                            .task { await store.loadMore(after: user) }
                    }
                }
            }
            .readableWidth()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { await store.loadIfNeeded() }
        .refreshable { await store.reload() }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.reload() } }
            }
        }
        #endif
    }
}

struct UserRow: View {
    let user: XUser

    @Environment(Router.self) private var router
    @Environment(\.postStyle) private var style

    var body: some View {
        Button { router.push(.profile(user)) } label: {
            HStack(alignment: .top, spacing: 12) {
                Avatar(user: user, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.name).font(style.name).lineLimit(1)
                        VerifiedBadge(verification: user.verification)
                    }
                    Text(user.handle).font(style.meta).foregroundStyle(.secondary)
                    if !user.bio.characters.isEmpty {
                        Text(user.bio)
                            .font(style.meta)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPointer()
        .rowSeparator()
    }
}

struct TrendRow: View {
    let trend: XTrend
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.push(.search(trend.name)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                if let category = trend.category {
                    Text(category).font(.footnote).foregroundStyle(.secondary)
                }
                Text(trend.name).font(.headline)
                if let count = trend.postCount {
                    Text("\(Formatting.compact(count)) posts").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverPointer()
    }
}

#if os(macOS)
/// The Mac's glass search capsule.
struct MacSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding?
    var prompt: LocalizedStringKey = "Search"
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            field
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .hoverPointer()
            }
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private var field: some View {
        let field = TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .onSubmit(onSubmit)
        if let isFocused {
            field.focused(isFocused)
        } else {
            field
        }
    }
}
#endif
