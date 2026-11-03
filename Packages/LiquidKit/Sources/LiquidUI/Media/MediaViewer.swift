import AVKit
import SwiftUI
import XKit

/// Full-window photo and video viewer: a swipeable paging carousel, zoom and
/// pan (pinch, double-tap), pull to dismiss and glass controls. Presented as
/// an overlay so it works identically on iOS and macOS.
struct MediaViewer: View {
    let context: MediaViewerContext
    let dismiss: () -> Void

    @Environment(Session.self) private var session
    @State private var position: Int?
    @State private var showsChrome = true
    @State private var isZoomed = false
    /// How far the current page has been pulled towards dismissal.
    @State private var pull: CGFloat = 0
    /// Video pages are pulled by a SwiftUI drag (images pull themselves).
    @State private var videoDrag: CGSize = .zero

    /// Room kept clear above videos for the top bar, so it never covers the
    /// player's own controls.
    private let topBarHeight: CGFloat = 76

    init(context: MediaViewerContext, dismiss: @escaping () -> Void) {
        self.context = context
        self.dismiss = dismiss
        _position = State(initialValue: context.index)
    }

    private var index: Int { position ?? context.index }
    private var current: XMedia { context.media[index] }
    private var isVideo: Bool { current.kind != .photo && current.videoURL != nil }
    private var chromeVisible: Bool { (showsChrome || isVideo) && pull < 8 }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(1 - min(0.7, pull / 300))
                    .ignoresSafeArea()

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(context.media.indices, id: \.self) { offset in
                            page(context.media[offset], isActive: offset == index, safeArea: proxy.safeAreaInsets)
                                .containerRelativeFrame([.horizontal, .vertical])
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $position)
                .scrollIndicators(.never)
                .scrollDisabled(isZoomed || context.media.count < 2)
                .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if chromeVisible { topBar }
        }
        .overlay(alignment: .bottom) {
            if chromeVisible, !isZoomed { bottomBar }
        }
        .overlay {
            if context.media.count > 1, chromeVisible, !isZoomed {
                HStack {
                    pager(-1, symbol: "chevron.left").opacity(index > 0 ? 1 : 0)
                    Spacer()
                    pager(1, symbol: "chevron.right").opacity(index < context.media.count - 1 ? 1 : 0)
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: chromeVisible)
        .animation(.snappy(duration: 0.25), value: isZoomed)
        .onChange(of: index) {
            isZoomed = false
            pull = 0
            if isVideo { showsChrome = true }
        }
        .environment(\.colorScheme, .dark)
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .focusable()
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func page(_ media: XMedia, isActive: Bool, safeArea: EdgeInsets) -> some View {
        if media.kind != .photo, let video = media.videoURL {
            InlinePlayer(url: video, loops: media.kind == .animatedGIF, isActive: isActive)
                .padding(.top, safeArea.top + topBarHeight)
                .padding(.bottom, safeArea.bottom)
                .offset(isActive ? videoDrag : .zero)
                .simultaneousGesture(videoDismissDrag)
        } else {
            ZoomableImage(
                media: media,
                isActive: isActive,
                onZoom: { zoomed in if isActive { isZoomed = zoomed } },
                onTap: { withAnimation(.snappy) { showsChrome.toggle() } },
                onPull: { distance in if isActive { pull = distance } },
                onDismiss: dismiss
            )
            .accessibilityLabel(Text(media.altText ?? "Image"))
        }
    }

    private var videoDismissDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                videoDrag = CGSize(width: 0, height: value.translation.height)
                pull = abs(value.translation.height)
            }
            .onEnded { value in
                if abs(videoDrag.height) > 140 {
                    dismiss()
                } else {
                    withAnimation(.snappy) {
                        videoDrag = .zero
                        pull = 0
                    }
                }
            }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard context.media.indices.contains(next), !isZoomed else { return }
        withAnimation(.smooth(duration: 0.35)) { position = next }
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
                    .contentTransition(.numericText(value: Double(index)))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .animation(.snappy, value: index)
            }
            Spacer()
            Button { session.save([current]) } label: {
                Image(systemName: "square.and.arrow.down").font(.body.weight(.semibold)).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel(Text(MediaSaver.title(for: [current])))
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

/// One photo page: shows the timeline's cached rendition at once, then swaps
/// in the large one, inside a zooming surface.
private struct ZoomableImage: View {
    let media: XMedia
    let isActive: Bool
    let onZoom: (Bool) -> Void
    let onTap: () -> Void
    let onPull: (CGFloat) -> Void
    let onDismiss: () -> Void

    @State private var image: CGImage?

    var body: some View {
        ZoomingImageView(
            image: image,
            aspectRatio: media.aspectRatio ?? 1,
            isActive: isActive,
            onZoom: onZoom,
            onTap: onTap,
            onPull: onPull,
            onDismiss: onDismiss
        )
        .task(id: media.id) { await load() }
    }

    private func load() async {
        guard let url = media.imageURL(.large) else { return }
        if url.scheme == "demo" {
            image = DemoArtwork.render(seed: url.path(), aspectRatio: media.aspectRatio ?? 1)
            return
        }
        if image == nil {
            // The grid loaded one of these at its display size; any is better than black.
            let previews: [(XMedia.Size, CGFloat)] = [(.medium, 1_800), (.medium, 1_200), (.small, 960), (.small, 640)]
            image = previews.lazy.compactMap { size, pixels in
                media.imageURL(size).flatMap { ImagePipeline.shared.cachedImage(for: $0, maxPixelSize: pixels) }
            }.first
        }
        if let large = await ImagePipeline.shared.image(for: url, maxPixelSize: 2_048), !Task.isCancelled {
            image = large
        }
    }
}

#if os(iOS)
/// UIKit's zooming scroll view: pinch and double-tap to zoom, pan with
/// momentum and bounce while zoomed, and at normal size a vertical
/// rubber-band pull that dismisses the viewer. At normal size it can't scroll
/// sideways, so horizontal swipes fall through to the carousel.
private struct ZoomingImageView: UIViewRepresentable {
    let image: CGImage?
    let aspectRatio: CGFloat
    let isActive: Bool
    let onZoom: (Bool) -> Void
    let onTap: () -> Void
    let onPull: (CGFloat) -> Void
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.onZoom = onZoom
        view.onTap = onTap
        view.onPull = onPull
        view.onDismiss = onDismiss
        view.setImage(image, aspectRatio: aspectRatio)
        if !isActive { view.resetZoom() }
    }
}

private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    var onZoom: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onPull: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    private let imageView = UIImageView()
    private var image: CGImage?
    private var aspectRatio: CGFloat = 1
    private var laidOutSize: CGSize = .zero
    private var isZoomed = false
    /// Set while the view adjusts itself, so it doesn't report back to SwiftUI
    /// in the middle of a view update.
    private var isAdjusting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ newImage: CGImage?, aspectRatio fallback: CGFloat) {
        guard newImage !== image else { return }
        image = newImage
        imageView.image = newImage.map { UIImage(cgImage: $0) }
        let ratio = newImage.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? fallback
        // Swapping the preview for the large rendition keeps the zoom.
        if abs(ratio - aspectRatio) > 0.01 {
            aspectRatio = ratio
            laidOutSize = .zero
            setNeedsLayout()
        }
    }

    func resetZoom() {
        guard zoomScale != minimumZoomScale else { return }
        isAdjusting = true
        setZoomScale(minimumZoomScale, animated: false)
        isZoomed = false
        isAdjusting = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != laidOutSize {
            laidOutSize = bounds.size
            isAdjusting = true
            zoomScale = minimumZoomScale
            isZoomed = false
            let width = min(bounds.width, bounds.height * aspectRatio)
            let fitted = CGSize(width: width, height: width / aspectRatio)
            imageView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
            centerContent()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            isAdjusting = false
        } else {
            centerContent()
        }
    }

    /// Insets that keep content smaller than the page centred in it.
    private func centerContent() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }

    @objc private func didTap() {
        onTap()
    }

    @objc private func didDoubleTap(_ gesture: UITapGestureRecognizer) {
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        let zoomed = zoomScale > minimumZoomScale + 0.01
        guard zoomed != isZoomed, !isAdjusting else { return }
        isZoomed = zoomed
        onZoom(zoomed)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isZoomed, !isZooming, !isAdjusting else { return }
        onPull(abs(contentOffset.y + contentInset.top))
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !isZoomed else { return }
        let pull = abs(contentOffset.y + contentInset.top)
        if pull > 90 || (abs(velocity.y) > 1.2 && pull > 16) { onDismiss() }
    }
}
#else
/// The Mac's zooming surface: pinch or double-click to zoom (towards the
/// pointer), drag to pan while zoomed, and drag vertically at normal size to
/// pull the viewer away.
private struct ZoomingImageView: View {
    let image: CGImage?
    let aspectRatio: CGFloat
    let isActive: Bool
    let onZoom: (Bool) -> Void
    let onTap: () -> Void
    let onPull: (CGFloat) -> Void
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pinch: CGFloat = 1
    @State private var drag: CGSize = .zero

    private var ratio: CGFloat {
        image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? aspectRatio
    }

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            let fitted = fit(in: container)
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .scaleEffect(scale * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .frame(width: container.width, height: container.height)
            .contentShape(Rectangle())
            .gesture(magnify(fitted: fitted, container: container))
            .simultaneousGesture(pan(fitted: fitted, container: container))
            .onTapGesture(count: 2) { location in toggleZoom(at: location, fitted: fitted, container: container) }
            .onTapGesture { onTap() }
        }
        .onChange(of: isActive) { _, active in
            if !active { setScale(1, offset: .zero, animated: false) }
        }
    }

    private func fit(in container: CGSize) -> CGSize {
        let width = min(container.width, container.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    private func magnify(fitted: CGSize, container: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in pinch = value.magnification }
            .onEnded { value in
                let target = min(max(scale * value.magnification, 1), 4)
                pinch = 1
                scale *= value.magnification
                setScale(target, offset: clamped(offset, scale: target, fitted: fitted, container: container), animated: true)
            }
    }

    private func pan(fitted: CGSize, container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if scale > 1 {
                    drag = value.translation
                } else if abs(value.translation.height) > abs(value.translation.width) {
                    drag = CGSize(width: 0, height: value.translation.height)
                    onPull(abs(value.translation.height))
                }
            }
            .onEnded { value in
                if scale > 1 {
                    let moved = CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
                    offset = moved
                    drag = .zero
                    withAnimation(.snappy) { offset = clamped(moved, scale: scale, fitted: fitted, container: container) }
                } else if abs(drag.height) > 140 {
                    onDismiss()
                } else {
                    withAnimation(.snappy) { drag = .zero }
                    onPull(0)
                }
            }
    }

    private func toggleZoom(at location: CGPoint, fitted: CGSize, container: CGSize) {
        if scale > 1 {
            setScale(1, offset: .zero, animated: true)
            return
        }
        // Keep the clicked point under the pointer while zooming in.
        let target: CGFloat = 2.5
        let point = CGSize(width: location.x - container.width / 2, height: location.y - container.height / 2)
        let anchored = CGSize(width: -point.width * (target - 1), height: -point.height * (target - 1))
        setScale(target, offset: clamped(anchored, scale: target, fitted: fitted, container: container), animated: true)
    }

    private func setScale(_ target: CGFloat, offset newOffset: CGSize, animated: Bool) {
        withAnimation(animated ? .snappy : nil) {
            scale = target
            offset = target > 1 ? newOffset : .zero
        }
        onZoom(target > 1)
    }

    private func clamped(_ offset: CGSize, scale: CGFloat, fitted: CGSize, container: CGSize) -> CGSize {
        let maxX = max(0, (fitted.width * scale - container.width) / 2)
        let maxY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}
#endif

/// Plays a video or GIF with AVKit's own player view. (SwiftUI's `VideoPlayer`
/// crashes while loading its type metadata on macOS 27, so it is not used.)
/// GIFs loop silently without controls, as on X. Only the carousel's current
/// page plays, so neighbouring pages never make a sound.
private struct InlinePlayer: View {
    let url: URL
    let loops: Bool
    let isActive: Bool

    @State private var playback: Playback?

    var body: some View {
        Group {
            if let playback {
                NativePlayerView(player: playback.player, showsControls: !loops)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let playback = Playback(url: url, loops: loops, muted: loops)
            self.playback = playback
            if isActive { play() }
        }
        .onChange(of: isActive) { _, active in
            if active { play() } else { playback?.player.pause() }
        }
        .onDisappear { playback?.player.pause() }
    }

    private func play() {
        Playback.activateAudio()
        playback?.player.play()
    }
}

#if os(macOS)
private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let showsControls: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        // Lets trackpad swipes page the carousel instead of scrubbing.
        let view = ScrollThroughPlayerView()
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true
        update(view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        update(view)
    }

    private func update(_ view: AVPlayerView) {
        if view.player !== player { view.player = player }
        view.controlsStyle = showsControls ? .floating : .none
    }
}
#else
private struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        update(controller)
    }

    private func update(_ controller: AVPlayerViewController) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsControls
    }
}
#endif
