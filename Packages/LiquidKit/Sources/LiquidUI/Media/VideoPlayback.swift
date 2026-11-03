import AVFoundation
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
/// X), shows the poster until the first frame, and has a glass mute toggle
/// for videos. The player is created on appear and released on disappear, so
/// only visible videos cost anything.
struct InlineVideo: View {
    let media: XMedia
    let url: URL
    let posterURL: URL?
    let pointSize: CGFloat

    @State private var playback: Playback?
    @State private var isMuted = true

    var body: some View {
        RemoteImage(posterURL, pointSize: pointSize)
            .overlay {
                if let playback {
                    PlayerLayerView(player: playback.player)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if media.kind == .video {
                    Button {
                        isMuted.toggle()
                        if !isMuted { Playback.activateAudio() }
                        playback?.player.isMuted = isMuted
                    } label: {
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
            }
    }
}
