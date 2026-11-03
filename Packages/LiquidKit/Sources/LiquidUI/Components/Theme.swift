import SwiftUI

enum Theme {
    static let accent = Color(red: 0.114, green: 0.608, blue: 0.941)
    static let like = Color(red: 0.976, green: 0.094, blue: 0.502)
    static let repost = Color(red: 0.0, green: 0.729, blue: 0.486)
    static let gold = Color(red: 0.89, green: 0.69, blue: 0.2)

    /// Pure black in dark mode (like X), white in light mode.
    static let canvas = Color(light: .white, dark: .black)
    /// Raised panels and cards on the canvas.
    static let panel = Color(light: Color(white: 0.965), dark: Color(white: 0.085))
    static let hairline = Color(light: Color(white: 0.88), dark: Color(white: 0.18))
    static let placeholder = Color(light: Color(white: 0.92), dark: Color(white: 0.14))
}

extension Color {
    /// A colour that follows light/dark mode. `nonisolated`, because SwiftUI
    /// resolves dynamic colours on its background render thread; a main-actor
    /// provider closure traps there under Swift 6's isolation checks.
    nonisolated init(light: Color, dark: Color) {
        #if os(iOS)
        let light = UIColor(light)
        let dark = UIColor(dark)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        #else
        let light = NSColor(light)
        let dark = NSColor(dark)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
        #endif
    }
}

/// Stable string hash (Swift's `Hasher` is randomized per launch).
func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 0x100_0000_01b3
    }
    return hash
}

extension View {
    /// Hairline used between timeline rows.
    func rowSeparator() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }

    /// Caps content at a comfortable reading width and centres it, so feeds
    /// don't stretch edge to edge on iPad and wide windows.
    func readableWidth() -> some View {
        frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    /// Label-coloured (white/black) foreground for glass *menus*. iOS uses the
    /// tint for the label only; macOS menus already render neutral.
    func neutralGlassTint() -> some View {
        #if os(iOS)
        tint(.primary)
        #else
        self
        #endif
    }

    /// A neutral (untinted) glass button. iOS: the system glass style with a
    /// label-coloured foreground. macOS fills tinted glass buttons with the tint
    /// and forces white labels, so it uses plain glass via `NeutralGlassButtonStyle`.
    @ViewBuilder
    func neutralGlassButton(circle: Bool) -> some View {
        #if os(iOS)
        if circle {
            buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large).tint(.primary)
        } else {
            buttonStyle(.glass).controlSize(.large).tint(.primary)
        }
        #else
        buttonStyle(NeutralGlassButtonStyle(isCircle: circle))
        #endif
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

#if os(macOS)
struct NeutralGlassButtonStyle: ButtonStyle {
    var isCircle: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, isCircle ? 6 : 18)
            .padding(.vertical, isCircle ? 6 : 8)
            .contentShape(isCircle ? AnyShape(Circle()) : AnyShape(Capsule()))
            .glassEffect(.regular.interactive(), in: isCircle ? AnyShape(Circle()) : AnyShape(Capsule()))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}
#endif

/// Reading size chosen in Settings → Display (X offers the same five steps).
enum PostTextSize: Int, CaseIterable, Identifiable {
    case extraSmall, small, medium, large, extraLarge

    var id: Self { self }

    var offset: CGFloat {
        switch self {
        case .extraSmall: -2
        case .small: -1
        case .medium: 0
        case .large: 2
        case .extraLarge: 4
        }
    }
}

/// How posts are drawn: text size and whether avatars get their own column.
/// Names use the same size as the post text, as on X.
struct PostStyle: Equatable {
    var textSize: PostTextSize = .medium
    /// When false, the avatar sits inline with the name and the text spans
    /// the full width (no empty gutter on the left).
    var showsAvatarColumn = true

    private var base: CGFloat {
        #if os(macOS)
        15 + textSize.offset
        #else
        16 + textSize.offset
        #endif
    }

    private func font(_ delta: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        #if os(iOS)
        // Still honour the system Dynamic Type setting on iOS.
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: base + delta), weight: weight)
        #else
        .system(size: base + delta, weight: weight)
        #endif
    }

    var name: Font { font(0, .bold) }
    var body: Font { font(0) }
    var meta: Font { font(-1) }
    var label: Font { font(-1, .semibold) }
    var actions: Font { font(-2) }
    var detailName: Font { font(1, .bold) }
    var detailBody: Font { font(4) }
}

extension EnvironmentValues {
    @Entry var postStyle = PostStyle()
}
