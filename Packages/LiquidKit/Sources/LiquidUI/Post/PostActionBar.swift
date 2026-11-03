import SwiftUI
import XKit

struct PostActionBar: View {
    let post: XPost
    var showsViews = true

    @Environment(Session.self) private var session
    @Environment(\.postStyle) private var style

    var body: some View {
        let state = session.engagement.state(for: post)
        HStack(spacing: 0) {
            ActionButton(symbol: "bubble.left", count: state.replies, label: "Reply") {
                session.compose(replyingTo: post)
            }
            Spacer(minLength: 0)
            Menu {
                Button(state.reposted ? "Undo Repost" : "Repost", systemImage: "arrow.2.squarepath") {
                    session.engagement.toggleRepost(post)
                }
                Button("Quote", systemImage: "square.and.pencil") { session.compose(quoting: post) }
            } label: {
                ActionLabel(symbol: "arrow.2.squarepath", count: state.reposts, isActive: state.reposted, tint: Theme.repost)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(state.reposted ? "Undo repost" : "Repost")
            Spacer(minLength: 0)
            ActionButton(
                symbol: state.liked ? "heart.fill" : "heart",
                count: state.likes,
                isActive: state.liked,
                tint: Theme.like,
                label: state.liked ? "Unlike" : "Like"
            ) {
                session.engagement.toggleLike(post)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: state.liked) { _, liked in liked }
            Spacer(minLength: 0)
            if showsViews, let views = post.metrics.views {
                ActionLabel(symbol: "chart.bar.xaxis", count: views)
                    .accessibilityLabel(Text("\(views) views"))
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Button {
                    session.engagement.toggleBookmark(post)
                } label: {
                    Image(systemName: state.bookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(state.bookmarked ? Theme.accent : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.bookmarked ? "Remove bookmark" : "Bookmark")
                ShareLink(item: post.url) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
            }
        }
        .font(style.actions)
        .imageScale(.medium)
    }
}

private struct ActionButton: View {
    let symbol: String
    let count: Int
    var isActive = false
    var tint: Color = .secondary
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(symbol: symbol, count: count, isActive: isActive, tint: tint)
        }
        .buttonStyle(.plain)
        .hoverPointer()
        .accessibilityLabel(label)
    }
}

private struct ActionLabel: View {
    let symbol: String
    let count: Int
    var isActive = false
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolEffect(.bounce, value: isActive)
                .contentTransition(.symbolEffect(.replace))
            Text(count > 0 ? Formatting.compact(count) : " ")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .frame(minWidth: 20, alignment: .leading)
        }
        .foregroundStyle(isActive ? tint : .secondary)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .animation(.snappy, value: count)
    }
}
