import SwiftUI
import XKit

/// X's compact composer, used both for replies (docked at the bottom of a
/// post page, growing while you type) and for new posts (a floating glass
/// card above the keyboard). Expand opens the full composer with the draft.
struct QuickComposer: View {
    enum Mode {
        case post
        case reply(XPost)
    }

    let mode: Mode
    /// Floating new-post card: always expanded, focused, closable.
    var isFloating = false
    var onDismiss: (() -> Void)?
    let onSent: (XPost) -> Void

    @Environment(Session.self) private var session
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private let limit = 280

    private var replyingTo: XPost? {
        if case .reply(let post) = mode { post } else { nil }
    }

    private var isExpanded: Bool { isFloating || isFocused || !text.isEmpty }
    private var count: Int { PostLength.weighted(text) }
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && count <= limit && !isSending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isExpanded, let post = replyingTo {
                Text("Replying to \(Text(recipients(of: post)).foregroundStyle(Theme.accent))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: isFloating ? .top : .center, spacing: 10) {
                Avatar(user: session.me, size: isExpanded ? 34 : 28)
                TextField(replyingTo == nil ? "What's happening?" : "Post your reply", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(isFloating ? .title3 : .body)
                    .lineLimit(isFloating ? 3...8 : 1...6)
                    .focused($isFocused)
                    .padding(.top, isFloating ? 5 : 0)
            }
            if isExpanded {
                HStack(spacing: 14) {
                    if replyingTo == nil {
                        Label("Everyone can reply", systemImage: "globe")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    if !text.isEmpty {
                        CharacterRing(count: count, limit: limit)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        let draft = text
                        text = ""
                        isFocused = false
                        onDismiss?()
                        session.openFullComposer(replyingTo: replyingTo, draft: draft)
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
                    .accessibilityLabel(replyingTo == nil ? "Post" : "Reply")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 14 : 9)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: isExpanded ? 26 : 24))
        .overlay(alignment: .topTrailing) {
            if let onDismiss {
                Button {
                    isFocused = false
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .offset(x: 6, y: -10)
                .hoverPointer()
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
        }
        .animation(.snappy(duration: 0.3), value: isExpanded)
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
        .onAppear { if isFloating { isFocused = true } }
    }

    /// "@author and @other", like X's "Replying to" line.
    private func recipients(of post: XPost) -> String {
        var names = [post.author.username]
        for name in post.replyingTo where !names.contains(name) { names.append(name) }
        let handles = names.prefix(3).map { "@\($0)" }
        return handles.count > 1 ? handles.dropLast().joined(separator: ", ") + " and " + handles.last! : handles[0]
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let post = try await session.service.createPost(text: body, replyingTo: replyingTo?.id)
            text = ""
            isFocused = false
            session.didPost(post, replyingTo: replyingTo)
            onSent(post)
        } catch {
            session.report(error)
        }
    }
}

enum PostLength {
    /// X counts every link as 23 characters; close enough for a meter.
    static func weighted(_ text: String) -> Int {
        var count = 0
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            count += (word.hasPrefix("http://") || word.hasPrefix("https://")) ? 23 : word.count
            count += 1
        }
        return max(0, count - 1)
    }
}

/// The floating new-post (or reply) card over the whole app: dims the
/// content behind, rises with the keyboard, closes on tap outside when empty.
/// The dimming fades in place while only the card moves.
struct FloatingComposer: View {
    let context: QuickComposeContext?

    @Environment(Session.self) private var session

    var body: some View {
        // iPhone: docked above the keyboard. Mac: a centred panel, clear of the rail.
        ZStack(alignment: placement) {
            if context != nil {
                Color.black.opacity(dimming)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }
            if let context {
                QuickComposer(mode: context.replyingTo.map { .reply($0) } ?? .post, isFloating: true, onDismiss: close) { _ in
                    close()
                }
                #if os(macOS)
                .frame(maxWidth: 600)
                .padding(.bottom, 140)
                // Centre over the content, not the whole window (clear of the rail).
                .padding(.leading, 104)
                .padding(.trailing, 16)
                #else
                .readableWidth()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                #endif
                .id(context.id)
                .transition(cardTransition)
            }
        }
    }

    /// The Mac panel grows out of the centre; the iPhone card rises a little
    /// with the keyboard instead of travelling up from off screen.
    private var cardTransition: AnyTransition {
        #if os(macOS)
        .scale(scale: 0.94).combined(with: .opacity)
        #else
        .offset(y: 24).combined(with: .opacity)
        #endif
    }

    /// Stronger on the Mac, where the panel floats over bright media.
    private var dimming: Double {
        #if os(macOS)
        0.5
        #else
        0.28
        #endif
    }

    private var placement: Alignment {
        #if os(macOS)
        .center
        #else
        .bottom
        #endif
    }

    private func close() {
        withAnimation(.snappy(duration: 0.3)) { session.quickComposer = nil }
    }
}
