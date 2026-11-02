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
struct FeedScreen<Header: View>: View {
    let store: FeedStore
    var emptyTitle: LocalizedStringKey = "Nothing to see here yet"
    var emptySymbol = "text.bubble"
    var emptyMessage: LocalizedStringKey = "Posts will show up here."
    @ViewBuilder var header: Header

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                FeedRows(store: store, emptyTitle: emptyTitle, emptySymbol: emptySymbol, emptyMessage: emptyMessage)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
    }
}

extension FeedScreen where Header == EmptyView {
    init(
        store: FeedStore,
        emptyTitle: LocalizedStringKey = "Nothing to see here yet",
        emptySymbol: String = "text.bubble",
        emptyMessage: LocalizedStringKey = "Posts will show up here."
    ) {
        self.init(store: store, emptyTitle: emptyTitle, emptySymbol: emptySymbol, emptyMessage: emptyMessage) { EmptyView() }
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
