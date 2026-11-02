public import Foundation

/// A shortened link from the API's `entities.urls`.
public struct LinkEntity: Hashable, Sendable {
    public var shortURL: String
    public var expandedURL: URL?
    public var displayURL: String?

    public init(shortURL: String, expandedURL: URL?, displayURL: String?) {
        self.shortURL = shortURL
        self.expandedURL = expandedURL
        self.displayURL = displayURL
    }
}

/// Turns raw post text into display-ready attributed text: decodes HTML
/// entities, swaps t.co links for their display form, hides media/quote links,
/// and links mentions, hashtags and cashtags to in-app destinations.
///
/// Entity *indices* are deliberately ignored: they disagree between UTF-16,
/// code points and grapheme clusters across API versions; matching the literal
/// short URL is robust and cheap.
public enum RichText {
    public static func make(
        _ raw: String,
        links: [LinkEntity] = [],
        hiding hidden: Set<String> = [],
        stripLeadingMentions: Bool = false
    ) -> AttributedString {
        var text = decodeEntities(raw)
        if stripLeadingMentions {
            text = text.replacing(/^(?:@\w{1,15}\s+)+/, with: "")
        }
        if !hidden.isEmpty {
            for short in hidden {
                text = text.replacingOccurrences(of: short, with: "")
            }
            // Removing a link mid-text leaves doubled or trailing spaces behind.
            text = text.replacing(/[ \t]{2,}/, with: " ").replacing(/\ +\n/, with: "\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var result = AttributedString(text)
        for link in links where !hidden.contains(link.shortURL) {
            replace(link, in: &result)
        }
        linkPatterns(in: &result)
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replace(_ link: LinkEntity, in result: inout AttributedString) {
        let target = link.expandedURL ?? URL(string: link.shortURL)
        let display = link.displayURL ?? link.expandedURL?.host() ?? link.shortURL
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let range = result[searchStart...].range(of: link.shortURL) {
            var replacement = AttributedString(display)
            replacement.link = target
            result.replaceSubrange(range, with: replacement)
            // Indices are invalidated by the replacement; continue after it.
            let offset = result.characters.distance(from: result.startIndex, to: range.lowerBound) + replacement.characters.count
            searchStart = result.characters.index(result.startIndex, offsetBy: offset)
        }
    }

    // `NSRegularExpression` supports the lookbehinds Swift Regex lacks.
    private static let mention = try! NSRegularExpression(pattern: #"(?<![\w@/])@([A-Za-z0-9_]{1,15})\b"#)
    private static let tag = try! NSRegularExpression(pattern: #"(?<![\w&/])([#$])([\p{L}\p{N}_]*\p{L}[\p{L}\p{N}_]*)"#)

    private static func linkPatterns(in result: inout AttributedString) {
        let string = String(result.characters)
        guard string.contains("@") || string.contains("#") || string.contains("$") || string.contains("http") else { return }
        let whole = NSRange(string.startIndex..., in: string)
        var pending: [(Range<String.Index>, URL)] = []

        for match in mention.matches(in: string, range: whole) {
            guard let range = Range(match.range, in: string),
                  let nameRange = Range(match.range(at: 1), in: string) else { continue }
            pending.append((range, AppLink.user(String(string[nameRange])).url))
        }
        for match in tag.matches(in: string, range: whole) {
            guard let range = Range(match.range, in: string) else { continue }
            pending.append((range, AppLink.search(String(string[range])).url))
        }
        if string.contains("http"), let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: string, range: whole) {
                guard let url = match.url, let range = Range(match.range, in: string) else { continue }
                pending.append((range, url))
            }
        }

        for (range, url) in pending {
            guard let attributed = Range<AttributedString.Index>(range, in: result) else { continue }
            // Never re-link text that already carries an expanded URL.
            guard result[attributed].runs.allSatisfy({ $0.link == nil }) else { continue }
            result[attributed].link = url
        }
    }
}
