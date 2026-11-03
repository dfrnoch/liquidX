import SwiftUI
import XKit

/// A remote image that fills its frame (`scaledToFill`, clipped by the caller).
/// Reads the memory cache synchronously on creation, so cells that scroll back
/// into view never flash a placeholder.
struct RemoteImage: View {
    let url: URL?
    /// Longest side, in points, the image will be displayed at.
    var pointSize: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    init(_ url: URL?, pointSize: CGFloat) {
        self.url = url
        self.pointSize = pointSize
        if let url, url.scheme != "demo" {
            // `displayScale` is not available in init; assume Retina for the lookup.
            _image = State(initialValue: ImagePipeline.shared.cachedImage(for: url, maxPixelSize: pointSize * 2))
        }
    }

    var body: some View {
        Color.clear
            .overlay {
                if let url, url.scheme == "demo" {
                    DemoArtwork(seed: url.path())
                } else if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                } else {
                    Theme.placeholder
                }
            }
            .clipped()
            .task(id: url) {
                guard let url, url.scheme != "demo", image == nil else { return }
                let loaded = await ImagePipeline.shared.image(for: url, maxPixelSize: pointSize * max(displayScale, 2))
                if !Task.isCancelled { image = loaded }
            }
    }
}

/// Procedural art for demo `demo://` image URLs: a mesh gradient with a few
/// soft shapes, coloured deterministically from the seed.
struct DemoArtwork: View {
    let seed: String

    private static let palettes: [(String, [Color])] = [
        ("aurora", [.black, Color(red: 0.05, green: 0.2, blue: 0.25), .black, Color(red: 0.1, green: 0.85, blue: 0.55), Color(red: 0.45, green: 0.3, blue: 0.9), Color(red: 0.05, green: 0.45, blue: 0.4), Color(red: 0.02, green: 0.05, blue: 0.12), Color(red: 0.05, green: 0.1, blue: 0.2), .black]),
        ("fjord", [Color(red: 0.1, green: 0.15, blue: 0.4), Color(red: 0.2, green: 0.3, blue: 0.6), Color(red: 0.4, green: 0.45, blue: 0.75), Color(red: 0.05, green: 0.1, blue: 0.3), Color(red: 0.3, green: 0.4, blue: 0.7), Color(red: 0.7, green: 0.6, blue: 0.75), Color(red: 0.02, green: 0.05, blue: 0.15), Color(red: 0.05, green: 0.1, blue: 0.25), Color(red: 0.1, green: 0.15, blue: 0.35)]),
        ("lantern", [Color(red: 0.05, green: 0.08, blue: 0.06), Color(red: 0.1, green: 0.15, blue: 0.1), Color(red: 0.05, green: 0.1, blue: 0.08), Color(red: 0.2, green: 0.25, blue: 0.12), Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 0.25, green: 0.3, blue: 0.15), Color(red: 0.02, green: 0.04, blue: 0.03), Color(red: 0.35, green: 0.2, blue: 0.08), Color(red: 0.03, green: 0.05, blue: 0.04)]),
        ("coast", [Color(red: 0.55, green: 0.8, blue: 0.9), Color(red: 0.75, green: 0.88, blue: 0.95), Color(red: 0.6, green: 0.82, blue: 0.92), Color(red: 0.1, green: 0.5, blue: 0.6), Color(red: 0.2, green: 0.6, blue: 0.65), Color(red: 0.15, green: 0.55, blue: 0.6), Color(red: 0.85, green: 0.78, blue: 0.62), Color(red: 0.9, green: 0.82, blue: 0.68), Color(red: 0.8, green: 0.72, blue: 0.58)]),
        ("saturn", [.black, Color(red: 0.08, green: 0.06, blue: 0.05), .black, Color(red: 0.3, green: 0.25, blue: 0.18), Color(red: 0.9, green: 0.78, blue: 0.55), Color(red: 0.2, green: 0.16, blue: 0.1), .black, Color(red: 0.06, green: 0.05, blue: 0.04), .black]),
        ("studio", [Color(white: 0.85), Color(white: 0.92), Color(white: 0.8), Color(white: 0.7), Color(red: 0.95, green: 0.7, blue: 0.6), Color(white: 0.75), Color(white: 0.6), Color(white: 0.65), Color(white: 0.55)]),
    ]

    private static let fallback: [[Color]] = [
        [Color(red: 0.95, green: 0.4, blue: 0.3), Color(red: 0.98, green: 0.7, blue: 0.3), Color(red: 0.9, green: 0.3, blue: 0.5), Color(red: 0.6, green: 0.2, blue: 0.6), Color(red: 0.95, green: 0.5, blue: 0.5), Color(red: 0.4, green: 0.2, blue: 0.7), Color(red: 0.2, green: 0.1, blue: 0.4), Color(red: 0.5, green: 0.2, blue: 0.5), Color(red: 0.3, green: 0.1, blue: 0.45)],
        [Color(red: 0.1, green: 0.3, blue: 0.9), Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.8, blue: 0.9), Color(red: 0.05, green: 0.15, blue: 0.5), Color(red: 0.4, green: 0.5, blue: 1.0), Color(red: 0.2, green: 0.9, blue: 0.8), Color(red: 0.02, green: 0.05, blue: 0.25), Color(red: 0.1, green: 0.2, blue: 0.6), Color(red: 0.1, green: 0.5, blue: 0.6)],
        [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.6, green: 0.9, blue: 0.5), Color(red: 0.9, green: 0.95, blue: 0.6), Color(red: 0.1, green: 0.4, blue: 0.3), Color(red: 0.3, green: 0.75, blue: 0.5), Color(red: 0.7, green: 0.85, blue: 0.4), Color(red: 0.05, green: 0.2, blue: 0.15), Color(red: 0.1, green: 0.35, blue: 0.25), Color(red: 0.3, green: 0.5, blue: 0.2)],
        [Color(red: 0.15, green: 0.12, blue: 0.3), Color(red: 0.4, green: 0.3, blue: 0.7), Color(red: 0.9, green: 0.5, blue: 0.7), Color(red: 0.1, green: 0.1, blue: 0.25), Color(red: 0.5, green: 0.35, blue: 0.8), Color(red: 0.95, green: 0.65, blue: 0.6), Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.2, green: 0.15, blue: 0.4), Color(red: 0.6, green: 0.3, blue: 0.5)],
        [Color(red: 0.98, green: 0.85, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.4), Color(red: 0.85, green: 0.35, blue: 0.3), Color(red: 0.9, green: 0.75, blue: 0.5), Color(red: 0.8, green: 0.45, blue: 0.35), Color(red: 0.55, green: 0.2, blue: 0.25), Color(red: 0.6, green: 0.5, blue: 0.4), Color(red: 0.45, green: 0.25, blue: 0.25), Color(red: 0.25, green: 0.1, blue: 0.15)],
    ]

    /// A representative colour of this artwork (its centre), for tinting.
    static func dominantColor(seed: String) -> Color {
        DemoArtwork(seed: seed).colors[4]
    }

    private var colors: [Color] {
        let lower = seed.lowercased()
        if let match = Self.palettes.first(where: { lower.contains($0.0) }) { return match.1 }
        return Self.fallback[Int(stableHash(seed) % UInt64(Self.fallback.count))]
    }

    var body: some View {
        let hash = stableHash(seed)
        let jitter = { (shift: UInt64) -> Float in Float((hash >> shift) & 0xFF) / 255 * 0.3 - 0.15 }
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + jitter(0), 0.5 + jitter(8)], [1, 0.5],
                [0, 1], [0.5 + jitter(16), 1], [1, 1],
            ],
            colors: colors
        )
        .overlay {
            Canvas { context, size in
                var generator = SeededGenerator(seed: hash)
                for _ in 0..<3 {
                    let diameter = size.width * CGFloat.random(in: 0.15...0.45, using: &generator)
                    let rect = CGRect(
                        x: CGFloat.random(in: -0.1...0.9, using: &generator) * size.width,
                        y: CGFloat.random(in: -0.1...0.8, using: &generator) * size.height,
                        width: diameter, height: diameter
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(Double.random(in: 0.04...0.12, using: &generator))))
                }
            }
            .blur(radius: 18)
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
