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
