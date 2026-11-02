public import Foundation

public struct XMedia: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case photo
        case video
        case animatedGIF = "animated_gif"
    }

    public var id: String
    public var kind: Kind
    /// Still image: the photo itself, or the poster frame of a video.
    public var imageURL: URL?
    /// Best progressive MP4 variant for videos and GIFs.
    public var videoURL: URL?
    public var width: Int?
    public var height: Int?
    public var altText: String?
    public var duration: TimeInterval?

    public init(
        id: String,
        kind: Kind,
        imageURL: URL?,
        videoURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        altText: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.width = width
        self.height = height
        self.altText = altText
        self.duration = duration
    }

    public var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    public enum Size: String, Sendable {
        case small, medium, large, orig
    }

    /// pbs.twimg.com serves several renditions of each photo; pick by name.
    public func imageURL(_ size: Size) -> URL? {
        guard let imageURL, imageURL.host()?.hasSuffix("twimg.com") == true,
              var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false)
        else { return imageURL }
        var items = (components.queryItems ?? []).filter { $0.name != "name" }
        items.append(URLQueryItem(name: "name", value: size.rawValue))
        components.queryItems = items
        return components.url ?? imageURL
    }
}
