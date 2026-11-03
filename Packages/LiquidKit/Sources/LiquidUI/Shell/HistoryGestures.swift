#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// Safari-style back/forward: two-finger horizontal trackpad swipes (when
    /// "Swipe between pages" allows them) and the mouse's back/forward buttons.
    func historyGestures(_ router: Router) -> some View {
        background(HistoryGestureMonitor(router: router))
    }
}

private struct HistoryGestureMonitor: NSViewRepresentable {
    let router: Router

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.router = router
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.router = router
    }

    final class MonitorView: NSView {
        var router: Router?
        private var monitor: Any?

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
                case 3 where router.canGoBack: navigate { router.goBack() }
                case 4 where router.canGoForward: navigate { router.goForward() }
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

        private func trackSwipe(_ event: NSEvent, router: Router) {
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                  router.canGoBack || router.canGoForward,
                  !isOverHorizontalScroller(event) else { return }
            // Positive amounts are a swipe to the right, which goes back.
            event.trackSwipeEvent(
                options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: router.canGoForward ? -1 : 0,
                max: router.canGoBack ? 1 : 0
            ) { [weak self] amount, _, isComplete, _ in
                guard isComplete, let self else { return }
                if amount >= 1 {
                    self.navigate { router.goBack() }
                } else if amount <= -1 {
                    self.navigate { router.goForward() }
                }
            }
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

        private func navigate(_ action: () -> Void) {
            withAnimation(.snappy) { action() }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
#endif
