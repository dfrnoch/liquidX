import Foundation
import Testing
@testable import XKit

struct GrokTranslationTests {
    private func post(media: [XMedia] = [], replyingTo: [String] = []) -> XPost {
        XPost(id: "1", author: .unknown(id: "2"), createdAt: .distantPast, text: RichText.make("Ciao"), media: media, replyingTo: replyingTo, language: "it")
    }

    @Test func joinsStreamedPiecesWithLinks() throws {
        var translation = GrokTranslation()
        #expect(try translation.add(#"{"result":{"content_type":"POST","text":"Read this "}}"#))
        #expect(try translation.add(#"{"result":{"content_type":"POST","text":"https://t.co/a &amp; #Glass","entities":{"urls":[{"url":"https://t.co/a","expanded_url":"https://example.com/a","display_url":"example.com/a","indices":[10,24]}]}}}"#))
        #expect(try !translation.add(""))

        let text = translation.rendered(for: post())
        #expect(String(text.characters) == "Read this example.com/a & #Glass")
        #expect(text.runs.compactMap(\.link) == [URL(string: "https://example.com/a")!, AppLink.search("#Glass").url])
    }

    @Test func hidesMediaLinksAndLeadingMentions() throws {
        var translation = GrokTranslation()
        _ = try translation.add(#"{"result":{"content_type":"POST","text":"@mira Look at this https://t.co/pic"}}"#)
        let media = XMedia(id: "m", kind: .photo, imageURL: nil, width: 1, height: 1)
        #expect(String(translation.rendered(for: post(media: [media], replyingTo: ["mira"])).characters) == "Look at this")
    }

    @Test func skipsPollChoicesAndThrowsServerErrors() throws {
        var translation = GrokTranslation()
        #expect(try !translation.add(#"{"result":{"content_type":"POLL","index":0,"text":"Yes"}}"#))
        #expect(translation.text.isEmpty)
        #expect(throws: XAPIError.server(status: 131, message: "Grok is busy")) {
            try translation.add(#"{"error":{"code":131,"message":"Grok is busy"}}"#)
        }
    }
}

struct PostLanguageTests {
    private func post(_ language: String?) -> XPost {
        XPost(id: "1", author: .unknown(id: "2"), createdAt: .distantPast, text: RichText.make("Text"), language: language)
    }

    @Test func offersOtherLanguagesOnly() {
        let english = Locale.Language(identifier: "en-US")
        #expect(post("it").isTranslatable(for: english))
        #expect(!post("en").isTranslatable(for: english))
        #expect(post("en").isTranslatable(for: Locale.Language(identifier: "cs-CZ")))
    }

    @Test func ignoresTextWithoutALanguage() {
        let english = Locale.Language(identifier: "en")
        for code in [nil, "", "und", "zxx", "qme", "qht"] {
            #expect(!post(code).isTranslatable(for: english))
        }
    }

    @Test func mapsRetiredCodes() {
        #expect(post("in").spokenLanguage?.languageCode?.identifier == "id")
        #expect(post("iw").spokenLanguage?.languageCode?.identifier == "he")
    }

    @Test func translatedTextKeepsTheOriginalsLinks() {
        let original = RichText.make(
            "Mira lo dice https://t.co/x",
            links: [LinkEntity(shortURL: "https://t.co/x", expandedURL: URL(string: "https://example.com/a"), displayURL: "example.com/a")]
        )
        let text = RichText.translation("Mira says so example.com/a @mira", of: original)
        #expect(text.runs.compactMap(\.link) == [URL(string: "https://example.com/a")!, AppLink.user("mira").url])
    }
}
