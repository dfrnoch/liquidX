import SwiftUI
import XKit

/// A post with its full timestamp and counts, followed by the replies in its
/// conversation (via recent search, so replies older than 7 days are absent).
struct PostDetailView: View {
    let post: XPost

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
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
        .background(Theme.canvas)
        .navigationTitle("Post")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaBar(edge: .bottom) { replyBar }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
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
                        Text(post.author.name).font(.headline)
                        VerifiedBadge(verification: post.author.verification, size: 16)
                    }
                    Text(post.author.handle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    PostMenuItems(post: post)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            PostBody(post: post, textStyle: .title3)
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
            if replies.isEmpty {
                Text("No replies yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(32)
            } else {
                ForEach(replies) { PostRow(item: $0) }
            }
        }
    }

    private var replyBar: some View {
        Button { session.compose(replyingTo: post) } label: {
            HStack(spacing: 10) {
                Avatar(user: session.me, size: 28)
                Text("Post your reply")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
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
