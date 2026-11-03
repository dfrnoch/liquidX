import Foundation
import Testing
@testable import XKit

struct WebParserTests {
    private func load() throws -> (items: [XTimelineItem], bottomCursor: String?) {
        let url = try #require(Bundle.module.url(forResource: "web_home_timeline", withExtension: "json", subdirectory: "Fixtures"))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return GraphQLParser.timeline(root)
    }

    @Test func skipsPromotedTombstonesAndCursors() throws {
        let page = try load()
        #expect(page.items.map(\.id) == ["100", "200", "300"])
        #expect(page.bottomCursor == "NEXT-PAGE")
    }

    @Test func photoPostWithViewerState() throws {
        let post = try load().items[0].post
        #expect(post.plainText == "Glass everywhere & nowhere")
        #expect(post.media.first?.altText == "A glass desk")
        #expect(post.media.first?.aspectRatio == 1.6)
        #expect(post.metrics.views == 9_200)
        #expect(post.viewer == ViewerState(liked: true, reposted: false, bookmarked: true))
        #expect(post.createdAt == Date(timeIntervalSince1970: 1_793_656_800))
    }

    @Test func userFromNewFieldLayout() throws {
        let author = try load().items[0].post.author
        #expect(author.username == "miraokafor")
        #expect(author.verification == .blue)
        #expect(author.followers == 48_200)
        #expect(author.isFollowedByMe == true)
        #expect(author.avatarURL?.absoluteString == "https://pbs.twimg.com/profile_images/1/m_400x400.jpg")
        #expect(author.bannerURL?.absoluteString == "https://pbs.twimg.com/profile_banners/1/123/1500x500")
        #expect(String(author.bio.characters) == "Designer at northwind.example")
    }

    @Test func repostUnwrapsVisibilityResultsAndPicksBestVideo() throws {
        let item = try load().items[1]
        #expect(item.repostedBy?.username == "jberg")
        #expect(item.post.id == "150")
        #expect(item.post.author.verification == .business)
        #expect(item.post.plainText == "Aurora tonight")
        #expect(item.post.media.first?.kind == .video)
        #expect(item.post.media.first?.videoURL?.absoluteString == "https://video.twimg.com/high.mp4")
        #expect(item.post.viewer?.reposted == true)
    }

    @Test func replyUsesLongTextAndQuote() throws {
        let post = try load().items[2].post
        #expect(post.plainText == "This is the full long text of the reply")
        #expect(post.replyingTo == ["miraokafor"])
        #expect(post.replyToID == "100")
        #expect(post.quoted?.author.username == "swiftweekly")
    }

    @Test func parsesMainBundle() {
        let script = #"a="AAAAAAAAAAAAAAAAAAAAAtest%3Dtoken";e.exports={queryId:"abc123",operationName:"UserByScreenName",operationType:"query",metadata:{featureSwitches:["f_one","f_two"],fieldToggles:["withPayments"]}}"#
        let parsed = WebAPIConfig.parse(script)
        #expect(parsed.bearer == "AAAAAAAAAAAAAAAAAAAAAtest=token")
        #expect(parsed.operations["UserByScreenName"] == WebOperation(queryId: "abc123", features: ["f_one", "f_two"], fieldToggles: ["withPayments"]))
    }

    @Test func featureValues() {
        let operation = WebOperation(queryId: "q", features: ["rweb_video_screen_enabled", "view_counts_everywhere_api_enabled"], fieldToggles: ["withPayments", "withArticleRichContentState"])
        #expect(operation.featuresJSON == ["rweb_video_screen_enabled": false, "view_counts_everywhere_api_enabled": true])
        #expect(operation.fieldTogglesJSON == ["withPayments": false, "withArticleRichContentState": true])
    }

    @Test func sessionCookies() {
        let credentials = WebCredentials(cookies: ["auth_token": "a", "ct0": "c", "twid": "u%3D42"], userAgent: "UA")
        #expect(credentials.isComplete)
        #expect(credentials.userID == "42")
        #expect(credentials.cookieHeader == "auth_token=a; ct0=c; twid=u%3D42")
        #expect(!WebCredentials(cookies: ["ct0": "c"], userAgent: "UA").isComplete)
    }
}
