import Foundation

/// Joins a v2 response's `data` with its `includes` (authors, referenced posts,
/// media) and produces display-ready models. Pure and synchronous; runs off the
/// main actor inside `XClient`.
struct Assembler {
    private let users: [String: WireUser]
    private let tweets: [String: WireTweet]
    private let media: [String: WireMedia]

    init(_ includes: WireIncludes?) {
        users = Dictionary((includes?.users ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        tweets = Dictionary((includes?.tweets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        media = Dictionary((includes?.media ?? []).map { ($0.media_key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func items(_ data: [WireTweet]) -> [XTimelineItem] {
        data.map(item)
    }

    func item(_ tweet: WireTweet) -> XTimelineItem {
        if let originalID = tweet.reference("retweeted"), let original = tweets[originalID] {
            var reposted = post(original)
            // Without the referenced-media expansion, the repost itself carries
            // the original's media keys.
            if reposted.media.isEmpty { reposted.media = mediaItems(tweet) }
            return XTimelineItem(id: tweet.id, post: reposted, repostedBy: author(of: tweet))
        }
        return XTimelineItem(id: tweet.id, post: post(tweet))
    }

    func post(_ tweet: WireTweet) -> XPost {
        let quotedID = tweet.reference("quoted")
        let attachedMedia = mediaItems(tweet)
        let (text, card) = content(of: tweet, quotedID: quotedID, hasMedia: !attachedMedia.isEmpty)
        let replyingTo: [String] = tweet.reference("replied_to") != nil
            ? [tweet.in_reply_to_user_id.flatMap { users[$0]?.username }].compactMap { $0 }
            : []
        let metrics = tweet.public_metrics
        return XPost(
            id: tweet.id,
            author: author(of: tweet),
            createdAt: tweet.created_at ?? .distantPast,
            text: text,
            media: attachedMedia,
            metrics: XPost.Metrics(
                replies: metrics?.reply_count ?? 0,
                reposts: metrics?.retweet_count ?? 0,
                likes: metrics?.like_count ?? 0,
                quotes: metrics?.quote_count ?? 0,
                bookmarks: metrics?.bookmark_count ?? 0,
                views: metrics?.impression_count
            ),
            conversationID: tweet.conversation_id,
            replyingTo: replyingTo,
            replyToID: tweet.reference("replied_to"),
            quoted: quotedID.flatMap { tweets[$0] }.map(quote),
            card: card
        )
    }

    private func quote(_ tweet: WireTweet) -> XQuotedPost {
        let attachedMedia = mediaItems(tweet)
        let (text, _) = content(of: tweet, quotedID: tweet.reference("quoted"), hasMedia: !attachedMedia.isEmpty)
        return XQuotedPost(
            id: tweet.id,
            author: author(of: tweet),
            createdAt: tweet.created_at ?? .distantPast,
            text: text,
            media: attachedMedia
        )
    }

    private func author(of tweet: WireTweet) -> XUser {
        guard let id = tweet.author_id else { return .unknown(id: "0") }
        return users[id].map(Self.user) ?? .unknown(id: id)
    }

    private func mediaItems(_ tweet: WireTweet) -> [XMedia] {
        (tweet.attachments?.media_keys ?? []).compactMap { media[$0] }.map(Self.media)
    }

    /// Long posts carry their full text in `note_tweet`; links to attached media
    /// and to the quoted post are hidden because they render as media/quote cards.
    private func content(of tweet: WireTweet, quotedID: String?, hasMedia: Bool) -> (AttributedString, XLinkCard?) {
        let raw = tweet.note?.text ?? tweet.text
        let urls = (tweet.note?.entities ?? tweet.entities)?.urls ?? []
        var hidden: Set<String> = []
        var links: [LinkEntity] = []
        var card: XLinkCard?

        for url in urls {
            let expanded = url.expanded_url ?? ""
            let isMedia = url.media_key != nil || (hasMedia && (expanded.contains("/photo/") || expanded.contains("/video/")))
            let isQuote = quotedID.map { expanded.contains("/status/\($0)") } ?? false
            if isMedia || isQuote {
                hidden.insert(url.url)
                continue
            }
            let target = URL(string: url.unwound_url ?? expanded)
            links.append(LinkEntity(shortURL: url.url, expandedURL: target, displayURL: url.display_url))
            if card == nil, let target, let title = url.title, !title.isEmpty {
                card = XLinkCard(
                    url: target,
                    host: target.host()?.replacingOccurrences(of: "www.", with: "") ?? "",
                    title: RichText.decodeEntities(title),
                    summary: url.description.map(RichText.decodeEntities),
                    imageURL: url.images?.max { ($0.width ?? 0) < ($1.width ?? 0) }.flatMap { URL(string: $0.url) }
                )
            }
        }
        let text = RichText.make(
            raw,
            links: links,
            hiding: hidden,
            stripLeadingMentions: tweet.reference("replied_to") != nil
        )
        return (text, card)
    }

    static func media(_ wire: WireMedia) -> XMedia {
        let kind = XMedia.Kind(rawValue: wire.type) ?? .photo
        let video = wire.variants?
            .filter { $0.content_type == "video/mp4" }
            .max { ($0.bit_rate ?? 0) < ($1.bit_rate ?? 0) }
        return XMedia(
            id: wire.media_key,
            kind: kind,
            imageURL: URL(string: wire.url ?? wire.preview_image_url ?? ""),
            videoURL: video.flatMap { URL(string: $0.url) },
            width: wire.width,
            height: wire.height,
            altText: wire.alt_text,
            duration: wire.duration_ms.map { TimeInterval($0) / 1_000 }
        )
    }

    static func user(_ wire: WireUser) -> XUser {
        let verification: XUser.Verification = switch wire.verified_type {
        case "business": .business
        case "government": .government
        case "blue": .blue
        default: wire.verified == true ? .blue : .none
        }
        let bioLinks = (wire.entities?.description?.urls ?? []).map {
            LinkEntity(shortURL: $0.url, expandedURL: URL(string: $0.expanded_url ?? $0.url), displayURL: $0.display_url)
        }
        let website = wire.entities?.url?.urls?.first
        let connections = wire.connection_status
        return XUser(
            id: wire.id,
            name: RichText.decodeEntities(wire.name),
            username: wire.username,
            avatarURL: wire.profile_image_url.flatMap { URL(string: $0.replacingOccurrences(of: "_normal.", with: "_400x400.")) },
            bannerURL: wire.profile_banner_url.flatMap { URL(string: $0.hasSuffix("/1500x500") ? $0 : $0 + "/1500x500") },
            bio: RichText.make(wire.description ?? "", links: bioLinks),
            verification: verification,
            isProtected: wire.protected ?? false,
            location: wire.location.flatMap { $0.isEmpty ? nil : $0 },
            website: URL(string: website?.expanded_url ?? wire.url ?? ""),
            websiteDisplay: website?.display_url,
            joined: wire.created_at,
            followers: wire.public_metrics?.followers_count ?? 0,
            following: wire.public_metrics?.following_count ?? 0,
            postCount: wire.public_metrics?.tweet_count ?? 0,
            isFollowedByMe: connections.map { $0.contains("following") }
        )
    }
}
