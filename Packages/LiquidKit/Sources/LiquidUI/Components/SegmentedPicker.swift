import SwiftUI

/// The system segmented control, the same one the home feed picker uses, so
/// every switch gets the platform's Liquid Glass selection animation.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].title).tag(options[index].value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #if os(macOS)
        // Outside the toolbar, regular-size Mac controls keep the old
        // rounded-rectangle bezel; large ones are Liquid Glass capsules.
        .controlSize(.large)
        #endif
    }
}

extension View {
    /// Pointing-hand cursor over clickable things on the Mac.
    func hoverPointer() -> some View {
        #if os(macOS)
        pointerStyle(.link)
        #else
        self
        #endif
    }
}

/// Mac push animation: NavigationStack switches pages instantly on macOS, so
/// pushed pages slide and fade in instead.
struct PushAppearance: ViewModifier {
    @State private var isShown = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .opacity(isShown ? 1 : 0)
            .offset(x: isShown ? 0 : 36)
            .onAppear { withAnimation(.smooth(duration: 0.32)) { isShown = true } }
        #else
        content
        #endif
    }
}
