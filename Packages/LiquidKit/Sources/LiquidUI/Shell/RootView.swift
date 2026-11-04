public import SwiftUI
import XKit

/// The app's single window content. The app target only hosts this.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        Group {
            switch model.phase {
            case .launching:
                model.palette.window.ignoresSafeArea()
            case .signedOut:
                SignInView(model: model)
                    #if os(macOS)
                    .updateBanner(model.updater)
                    #endif
                    .transition(.opacity)
            case .signedIn(let session):
                SessionView(session: session)
                    .transition(.opacity)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.postStyle, model.postStyle)
        .environment(\.palette, model.palette)
        .task { await model.start() }
    }
}

/// Signed-in chrome shared by both platforms: shell + overlays and sheets.
private struct SessionView: View {
    @Bindable var session: Session

    var body: some View {
        shell
            .environment(session)
            .overlay(alignment: .top) {
                if let toast = session.toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .overlay {
                // Always present so the dimming and the card animate separately.
                FloatingComposer(context: session.quickComposer)
                    .environment(session)
                    .environment(session.currentRouter)
                    .zIndex(5)
            }
            .overlay {
                if let viewer = session.mediaViewer {
                    MediaViewer(context: viewer) {
                        withAnimation(.smooth(duration: 0.25)) { session.mediaViewer = nil }
                    }
                    .environment(session)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
                }
            }
            .animation(.smooth(duration: 0.25), value: session.mediaViewer?.id)
            .sheet(item: $session.composer) { context in
                ComposeView(context: context)
                    .environment(session)
                    .environment(session.currentRouter)
            }
            #if os(iOS)
            .sheet(isPresented: $session.isShowingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { session.isShowingSettings = false }
                            }
                        }
                }
            }
            #endif
            .focusedSceneValue(\.session, session)
    }

    @ViewBuilder
    private var shell: some View {
        #if os(macOS)
        MacShell()
        #else
        PhoneShell()
        #endif
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label {
            Text(toast.message).font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isError ? .orange : Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension FocusedValues {
    @Entry var session: Session?
}

/// Menu bar commands (macOS) and hardware-keyboard shortcuts (iPad).
public struct LiquidCommands: Commands {
    @FocusedValue(\.session) private var session
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        #if os(macOS)
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { model.updater?.check(userInitiated: true) }
                .disabled(model.updater == nil)
        }
        #endif
        CommandGroup(after: .newItem) {
            Button("New Post") { session?.compose() }
                .keyboardShortcut("n")
                .disabled(session == nil)
        }
        CommandMenu("Go") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { offset, section in
                Button(section.title) { session?.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character(String(offset + 1))))
                    .disabled(session == nil)
            }
            Divider()
            Button("Back") { session?.currentRouter.goBack() }
                .keyboardShortcut("[")
                .disabled(session?.currentRouter.canGoBack != true)
            Button("Forward") { session?.currentRouter.goForward() }
                .keyboardShortcut("]")
                .disabled(session?.currentRouter.canGoForward != true)
            Divider()
            Button("Refresh") {
                guard let session else { return }
                Task { await session.home.refresh() }
            }
            .keyboardShortcut("r")
            .disabled(session == nil)
        }
    }
}
