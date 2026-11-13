import Foundation

/// Collects a translation from x.com's `2/grok/translation.json`, which answers
/// with newline-delimited JSON. Each line is either
/// `{"result":{"content_type":"POST","text":…,"entities":{…}}}` with the next
/// piece of the text, or `{"error":{"code":…,"message":…}}`. Read from x.com's
/// web client bundle on 2026-11-13; see docs/web-session.md.
struct GrokTranslation {
    private(set) var text = ""
    private var urls: [LinkEntity] = []

    /// Adds one line of the response and returns whether anything changed.
    mutating func add(_ line: String) throws -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSONObject else {
            return false
        }
        if let error = object.object("error") {
            throw XAPIError.server(status: error.int("code") ?? 0, message: error.string("message"))
        }
        // Polls send their choices as "POLL" lines; only the text is shown.
        guard let result = object.object("result"), result.string("content_type") == "POST" else { return false }
        let links = result.objects("entities.urls").compactMap { url -> LinkEntity? in
            guard let short = url.string("url") else { return nil }
            return LinkEntity(shortURL: short, expandedURL: url.string("expanded_url").flatMap(URL.init(string:)), displayURL: url.string("display_url"))
        }
        urls += links
        let piece = result["text"] as? String ?? ""
        text += piece
        return !piece.isEmpty || !links.isEmpty
    }

    /// The text so far, prepared like the original: links to the post's own
    /// media and quoted post hidden, other links in their display form.
    func rendered(for post: XPost) -> AttributedString {
        var hidden: Set<String> = []
        var links: [LinkEntity] = []
        for url in urls {
            let expanded = url.expandedURL?.absoluteString ?? ""
            let isMedia = expanded.contains("/photo/") || expanded.contains("/video/")
            let isQuote = post.quoted.map { expanded.contains("/status/\($0.id)") } ?? false
            if isMedia || isQuote { hidden.insert(url.shortURL) } else { links.append(url) }
        }
        // A media link isn't a URL entity, so it's the t.co link nothing explains.
        if !post.media.isEmpty {
            for match in text.matches(of: /https:\/\/t\.co\/[A-Za-z0-9]+/) where !urls.contains(where: { $0.shortURL == match.output }) {
                hidden.insert(String(match.output))
            }
        }
        return RichText.make(text, links: links, hiding: hidden, stripLeadingMentions: !post.replyingTo.isEmpty)
    }
}
