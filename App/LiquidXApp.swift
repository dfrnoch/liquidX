import LiquidUI
import SwiftUI

@main
struct LiquidXApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        #if os(macOS)
        .defaultSize(width: 1_180, height: 860)
        .windowToolbarStyle(.unified)
        #endif
        .commands { LiquidCommands(model: model) }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
        }
        #endif
    }
}
