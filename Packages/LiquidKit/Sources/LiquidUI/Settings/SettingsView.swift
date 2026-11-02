public import SwiftUI
import XKit

/// Account, developer app and storage settings. A sheet on iOS; the Settings
/// window on macOS.
public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingClientID = false
    @State private var clearedCache = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        Form {
            if let session = model.session {
                Section("Account") {
                    HStack(spacing: 12) {
                        Avatar(user: session.me, size: 44)
                        VStack(alignment: .leading) {
                            Text(session.me.name).font(.headline)
                            Text(session.me.handle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.service.isDemo {
                            Text("Demo").font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.orange.opacity(0.2), in: Capsule())
                        }
                    }
                    LabeledContent("Connection") {
                        switch session.service.connection {
                        case .officialAPI: Text("Official X API")
                        case .webSession: Text("x.com session (unofficial)").foregroundStyle(.orange)
                        case .demo: Text("Demo")
                        }
                    }
                    Button(session.service.isDemo ? "Leave Demo" : "Sign Out", role: .destructive) {
                        Task { await model.signOut() }
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $model.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Client ID") {
                    Text(model.effectiveClientID.isEmpty ? "Not set" : masked(model.effectiveClientID))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Change Client ID…") { isShowingClientID = true }
            } header: {
                Text("X Developer App")
            } footer: {
                Text("LiquidX signs in with OAuth 2.0 and PKCE using your own X developer app. Tokens are stored only in this device's Keychain.")
            }

            Section("Storage") {
                Button(clearedCache ? "Cache Cleared" : "Clear Image and Timeline Cache") {
                    ImagePipeline.shared.removeAll()
                    FeedCache.deleteAll()
                    clearedCache = true
                }
                .disabled(clearedCache)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("Source Code on GitHub", destination: URL(string: "https://github.com/dfrnoch/liquidX")!)
                Text("LiquidX is an independent open-source project and is not affiliated with, endorsed by, or sponsored by X Corp.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $isShowingClientID) { ClientIDSheet(model: model) }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
    }

    private func masked(_ id: String) -> String {
        guard id.count > 8 else { return id }
        return String(id.prefix(4)) + "…" + String(id.suffix(4))
    }
}
