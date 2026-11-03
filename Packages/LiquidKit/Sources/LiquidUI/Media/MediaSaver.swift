import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XKit
#if os(iOS)
import Photos
#endif

/// Saves a post's photos and videos at full quality: to Photos on iPhone and
/// iPad, to the Downloads folder on the Mac. GIFs are MP4s on X and save as
/// videos.
enum MediaSaver {
    enum Failure: LocalizedError {
        case unavailable
        case denied

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "This media can't be saved.")
            case .denied: String(localized: "Allow LiquidX to add to Photos in Settings to save media.")
            }
        }
    }

    static var savedMessage: LocalizedStringKey {
        #if os(iOS)
        "Saved to Photos"
        #else
        "Saved to Downloads"
        #endif
    }

    /// Menu title for saving `media`: "Save Image", "Save Video", "Save GIF",
    /// or a plural for several.
    static func title(for media: [XMedia]) -> LocalizedStringKey {
        if media.count == 1 {
            switch media[0].kind {
            case .photo: return "Save Image"
            case .video: return "Save Video"
            case .animatedGIF: return "Save GIF"
            }
        }
        return media.allSatisfy { $0.kind == .photo } ? "Save Images" : "Save Media"
    }

    static func save(_ media: [XMedia]) async throws {
        #if os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        #endif
        for item in media {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = try await download(item, into: folder)
            try await store(file, isVideo: item.kind != .photo)
        }
    }

    private static func download(_ item: XMedia, into folder: URL) async throws -> URL {
        let isVideo = item.kind != .photo
        guard let source = isVideo ? item.videoURL : item.imageURL(.orig) else { throw Failure.unavailable }
        if source.scheme == "demo" {
            let file = folder.appending(path: "\(item.id).png")
            try demoArtwork(seed: source.path(), aspectRatio: item.aspectRatio ?? 1).write(to: file)
            return file
        }
        let (temporary, response) = try await URLSession.shared.download(from: source)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        // pbs.twimg.com and video.twimg.com names carry the media key and,
        // via the MIME type, the right extension.
        var name = response.suggestedFilename ?? item.id
        if (name as NSString).pathExtension.isEmpty {
            name += isVideo ? ".mp4" : ".jpg"
        }
        let file = folder.appending(path: name)
        try FileManager.default.moveItem(at: temporary, to: file)
        return file
    }

    #if os(iOS)
    private static func store(_ file: URL, isVideo: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: file, options: nil)
        }
    }
    #else
    private static func store(_ file: URL, isVideo: Bool) async throws {
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try FileManager.default.moveItem(at: file, to: uniqueFile(named: file.lastPathComponent, in: downloads))
    }

    /// "name.jpg", then "name 2.jpg", "name 3.jpg"… like Safari's downloads.
    private static func uniqueFile(named name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path()) {
            candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
    #endif

    /// Demo media is procedural, so render it to a PNG instead of downloading.
    private static func demoArtwork(seed: String, aspectRatio: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let image = DemoArtwork.render(seed: seed, aspectRatio: aspectRatio),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.unavailable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unavailable }
        return data as Data
    }
}
