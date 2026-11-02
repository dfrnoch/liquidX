import Foundation
import Testing
@testable import XKit

struct RichTextTests {
    @Test func linksMentionsHashtagsAndCashtags() {
        let text = RichText.make("Hi @mira, see #Glass and $AAPL. Email me@example.com")
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        #expect(links.map(\.0) == ["@mira", "#Glass", "$AAPL"])
        #expect(links[0].1 == AppLink.user("mira").url)
    }

    @Test func expandsShortLinks() {
        let text = RichText.make(
            "Read https://t.co/x and again https://t.co/x",
            links: [LinkEntity(shortURL: "https://t.co/x", expandedURL: URL(string: "https://example.com/a"), displayURL: "example.com/a")]
        )
        #expect(String(text.characters) == "Read example.com/a and again example.com/a")
        #expect(text.runs.compactMap(\.link).count == 2)
    }

    @Test func decodesEntities() {
        #expect(RichText.decodeEntities("a &amp;lt; b &gt; c &quot;d&quot; &#39;e&#39;") == "a &lt; b > c \"d\" 'e'")
    }
}

struct AppLinkTests {
    @Test func roundTrips() {
        for link in [AppLink.user("jack_dorsey"), .search("#SwiftUI rocks")] {
            #expect(AppLink(url: link.url) == link)
        }
    }

    @Test func recognizesProfileWebLinks() {
        #expect(AppLink(webURL: URL(string: "https://x.com/miraokafor")!) == .user("miraokafor"))
        #expect(AppLink(webURL: URL(string: "https://twitter.com/home")!) == nil)
        #expect(AppLink(webURL: URL(string: "https://x.com/a/status/1")!) == .post("1"))
        #expect(AppLink(webURL: URL(string: "https://twitter.com/a/status/42/photo/1")!) == .post("42"))
        #expect(AppLink(webURL: URL(string: "https://x.com/a/status/abc")!) == nil)
        #expect(AppLink(url: AppLink.post("123").url) == .post("123"))
        #expect(AppLink(webURL: URL(string: "https://example.com/a")!) == nil)
    }
}

struct OAuthTests {
    @Test func pkceChallengeMatchesRFC7636Example() {
        // RFC 7636, Appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierUsesUnreservedCharacters() {
        let verifier = PKCE.makeVerifier()
        #expect(verifier.count == 64)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
    }

    @Test func authorizationURL() throws {
        let request = AuthorizationRequest(configuration: OAuthConfiguration(clientID: " abc123 "))
        let items = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(request.url.host() == "x.com")
        #expect(value("client_id") == "abc123")
        #expect(value("response_type") == "code")
        #expect(value("redirect_uri") == "liquidx://oauth-callback")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == request.state)
        #expect(value("scope")?.split(separator: " ").contains("offline.access") == true)
    }

    @Test func callbackValidation() throws {
        let request = AuthorizationRequest(configuration: OAuthConfiguration(clientID: "abc"))
        let good = URL(string: "liquidx://oauth-callback?state=\(request.state)&code=xyz")!
        #expect(try request.code(from: good) == "xyz")

        let forged = URL(string: "liquidx://oauth-callback?state=nope&code=xyz")!
        #expect(throws: XAPIError.self) { try request.code(from: forged) }

        let denied = URL(string: "liquidx://oauth-callback?error=access_denied&state=\(request.state)")!
        #expect(throws: XAPIError.cancelled) { try request.code(from: denied) }
    }
}

struct FormattingTests {
    @Test func compactCounts() {
        #expect(Formatting.compact(942) == "942")
        #expect(Formatting.compact(9_200) == "9.2K")
        #expect(Formatting.compact(9_999) == "9.9K")
        #expect(Formatting.compact(12_400) == "12K")
        #expect(Formatting.compact(1_000) == "1K")
        #expect(Formatting.compact(1_340_000) == "1.3M")
    }

    @Test func relativeTimes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Formatting.relative(now.addingTimeInterval(-2), now: now) == "now")
        #expect(Formatting.relative(now.addingTimeInterval(-42), now: now) == "42s")
        #expect(Formatting.relative(now.addingTimeInterval(-5 * 60), now: now) == "5m")
        #expect(Formatting.relative(now.addingTimeInterval(-3 * 3_600), now: now) == "3h")
    }

    @Test func photoRenditions() {
        let media = XMedia(id: "1", kind: .photo, imageURL: URL(string: "https://pbs.twimg.com/media/abc.jpg"))
        #expect(media.imageURL(.small)?.absoluteString == "https://pbs.twimg.com/media/abc.jpg?name=small")
    }
}

struct DemoServiceTests {
    @Test func paginatesAndRefreshesSinceNewest() async throws {
        let service = DemoService(latency: .zero)
        let first = try await service.homeTimeline(.newest(since: nil), filter: HomeFilter())
        #expect(first.items.count == 12)
        let cursor = try #require(first.nextCursor)
        let second = try await service.homeTimeline(.older(cursor: cursor), filter: HomeFilter())
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))

        _ = try await service.createPost(text: "Hello", replyingTo: nil)
        let refreshed = try await service.homeTimeline(.newest(since: first.items[0].id), filter: HomeFilter())
        // A demo refresh also "receives" one new post from someone else.
        #expect(refreshed.items.count == 2)
        #expect(refreshed.items[0].post.author.username == "orbitlab")
        #expect(refreshed.items[1].post.plainText == "Hello")
    }

    @Test func filtersRepostsAndReplies() async throws {
        let service = DemoService(latency: .zero)
        let filtered = try await service.homeTimeline(.newest(since: nil), filter: HomeFilter(hideReplies: true, hideReposts: true))
        #expect(filtered.items.allSatisfy { $0.repostedBy == nil && $0.post.replyingTo.isEmpty })
    }
}
