import SwiftUI
import XKit

/// The rows of a feed (states, posts, paging footer) without a scroll view, so
/// screens like Profile can put their own header above them.
struct FeedRows: View {
    let store: FeedStore
    var emptyTitle: LocalizedStringKey = "Nothing to see here yet"
    var emptySymbol = "text.bubble"
    var emptyMessage: LocalizedStringKey = "Posts will show up here."

    var body: some View {
        switch store.phase {
        case .idle:
            PlaceholderRows()
        case .loading where store.isEmpty:
            PlaceholderRows()
        case .failed(let message) where store.isEmpty:
            ContentUnavailableView {
                Label("Couldn't load posts", systemImage: "exclamationmark.icloud")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.reload() } }
                    .buttonStyle(.glassProminent)
            }
            .padding(.top, 40)
        default:
            if store.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol, description: Text(emptyMessage))
                    .padding(.top, 40)
            } else {
                if let error = store.transientError {
                    ErrorBanner(message: error) { store.transientError = nil }
                }
                ForEach(store.items) { item in
                    PostRow(item: item)
                        .onAppear { store.loadMoreIfNeeded(after: item) }
                }
                FeedFooter(store: store)
            }
        }
    }
}

/// A full-screen scrolling feed with pull to refresh.
///
/// The scroll position is anchored to the top visible post, so posts arriving
/// from a background refresh appear *above* the reader instead of pushing the
/// content down; a "new posts" pill then offers to jump up to them.
struct FeedScreen<Header: View>: View {
    let store: FeedStore
    var emptyTitle: LocalizedStringKey = "Nothing to see here yet"
    var emptySymbol = "text.bubble"
    var emptyMessage: LocalizedStringKey = "Posts will show up here."
    /// Changing this value scrolls to the top (re-selecting the current tab).
    var scrollToTopTrigger = 0
    @ViewBuilder var header: Header

    @State private var position = ScrollPosition(idType: String.self)
    @State private var isNearTop = true
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                FeedRows(store: store, emptyTitle: emptyTitle, emptySymbol: emptySymbol, emptyMessage: emptyMessage)
            }
            .scrollTargetLayout()
            .readableWidth()
        }
        .scrollPosition($position, anchor: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < 40
        } action: { _, nearTop in
            isNearTop = nearTop
            if nearTop { store.markSeen() }
        }
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .overlay(alignment: .top) {
            if store.unseenCount > 0, !isNearTop {
                NewPostsPill(count: store.unseenCount, authors: store.unseenAuthors) {
                    scrollToTop()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.unseenCount > 0 && !isNearTop)
        .refreshable {
            await store.refresh()
            // A pull is an explicit request to see what's new.
            store.markSeen()
            position.scrollTo(edge: .top)
        }
        .onChange(of: scrollToTopTrigger) { scrollToTop() }
        #if os(macOS)
        // Every Mac page shows at least one toolbar item, so the title bar keeps
        // the same height across sections.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .help("Refresh (⌘R)")
            }
        }
        #endif
        .task { await store.loadIfNeeded() }
    }

    private func scrollToTop() {
        withAnimation(.smooth) { position.scrollTo(edge: .top) }
        store.markSeen()
    }
}

extension FeedScreen where Header == EmptyView {
    init(
        store: FeedStore,
        emptyTitle: LocalizedStringKey = "Nothing to see here yet",
        emptySymbol: String = "text.bubble",
        emptyMessage: LocalizedStringKey = "Posts will show up here.",
        scrollToTopTrigger: Int = 0
    ) {
        self.init(
            store: store,
            emptyTitle: emptyTitle,
            emptySymbol: emptySymbol,
            emptyMessage: emptyMessage,
            scrollToTopTrigger: scrollToTopTrigger
        ) { EmptyView() }
    }
}

/// "↑ (avatars) 5 new posts", as on X: a tinted glass capsule.
private struct NewPostsPill: View {
    let count: Int
    let authors: [XUser]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                HStack(spacing: -8) {
                    ForEach(authors) { author in
                        Avatar(user: author, size: 24)
                            .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                    }
                }
                Text(count == 1 ? "1 new post" : "\(count) new posts")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.accent).interactive(), in: .capsule)
        .accessibilityLabel(count == 1 ? Text("Show 1 new post") : Text("Show \(count) new posts"))
    }
}

private struct FeedFooter: View {
    let store: FeedStore

    var body: some View {
        Group {
            if store.isLoadingMore {
                ProgressView().controlSize(.regular)
            } else if store.reachedEnd {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(.tertiary)
            } else {
                Button("Load More") { Task { await store.loadMore() } }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .padding(.bottom, 40)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).lineLimit(3)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Redacted rows shown while the first page loads.
struct PlaceholderRows: View {
    var count = 6

    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Theme.placeholder).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Placeholder name @handle").font(.subheadline.bold())
                    Text(index.isMultiple(of: 2)
                         ? "A placeholder line of text that stands in for a post while the timeline loads."
                         : "Short placeholder post.")
                    if index == 1 {
                        RoundedRectangle(cornerRadius: 16).fill(Theme.placeholder).aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
            }
            .redacted(reason: .placeholder)
            .padding(16)
            .rowSeparator()
        }
        .phaseAnimator([0.45, 1]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityLabel("Loading")
    }
}
