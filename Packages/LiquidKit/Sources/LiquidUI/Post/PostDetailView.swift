import SwiftUI
import XKit

/// A post with its full timestamp and counts, followed by the replies in its
/// conversation (via recent search, so replies older than 7 days are absent).
struct PostDetailView: View {
    let post: XPost

    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(\.postStyle) private var style
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
                        Text(post.author.name).font(style.detailName)
                        VerifiedBadge(verification: post.author.verification, size: 16)
                    }
                    Text(post.author.handle).font(style.meta).foregroundStyle(.secondary)
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
        InlineReplyComposer(post: post) { reply in
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

/// X's inline reply box: a slim glass bar that grows into a small composer
/// (who you're replying to, the text, expand and send) while you type.
private struct InlineReplyComposer: View {
    let post: XPost
    let onSent: (XPost) -> Void

    @Environment(Session.self) private var session
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private var isExpanded: Bool { isFocused || !text.isEmpty }
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending }

    /// "@author and @other", like X's "Replying to" line.
    private var recipients: String {
        var names = [post.author.username]
        for name in post.replyingTo where !names.contains(name) { names.append(name) }
        let handles = names.prefix(3).map { "@\($0)" }
        return handles.count > 1 ? handles.dropLast().joined(separator: ", ") + " and " + handles.last! : handles[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isExpanded {
                Text("Replying to \(Text(recipients).foregroundStyle(Theme.accent))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .center, spacing: 10) {
                Avatar(user: session.me, size: isExpanded ? 34 : 28)
                TextField("Post your reply", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit { if canSend { Task { await send() } } }
            }
            if isExpanded {
                HStack(spacing: 14) {
                    Spacer()
                    Button {
                        session.compose(replyingTo: post, draft: text)
                        text = ""
                        isFocused = false
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .hoverPointer()
                    .accessibilityLabel("Open full composer")

                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "arrow.up").font(.body.weight(.bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Theme.accent.opacity(canSend ? 1 : 0.4)).interactive(), in: .circle)
                    .disabled(!canSend)
                    .hoverPointer()
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Reply")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 14 : 9)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: isExpanded ? 26 : 24))
        .animation(.snappy(duration: 0.3), value: isExpanded)
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await session.service.createPost(text: body, replyingTo: post.id)
            text = ""
            isFocused = false
            session.didPost(reply, replyingTo: post)
            onSent(reply)
        } catch {
            session.report(error)
        }
    }
}
