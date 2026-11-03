import AVFoundation
import AVKit
import SwiftUI
import XKit

/// Owns a player and, when looping, the looper that keeps it repeating.
final class Playback {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper?

    init(url: URL, loops: Bool, muted: Bool) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = muted
        player.preventsDisplaySleepDuringVideoPlayback = !muted
        if loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            looper = nil
            player.insert(item, after: nil)
        }
    }

    /// Muted inline previews must not interrupt the user's music; switch to
    /// playback audio only when sound is actually wanted.
    static func useAmbientAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .moviePlayback)
        #endif
    }

    static func activateAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}

/// A bare video surface (no controls) for inline playback in timelines.
#if os(iOS)
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
#else
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
        }

        required init?(coder: NSCoder) { nil }
    }

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
#endif

/// Inline timeline video or GIF: plays muted and loops while on screen (as on
/// X), shows the poster until the first frame. The player is created on
/// appear and released on disappear, so only visible videos cost anything.
///
/// iPhone and iPad: a glass mute toggle; taps open the viewer. Mac: click to
/// pause, remaining time in the corner, and on hover a glass control bar
/// along the bottom edge (play, scrubber, mute, expand to the viewer).
struct InlineVideo: View {
    let media: XMedia
    let url: URL
    let posterURL: URL?
    let pointSize: CGFloat
    var onExpand: () -> Void = {}

    @State private var playback: Playback?
    @State private var isMuted = true
    @State private var isPaused = false
    @State private var isHovering = false

    var body: some View {
        RemoteImage(posterURL, pointSize: pointSize)
            .overlay {
                if let playback {
                    PlayerLayerView(player: playback.player)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            #if os(macOS)
            // GIFs keep the grid's tap-to-open.
            .if(media.kind == .video) { $0.contentShape(Rectangle()).onTapGesture { togglePlayback() } }
            .overlay(alignment: .bottom) {
                if media.kind == .video, let playback {
                    InlineVideoControls(
                        player: playback.player,
                        fallbackDuration: media.duration,
                        isExpanded: isHovering,
                        isPaused: isPaused,
                        isMuted: isMuted,
                        onTogglePlayback: togglePlayback,
                        onToggleMute: toggleMute,
                        onExpand: {
                            playback.player.pause()
                            onExpand()
                        }
                    )
                }
            }
            .onHover { hovering in
                withAnimation(.snappy(duration: 0.25)) { isHovering = hovering }
            }
            #else
            .overlay(alignment: .bottomTrailing) {
                if media.kind == .video {
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(8)
                    .hoverPointer()
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                }
            }
            #endif
            .onAppear {
                guard playback == nil else { return }
                Playback.useAmbientAudio()
                let playback = Playback(url: url, loops: true, muted: true)
                withAnimation(.easeIn(duration: 0.2).delay(0.15)) { self.playback = playback }
                playback.player.play()
            }
            .onDisappear {
                playback?.player.pause()
                playback = nil
                isMuted = true
                isPaused = false
            }
    }

    private func toggleMute() {
        isMuted.toggle()
        if !isMuted { Playback.activateAudio() }
        playback?.player.isMuted = isMuted
    }

    private func togglePlayback() {
        guard let player = playback?.player else { return }
        isPaused.toggle()
        if isPaused { player.pause() } else { player.play() }
    }
}

#if os(macOS)
/// The Mac's inline video chrome. Idle: a small remaining-time capsule.
/// Hovered: a glass bar pinned to the bottom edge, so it never covers the
/// middle of the video the way AVKit's floating controls do.
private struct InlineVideoControls: View {
    let player: AVPlayer
    let fallbackDuration: TimeInterval?
    let isExpanded: Bool
    let isPaused: Bool
    let isMuted: Bool
    let onTogglePlayback: () -> Void
    let onToggleMute: () -> Void
    let onExpand: () -> Void

    /// While dragging the scrubber, the position the user is holding.
    @State private var scrubbing: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: isExpanded ? 0.1 : 0.5)) { _ in
            let duration = duration
            let elapsed = scrubbing.map { $0 * duration } ?? max(0, player.currentTime().seconds.finite)
            Group {
                if isExpanded {
                    bar(elapsed: elapsed, duration: duration)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text(Formatting.duration(max(0, duration - elapsed)))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    private var duration: Double {
        let item = player.currentItem?.duration.seconds.finite ?? 0
        return item > 0 ? item : fallbackDuration ?? 0
    }

    private func bar(elapsed: Double, duration: Double) -> some View {
        HStack(spacing: 12) {
            control(isPaused ? "play.fill" : "pause.fill", label: isPaused ? "Play" : "Pause", action: onTogglePlayback)
            Text("\(Formatting.duration(elapsed)) / \(Formatting.duration(duration))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .fixedSize()
            Scrubber(progress: duration > 0 ? elapsed / duration : 0) { fraction in
                scrubbing = fraction
                seek(to: fraction * duration, exact: false)
            } onEnded: { fraction in
                seek(to: fraction * duration, exact: true)
                scrubbing = nil
            }
            control(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isMuted ? "Unmute" : "Mute", action: onToggleMute)
            control("arrow.up.left.and.arrow.down.right", label: "Expand", action: onExpand)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
        .padding(8)
    }

    private func control(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 28)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .hoverPointer()
        .accessibilityLabel(label)
    }

    private func seek(to seconds: Double, exact: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }
}

/// A thin capsule track that thickens under the pointer; drag or click to seek.
private struct Scrubber: View {
    let progress: Double
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let thickness: CGFloat = isHovering || isDragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white)
                    .frame(width: max(thickness, proxy.size.width * min(max(progress, 0), 1)))
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onChanged(fraction(value.location.x, width: proxy.size.width))
                    }
                    .onEnded { value in
                        isDragging = false
                        onEnded(fraction(value.location.x, width: proxy.size.width))
                    }
            )
        }
        .frame(height: 28)
        .onHover { hovering in withAnimation(.snappy(duration: 0.15)) { isHovering = hovering } }
        .animation(.snappy(duration: 0.15), value: isDragging)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? Double(min(max(x / width, 0), 1)) : 0
    }
}

/// AVKit's player view, letting scroll-wheel and trackpad swipes through to
/// the enclosing scroll view (it otherwise takes them for scrubbing, which
/// stops paging and scrolling under the cursor). Clicks still reach the
/// controls.
final class ScrollThroughPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, NSApp.currentEvent?.type == .scrollWheel { return self }
        return hit
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
#endif

private extension Double {
    /// Zero for NaN and infinity (an item's duration before it loads).
    var finite: Double { isFinite ? self : 0 }
}
