import AuthenticationServices
public import Observation
import SwiftUI
import XKit

/// Root state: launching → signed out → signed in (live or demo).
@MainActor
@Observable
public final class AppModel {
    enum Phase {
        case launching
        case signedOut
        case signedIn(Session)
    }

    private(set) var phase: Phase = .launching
    var isSigningIn = false
    var signInError: String?

    /// OAuth 2.0 Client ID: user-entered (Settings / sign-in) wins over the one
    /// baked in at build time via `LIQUIDX_X_CLIENT_ID` in `Config/Local.xcconfig`.
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Self.clientIDKey) }
    }

    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    let bundledClientID: String
    private let credentials: any CredentialStore
    private let launchDemo: Bool
    private static let clientIDKey = "LiquidX.clientID"
    private static let appearanceKey = "LiquidXAppearance"
    private static let meCacheKey = "LiquidX.me"

    public convenience init() {
        self.init(bundle: .main, defaults: .standard)
    }

    init(bundle: Bundle, defaults: UserDefaults) {
        bundledClientID = (bundle.object(forInfoDictionaryKey: "LXClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clientID = defaults.string(forKey: Self.clientIDKey) ?? ""
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        launchDemo = defaults.bool(forKey: "LiquidXDemo")
        credentials = defaults.bool(forKey: "LiquidXUITesting") ? EphemeralCredentialStore() : KeychainCredentialStore()
    }

    var effectiveClientID: String {
        clientID.isEmpty ? bundledClientID : clientID
    }

    var session: Session? {
        if case .signedIn(let session) = phase { session } else { nil }
    }

    func start() async {
        guard case .launching = phase else { return }
        if launchDemo {
            await startDemo()
        } else if let stored = credentials.load() {
            await activate(XClient(credentials: stored, store: credentials))
        } else {
            phase = .signedOut
        }
    }

    func startDemo() async {
        await activate(DemoService())
    }

    func signIn(using webAuthentication: WebAuthenticationSession) async {
        let clientID = effectiveClientID
        guard !clientID.isEmpty else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        let request = AuthorizationRequest(configuration: OAuthConfiguration(clientID: clientID))
        do {
            let callback = try await webAuthentication.authenticate(
                using: request.url,
                callback: .customScheme(OAuthConfiguration.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            let client = try await XClient.signIn(with: request, callback: callback, store: credentials)
            await activate(client)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // The user closed the sheet; nothing to report.
        } catch XAPIError.cancelled {
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func activate(_ service: any XService) async {
        do {
            let me = try await service.me()
            if !service.isDemo, let data = try? JSONEncoder().encode(me) {
                UserDefaults.standard.set(data, forKey: Self.meCacheKey)
            }
            open(service, as: me)
        } catch XAPIError.unauthorized {
            credentials.delete()
            phase = .signedOut
            signInError = XAPIError.unauthorized.localizedDescription
        } catch {
            // Offline launch with a saved account: show cached content and let
            // requests fail (and retry) individually.
            if !service.isDemo,
               let data = UserDefaults.standard.data(forKey: Self.meCacheKey),
               let me = try? JSONDecoder().decode(XUser.self, from: data) {
                open(service, as: me)
            } else {
                phase = .signedOut
                signInError = error.localizedDescription
            }
        }
    }

    private func open(_ service: any XService, as me: XUser) {
        let session = Session(service: service, me: me) { [weak self] in
            Task { await self?.signOut() }
        }
        if let section = UserDefaults.standard.string(forKey: "LiquidXSection").flatMap(AppSection.init(rawValue:)) {
            session.section = section
        }
        if let username = UserDefaults.standard.string(forKey: "LiquidXOpenProfile") {
            session.router(for: session.section).push(.user(username))
        }
        withAnimation(.smooth) { phase = .signedIn(session) }
        Task { await session.start() }
    }

    func signOut() async {
        guard let session else { return }
        await session.service.signOut()
        if !session.service.isDemo {
            credentials.delete()
            FeedCache.deleteAll()
            UserDefaults.standard.removeObject(forKey: Self.meCacheKey)
        }
        withAnimation(.smooth) { phase = .signedOut }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
