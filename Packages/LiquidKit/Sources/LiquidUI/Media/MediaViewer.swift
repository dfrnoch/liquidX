import AVKit
import SwiftUI
import XKit

/// Full-window photo and video viewer with paging, pinch/scroll zoom and glass
/// controls. Presented as an overlay so it works identically on iOS and macOS.
struct MediaViewer: View {
    let context: MediaViewerContext
    let dismiss: () -> Void

    @State private var index: Int
    @State private var dragOffset: CGSize = .zero
    @State private var showsChrome = true

    init(context: MediaViewerContext, dismiss: @escaping () -> Void) {
        self.context = context
        self.dismiss = dismiss
        _index = State(initialValue: context.index)
    }

    private var current: XMedia { context.media[index] }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(0.6, abs(dragOffset.height) / 600))
                .ignoresSafeArea()

            page(current)
                .id(current.id)
                .offset(dragOffset)
                .gesture(dismissDrag)
                .onTapGesture { withAnimation(.snappy) { showsChrome.toggle() } }
                .transition(.opacity)
        }
        .overlay(alignment: .top) { if showsChrome { topBar } }
        .overlay(alignment: .bottom) { if showsChrome { bottomBar } }
        .overlay {
            if context.media.count > 1, showsChrome {
                HStack {
                    pager(-1, symbol: "chevron.left").opacity(index > 0 ? 1 : 0)
                    Spacer()
                    pager(1, symbol: "chevron.right").opacity(index < context.media.count - 1 ? 1 : 0)
                }
                .padding(.horizontal, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .focusable()
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func page(_ media: XMedia) -> some View {
        if media.kind != .photo, let video = media.videoURL {
            InlinePlayer(url: video, loops: media.kind == .animatedGIF)
        } else {
            ZoomableImage(url: media.imageURL(.large), aspectRatio: media.aspectRatio ?? 1)
                .accessibilityLabel(Text(media.altText ?? "Image"))
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) { dragOffset = value.translation }
            }
            .onEnded { value in
                if abs(value.translation.height) > 140 {
                    dismiss()
                } else if abs(value.translation.width) > 80, abs(value.translation.width) > abs(value.translation.height) {
                    step(value.translation.width < 0 ? 1 : -1)
                    withAnimation(.snappy) { dragOffset = .zero }
                } else {
                    withAnimation(.snappy) { dragOffset = .zero }
                }
            }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard context.media.indices.contains(next) else { return }
        withAnimation(.snappy) { index = next }
    }

    private func pager(_ delta: Int, symbol: String) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(delta < 0 ? "Previous" : "Next")
    }

    private var topBar: some View {
        HStack {
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
            Spacer()
            if context.media.count > 1 {
                Text("\(index + 1) of \(context.media.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
            }
            Spacer()
            ShareLink(item: context.post.url) {
                Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
        .padding(16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let alt = current.altText, !alt.isEmpty {
            Text(alt)
                .font(.footnote)
                .padding(12)
                .frame(maxWidth: 560, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct ZoomableImage: View {
    let url: URL?
    let aspectRatio: CGFloat

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        RemoteImage(url, pointSize: 2_000)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .scaleEffect(scale * pinch)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        withAnimation(.snappy) { scale = min(max(scale * value.magnification, 1), 4) }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InlinePlayer: View {
    let url: URL
    let loops: Bool

    @State private var player: AVPlayer?
    @State private var looper: (any NSObjectProtocol)?

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                let player = AVPlayer(url: url)
                if loops {
                    looper = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { _ in
                        Task { @MainActor in
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
                }
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                if let looper { NotificationCenter.default.removeObserver(looper) }
            }
    }
}
