import Foundation

// Decodable mirrors of X API v2 JSON. Kept internal: the rest of the app only
// sees the models in `Models/`. Newer API docs rename "tweet" to "post" in a few
// keys, so both spellings are accepted wherever that has been observed.

struct WireEnvelope<Payload: Decodable>: Decodable {
    var data: Payload?
    var includes: WireIncludes?
    var meta: WireMeta?
    var errors: [WireProblem]?
}

struct WireIncludes: Decodable {
    var users: [WireUser]
    var tweets: [WireTweet]
    var media: [WireMedia]

    enum CodingKeys: String, CodingKey { case users, tweets, posts, media }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users = try c.decodeIfPresent([WireUser].self, forKey: .users) ?? []
        tweets = try c.decodeIfPresent([WireTweet].self, forKey: .tweets)
            ?? c.decodeIfPresent([WireTweet].self, forKey: .posts) ?? []
        media = try c.decodeIfPresent([WireMedia].self, forKey: .media) ?? []
    }

    init(users: [WireUser] = [], tweets: [WireTweet] = [], media: [WireMedia] = []) {
        self.users = users
        self.tweets = tweets
        self.media = media
    }
}

struct WireMeta: Decodable {
    var result_count: Int?
    var newest_id: String?
    var oldest_id: String?
    var next_token: String?
}

struct WireProblem: Decodable, Error {
    var title: String?
    var detail: String?
    var type: String?
    var message: String?
    var parameter: String?

    var summary: String? { detail ?? message ?? title }
}

struct WireTweet: Decodable {
    struct Reference: Decodable {
        var type: String
        var id: String
    }

    struct Attachments: Decodable {
        var media_keys: [String]?
    }

    struct Metrics: Decodable {
        var retweet_count: Int?
        var reply_count: Int?
        var like_count: Int?
        var quote_count: Int?
        var bookmark_count: Int?
        var impression_count: Int?
    }

    struct NoteTweet: Decodable {
        var text: String
        var entities: WireEntities?
    }

    var id: String
    var text: String
    var author_id: String?
    var created_at: Date?
    var conversation_id: String?
    var in_reply_to_user_id: String?
    var references: [Reference]
    var attachments: Attachments?
    var public_metrics: Metrics?
    var entities: WireEntities?
    var note: NoteTweet?

    enum CodingKeys: String, CodingKey {
        case id, text, author_id, created_at, conversation_id, in_reply_to_user_id
        case referenced_tweets, referenced_posts, attachments, public_metrics, entities
        case note_tweet, note_post
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        author_id = try c.decodeIfPresent(String.self, forKey: .author_id)
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at)
        conversation_id = try c.decodeIfPresent(String.self, forKey: .conversation_id)
        in_reply_to_user_id = try c.decodeIfPresent(String.self, forKey: .in_reply_to_user_id)
        references = try c.decodeIfPresent([Reference].self, forKey: .referenced_tweets)
            ?? c.decodeIfPresent([Reference].self, forKey: .referenced_posts) ?? []
        attachments = try c.decodeIfPresent(Attachments.self, forKey: .attachments)
        public_metrics = try c.decodeIfPresent(Metrics.self, forKey: .public_metrics)
        entities = try c.decodeIfPresent(WireEntities.self, forKey: .entities)
        note = try c.decodeIfPresent(NoteTweet.self, forKey: .note_tweet)
            ?? c.decodeIfPresent(NoteTweet.self, forKey: .note_post)
    }

    func reference(_ type: String) -> String? {
        references.first { $0.type == type }?.id
    }
}

struct WireEntities: Decodable {
    struct URLEntity: Decodable {
        struct Image: Decodable {
            var url: String
            var width: Int?
            var height: Int?
        }

        var url: String
        var expanded_url: String?
        var display_url: String?
        var unwound_url: String?
        var media_key: String?
        var title: String?
        var description: String?
        var images: [Image]?
    }

    var urls: [URLEntity]?
}

struct WireUser: Decodable {
    struct Metrics: Decodable {
        var followers_count: Int?
        var following_count: Int?
        var tweet_count: Int?
    }

    struct Entities: Decodable {
        struct Group: Decodable { var urls: [WireEntities.URLEntity]? }
        var url: Group?
        var description: Group?
    }

    var id: String
    var name: String
    var username: String
    var profile_image_url: String?
    var profile_banner_url: String?
    var description: String?
    var verified: Bool?
    var verified_type: String?
    var protected: Bool?
    var location: String?
    var url: String?
    var created_at: Date?
    var public_metrics: Metrics?
    var entities: Entities?
    var connection_status: [String]?
}

struct WireMedia: Decodable {
    struct Variant: Decodable {
        var bit_rate: Int?
        var content_type: String?
        var url: String
    }

    var media_key: String
    var type: String
    var url: String?
    var preview_image_url: String?
    var width: Int?
    var height: Int?
    var alt_text: String?
    var duration_ms: Int?
    var variants: [Variant]?
}

struct WireTrend: Decodable {
    var trend_name: String?
    var name: String?
    var category: String?
    var post_count: Int?
    var tweet_count: Int?
}

struct WireID: Decodable {
    var id: String
}

extension JSONDecoder {
    static let xAPI: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date"))
        }
        return decoder
    }()
}
