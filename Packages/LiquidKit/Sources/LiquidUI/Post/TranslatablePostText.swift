import SwiftUI
import Translation
import XKit

/// Post text that translates in place, with X's "Translate post" below it.
/// While the translation is on its way a highlight sweeps across the
/// original; the translation then writes itself in glyph by glyph, each one
/// rising out of a blur, and keeps pace as more of it streams in.
struct TranslatablePostText<Original: View>: View {
    let post: XPost
    let font: Font
    /// Mac timeline rows open the post on a click, so their text isn't selectable.
    var isSelectable = true
    /// The regular text view, shown whenever nothing is animating.
    @ViewBuilder let original: Original

    @Environment(Session.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: TextReveal?

    var body: some View {
        let state = session.translations.state(for: post)
        VStack(alignment: .leading, spacing: 6) {
            text(state)
            TranslationControl(post: post, state: state)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: state.phase)
        .translationTask(state.deviceRequest) { @concurrent [post, translations = session.translations] translator in
            // The session isn't Sendable: translate off the main actor and
            // hand back only the text.
            let result: Result<String, any Error>
            do {
                result = .success(try await translator.translate(post.plainText).targetText)
            } catch {
                result = .failure(error)
            }
            await translations.finishOnDevice(post, with: result)
        }
        .onChange(of: RevealKey(state, original: post.text)) { old, new in startReveal(from: old, to: new) }
        .task(id: reveal) {
            // Stop the timeline once the last glyph is in place.
            guard let reveal else { return }
            try? await Task.sleep(for: .seconds(reveal.duration))
            if self.reveal == reveal { self.reveal = nil }
        }
    }

    @ViewBuilder
    private func text(_ state: PostTranslation) -> some View {
        let shown = state.phase == .translated ? state.text : nil
        if reduceMotion {
            if let shown { styled(Text(shown)).transition(.opacity) } else { original.transition(.opacity) }
        } else if state.phase == .translating {
            TimelineView(.animation) { context in
                styled(Text(post.text))
                    .textRenderer(ShimmerRenderer(phase: ShimmerRenderer.phase(at: context.date)))
            }
        } else if shown != nil || reveal != nil {
            TimelineView(.animation(paused: reveal == nil)) { context in
                styled(Text(shown ?? post.text))
                    .textRenderer(RevealRenderer(settled: reveal?.settled ?? 0, front: reveal?.front(at: context.date) ?? .infinity))
            }
        } else {
            original
        }
    }

    @ViewBuilder
    private func styled(_ text: Text) -> some View {
        let text = text.font(font).tint(Theme.accent).fixedSize(horizontal: false, vertical: true)
        if isSelectable { text.textSelection(.enabled) } else { text }
    }

    private func startReveal(from old: RevealKey, to new: RevealKey) {
        guard !reduceMotion else { return }
        let now = Date.now
        if old.showsTranslation != new.showsTranslation {
            reveal = TextReveal(settled: 0, from: 0, to: Double(new.length), start: now)
        } else if new.showsTranslation, new.length > old.length {
            // More of the stream arrived: carry on from where the front is,
            // or after the text that is already in place.
            reveal = if let reveal {
                TextReveal(settled: reveal.settled, from: reveal.front(at: now), to: Double(new.length), start: now)
            } else {
                TextReveal(settled: Double(old.length), from: Double(old.length), to: Double(new.length), start: now)
            }
        }
    }
}

/// What the reveal follows: which text is up, and how much of it there is.
private struct RevealKey: Equatable {
    var showsTranslation: Bool
    var length: Int

    init(_ state: PostTranslation, original: AttributedString) {
        let translation = state.phase == .translated ? state.text : nil
        showsTranslation = translation != nil
        // UTF-16 units: at least one per glyph for nearly all text.
        length = (translation ?? original).characters.reduce(0) { $0 + $1.utf16.count }
    }
}

/// A reveal front moving through the glyphs, from `from` to `to` (plus the
/// width of the fade), fast enough that a whole post takes under a second.
private struct TextReveal: Equatable {
    /// Glyphs before this one are already in place.
    var settled: Double
    var from: Double
    var to: Double
    var start: Date

    private var rate: Double { max(70, (to - from) / 0.8) }
    var duration: TimeInterval { (to + RevealRenderer.spread - from) / rate }

    func front(at date: Date) -> Double {
        from + max(0, date.timeIntervalSince(start)) * rate
    }
}

/// Draws glyphs up to `front`; the last few fade in from a blur as they rise
/// into place.
private struct RevealRenderer: TextRenderer {
    /// How many glyphs the fade spans.
    static let spread = 12.0
    /// Glyphs before this one are drawn as they are.
    var settled: Double
    var front: Double

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard front.isFinite else {
            for line in layout { context.draw(line) }
            return
        }
        var index = 0.0
        for line in layout {
            for run in line {
                for glyph in run {
                    let progress = index < settled ? 1 : (front - index) / Self.spread
                    index += 1
                    if progress >= 1 {
                        context.draw(glyph)
                        continue
                    }
                    // Everything after this glyph is hidden too.
                    guard progress > 0 else { return }
                    var fading = context
                    fading.opacity = progress
                    fading.translateBy(x: 0, y: (1 - progress) * 6)
                    fading.addFilter(.blur(radius: (1 - progress) * 5))
                    fading.draw(glyph)
                }
            }
        }
    }
}

/// Dims the text and sweeps a highlight across it, slanted so lower lines
/// trail a little.
private struct ShimmerRenderer: TextRenderer {
    /// 0 to 1 over one sweep.
    var phase: Double

    static func phase(at date: Date) -> Double {
        let period = 1.5
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let width = max(1, layout.map { $0.typographicBounds.rect.maxX }.max() ?? 1)
        let lines = Double(max(1, layout.count))
        // Start and end past the edges so the band slides in and out.
        let center = phase * 1.6 - 0.3
        for (number, line) in layout.enumerated() {
            let slant = Double(number) / lines * 0.25
            for run in line {
                for glyph in run {
                    let distance = glyph.typographicBounds.rect.midX / width * 0.75 + slant - center
                    var lit = context
                    lit.opacity = 0.35 + 0.65 * exp(-distance * distance / 0.012)
                    lit.draw(glyph)
                }
            }
        }
    }
}

/// "Translate post", "Translating…", or "Translated from Italian · Show original".
private struct TranslationControl: View {
    let post: XPost
    let state: PostTranslation

    @Environment(Session.self) private var session
    @Environment(\.postStyle) private var style

    var body: some View {
        HStack(spacing: 4) {
            switch state.phase {
            case .original:
                Button(state.text == nil ? "Translate post" : "Show translation") { toggle() }
                    .foregroundStyle(Theme.accent)
            case .translating:
                Image(systemName: "translate")
                    .symbolEffect(.pulse, options: .repeating)
                Text("Translating…")
            case .translated:
                Image(systemName: "translate")
                if let language {
                    Text("Translated from \(language)")
                } else {
                    Text("Translated")
                }
                Text(verbatim: "·")
                Button("Show original") { toggle() }
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(style.meta)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .hoverPointer()
        .lineLimit(1)
        .contentTransition(.opacity)
        .animation(.snappy, value: state.phase)
    }

    private var language: String? {
        post.spokenLanguage?.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) }
    }

    private func toggle() {
        session.translations.toggle(post)
    }
}
