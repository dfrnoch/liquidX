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
    private let webCredentials: any WebCredentialStore
    private let launchDemo: Bool
    private static let clientIDKey = "LiquidX.clientID"
    private static let appearanceKey = "LiquidXAppearance"
    private static let meCacheKey = "LiquidX.me"
    private static let connectionKey = "LiquidX.connection"

    public convenience init() {
        self.init(bundle: .main, defaults: .standard)
    }

    init(bundle: Bundle, defaults: UserDefaults) {
        bundledClientID = (bundle.object(forInfoDictionaryKey: "LXClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clientID = defaults.string(forKey: Self.clientIDKey) ?? ""
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        launchDemo = defaults.bool(forKey: "LiquidXDemo")
        let uiTesting = defaults.bool(forKey: "LiquidXUITesting")
        credentials = uiTesting ? EphemeralCredentialStore() : KeychainCredentialStore()
        webCredentials = uiTesting ? EphemeralStore<WebCredentials>() : KeychainStore<WebCredentials>()
    }

    var effectiveClientID: String {
        clientID.isEmpty ? bundledClientID : clientID
    }

    var session: Session? {
        if case .signedIn(let session) = phase { session } else { nil }
    }

    func start() async {
        guard case .launching = phase else { return }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "LiquidXKeychainSelfTest") {
            Self.keychainSelfTest()
        }
        #endif
        if launchDemo {
            await startDemo()
            return
        }
        // Keychain reads can block on a system permission prompt (notably for
        // ad hoc signed development builds), so never do them on the main actor.
        let credentials = credentials
        let webCredentials = webCredentials
        let preferWeb = UserDefaults.standard.string(forKey: Self.connectionKey) == ConnectionKind.webSession.rawValue
        let (oauth, web) = await Task.detached(priority: .userInitiated) {
            preferWeb ? (nil, webCredentials.load()) : (credentials.load(), webCredentials.load())
        }.value
        if let web, web.isComplete, preferWeb || oauth == nil {
            await activate(WebClient(credentials: web, store: webCredentials))
        } else if let oauth {
            await activate(XClient(credentials: oauth, store: credentials))
        } else {
            phase = .signedOut
        }
    }

    #if DEBUG
    /// Debug-only: proves tokens survive a save/load/delete round trip in this
    /// build's real Keychain context (sandbox, signing), using a separate service.
    private static func keychainSelfTest() {
        let store = KeychainCredentialStore(service: "dev.frnoch.liquidx.selftest")
        let sample = StoredCredentials(
            clientID: "self-test",
            tokens: OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: .now.addingTimeInterval(60), scope: nil)
        )
        store.save(sample)
        let loaded = store.load()
        store.delete()
        let deleted = store.load() == nil
        FileHandle.standardError.write(Data("LiquidX keychain self-test: saved+loaded=\(loaded == sample) deleted=\(deleted)\n".utf8))
    }
    #endif

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
            let webCredentials = webCredentials
            await Task.detached { webCredentials.delete() }.value
            await activate(client)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // The user closed the sheet; nothing to report.
        } catch XAPIError.cancelled {
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Unofficial: signs in with an x.com browser session (see WebClient).
    func signIn(with web: WebCredentials) async {
        signInError = nil
        let credentials = credentials
        await Task.detached { credentials.delete() }.value
        webCredentials.save(web)
        isSigningIn = true
        defer { isSigningIn = false }
        await activate(WebClient(credentials: web, store: webCredentials))
    }

    private func forget(_ service: any XService) {
        switch service.connection {
        case .officialAPI: credentials.delete()
        case .webSession: webCredentials.delete()
        case .demo: break
        }
    }

    private func activate(_ service: any XService) async {
        do {
            let me = try await service.me()
            if !service.isDemo, let data = try? JSONEncoder().encode(me) {
                UserDefaults.standard.set(data, forKey: Self.meCacheKey)
                UserDefaults.standard.set(service.connection.rawValue, forKey: Self.connectionKey)
            }
            open(service, as: me)
        } catch XAPIError.unauthorized {
            forget(service)
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
        if let id = UserDefaults.standard.string(forKey: "LiquidXOpenPost") {
            session.router(for: session.section).push(.postID(id))
        }
        if UserDefaults.standard.bool(forKey: "LiquidXUITesting") {
            session.autoRefreshInterval = 0
        }
        withAnimation(.smooth) { phase = .signedIn(session) }
        Task { await session.start() }
    }

    func signOut() async {
        guard let session else { return }
        await session.service.signOut()
        if !session.service.isDemo {
            forget(session.service)
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
