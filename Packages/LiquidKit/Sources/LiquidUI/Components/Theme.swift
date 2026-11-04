import SwiftUI

enum Theme {
    #if os(macOS)
    /// The accent chosen in System Settings ▸ Appearance; with "Multicolor", the
    /// app's AccentColor asset (the same blue as on iOS).
    static let accent = Color.accentColor
    #else
    /// X's blue, a shade darker (#1A8CD8). Keep in sync with the AccentColor asset.
    static let accent = Color(red: 0.102, green: 0.549, blue: 0.847)
    #endif
    static let like = Color(red: 0.976, green: 0.094, blue: 0.502)
    static let repost = Color(red: 0.0, green: 0.729, blue: 0.486)
    static let gold = Color(red: 0.89, green: 0.69, blue: 0.2)

    /// Pure black in dark mode (like X), white in light mode.
    static let canvas = Color(light: .white, dark: .black)
    /// Raised panels and cards on the canvas.
    static let panel = Color(light: Color(white: 0.965), dark: Color(white: 0.085))
    static let hairline = Color(light: Color(white: 0.88), dark: Color(white: 0.18))
    /// Joins a post to the reply below it.
    static let threadLine = Color(light: Color(white: 0.8), dark: Color(white: 0.27))
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

    /// A Liquid Glass circle around an icon, the size of the neighbouring
    /// glass buttons (menus can't use the glass button style reliably).
    func glassCircle() -> some View {
        #if os(macOS)
        frame(width: 36, height: 36)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
        #else
        frame(width: 48, height: 48)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
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

/// The Mac window's look, from Settings → Appearance. iPhone and iPad always
/// use `.classic`. Each theme has light and dark variants.
enum WindowTheme: String, CaseIterable, Identifiable {
    /// X's own: pure black (or white) everywhere.
    case classic
    /// Soft charcoal window with slightly raised columns and cards.
    case graphite
    /// X's "Dim": deep blue-grey.
    case dim
    /// The desktop shows through a blur behind translucent columns.
    case glass

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .graphite: "Graphite"
        case .dim: "Dim"
        case .glass: "Glass"
        }
    }

    var palette: Palette {
        switch self {
        case .classic:
            .classic
        case .graphite:
            Palette(
                window: Color(light: Color(white: 0.94), dark: Color(white: 0.055)),
                column: Color(light: .white, dark: Color(white: 0.075)),
                panel: Color(light: .white, dark: Color(white: 0.075))
            )
        case .dim:
            Palette(
                window: Color(light: Color(red: 0.93, green: 0.95, blue: 0.96), dark: Color(red: 0.063, green: 0.09, blue: 0.118)),
                column: Color(light: Color(red: 0.97, green: 0.98, blue: 0.98), dark: Color(red: 0.082, green: 0.125, blue: 0.169)),
                panel: Color(light: .white, dark: Color(red: 0.118, green: 0.153, blue: 0.196))
            )
        case .glass:
            Palette(
                window: .clear,
                column: Color(light: Color.white.opacity(0.5), dark: Color.black.opacity(0.32)),
                canvas: .clear,
                panel: Color(light: Color.white.opacity(0.5), dark: Color.white.opacity(0.06)),
                isTranslucent: true
            )
        }
    }
}

/// Background colours for one `WindowTheme`, read from the environment.
struct Palette: Equatable {
    /// Behind the columns: the Mac window itself.
    var window: Color
    /// Each column's fill (the timeline panel).
    var column: Color
    /// Screen backgrounds inside a column. Clear for glass, so the column's
    /// translucent fill isn't stacked once per screen.
    var canvas: Color
    /// Raised cards (trends, about).
    var panel: Color
    /// The window shows the desktop through a behind-window blur.
    var isTranslucent = false

    init(window: Color, column: Color, canvas: Color? = nil, panel: Color, isTranslucent: Bool = false) {
        self.window = window
        self.column = column
        self.canvas = canvas ?? column
        self.panel = panel
        self.isTranslucent = isTranslucent
    }

    static let classic = Palette(window: Theme.canvas, column: Theme.canvas, panel: Theme.panel)
}

extension EnvironmentValues {
    @Entry var palette = Palette.classic
}

#if os(macOS)
/// The behind-window blur under the glass theme.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        // Stay see-through when the window is in the background too.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif
