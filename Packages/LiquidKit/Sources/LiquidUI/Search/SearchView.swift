import SwiftUI
import XKit

/// Search tab root: trends while idle, results once a query is submitted.
struct SearchScreen: View {
    @Environment(Session.self) private var session
    @State private var submitted: String?

    var body: some View {
        @Bindable var session = session
        Group {
            if let submitted {
                SearchResults(query: submitted)
                    .id(submitted)
            } else {
                TrendsList()
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $session.searchText, prompt: "Search X")
        .onSubmit(of: .search) { submit(session.searchText) }
        #else
        // One search field on the Mac: inline at the top of the column (the
        // trends column hides its own while Search is open).
        .safeAreaInset(edge: .top, spacing: 0) {
            MacSearchField(text: $session.searchText) { submit(session.searchText) }
                .readableWidth()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await session.reloadTrends() }
                }
            }
        }
        #endif
        .onChange(of: session.searchText) { _, text in
            if text.isEmpty { submitted = nil }
        }
        .onChange(of: session.searchSubmissions) { submit(session.searchText) }
        .onAppear {
            // The Mac's search field in the trends column hands its query over.
            if !session.searchText.isEmpty, submitted != session.searchText { submit(session.searchText) }
        }
    }

    private func submit(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        submitted = query
    }
}

/// A pushed search (hashtag tap, "from:" search on a profile).
struct SearchResultsView: View {
    let query: String

    var body: some View {
        SearchResults(query: query)
            .background(Theme.canvas)
            .navigationTitle(query)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

private struct SearchResults: View {
    let query: String
    @State private var store: FeedStore?
    @Environment(Session.self) private var session

    private var username: String? {
        let trimmed = query.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !trimmed.isEmpty, trimmed.count <= 15, !query.contains(" "), !query.hasPrefix("#"), !query.contains(":"),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return trimmed
    }

    var body: some View {
        Group {
            if let store {
                FeedScreen(store: store, emptyTitle: "No results for \"\(query)\"", emptySymbol: "magnifyingglass", emptyMessage: "Try searching for something else. Search covers the last 7 days.") {
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
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard store == nil else { return }
            let service = session.service
            let query = query
            store = FeedStore { page in try await service.search(query, page) }
        }
    }
}

struct TrendsList: View {
    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's happening")
                    .font(.title2.weight(.heavy))
                    .padding(16)
                if session.trends.isEmpty {
                    ContentUnavailableView("Search X", systemImage: "magnifyingglass", description: Text("Find posts, people and topics."))
                        .padding(.top, 20)
                } else {
                    ForEach(session.trends) { trend in
                        TrendRow(trend: trend)
                            .rowSeparator()
                    }
                }
            }
            .readableWidth()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
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
    }
}

#if os(macOS)
/// The Mac's glass search capsule.
struct MacSearchField: View {
    @Binding var text: String
    var prompt: LocalizedStringKey = "Search"
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
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
}
#endif
