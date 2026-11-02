public import Foundation

/// An X account as the interface needs it. Built from API v2 user objects
/// (see `Wire.swift`) or from demo data.
public struct XUser: Identifiable, Hashable, Sendable, Codable {
    public enum Verification: String, Hashable, Sendable, Codable {
        case none, blue, business, government
    }

    public var id: String
    public var name: String
    public var username: String
    public var avatarURL: URL?
    public var bannerURL: URL?
    public var bio: AttributedString
    public var verification: Verification
    public var isProtected: Bool
    public var location: String?
    public var website: URL?
    public var websiteDisplay: String?
    public var joined: Date?
    public var followers: Int
    public var following: Int
    public var postCount: Int
    /// `true`/`false` when the API reported the signed-in account's relationship,
    /// `nil` when unknown (timeline expansions do not carry it).
    public var isFollowedByMe: Bool?

    public init(
        id: String,
        name: String,
        username: String,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil,
        bio: AttributedString = AttributedString(),
        verification: Verification = .none,
        isProtected: Bool = false,
        location: String? = nil,
        website: URL? = nil,
        websiteDisplay: String? = nil,
        joined: Date? = nil,
        followers: Int = 0,
        following: Int = 0,
        postCount: Int = 0,
        isFollowedByMe: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.bio = bio
        self.verification = verification
        self.isProtected = isProtected
        self.location = location
        self.website = website
        self.websiteDisplay = websiteDisplay
        self.joined = joined
        self.followers = followers
        self.following = following
        self.postCount = postCount
        self.isFollowedByMe = isFollowedByMe
    }

    public var handle: String { "@\(username)" }

    public var profileURL: URL {
        URL(string: "https://x.com/\(username)")!
    }

    /// Stand-in used when an expansion is missing from a response.
    public static func unknown(id: String) -> XUser {
        XUser(id: id, name: "Unknown", username: "i/user/\(id)")
    }
}
