#if os(macOS)
import AppKit
public import Observation
import LiquidUpdateSupport
import XKit

/// Automatic updates of the Mac app from LiquidX's GitHub releases (docs/updates.md).
///
/// Checks shortly after launch and every six hours while `checksAutomatically` is
/// on (Settings ▸ Updates), and whenever the user chooses Check for Updates…. A
/// newer release on the chosen channel is downloaded into the app's Caches; its
/// SHA-256, Developer ID signature, notarization, bundle identifier and build are
/// checked, and a "Restart to Update" banner appears. The embedded installer
/// service then swaps the app bundle and reopens LiquidX once it has quit. When
/// the app can't replace itself (translocated, on a disk image), the DMG is
/// offered instead.
@MainActor
@Observable
public final class AppUpdater {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case downloading(label: String)
        case ready(label: String)
        case installing(label: String)
        case failed(message: String)
    }

    struct Configuration {
        var installedApp: URL
        var currentBuild: Int
        var currentLabel: String
        var workDirectory: URL
        var requirement = UpdateSupport.updateRequirement
        var relaunchArguments: [String]
        var overrideReleasesURL: URL?
        var firstCheckDelay: Duration = .seconds(20)
        /// Development only: install as soon as an update is ready (no banner click).
        var installsWhenReady = false
    }

    private(set) var phase: Phase = .idle {
        didSet {
            // Development end-to-end runs (`-LiquidXUpdateAutoInstall`) report each
            // step on stderr; no account data is involved.
            if configuration.installsWhenReady {
                FileHandle.standardError.write(Data("LiquidX update: \(phase)\n".utf8))
            }
        }
    }
    /// The newest known release on the channel (also while downloading or ready).
    private(set) var available: AvailableUpdate?
    /// Set when the banner was dismissed for this update ("Later").
    private(set) var dismissedBuild: Int?
    /// A result worth telling the user: the answer to Check for Updates…, or why an
    /// install failed. Shown as a banner until dismissed.
    private(set) var notice: String?
    /// The notice follows a failed install: offer the disk image instead.
    private(set) var offersDiskImage = false
    let configuration: Configuration

    var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Self.automaticKey) }
    }

    /// Nightly builds follow nightlies unless the user chose otherwise.
    var channel: UpdateChannel {
        didSet {
            defaults.set(channel.rawValue, forKey: Self.channelKey)
            check(userInitiated: false)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let http: any UpdateHTTP
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var prepared: PreparedUpdate?
    @ObservationIgnored var install: @MainActor (PreparedUpdate, URL, [String]) async throws -> Void = { update, installed, arguments in
        try await UpdateInstallerClient.install(update, replacing: installed, arguments: arguments)
    }
    /// Quits like ⌘Q. Scheduled on the run loop rather than called from the task, so
    /// `terminate` never waits on the main actor the task is holding.
    @ObservationIgnored var terminate: @MainActor () -> Void = {
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    static let checkInterval: Duration = .seconds(6 * 60 * 60)
    private static let automaticKey = "LiquidX.checksForUpdates"
    private static let channelKey = "LiquidX.updateChannel"

    init(defaults: UserDefaults, http: any UpdateHTTP, configuration: Configuration) {
        self.defaults = defaults
        self.http = http
        self.configuration = configuration
        checksAutomatically = defaults.object(forKey: Self.automaticKey) == nil || defaults.bool(forKey: Self.automaticKey)
        channel = defaults.string(forKey: Self.channelKey).flatMap(UpdateChannel.init(rawValue:))
            ?? (configuration.currentLabel.contains("-nightly.") ? .nightly : .stable)
    }

    /// Release builds update from GitHub releases. Development builds (`-dev`
    /// label) and UI tests don't, unless a development feed is given with
    /// `-LiquidXUpdateFeed <url>` (Debug only).
    static func make(bundle: Bundle, defaults: UserDefaults) -> AppUpdater? {
        let info = bundle.infoDictionary ?? [:]
        guard let buildText = info["CFBundleVersion"] as? String, let build = Int(buildText) else { return nil }
        let short = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let label = (info["LXVersionLabel"] as? String).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? short
        #if DEBUG
        let feed = defaults.string(forKey: "LiquidXUpdateFeed").flatMap(URL.init(string:))
        let autoInstall = defaults.bool(forKey: "LiquidXUpdateAutoInstall")
        // Development builds are signed with Apple Development and not notarized.
        let requirement = UpdateSupport.teamRequirement
        #else
        let feed: URL? = nil
        let autoInstall = false
        let requirement = UpdateSupport.updateRequirement
        #endif
        let uiTesting = defaults.bool(forKey: "LiquidXUITesting")
        guard feed != nil || (!uiTesting && !label.hasSuffix("-dev")) else { return nil }
        let configuration = Configuration(
            installedApp: bundle.bundleURL, currentBuild: build, currentLabel: label,
            workDirectory: URL.cachesDirectory.appending(path: "LiquidXUpdates", directoryHint: .isDirectory),
            requirement: requirement, relaunchArguments: Array(ProcessInfo.processInfo.arguments.dropFirst()),
            overrideReleasesURL: feed, firstCheckDelay: feed == nil ? .seconds(20) : .seconds(1),
            installsWhenReady: autoInstall)
        return AppUpdater(defaults: defaults, http: URLSessionUpdateHTTP(userAgent: "LiquidX/\(label) (macOS)"),
                          configuration: configuration)
    }

    /// The version the banner offers, when it should be shown.
    var bannerLabel: String? {
        guard let available, available.manifest.build != dismissedBuild else { return nil }
        switch phase {
        case .ready, .installing: return available.manifest.label
        default: return nil
        }
    }

    // MARK: Scheduling

    func start() {
        guard schedule == nil else { return }
        // A previous download (installed or abandoned) is not reused across launches.
        try? FileManager.default.removeItem(at: configuration.workDirectory)
        let delay = configuration.firstCheckDelay
        schedule = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                guard let self else { return }
                if checksAutomatically { check(userInitiated: false) }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func stop() {
        schedule?.cancel()
        schedule = nil
        work?.cancel()
        work = nil
    }

    // MARK: Checking and downloading

    /// Checks the feed, then downloads and verifies a newer release.
    func check(userInitiated: Bool) {
        if userInitiated {
            dismissedBuild = nil
            dismissNotice()
        }
        switch phase {
        case .checking, .downloading, .installing: return
        case .ready where !userInitiated: return
        default: break
        }
        work?.cancel()
        phase = .checking
        let feed = GitHubUpdateFeed(http: http, overrideReleasesURL: configuration.overrideReleasesURL)
        let channel = channel
        let current = configuration.currentBuild
        work = Task { [weak self] in
            do {
                let update = try await feed.latest(for: channel, newerThan: current)
                guard let self, !Task.isCancelled else { return }
                guard let update else {
                    available = nil
                    phase = .upToDate(.now)
                    if userInitiated {
                        notice = String(localized: "LiquidX \(configuration.currentLabel) is up to date.")
                    }
                    return
                }
                if let ready = prepared, ready.build == update.manifest.build,
                   FileManager.default.fileExists(atPath: ready.archive.path) {
                    available = update
                    phase = .ready(label: update.manifest.label)
                    return
                }
                available = update
                phase = .downloading(label: update.manifest.label)
                let ready = try await UpdatePreparer.prepare(update, http: http, workDirectory: configuration.workDirectory,
                                                             installedApp: configuration.installedApp,
                                                             requirement: configuration.requirement)
                guard !Task.isCancelled else { return }
                prepared = ready
                phase = .ready(label: update.manifest.label)
                if configuration.installsWhenReady { restartToUpdate() }
            } catch let error as UpdateError {
                guard let self, !Task.isCancelled else { return }
                phase = .failed(message: error.description)
                if userInitiated {
                    notice = error.description
                    offersDiskImage = available?.diskImageURL != nil
                }
            } catch {}
        }
    }

    func dismissBanner() {
        dismissedBuild = available?.manifest.build
    }

    func dismissNotice() {
        notice = nil
        offersDiskImage = false
    }

    // MARK: Installing

    /// Whether LiquidX can replace its own bundle where it runs from: not from the
    /// disk image or a translocated copy. (Write access isn't checked here: the
    /// sandbox always denies it; the installer service reports a real failure.)
    var canInstallInPlace: Bool {
        let path = configuration.installedApp.path
        return !path.contains("/AppTranslocation/") && !path.hasPrefix("/Volumes/")
    }

    /// Installs the prepared update and quits; the installer reopens LiquidX.
    func restartToUpdate() {
        guard case .ready(let label) = phase, let app = prepared else { return }
        guard canInstallInPlace else {
            failInstall(String(localized: """
                LiquidX can't update itself where it is. Move it to the Applications folder, \
                or install the new version from the disk image.
                """))
            return
        }
        phase = .installing(label: label)
        let installed = configuration.installedApp
        let arguments = configuration.relaunchArguments
        work = Task { [weak self] in
            do {
                try await self?.install(app, installed, arguments)
                self?.terminate()
            } catch let error as UpdateError {
                self?.failInstall(error.description)
            } catch {
                self?.failInstall(String(localized: "The update could not be installed."))
            }
        }
    }

    private func failInstall(_ message: String) {
        phase = .failed(message: message)
        dismissedBuild = available?.manifest.build
        notice = message
        offersDiskImage = available?.diskImageURL != nil
    }

    /// Opens the release's disk image in the browser (manual install fallback).
    func downloadDiskImage() {
        guard let url = available?.diskImageURL ?? available?.releasePage else { return }
        NSWorkspace.shared.open(url)
    }

    func openReleaseNotes() {
        guard let url = available?.releasePage else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
