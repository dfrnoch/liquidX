public import CoreGraphics
public import Foundation
import ImageIO
import Synchronization

/// Fetches, downsamples and caches remote images.
///
/// - Bytes are cached on disk by `URLCache` (profile pictures and media are
///   immutable on pbs.twimg.com).
/// - Decoded, *downsampled* bitmaps are kept in a bounded in-memory LRU, keyed by
///   URL and pixel size, so scrolling back never decodes twice.
/// - Concurrent requests for the same image share one download.
/// - Decoding happens off the main thread via ImageIO thumbnails, which never
///   materialize the full-size bitmap.
public final class ImagePipeline: Sendable {
    public static let shared = ImagePipeline()

    private struct Key: Hashable, Sendable {
        var url: URL
        var bucket: Int
    }

    private struct Entry {
        var image: CGImage
        var cost: Int
        var lastUse: UInt64
    }

    private struct Memory {
        var entries: [Key: Entry] = [:]
        var totalCost = 0
        var clock: UInt64 = 0
    }

    private let memory = Mutex(Memory())
    private let inFlight = Mutex<[Key: Task<CGImage?, Never>]>([:])
    private let memoryLimit: Int
    private let session: URLSession

    public init(memoryLimit: Int = 160 * 1_024 * 1_024, diskLimit: Int = 300 * 1_024 * 1_024) {
        self.memoryLimit = memoryLimit
        let configuration = URLSessionConfiguration.default
        let directory = URL.cachesDirectory.appending(path: "LiquidXImages", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: diskLimit, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    /// Sizes are bucketed so slightly different layouts share one decode.
    private static func bucket(_ pixels: CGFloat) -> Int {
        let steps: [Int] = [64, 128, 256, 512, 768, 1_024, 1_536, 2_048, 4_096]
        return steps.first { CGFloat($0) >= pixels } ?? 4_096
    }

    /// Synchronous memory lookup, cheap enough to call from a view initializer.
    public func cachedImage(for url: URL, maxPixelSize: CGFloat) -> CGImage? {
        let key = Key(url: url, bucket: Self.bucket(maxPixelSize))
        return memory.withLock { memory in
            guard var entry = memory.entries[key] else { return nil }
            memory.clock += 1
            entry.lastUse = memory.clock
            memory.entries[key] = entry
            return entry.image
        }
    }

    public func image(for url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) { return cached }
        let key = Key(url: url, bucket: Self.bucket(maxPixelSize))
        let task = inFlight.withLock { tasks in
            if let existing = tasks[key] { return existing }
            let task = Task<CGImage?, Never> { [session] in
                guard let (data, response) = try? await session.data(from: url),
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
                else { return nil }
                return await Self.decode(data, maxPixelSize: CGFloat(key.bucket))
            }
            tasks[key] = task
            return task
        }
        let image = await task.value
        inFlight.withLock { _ = $0.removeValue(forKey: key) }
        if let image { store(image, for: key) }
        return image
    }

    @concurrent
    private static func decode(_ data: Data, maxPixelSize: CGFloat) async -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func store(_ image: CGImage, for key: Key) {
        let cost = image.bytesPerRow * image.height
        memory.withLock { memory in
            memory.clock += 1
            if let old = memory.entries[key] { memory.totalCost -= old.cost }
            memory.entries[key] = Entry(image: image, cost: cost, lastUse: memory.clock)
            memory.totalCost += cost
            while memory.totalCost > memoryLimit, let oldest = memory.entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
                memory.totalCost -= oldest.value.cost
                memory.entries.removeValue(forKey: oldest.key)
            }
        }
    }

    public func removeAll() {
        memory.withLock { $0 = Memory() }
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}
