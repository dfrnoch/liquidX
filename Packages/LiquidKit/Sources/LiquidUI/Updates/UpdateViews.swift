#if os(macOS)
import SwiftUI
import XKit

/// "LiquidX 0.1.1 is ready to install" with Restart to Update, and update notices.
struct UpdateBanner: View {
    let updater: AppUpdater

    var body: some View {
        Group {
            if let label = updater.bannerLabel {
                card(symbol: "arrow.down.circle.fill", tint: Theme.accent,
                     message: String(localized: "LiquidX \(label) is ready to install.")) {
                    Button("Release Notes") { updater.openReleaseNotes() }
                    Button("Later") { updater.dismissBanner() }
                    if case .installing = updater.phase {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Restart to Update") { updater.restartToUpdate() }
                            .buttonStyle(.glassProminent)
                    }
                }
                .accessibilityIdentifier("updateBanner")
            } else if let notice = updater.notice {
                card(symbol: updater.offersDiskImage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                     tint: updater.offersDiskImage ? .orange : Theme.accent, message: notice) {
                    Button("Dismiss") { updater.dismissNotice() }
                    if updater.offersDiskImage {
                        Button("Download Disk Image") { updater.downloadDiskImage() }
                            .buttonStyle(.glassProminent)
                    }
                }
                .accessibilityIdentifier("updateNotice")
            }
        }
        .animation(.smooth(duration: 0.25), value: updater.bannerLabel)
        .animation(.smooth(duration: 0.25), value: updater.notice)
    }

    private func card(symbol: String, tint: Color, message: String,
                      @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 14) {
            Label {
                Text(message).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 12) { actions() }
                .buttonStyle(.borderless)
                .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows the update banner at the bottom, when there is one.
    func updateBanner(_ updater: AppUpdater?) -> some View {
        overlay(alignment: .bottom) {
            if let updater {
                UpdateBanner(updater: updater).padding(16)
            }
        }
    }
}

/// Settings ▸ Updates.
struct UpdateSettingsSection: View {
    let updater: AppUpdater?

    var body: some View {
        Section {
            if let updater {
                @Bindable var updater = updater
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                Picker("Channel", selection: $updater.channel) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Nightly").tag(UpdateChannel.nightly)
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    Button("Check Now") { updater.check(userInitiated: true) }
                        .disabled(updater.phase == .checking)
                } label: {
                    Text(status(updater))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("This build doesn't update itself. Releases from GitHub do.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Updates")
        } footer: {
            if let updater {
                Text(updater.channel == .stable
                     ? "Production releases from GitHub. Checking contacts github.com only; no account data is sent."
                     : "Nightly builds of the next version, and production releases. Checking contacts github.com only; no account data is sent.")
            }
        }
    }

    private func status(_ updater: AppUpdater) -> String {
        switch updater.phase {
        case .idle: String(localized: "Not checked yet")
        case .checking: String(localized: "Checking…")
        case .upToDate(let date):
            String(localized: "Up to date, checked \(date.formatted(date: .omitted, time: .shortened))")
        case .downloading(let label): String(localized: "Downloading \(label)…")
        case .ready(let label): String(localized: "\(label) is ready: restart LiquidX to install it")
        case .installing(let label): String(localized: "Installing \(label)…")
        case .failed(let message): message
        }
    }
}
#endif
