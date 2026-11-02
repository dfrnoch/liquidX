import SwiftUI
import XKit

/// X's 1–4 media layouts inside one rounded frame.
struct MediaGrid: View {
    let media: [XMedia]
    var cornerRadius: CGFloat = 16
    var maxHeight: CGFloat = 520
    let onOpen: (Int) -> Void

    private let spacing: CGFloat = 2

    var body: some View {
        layout
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var layout: some View {
        switch media.count {
        case 1:
            let ratio = min(max(media[0].aspectRatio ?? 16 / 9, 0.75), 2)
            tile(0)
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
        case 2:
            HStack(spacing: spacing) { tile(0); tile(1) }
                .aspectRatio(16 / 9, contentMode: .fit)
        case 3:
            HStack(spacing: spacing) {
                tile(0)
                VStack(spacing: spacing) { tile(1); tile(2) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        default:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) { tile(0); tile(1) }
                HStack(spacing: spacing) { tile(2); tile(3) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func tile(_ index: Int) -> some View {
        let item = media[index]
        return RemoteImage(item.imageURL(media.count == 1 ? .medium : .small), pointSize: media.count == 1 ? 600 : 320)
            .overlay(alignment: .bottomLeading) {
                if item.kind != .photo {
                    VideoBadge(media: item)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let alt = item.altText, !alt.isEmpty {
                    Text("ALT")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen(index) }
            .accessibilityElement()
            .accessibilityLabel(Text(item.altText ?? (item.kind == .photo ? "Image" : "Video")))
            .accessibilityAddTraits(.isButton)
    }
}

private struct VideoBadge: View {
    let media: XMedia

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
            if media.kind == .animatedGIF {
                Text("GIF")
            } else if let duration = media.duration {
                Text(Formatting.duration(duration)).monospacedDigit()
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(8)
    }
}

struct QuoteCard: View {
    let quote: XQuotedPost

    @Environment(Router.self) private var router
    @Environment(Session.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Avatar(user: quote.author, size: 20)
                Text(quote.author.name).font(.subheadline.weight(.bold)).lineLimit(1)
                VerifiedBadge(verification: quote.author.verification, size: 13)
                Text("\(quote.author.handle) · \(Formatting.relative(quote.createdAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !quote.text.characters.isEmpty {
                Text(quote.text)
                    .font(.subheadline)
                    .lineLimit(6)
                    .tint(Theme.accent)
            }
            if !quote.media.isEmpty {
                MediaGrid(media: quote.media, cornerRadius: 12, maxHeight: 260) { _ in }
                    .allowsHitTesting(false)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            Task {
                if let post = try? await session.service.post(id: quote.id) {
                    router.push(.post(post))
                } else {
                    router.push(.post(XPost(id: quote.id, author: quote.author, createdAt: quote.createdAt, text: quote.text, media: quote.media)))
                }
            }
        }
    }
}

struct LinkCardView: View {
    let card: XLinkCard

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(card.url) } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image = card.imageURL {
                    RemoteImage(image, pointSize: 600)
                        .aspectRatio(1.91, contentMode: .fit)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.host).font(.footnote).foregroundStyle(.secondary)
                    Text(card.title).font(.subheadline).lineLimit(2).foregroundStyle(.primary)
                    if let summary = card.summary {
                        Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(card.title), \(card.host)"))
    }
}
