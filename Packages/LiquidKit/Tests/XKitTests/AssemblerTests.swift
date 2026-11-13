import Foundation
import Testing
@testable import XKit

struct AssemblerTests {
    private func load() throws -> (items: [XTimelineItem], meta: WireMeta?) {
        let url = try #require(Bundle.module.url(forResource: "home_timeline", withExtension: "json", subdirectory: "Fixtures"))
        let envelope = try JSONDecoder.xAPI.decode(WireEnvelope<[WireTweet]>.self, from: Data(contentsOf: url))
        return (Assembler(envelope.includes).items(envelope.data ?? []), envelope.meta)
    }

    @Test func repostShowsOriginalWithReposter() throws {
        let item = try load().items[0]
        #expect(item.id == "1850000000000000003")
        #expect(item.post.id == "1850000000000000001")
        #expect(item.repostedBy?.username == "avalind")
        #expect(item.post.author.username == "orbitlab")
        #expect(item.post.author.verification == .business)
        #expect(item.post.metrics.views == 1_220_000)
    }

    @Test func mediaLinksAreHiddenAndMediaAttached() throws {
        let post = try load().items[0].post
        #expect(post.plainText == "Aurora tonight!")
        #expect(post.media.count == 1)
        #expect(post.media[0].altText == "Green sky")
        #expect(post.media[0].aspectRatio == 1.5)
    }

    @Test func quoteAndLinkCard() throws {
        let post = try load().items[1].post
        #expect(post.plainText == "So good & worth reading example.com/article #SwiftUI cc @orbitlab")
        #expect(post.quoted?.author.username == "swiftweekly")
        #expect(post.language == "en")
        #expect(post.card?.title == "An \"article\"")
        #expect(post.card?.host == "example.com")
        #expect(post.card?.imageURL?.absoluteString == "https://pbs.twimg.com/news_img/a.jpg")

        let links = post.text.runs.compactMap(\.link)
        #expect(links.contains(URL(string: "https://example.com/article")!))
        #expect(links.contains(AppLink.search("#SwiftUI").url))
        #expect(links.contains(AppLink.user("orbitlab").url))
    }

    @Test func replyUsesLongTextAndStripsLeadingMentions() throws {
        let post = try load().items[2].post
        #expect(post.plainText == "Thanks, this is the full long version of the post.")
        #expect(post.replyingTo == ["orbitlab"])
        #expect(post.conversationID == "1850000000000000001")
        #expect(post.replyToID == "1850000000000000001")
    }

    @Test func avatarsUseLargeRendition() throws {
        let author = try load().items[0].repostedBy
        #expect(author?.avatarURL?.absoluteString == "https://pbs.twimg.com/profile_images/1/a_400x400.jpg")
    }

    @Test func paginationMeta() throws {
        #expect(try load().meta?.next_token == "7140dibdnow9c7btw4")
    }

    @Test func videoPicksHighestBitrateMP4() {
        let wire = WireMedia(
            media_key: "7_2", type: "video", url: nil, preview_image_url: "https://pbs.twimg.com/t.jpg",
            width: nil, height: nil, alt_text: nil, duration_ms: 61_500,
            variants: [
                .init(bit_rate: nil, content_type: "application/x-mpegURL", url: "https://video.twimg.com/x.m3u8"),
                .init(bit_rate: 832_000, content_type: "video/mp4", url: "https://video.twimg.com/low.mp4"),
                .init(bit_rate: 2_176_000, content_type: "video/mp4", url: "https://video.twimg.com/high.mp4"),
            ]
        )
        let media = Assembler.media(wire)
        #expect(media.kind == .video)
        #expect(media.videoURL?.absoluteString == "https://video.twimg.com/high.mp4")
        #expect(media.duration == 61.5)
        #expect(media.imageURL?.absoluteString == "https://pbs.twimg.com/t.jpg")
    }

    @Test func timelineItemsRoundTripThroughCache() throws {
        let page = TimelinePage(items: try load().items, nextCursor: "abc")
        let decoded = try JSONDecoder().decode(TimelinePage.self, from: JSONEncoder().encode(page))
        #expect(decoded == page)
        #expect(decoded.items[1].post.text.runs.compactMap(\.link).count == 3)
    }
}
