import SwiftUI
import XKit

/// A timeline row. Cheap to build: text is pre-rendered, images come from the
/// pipeline cache, and only the engagement object for this post is observed.
struct PostRow: View {
    let item: XTimelineItem

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var isHovering = false

    private var post: XPost { item.post }
    private let avatarSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reposter = item.repostedBy {
                Label {
                    Text("\(reposter.name) reposted")
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(RepostLabelStyle(indent: avatarSize))
                .onTapGesture { router.push(.profile(reposter)) }
            }

            HStack(alignment: .top, spacing: 12) {
                Button { router.push(.profile(post.author)) } label: {
                    Avatar(user: post.author, size: avatarSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(post.author.name), profile"))

                VStack(alignment: .leading, spacing: 6) {
                    PostHeader(post: post)
                    PostBody(post: post)
                    PostActionBar(post: post)
                        .padding(.top, 2)
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
}

private struct RepostLabelStyle: LabelStyle {
    let indent: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
            }
        }
    }

    private var name: some View {
        HStack(spacing: 4) {
            Text(post.author.name)
                .font(.postName)
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
            .font(.postMeta)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Text, media, quote and link card.
struct PostBody: View {
    let post: XPost
    var textStyle: Font = .postBody

    @Environment(Session.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !post.replyingTo.isEmpty {
                Text("Replying to \(Text(post.replyingTo.map { "@\($0)" }.joined(separator: " ")).foregroundStyle(Theme.accent))")
                    .font(.postMeta)
                    .foregroundStyle(.secondary)
            }
            if !post.text.characters.isEmpty {
                Text(post.text)
                    .font(textStyle)
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
