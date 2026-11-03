import SwiftUI
import XKit

struct ComposeView: View {
    let context: ComposerContext

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private let limit = 280

    /// X counts every link as 23 characters; this is close enough for a meter.
    private var weightedCount: Int {
        let urlLength = 23
        var count = 0
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            count += (word.hasPrefix("http://") || word.hasPrefix("https://")) ? urlLength : word.count
            count += 1
        }
        return max(0, count - 1) + (context.quoting == nil ? 0 : urlLength + 1)
    }

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && weightedCount <= limit && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let reply = context.replyingTo {
                        ReplyContext(post: reply)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Avatar(user: session.me, size: 40)
                        TextField(context.replyingTo == nil ? "What's happening?" : "Post your reply", text: $text, axis: .vertical)
                            .font(.title3)
                            .textFieldStyle(.plain)
                            .lineLimit(4...)
                            .focused($isFocused)
                    }
                    if let quoted = context.quoting {
                        QuoteCard(quote: XQuotedPost(id: quoted.id, author: quoted.author, createdAt: quoted.createdAt, text: quoted.text, media: quoted.media))
                            .allowsHitTesting(false)
                            .padding(.leading, 52)
                    }
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Label("Everyone can reply", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    CharacterRing(count: weightedCount, limit: limit)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(context.replyingTo == nil ? "Post" : "Reply").bold()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .disabled(!canPost)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .onAppear {
            if text.isEmpty { text = context.initialText }
            isFocused = true
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 320)
        #endif
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let quoted = context.quoting { body += " \(quoted.url.absoluteString)" }
        do {
            let post = try await session.service.createPost(text: body, replyingTo: context.replyingTo?.id)
            session.didPost(post, replyingTo: context.replyingTo)
            dismiss()
        } catch {
            session.report(error)
        }
    }
}

private struct ReplyContext: View {
    let post: XPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Avatar(user: post.author, size: 40)
                Rectangle().fill(Theme.hairline).frame(width: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                PostHeader(post: post, showsMenu: false)
                Text(post.text).lineLimit(4)
                Text("Replying to \(Text(post.author.handle).foregroundStyle(Theme.accent))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }
}

private struct CharacterRing: View {
    let count: Int
    let limit: Int

    private var remaining: Int { limit - count }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(count) / CGFloat(limit)))
                .stroke(remaining < 0 ? .red : remaining <= 20 ? .orange : Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if remaining <= 20 {
                Text("\(remaining)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(remaining < 0 ? .red : .secondary)
            }
        }
        .frame(width: remaining <= 20 ? 30 : 22, height: remaining <= 20 ? 30 : 22)
        .animation(.snappy, value: remaining <= 20)
        .accessibilityLabel(Text("\(remaining) characters remaining"))
    }
}
