import SwiftUI
import XKit

/// A post with its full timestamp and counts, followed by the replies in its
/// conversation (via recent search, so replies older than 7 days are absent).
struct PostDetailView: View {
    let post: XPost

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.postStyle) private var style
    @Environment(\.palette) private var palette
    @State private var replies: [XTimelineItem] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                focused
                repliesSection
            }
            .readableWidth()
        }
        .background(palette.canvas)
        .navigationTitle("Post")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaBar(edge: .bottom) { replyBar }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .task { await loadReplies() }
        .refreshable { await loadReplies() }
    }

    private var focused: some View {
        let state = session.engagement.state(for: post)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { router.push(.profile(post.author)) } label: {
                    Avatar(user: post.author, size: 48)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.author.name).font(style.detailName)
                        VerifiedBadge(verification: post.author.verification, size: 16)
                    }
                    Text(post.author.handle).font(style.meta).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    PostMenuItems(post: post)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .hoverPointer()
                .accessibilityLabel("More")
                .menuIndicator(.hidden)
                .fixedSize()
            }
            PostBody(post: post, isFocused: true)
            Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    stat(state.reposts, "Reposts")
                    stat(post.metrics.quotes, "Quotes")
                    stat(state.likes, "Likes")
                    stat(state.bookmarks, "Bookmarks")
                    if let views = post.metrics.views { stat(views, "Views") }
                }
            }
            .scrollIndicators(.never)
            .font(.subheadline)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            PostActionBar(post: post, showsViews: false)
                .font(.body)
        }
        .padding(16)
        .rowSeparator()
    }

    @ViewBuilder
    private func stat(_ value: Int, _ label: LocalizedStringKey) -> some View {
        if value > 0 {
            HStack(spacing: 4) {
                Text(Formatting.compact(value)).bold().monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(label).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var repliesSection: some View {
        switch phase {
        case .loading:
            PlaceholderRows(count: 2)
        case .failed(let message):
            ContentUnavailableView("Replies unavailable", systemImage: "bubble.left.and.exclamationmark.bubble.right", description: Text(message))
                .padding(.top, 24)
        case .loaded:
            let (thread, related) = partitionedReplies
            if thread.isEmpty {
                Text("No replies yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .rowSeparator()
            } else {
                let links = ThreadLinks(thread)
                ForEach(thread) { item in
                    PostRow(item: item, connectsAbove: links.continuesAbove.contains(item.id), connectsBelow: links.continuesBelow.contains(item.id))
                }
                .environment(\.impliedReplyRecipients, [post.author.username.lowercased()])
            }
            if !related.isEmpty {
                Text("Discover more")
                    .font(.title3.weight(.heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 6) }
                    .rowSeparator()
                    .accessibilityAddTraits(.isHeader)
                let links = ThreadLinks(related)
                ForEach(related) { item in
                    PostRow(item: item, connectsAbove: links.continuesAbove.contains(item.id), connectsBelow: links.continuesBelow.contains(item.id))
                }
            }
        }
    }

    /// Posts in this post's conversation, then everything else the source
    /// mixed in (x.com appends unrelated "Discover more" posts).
    private var partitionedReplies: (thread: [XTimelineItem], related: [XTimelineItem]) {
        let conversation = post.conversationID ?? post.id
        var thread: [XTimelineItem] = []
        var related: [XTimelineItem] = []
        for item in replies {
            if let other = item.post.conversationID, other != conversation {
                related.append(item)
            } else {
                thread.append(item)
            }
        }
        return (thread, related)
    }

    private var replyBar: some View {
        QuickComposer(mode: .reply(post)) { reply in
            withAnimation(.snappy) { replies.append(XTimelineItem(reply)) }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .readableWidth()
    }


    private func loadReplies() async {
        do {
            replies = try await session.service.replies(to: post)
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = replies.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }
}
