import Foundation

/// Fictional accounts and posts for the demo. Any resemblance to real accounts
/// is unintended; keep it that way when editing.
enum DemoData {
    private static func art(_ seed: String) -> URL { URL(string: "demo://art/\(seed)")! }
    private static func avatar(_ seed: String) -> URL { URL(string: "demo://avatar/\(seed)")! }
    private static func banner(_ seed: String) -> URL { URL(string: "demo://banner/\(seed)")! }

    private static func person(
        _ id: String, _ name: String, _ username: String, bio: String,
        verification: XUser.Verification = .none, location: String? = nil, website: String? = nil,
        followers: Int, following: Int, posts: Int, joined: String
    ) -> XUser {
        XUser(
            id: id,
            name: name,
            username: username,
            avatarURL: avatar(username),
            bannerURL: banner(username),
            bio: RichText.make(bio),
            verification: verification,
            location: location,
            website: website.flatMap { URL(string: "https://\($0)") },
            websiteDisplay: website,
            joined: try? Date(joined + "-01T12:00:00Z", strategy: .iso8601),
            followers: followers,
            following: following,
            postCount: posts
        )
    }

    static let me = person(
        "100", "Ava Lindqvist", "avalind",
        bio: "Designing calm software. Liquid glass enthusiast. Building #LiquidX in the open.",
        verification: .blue, location: "Prague", website: "github.com/dfrnoch/liquidX",
        followers: 7_912, following: 353, posts: 1_204, joined: "2019-03"
    )

    static let people: [XUser] = [
        person("101", "Mira Okafor", "miraokafor", bio: "Product designer @northwind. Type nerd. Shipping small delightful things.",
               verification: .blue, location: "Lisbon", website: "mira.design", followers: 48_200, following: 611, posts: 8_402, joined: "2014-06"),
        person("102", "Swift Weekly", "swiftweekly", bio: "The week in Swift, SwiftUI and the Apple developer platforms. Curated by humans.",
               verification: .business, website: "swiftweekly.dev", followers: 212_000, following: 12, posts: 4_310, joined: "2015-11"),
        person("103", "Jonas Berg", "jberg", bio: "Photographer. Mostly mountains, sometimes people. 📷",
               location: "Tromsø", followers: 3_180, following: 402, posts: 990, joined: "2017-02"),
        person("104", "Priya Raman", "priyacodes", bio: "iOS engineer. Accessibility advocate. Opinions are my cat's.",
               verification: .blue, location: "Bengaluru", followers: 21_400, following: 870, posts: 6_120, joined: "2016-09"),
        person("105", "Orbit Lab", "orbitlab", bio: "Independent space science newsletter. Launch schedules, mission explainers, pretty pictures.",
               verification: .business, website: "orbitlab.space", followers: 1_340_000, following: 48, posts: 22_900, joined: "2012-04"),
        person("106", "Theo Marchetti", "theom", bio: "Making indie games in a tiny apartment. Current project: Lanternfall.",
               location: "Turin", followers: 9_870, following: 1_203, posts: 3_402, joined: "2018-01"),
        person("107", "City Transit Updates", "citytransit", bio: "Service updates for the metro, trams and buses. Not monitored 24/7.",
               verification: .government, followers: 402_000, following: 3, posts: 51_200, joined: "2010-08"),
        person("108", "Noor Haddad", "noorhaddad", bio: "Writer. Coffee. Long walks and longer threads.",
               followers: 15_300, following: 299, posts: 2_870, joined: "2013-05"),
    ]

    private static func user(_ username: String) -> XUser {
        people.first { $0.username == username } ?? me
    }

    private static func photo(_ seed: String, _ width: Int, _ height: Int, alt: String? = nil) -> XMedia {
        XMedia(id: "m-\(seed)", kind: .photo, imageURL: art(seed), width: width, height: height, altText: alt)
    }

    private static func make(
        _ id: String, _ username: String, minutesAgo: Double, now: Date, _ text: String,
        media: [XMedia] = [], replies: Int = 0, reposts: Int = 0, likes: Int = 0, views: Int? = nil,
        replyingTo: [String] = [], replyTo: String? = nil, quoted: XQuotedPost? = nil, card: XLinkCard? = nil
    ) -> XPost {
        XPost(
            id: id,
            author: user(username),
            createdAt: now.addingTimeInterval(-minutesAgo * 60),
            text: RichText.make(text),
            media: media,
            metrics: XPost.Metrics(replies: replies, reposts: reposts, likes: likes, bookmarks: likes / 12, views: views),
            conversationID: replyTo ?? id,
            replyingTo: replyingTo,
            replyToID: replyTo,
            quoted: quoted,
            card: card
        )
    }

    static func timeline(now: Date) -> [XTimelineItem] {
        let quoteSource = make("2009", "swiftweekly", minutesAgo: 600, now: now,
                               "SwiftUI tip: glassEffectID + a namespace lets glass shapes morph into each other when they appear and disappear. Wrap them in a GlassEffectContainer.")
        let posts: [XTimelineItem] = [
            XTimelineItem(make("2001", "miraokafor", minutesAgo: 4, now: now,
                "Spent the afternoon redesigning a profile screen around liquid glass. The trick: let the banner bleed under the navigation controls and keep every control a single glass shape.",
                media: [photo("mira-1", 1600, 1000, alt: "Profile screen mockups on a desk")],
                replies: 23, reposts: 41, likes: 259, views: 9_200)),
            XTimelineItem(make("2002", "orbitlab", minutesAgo: 18, now: now,
                "The aurora forecast for tonight is the strongest of the year. If you're north of 55°, look up after 22:00 local time. Thread with tips for phone cameras ↓",
                media: [photo("aurora-1", 1200, 1500), photo("aurora-2", 1200, 1500)],
                replies: 380, reposts: 2_100, likes: 18_400, views: 1_220_000)),
            XTimelineItem(id: "3003", post: make("2003", "jberg", minutesAgo: 47, now: now,
                "Blue hour above the fjord. No edits, just patience and cold fingers.",
                media: [photo("fjord", 2000, 1333)], replies: 12, reposts: 88, likes: 1_045, views: 30_400),
                repostedBy: user("miraokafor")),
            XTimelineItem(make("2004", "priyacodes", minutesAgo: 75, now: now,
                "Reminder that every icon-only button needs an accessibility label. VoiceOver reading \"button, button, button\" is not a navigation experience. #a11y",
                replies: 64, reposts: 512, likes: 3_870, views: 98_000)),
            XTimelineItem(make("2005", "theom", minutesAgo: 130, now: now,
                "Lanternfall devlog #14: the lantern now casts real-time shadows and the whole forest feels alive. Four screenshots from today's build:",
                media: [photo("lantern-1", 1600, 900), photo("lantern-2", 1600, 900), photo("lantern-3", 1600, 900), photo("lantern-4", 1600, 900)],
                replies: 41, reposts: 230, likes: 2_310, views: 54_000)),
            XTimelineItem(make("2006", "citytransit", minutesAgo: 190, now: now,
                "Line B: trams are running with delays of up to 10 minutes between Central Station and Riverside due to a signal fault. Crews are on site.",
                replies: 28, reposts: 61, likes: 140, views: 41_000)),
            XTimelineItem(make("2007", "noorhaddad", minutesAgo: 260, now: now,
                "Good software feels like a well-designed kitchen: everything is where your hand expects it, and nothing makes noise unless something is actually wrong.",
                replies: 77, reposts: 940, likes: 6_400, views: 210_000)),
            XTimelineItem(make("2008", "avalind", minutesAgo: 320, now: now,
                "LiquidX is open source now. Native SwiftUI on iOS and macOS, liquid glass everywhere, and it talks to the official X API with your own developer app.",
                replies: 31, reposts: 120, likes: 980, views: 22_000,
                card: XLinkCard(url: URL(string: "https://github.com/dfrnoch/liquidX")!, host: "github.com",
                                title: "dfrnoch/liquidX: a native X client for iOS and macOS",
                                summary: "SwiftUI, liquid glass, zero dependencies.", imageURL: art("repo-card")))),
            XTimelineItem(make("2010", "miraokafor", minutesAgo: 420, now: now,
                "This is the best explanation of glass morphing I've seen.",
                replies: 5, reposts: 19, likes: 210, views: 8_700,
                quoted: XQuotedPost(id: quoteSource.id, author: quoteSource.author, createdAt: quoteSource.createdAt, text: quoteSource.text))),
            XTimelineItem(make("2011", "priyacodes", minutesAgo: 470, now: now,
                "@miraokafor Agree, and it scales up nicely with Dynamic Type too. Tested it at AX5 this morning.",
                replies: 2, reposts: 1, likes: 48, views: 2_100, replyingTo: ["miraokafor"], replyTo: "2010")),
            XTimelineItem(make("2012", "jberg", minutesAgo: 540, now: now,
                "Three frames from the coast trip.",
                media: [photo("coast-1", 1200, 1600), photo("coast-2", 1600, 1200), photo("coast-3", 1600, 1200)],
                replies: 9, reposts: 30, likes: 612, views: 17_800)),
            XTimelineItem(quoteSource.withMetrics(replies: 44, reposts: 360, likes: 2_900, views: 120_000)),
            XTimelineItem(make("2013", "orbitlab", minutesAgo: 720, now: now,
                "A new crewed mission patch was revealed today, and the design has a hidden constellation in it. Can you spot it?",
                media: [photo("patch", 1400, 1400)], replies: 210, reposts: 800, likes: 9_900, views: 640_000)),
            XTimelineItem(make("2014", "theom", minutesAgo: 900, now: now,
                "Hot take: the best game UI is the one you forget is there.",
                replies: 120, reposts: 75, likes: 1_480, views: 39_000)),
            XTimelineItem(make("2015", "noorhaddad", minutesAgo: 1_300, now: now,
                "Started a new notebook today. First page: a list of things that made me smile this week. It was longer than I expected.",
                replies: 18, reposts: 40, likes: 1_200, views: 26_000)),
            XTimelineItem(make("2016", "swiftweekly", minutesAgo: 1_700, now: now,
                "Issue #412 is out: Observation performance tips, scroll edge effects, and a deep dive into Swift 6 strict concurrency for app targets.",
                replies: 12, reposts: 210, likes: 1_640, views: 77_000,
                card: XLinkCard(url: URL(string: "https://swiftweekly.dev/412")!, host: "swiftweekly.dev",
                                title: "Swift Weekly #412", summary: "Observation, scroll edges and strict concurrency.", imageURL: art("issue-412")))),
            XTimelineItem(make("2017", "citytransit", minutesAgo: 2_100, now: now,
                "Weekend works: Line A will not stop at Old Town on Saturday and Sunday. Replacement buses run every 6 minutes.",
                replies: 40, reposts: 220, likes: 310, views: 88_000)),
            XTimelineItem(make("2018", "jberg", minutesAgo: 2_900, now: now,
                "Studio test with the new lens.",
                media: [photo("studio-1", 1080, 1350), photo("studio-2", 1080, 1350)],
                replies: 6, reposts: 14, likes: 402, views: 11_400)),
            XTimelineItem(make("2019", "avalind", minutesAgo: 3_400, now: now,
                "Small UX detail I love: when you pull to refresh, only posts newer than what you already have are fetched. Faster, and cheaper on the API.",
                replies: 9, reposts: 22, likes: 301, views: 9_900)),
            XTimelineItem(make("2020", "orbitlab", minutesAgo: 4_400, now: now,
                "Saturn's rings are tilting edge-on this year, which makes them almost disappear from Earth's point of view. Here's why it happens.",
                media: [photo("saturn", 1600, 900)], replies: 150, reposts: 1_700, likes: 14_200, views: 900_000)),
            XTimelineItem(make("2021", "priyacodes", minutesAgo: 5_000, now: now,
                "Shipped: our app now supports Reduce Transparency properly. Liquid glass falls back to solid materials automatically if you use the system APIs. Don't fight them!",
                replies: 30, reposts: 190, likes: 2_050, views: 61_000)),
            XTimelineItem(make("2022", "miraokafor", minutesAgo: 6_100, now: now,
                "Moodboard for the next project.",
                media: [photo("mood-1", 1200, 1200), photo("mood-2", 1200, 1200), photo("mood-3", 1200, 1200), photo("mood-4", 1200, 1200)],
                replies: 14, reposts: 52, likes: 880, views: 24_000)),
            XTimelineItem(make("2023", "theom", minutesAgo: 7_300, now: now,
                "Two years of evenings and weekends. Lanternfall has a release date. More soon.",
                media: [photo("lantern-key", 1920, 1080)], replies: 320, reposts: 1_100, likes: 8_800, views: 310_000)),
            XTimelineItem(make("2024", "noorhaddad", minutesAgo: 9_000, now: now,
                "The older I get, the more I appreciate apps that open instantly.",
                replies: 66, reposts: 410, likes: 4_900, views: 150_000)),
        ]
        return posts
    }

    static func arrivals(now: Date) -> [XPost] {
        [
            make("3001", "orbitlab", minutesAgo: 0, now: now,
                 "Update: the aurora is visible right now across the whole north. Go outside!",
                 media: [photo("aurora-live", 1600, 1067)], replies: 12, reposts: 90, likes: 640, views: 8_100),
            make("3002", "theom", minutesAgo: 0, now: now,
                 "Pushed a Lanternfall build with the new glass menus. Feels so much calmer.",
                 replies: 3, reposts: 8, likes: 77, views: 1_900),
            make("3003", "noorhaddad", minutesAgo: 0, now: now,
                 "Small joys: a timeline that keeps your place when new posts arrive.",
                 replies: 6, reposts: 21, likes: 230, views: 4_400),
        ]
    }

    static func mentions(now: Date) -> [XTimelineItem] {
        [
            XTimelineItem(make("4001", "miraokafor", minutesAgo: 9, now: now,
                "@avalind the new profile header is gorgeous. How did you get the banner to stretch so smoothly?",
                replies: 1, likes: 12, replyingTo: ["avalind"])),
            XTimelineItem(make("4002", "priyacodes", minutesAgo: 95, now: now,
                "@avalind happy to help test VoiceOver on LiquidX this weekend!",
                likes: 8, replyingTo: ["avalind"])),
            XTimelineItem(make("4003", "theom", minutesAgo: 600, now: now,
                "Shoutout to @avalind for the liquid glass tips, Lanternfall's menus look so much better now.",
                media: [photo("lantern-menu", 1600, 900)], replies: 3, likes: 54)),
        ]
    }

    static func replies(to post: XPost) -> [XTimelineItem] {
        let lines = [
            ("priyacodes", "This is great. Bookmarking for later."),
            ("noorhaddad", "Love this, thanks for sharing."),
            ("theom", "Okay, now I want to try this in Lanternfall too."),
        ]
        return lines.filter { $0.0 != post.author.username }.enumerated().map { index, line in
            XTimelineItem(XPost(
                id: "\(post.id)-r\(index)",
                author: user(line.0),
                createdAt: post.createdAt.addingTimeInterval(Double(index + 1) * 420),
                text: RichText.make(line.1),
                metrics: XPost.Metrics(replies: index, likes: 12 - index * 3),
                conversationID: post.conversationID ?? post.id,
                replyingTo: [post.author.username],
                replyToID: post.id
            ))
        }
    }

    static let trends: [XTrend] = [
        XTrend(name: "#LiquidGlass", category: "Technology", postCount: 48_200),
        XTrend(name: "Aurora", category: "Trending in Science", postCount: 112_000),
        XTrend(name: "Lanternfall", category: "Gaming", postCount: 9_400),
        XTrend(name: "#SwiftUI", category: "Technology", postCount: 21_700),
        XTrend(name: "Line B", category: "Trending in Prague", postCount: 2_100),
    ]
}

private extension XPost {
    func withMetrics(replies: Int, reposts: Int, likes: Int, views: Int) -> XPost {
        var copy = self
        copy.metrics = Metrics(replies: replies, reposts: reposts, likes: likes, bookmarks: likes / 12, views: views)
        return copy
    }
}
