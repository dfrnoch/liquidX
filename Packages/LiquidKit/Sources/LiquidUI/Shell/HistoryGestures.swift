#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Safari-style back/forward: two-finger horizontal trackpad swipes (when
    /// "Swipe between pages" allows them) and the mouse's back/forward buttons.
    /// The page follows the fingers over a snapshot of the page being swiped to,
    /// so `fill` (the column's background) is drawn here and slides with it.
    func historyGestures(_ router: Router, fill: Color) -> some View {
        modifier(HistorySlideModifier(router: router, fill: fill))
    }
}

extension EnvironmentValues {
    /// Set while a swipe hands over to the real page: `PushAppearance` shows the
    /// page at once instead of sliding it in a second time.
    @Entry var skipsPushAppearance = false
}

/// Where the column is in a back/forward slide. `progress` runs from -1 (forward:
/// the next page covers the column) through 0 to 1 (back: the current page has
/// slid off to the right).
@Observable
private final class HistorySlide {
    enum Stage { case idle, sliding, settling }

    var stage = Stage.idle
    var progress: CGFloat = 0
    /// Snapshot of the page being slid to; nil shows an empty column.
    var target: CGImage?
    /// After navigating, the snapshot covers the real page and fades out.
    var coverOpacity: Double = 1
}

private struct HistorySlideModifier: ViewModifier {
    let router: Router
    let fill: Color

    @State private var slide = HistorySlide()
    @State private var width: CGFloat = 0
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let progress = slide.progress
        // Over a translucent column the pages can't overlap, so they sit side by
        // side; otherwise the lower page moves less, as in Safari.
        let parallax: CGFloat = palette.isTranslucent ? 1 : 0.3
        content
            .environment(\.skipsPushAppearance, slide.stage == .settling)
            .background(fill)
            .overlay(alignment: .leading) {
                if progress > 0, !palette.isTranslucent { edgeShadow }
            }
            .offset(x: progress > 0 ? progress * width : progress * width * parallax)
            .background {
                if progress > 0 {
                    page.offset(x: (progress - 1) * width * parallax)
                }
            }
            .overlay {
                if progress < 0 {
                    page
                        .overlay(alignment: .leading) {
                            if !palette.isTranslucent { edgeShadow }
                        }
                        .offset(x: (1 + progress) * width)
                } else if slide.stage == .settling {
                    page.opacity(slide.coverOpacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(HistoryGestureMonitor(router: router, slide: slide))
    }

    private var page: some View {
        Group {
            if let image = slide.target {
                Image(decorative: image, scale: displayScale).resizable()
            } else {
                fill
            }
        }
        .allowsHitTesting(false)
    }

    /// The shadow the upper page casts on the one below.
    private var edgeShadow: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
            .frame(width: 14)
            .offset(x: -14)
            .allowsHitTesting(false)
    }
}

private struct HistoryGestureMonitor: NSViewRepresentable {
    let router: Router
    let slide: HistorySlide

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.slide = slide
        view.router = router
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.slide = slide
        view.router = router
    }

    final class MonitorView: NSView {
        var router: Router? {
            didSet {
                guard router !== oldValue else { return }
                oldValue?.willChangePath = nil
                router?.willChangePath = { [weak self] in self?.pathWillChange() }
                cancelSlide()
            }
        }
        var slide: HistorySlide?
        private var monitor: Any?
        private var snapshots: [Snapshot] = []
        /// Ignores path changes made by the slide itself.
        private var isNavigating = false
        /// Identifies the current slide, so a superseded swipe's callbacks stop.
        private var slideID = 0

        private enum Direction { case back, forward }

        /// A page as it looked when it was left.
        private struct Snapshot {
            let router: ObjectIdentifier
            let path: [Route]
            let image: CGImage
        }

        /// Full-resolution column snapshots are a few MB each.
        private static let snapshotLimit = 8

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        /// Returns true when the event was consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard let router, let window, event.window === window, NSApp.modalWindow == nil else { return false }
            switch event.type {
            case .otherMouseDown:
                // Buttons 3 and 4 are the side "back" and "forward" buttons.
                switch event.buttonNumber {
                case 3 where router.canGoBack: animateSlide(.back)
                case 4 where router.canGoForward: animateSlide(.forward)
                default: return false
                }
                return true
            case .scrollWheel:
                trackSwipe(event, router: router)
                return false
            default:
                return false
            }
        }

        // MARK: Sliding

        private func trackSwipe(_ event: NSEvent, router: Router) {
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                  router.canGoBack || router.canGoForward,
                  slide?.stage == .idle,
                  !isOverHorizontalScroller(event) else { return }
            let id = beginSlide()
            let back = snapshot(for: Array(router.path.dropLast()))
            let forward = router.forwardRoutes.last.flatMap { snapshot(for: router.path + [$0]) }
            // Positive amounts are a swipe to the right, which goes back.
            event.trackSwipeEvent(
                options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: router.canGoForward ? -1 : 0,
                max: router.canGoBack ? 1 : 0
            ) { [weak self] amount, _, isComplete, stop in
                guard let self, let slide = self.slide, self.slideID == id else {
                    stop.pointee = true
                    return
                }
                let target = amount > 0 ? back : amount < 0 ? forward : slide.target
                if slide.target !== target { slide.target = target }
                slide.progress = amount
                guard isComplete else { return }
                if amount >= 1 {
                    self.finishSlide(.back)
                } else if amount <= -1 {
                    self.finishSlide(.forward)
                } else {
                    self.cancelSlide()
                }
            }
        }

        private func animateSlide(_ direction: Direction) {
            guard let router, let slide, slide.stage == .idle else { return }
            let id = beginSlide()
            switch direction {
            case .back:
                slide.target = snapshot(for: Array(router.path.dropLast()))
            case .forward:
                slide.target = router.forwardRoutes.last.flatMap { snapshot(for: router.path + [$0]) }
            }
            withAnimation(.smooth(duration: 0.3)) {
                slide.progress = direction == .back ? 1 : -1
            } completion: { [weak self] in
                guard let self, self.slideID == id else { return }
                self.finishSlide(direction)
            }
        }

        /// Snapshots the page being left, for sliding forward to it later.
        private func beginSlide() -> Int {
            if let router { remember(router.path) }
            slideID += 1
            slide?.stage = .sliding
            return slideID
        }

        /// Navigates without NavigationStack's transition, then fades the
        /// snapshot out over the real page.
        private func finishSlide(_ direction: Direction) {
            guard let router, let slide else { return }
            let hasCover = slide.target != nil
            isNavigating = true
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch direction {
                case .back: router.goBack()
                case .forward: router.goForward()
                }
                slide.progress = 0
                slide.coverOpacity = 1
                slide.stage = hasCover ? .settling : .idle
            }
            isNavigating = false
            guard hasCover else {
                slide.target = nil
                return
            }
            let id = slideID
            withAnimation(.easeOut(duration: 0.2)) {
                slide.coverOpacity = 0
            } completion: { [weak self] in
                guard let self, self.slideID == id else { return }
                self.cancelSlide()
            }
        }

        private func cancelSlide() {
            slideID += 1
            guard let slide, slide.stage != .idle || slide.progress != 0 else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                slide.stage = .idle
                slide.progress = 0
                slide.target = nil
            }
        }

        // MARK: Snapshots

        private func pathWillChange() {
            guard !isNavigating, let router else { return }
            cancelSlide()
            remember(router.path)
        }

        private func remember(_ path: [Route]) {
            guard let router, let image = capture() else { return }
            let id = ObjectIdentifier(router)
            snapshots.removeAll { $0.router == id && $0.path == path }
            snapshots.append(Snapshot(router: id, path: path, image: image))
            if snapshots.count > Self.snapshotLimit { snapshots.removeFirst() }
        }

        private func snapshot(for path: [Route]) -> CGImage? {
            guard let router else { return nil }
            let id = ObjectIdentifier(router)
            return snapshots.last { $0.router == id && $0.path == path }?.image
        }

        /// Renders the column as it is on screen. Glass doesn't render, which is
        /// fine for the moment a slide lasts.
        private func capture() -> CGImage? {
            guard let window, let root = window.contentView, let layer = root.layer else { return nil }
            let rect = convert(bounds, to: root)
            let scale = window.backingScaleFactor
            guard rect.width >= 1, rect.height >= 1,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: Int((rect.width * scale).rounded(.up)),
                      height: Int((rect.height * scale).rounded(.up)),
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            context.scaleBy(x: scale, y: scale)
            if layer.isGeometryFlipped {
                context.translateBy(x: 0, y: rect.height)
                context.scaleBy(x: 1, y: -1)
            }
            context.translateBy(x: -rect.minX, y: -rect.minY)
            layer.render(in: context)
            return context.makeImage()
        }

        /// Horizontal carousels keep their own swipes, as in Safari.
        private func isOverHorizontalScroller(_ event: NSEvent) -> Bool {
            guard let content = window?.contentView else { return false }
            // hitTest takes a point in the receiver's superview coordinates.
            let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            var view = content.hitTest(point)
            while let current = view {
                if let scrollView = current as? NSScrollView, let document = scrollView.documentView,
                   document.frame.width > scrollView.contentView.bounds.width + 1 {
                    return true
                }
                view = current.superview
            }
            return false
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            router?.willChangePath = nil
            super.removeFromSuperview()
        }
    }
}
#endif
