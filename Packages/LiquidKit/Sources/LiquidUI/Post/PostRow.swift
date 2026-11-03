import SwiftUI
import XKit

/// A timeline row. Cheap to build: text is pre-rendered, images come from the
/// pipeline cache, and only the engagement object for this post is observed.
struct PostRow: View {
    let item: XTimelineItem

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.postStyle) private var style
    @State private var isHovering = false

    private var post: XPost { item.post }
    private var avatarSize: CGFloat { style.showsAvatarColumn ? 44 : 34 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reposter = item.repostedBy {
                Label {
                    Text("\(reposter.name) reposted")
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                }
                .font(style.label)
                .foregroundStyle(.secondary)
                .labelStyle(RepostLabelStyle(indent: style.showsAvatarColumn ? avatarSize : nil))
                .onTapGesture { router.push(.profile(reposter)) }
                .hoverPointer()
            }

            if style.showsAvatarColumn {
                HStack(alignment: .top, spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 6) {
                        PostHeader(post: post)
                        content
                    }
                }
            } else {
                // No gutter: the avatar sits beside the name and everything
                // below uses the full width.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        avatar
                        PostHeader(post: post)
                    }
                    content
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(isHovering ? Color.primary.opacity(0.035) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { router.push(.post(post)) }
        #if os(macOS)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .hoverPointer()
        #endif
        .rowSeparator()
        .contextMenu { PostMenuItems(post: post) }
        .accessibilityElement(children: .contain)
    }

    private var avatar: some View {
        Button { router.push(.profile(post.author)) } label: {
            Avatar(user: post.author, size: avatarSize)
        }
        .buttonStyle(.plain)
        .hoverPointer()
        .accessibilityLabel(Text("\(post.author.name), profile"))
    }

    @ViewBuilder
    private var content: some View {
        PostBody(post: post)
        PostActionBar(post: post)
            .padding(.top, 2)
    }
}

private struct RepostLabelStyle: LabelStyle {
    /// Width of the avatar column to align the icon under, or nil for none.
    let indent: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: indent == nil ? 6 : 12) {
            configuration.icon
                .frame(width: indent, alignment: .trailing)
            configuration.title
        }
    }
}

/// Name, badge, handle and time on one line (macOS / wide), or name over handle
/// on compact iPhone widths, as in the X concepts.
struct PostHeader: View {
    let post: XPost
    var showsMenu = true

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.postStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if sizeClass == .compact {
                VStack(alignment: .leading, spacing: 1) {
                    name
                    meta
                }
            } else {
                name
                meta
            }
            Spacer(minLength: 4)
            if showsMenu {
                Menu {
                    PostMenuItems(post: post)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .hoverPointer()
                .accessibilityLabel("More")
            }
        }
    }

    private var name: some View {
        HStack(spacing: 4) {
            Text(post.author.name)
                .font(style.name)
                .lineLimit(1)
            VerifiedBadge(verification: post.author.verification)
            if post.author.isProtected {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .layoutPriority(1)
    }

    private var meta: some View {
        Text("\(post.author.handle) · \(Formatting.relative(post.createdAt))")
            .font(style.meta)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Text, media, quote and link card.
struct PostBody: View {
    let post: XPost
    /// The focused post on its own page uses larger text.
    var isFocused = false

    @Environment(\.postStyle) private var style

    @Environment(Session.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !post.replyingTo.isEmpty {
                Text("Replying to \(Text(post.replyingTo.map { "@\($0)" }.joined(separator: " ")).foregroundStyle(Theme.accent))")
                    .font(style.meta)
                    .foregroundStyle(.secondary)
            }
            if !post.text.characters.isEmpty {
                Text(post.text)
                    .font(isFocused ? style.detailBody : style.body)
                    .tint(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !post.media.isEmpty {
                MediaGrid(media: post.media) { index in
                    session.showMedia(post.media, index: index, post: post)
                }
                .padding(.top, 2)
            }
            if let quoted = post.quoted {
                QuoteCard(quote: quoted)
            }
            if let card = post.card, post.media.isEmpty, post.quoted == nil {
                LinkCardView(card: card)
            }
        }
    }
}

/// Shared actions for the row's long-press/right-click menu and "…" button.
struct PostMenuItems: View {
    let post: XPost

    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Reply", systemImage: "bubble.left") { session.compose(replyingTo: post) }
        Button("Quote", systemImage: "quote.bubble") { session.compose(quoting: post) }
        Divider()
        ShareLink(item: post.url) { Label("Share Post", systemImage: "square.and.arrow.up") }
        Button("Copy Link", systemImage: "link") { Pasteboard.copy(post.url.absoluteString) }
        Button("Copy Text", systemImage: "doc.on.doc") { Pasteboard.copy(post.plainText) }
        Button("Open on x.com", systemImage: "safari") { openURL(post.url) }
        Divider()
        Button("View \(post.author.handle)", systemImage: "person.crop.circle") {
            session.open(.profile(post.author))
        }
    }
}

enum Pasteboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
