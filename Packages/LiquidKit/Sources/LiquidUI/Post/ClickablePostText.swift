#if os(macOS)
import AppKit
import SwiftUI

/// Post text in a Mac timeline row. Dragging or double-clicking selects, a
/// single click opens the post and links still open. SwiftUI's selectable
/// `Text` keeps every click for itself, so the row never saw them.
struct ClickablePostText: NSViewRepresentable {
    let text: AttributedString
    let fontSize: CGFloat
    let onClick: () -> Void

    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PostTextView {
        let view = PostTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.writingToolsBehavior = .none
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.delegate = context.coordinator
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateNSView(_ view: PostTextView, context: Context) {
        context.coordinator.openURL = openURL
        view.onClick = onClick
        view.linkTextAttributes = [.foregroundColor: NSColor(Theme.accent), .cursor: NSCursor.pointingHand]
        guard view.rendered?.text != text || view.rendered?.fontSize != fontSize else { return }
        let attributed = NSMutableAttributedString(text)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor]
        attributed.addAttributes(attributes, range: NSRange(location: 0, length: attributed.length))
        view.textStorage?.setAttributedString(attributed)
        view.rendered = (text, fontSize)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PostTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let used = nsView.usedSize(forWidth: width)
        return CGSize(width: proposal.width ?? used.width, height: used.height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var openURL: OpenURLAction?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            (textView as? PostTextView)?.clickedLink = true
            guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            openURL?(url)
            return true
        }
    }
}

final class PostTextView: NSTextView {
    var onClick: (() -> Void)?
    var rendered: (text: AttributedString, fontSize: CGFloat)?
    fileprivate var clickedLink = false

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        clickedLink = false
        let hadSelection = selectedRange().length > 0
        // Tracks the drag until the mouse goes up.
        super.mouseDown(with: event)
        // A click that only clears a selection doesn't also open the post.
        guard event.clickCount == 1, !clickedLink, !hadSelection, selectedRange().length == 0 else { return }
        onClick?()
    }

    /// The text's own menu (Copy, Look Up) when something is selected,
    /// otherwise the row's post menu.
    override func rightMouseDown(with event: NSEvent) {
        if selectedRange().length > 0 {
            super.rightMouseDown(with: event)
        } else {
            nextResponder?.rightMouseDown(with: event)
        }
    }

    func usedSize(forWidth width: CGFloat) -> CGSize {
        guard let container = textContainer, let layout = layoutManager else { return .zero }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: ceil(used.width), height: ceil(used.height))
    }
}
#endif
