import Foundation

/// Untyped access to x.com's deeply nested GraphQL JSON. The schema is
/// unofficial and shifts often, so parsing is deliberately forgiving: every
/// field is optional and older field locations are tried as fallbacks.
typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func value(_ path: String) -> Any? {
        var current: Any? = self
        for key in path.split(separator: ".") {
            current = (current as? JSONObject)?[String(key)]
        }
        return current
    }

    func object(_ path: String) -> JSONObject? { value(path) as? JSONObject }
    func objects(_ path: String) -> [JSONObject] { value(path) as? [JSONObject] ?? [] }

    func string(_ path: String) -> String? {
        switch value(path) {
        case let string as String: string.isEmpty ? nil : string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    func int(_ path: String) -> Int? {
        switch value(path) {
        case let number as NSNumber: number.intValue
        case let string as String: Int(string)
        default: nil
        }
    }

    func bool(_ path: String) -> Bool? { (value(path) as? NSNumber)?.boolValue }
}

enum GraphQLParser {
    // MARK: - Timelines

    /// Finds the first `instructions` array under `data`, wherever this
    /// operation nests it (home_timeline_urt, timeline_v2, search_timeline...).
    static func instructions(in root: JSONObject) -> [JSONObject] {
        func search(_ value: Any, depth: Int) -> [JSONObject]? {
            guard depth < 8 else { return nil }
            if let object = value as? JSONObject {
                if let instructions = object["instructions"] as? [JSONObject] { return instructions }
                for child in object.values {
                    if let found = search(child, depth: depth + 1) { return found }
                }
            }
            return nil
        }
        return search(root["data"] ?? root, depth: 0) ?? []
    }

    static func timeline(_ root: JSONObject) -> (items: [XTimelineItem], bottomCursor: String?) {
        var items: [XTimelineItem] = []
        var cursor: String?
        for instruction in instructions(in: root) {
            var entries = instruction.objects("entries")
            if let entry = instruction.object("entry") { entries.append(entry) }
            for entry in entries {
                let entryID = entry.string("entryId") ?? ""
                let content = entry.object("content") ?? [:]
                if content.string("cursorType") == "Bottom" || entryID.hasPrefix("cursor-bottom") {
                    cursor = content.string("value") ?? cursor
                    continue
                }
                if entryID.hasPrefix("promoted-") { continue }
                if let itemContent = content.object("itemContent") {
                    if let item = item(fromItemContent: itemContent) { items.append(item) }
                }
                for moduleItem in content.objects("items") {
                    if let itemContent = moduleItem.object("item.itemContent"), let item = item(fromItemContent: itemContent) {
                        items.append(item)
                    }
                }
            }
        }
        return (items, cursor)
    }

    /// People search: `TimelineUser` entries.
    static func users(_ root: JSONObject) -> (users: [XUser], bottomCursor: String?) {
        var users: [XUser] = []
        var cursor: String?
        for instruction in instructions(in: root) {
            for entry in instruction.objects("entries") {
                let content = entry.object("content") ?? [:]
                if content.string("cursorType") == "Bottom" {
                    cursor = content.string("value")
                } else if let result = content.object("itemContent.user_results.result"), let user = user(result) {
                    users.append(user)
                }
            }
        }
        return (users, cursor)
    }

    /// `1.1/search/typeahead.json`: suggested accounts and topics.
    static func suggestions(_ root: JSONObject) -> SearchSuggestions {
        let users = root.objects("users").compactMap { raw -> XUser? in
            guard let id = raw.string("id_str"), let username = raw.string("screen_name") else { return nil }
            return XUser(
                id: id,
                name: RichText.decodeEntities(raw.string("name") ?? username),
                username: username,
                avatarURL: raw.string("profile_image_url_https").flatMap { URL(string: $0.replacingOccurrences(of: "_normal.", with: "_200x200.")) },
                verification: (raw.bool("verified") ?? false) || (raw.bool("ext_is_blue_verified") ?? false) ? .blue : .none,
                isProtected: raw.bool("is_protected") ?? false
            )
        }
        let topics = root.objects("topics").compactMap { $0.string("topic") }
        return SearchSuggestions(users: Array(users.prefix(6)), topics: Array(topics.prefix(5)))
    }

    private static func item(fromItemContent content: JSONObject) -> XTimelineItem? {
        guard content.object("promotedMetadata") == nil, let result = content.object("tweet_results.result") else { return nil }
        return item(fromTweet: result)
    }

    // MARK: - Posts

    /// Unwraps visibility wrappers; returns nil for tombstones and unavailable posts.
    static func unwrap(_ result: JSONObject) -> JSONObject? {
        switch result.string("__typename") {
        case "TweetWithVisibilityResults": result.object("tweet")
        case "TweetTombstone", "TweetUnavailable": nil
        default: result.object("legacy") == nil ? nil : result
        }
    }

    static func item(fromTweet raw: JSONObject) -> XTimelineItem? {
        guard let tweet = unwrap(raw), let id = tweet.string("rest_id") else { return nil }
        if let retweeted = tweet.object("legacy.retweeted_status_result.result"),
           let original = post(from: retweeted, allowQuote: true) {
            return XTimelineItem(id: id, post: original, repostedBy: author(of: tweet))
        }
        return post(from: tweet, allowQuote: true).map(XTimelineItem.init)
    }

    static func post(from raw: JSONObject, allowQuote: Bool) -> XPost? {
        guard let tweet = unwrap(raw), let id = tweet.string("rest_id"), let legacy = tweet.object("legacy") else { return nil }
        let media = mediaItems(legacy)
        let quoted = allowQuote ? tweet.object("quoted_status_result.result").flatMap(quote) : nil
        var hidden = Set((legacy.objects("extended_entities.media") + legacy.objects("entities.media")).compactMap { $0.string("url") })
        if quoted != nil, let permalink = legacy.string("quoted_status_permalink.url") { hidden.insert(permalink) }

        let note = tweet.object("note_tweet.note_tweet_results.result")
        let rawText = note?.string("text") ?? legacy.string("full_text") ?? ""
        let urls = note?.objects("entity_set.urls") ?? legacy.objects("entities.urls")
        let links = urls.compactMap { url -> LinkEntity? in
            guard let short = url.string("url") else { return nil }
            return LinkEntity(shortURL: short, expandedURL: url.string("expanded_url").flatMap(URL.init(string:)), displayURL: url.string("display_url"))
        }
        let isReply = legacy.string("in_reply_to_status_id_str") != nil
        return XPost(
            id: id,
            author: author(of: tweet),
            createdAt: legacy.string("created_at").flatMap(parseDate) ?? .distantPast,
            text: RichText.make(rawText, links: links, hiding: hidden, stripLeadingMentions: isReply),
            media: media,
            metrics: XPost.Metrics(
                replies: legacy.int("reply_count") ?? 0,
                reposts: legacy.int("retweet_count") ?? 0,
                likes: legacy.int("favorite_count") ?? 0,
                quotes: legacy.int("quote_count") ?? 0,
                bookmarks: legacy.int("bookmark_count") ?? 0,
                views: tweet.int("views.count")
            ),
            conversationID: legacy.string("conversation_id_str"),
            replyingTo: isReply ? [legacy.string("in_reply_to_screen_name")].compactMap { $0 } : [],
            quoted: quoted,
            card: media.isEmpty && quoted == nil ? card(tweet.object("card.legacy"), links: links) : nil,
            viewer: ViewerState(
                liked: legacy.bool("favorited") ?? false,
                reposted: legacy.bool("retweeted") ?? false,
                bookmarked: legacy.bool("bookmarked") ?? false
            )
        )
    }

    private static func quote(_ raw: JSONObject) -> XQuotedPost? {
        guard let post = post(from: raw, allowQuote: false) else { return nil }
        return XQuotedPost(id: post.id, author: post.author, createdAt: post.createdAt, text: post.text, media: post.media)
    }

    private static func author(of tweet: JSONObject) -> XUser {
        tweet.object("core.user_results.result").flatMap(user) ?? .unknown(id: tweet.string("legacy.user_id_str") ?? "0")
    }

    private static func mediaItems(_ legacy: JSONObject) -> [XMedia] {
        let list = legacy.objects("extended_entities.media").isEmpty ? legacy.objects("entities.media") : legacy.objects("extended_entities.media")
        return list.compactMap { media in
            guard let key = media.string("media_key") ?? media.string("id_str") else { return nil }
            let kind = XMedia.Kind(rawValue: media.string("type") ?? "photo") ?? .photo
            let video = media.objects("video_info.variants")
                .filter { $0.string("content_type") == "video/mp4" }
                .max { ($0.int("bitrate") ?? 0) < ($1.int("bitrate") ?? 0) }
            return XMedia(
                id: key,
                kind: kind,
                imageURL: media.string("media_url_https").flatMap(URL.init(string:)),
                videoURL: video?.string("url").flatMap(URL.init(string:)),
                width: media.int("original_info.width"),
                height: media.int("original_info.height"),
                altText: media.string("ext_alt_text"),
                duration: media.int("video_info.duration_millis").map { TimeInterval($0) / 1_000 }
            )
        }
    }

    /// Link preview from a summary card's binding values.
    private static func card(_ legacy: JSONObject?, links: [LinkEntity]) -> XLinkCard? {
        guard let legacy else { return nil }
        var values: [String: JSONObject] = [:]
        for binding in legacy.objects("binding_values") {
            if let key = binding.string("key"), let value = binding.object("value") { values[key] = value }
        }
        guard let title = values["title"]?.string("string_value") else { return nil }
        let short = legacy.string("url")
        let target = links.first { $0.shortURL == short }?.expandedURL
            ?? values["card_url"]?.string("string_value").flatMap(URL.init(string:))
        guard let target else { return nil }
        let image = ["summary_photo_image_original", "thumbnail_image_original", "photo_image_full_size_original", "player_image_original"]
            .lazy.compactMap { values[$0]?.string("image_value.url") }.first
        return XLinkCard(
            url: target,
            host: values["vanity_url"]?.string("string_value") ?? values["domain"]?.string("string_value")
                ?? target.host()?.replacingOccurrences(of: "www.", with: "") ?? "",
            title: title,
            summary: values["description"]?.string("string_value"),
            imageURL: image.flatMap(URL.init(string:))
        )
    }

    // MARK: - Users

    static func user(_ raw: JSONObject) -> XUser? {
        guard raw.string("__typename") != "UserUnavailable", let id = raw.string("rest_id") else { return nil }
        let legacy = raw.object("legacy") ?? [:]
        func either(_ path: String, _ legacyPath: String) -> String? { raw.string(path) ?? legacy.string(legacyPath) }

        let verification: XUser.Verification = switch raw.string("verification.verified_type") ?? legacy.string("verified_type") {
        case "Business": .business
        case "Government": .government
        default: (raw.bool("is_blue_verified") ?? false) || (raw.bool("verification.verified") ?? false) ? .blue : .none
        }
        let bioURLs = raw.objects("profile_bio.entities.description.urls") + legacy.objects("entities.description.urls")
        let bioLinks = bioURLs.compactMap { url -> LinkEntity? in
            guard let short = url.string("url") else { return nil }
            return LinkEntity(shortURL: short, expandedURL: url.string("expanded_url").flatMap(URL.init(string:)), displayURL: url.string("display_url"))
        }
        let website = (raw.objects("profile_bio.entities.url.urls") + legacy.objects("entities.url.urls")).first
        let avatar = either("avatar.image_url", "profile_image_url_https")?.replacingOccurrences(of: "_normal.", with: "_400x400.")
        let banner = either("banner.image_url", "profile_banner_url").map { $0.hasSuffix("/1500x500") ? $0 : $0 + "/1500x500" }

        return XUser(
            id: id,
            name: RichText.decodeEntities(either("core.name", "name") ?? ""),
            username: either("core.screen_name", "screen_name") ?? id,
            avatarURL: avatar.flatMap(URL.init(string:)),
            bannerURL: banner.flatMap(URL.init(string:)),
            bio: RichText.make(either("profile_bio.description", "description") ?? "", links: bioLinks),
            verification: raw.string("profile_image_shape") == "Square" && verification == .blue ? .business : verification,
            isProtected: raw.bool("privacy.protected") ?? legacy.bool("protected") ?? false,
            location: either("location.location", "location"),
            website: (website?.string("expanded_url") ?? raw.string("website.url")).flatMap(URL.init(string:)),
            websiteDisplay: website?.string("display_url"),
            joined: either("core.created_at", "created_at").flatMap(parseDate),
            followers: raw.int("relationship_counts.followers") ?? legacy.int("followers_count") ?? 0,
            following: raw.int("relationship_counts.following") ?? legacy.int("friends_count") ?? 0,
            postCount: raw.int("tweet_counts.tweets") ?? legacy.int("statuses_count") ?? 0,
            isFollowedByMe: raw.bool("relationship_perspectives.following") ?? legacy.bool("following")
        )
    }

    // MARK: - Dates

    /// "Wed Oct 10 20:19:24 +0000 2018" (Twitter's classic format, always UTC).
    static func parseDate(_ string: String) -> Date? {
        let parts = string.split(separator: " ")
        guard parts.count == 6 else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let time = parts[3].split(separator: ":").compactMap { Int($0) }
        guard let month = months.firstIndex(of: String(parts[1])), time.count == 3,
              let day = Int(parts[2]), let year = Int(parts[5]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month + 1
        components.day = day
        components.hour = time[0]
        components.minute = time[1]
        components.second = time[2]
        return components.date
    }
}
