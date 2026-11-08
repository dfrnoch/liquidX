import SwiftUI

/// An iPhone-style segmented control: a glass capsule with a selection pill
/// that slides between segments. Used on macOS, where the system segmented
/// style draws rectangular bezels; iOS keeps the native control.
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.primary.opacity(0.13))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverPointer()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// The platform's segmented control: native on iOS, glass capsule on macOS.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    var body: some View {
        #if os(macOS)
        GlassSegmentedControl(selection: $selection, options: options)
        #else
        Picker("Section", selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].title).tag(options[index].value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
    #if os(macOS)
    @Environment(\.skipsPushAppearance) private var skipsAnimation
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .opacity(isShown ? 1 : 0)
            .offset(x: isShown ? 0 : 36)
            .onAppear {
                if skipsAnimation {
                    isShown = true
                } else {
                    withAnimation(.smooth(duration: 0.32)) { isShown = true }
                }
            }
        #else
        content
        #endif
    }
}
