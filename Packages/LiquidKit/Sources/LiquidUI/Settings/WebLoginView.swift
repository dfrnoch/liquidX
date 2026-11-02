import SwiftUI
import WebKit
import XKit

/// Signs in to x.com in an embedded web view and hands back the session.
///
/// The web view uses its own non-persistent data store, so nothing leaks into
/// Safari and nothing stays behind in WebKit: the cookies LiquidX needs are
/// copied to the Keychain and the rest is discarded with the view.
struct WebLoginView: View {
    let onComplete: (WebCredentials) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = WebLoginController()

    var body: some View {
        NavigationStack {
            WebLoginWebView(webView: controller.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if controller.isFinishing {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Connecting to your account…").font(.subheadline)
                        }
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }
                }
                .navigationTitle("Sign in to x.com")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 680, idealHeight: 760)
        #endif
        .onChange(of: controller.credentials) { _, credentials in
            guard let credentials else { return }
            onComplete(credentials)
            dismiss()
        }
    }
}

@Observable
final class WebLoginController: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    var credentials: WebCredentials?
    var isFinishing = false

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observed = WebObservations()
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(
            WKUserScript(source: WebLogin.observerScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebLogin.userAgent
        super.init()
        configuration.userContentController.add(MessageRelay(owner: self), name: "liquidx")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.websiteDataStore.httpCookieStore.add(self)
        webView.load(URLRequest(url: WebLogin.loginURL))
    }

    func handle(_ body: Any) {
        guard let message = body as? [String: Any], let kind = message["kind"] as? String else { return }
        switch kind {
        case "operation":
            if let name = message["name"] as? String, let queryID = message["queryId"] as? String {
                observed.queryIDs[name] = queryID
            }
        case "bearer":
            observed.bearer = message["value"] as? String
        case "main":
            observed.mainScriptURL = (message["url"] as? String).flatMap(URL.init(string:))
        default:
            break
        }
    }

    // MARK: Cookies

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in await self.checkSession() }
    }

    private func checkSession() async {
        guard finishTask == nil else { return }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let values = cookies
            .filter { $0.domain.hasSuffix(WebLogin.cookieDomain) }
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        let candidate = WebCredentials(cookies: values, userAgent: WebLogin.userAgent)
        guard candidate.isComplete else { return }

        isFinishing = true
        finishTask = Task {
            // Give x.com's home page a moment to load, so the observer can
            // report the current API bearer and query IDs.
            for _ in 0..<16 where observed.bearer == nil || observed.queryIDs.isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
            }
            let latest = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                .filter { $0.domain.hasSuffix(WebLogin.cookieDomain) }
                .reduce(into: [String: String]()) { $0[$1.name] = $1.value }
            credentials = WebCredentials(cookies: latest, userAgent: WebLogin.userAgent, observed: observed)
        }
    }

    // MARK: Pop-ups (Google / Apple sign-in) open in the same view.

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }
}

/// Breaks the retain cycle between WKUserContentController and the controller.
private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: WebLoginController?

    init(owner: WebLoginController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.handle(message.body)
    }
}

#if os(iOS)
private struct WebLoginWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#else
private struct WebLoginWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif

/// Explains the trade-offs before the unofficial sign-in starts.
struct WebSessionNotice: View {
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Unofficial connection", systemImage: "exclamationmark.shield.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("LiquidX will sign in to x.com like a browser and use the same private API the website uses. It's free and includes the For You feed, but:")
                    VStack(alignment: .leading, spacing: 12) {
                        Point(symbol: "hand.raised.fill", text: "It is not allowed by X's Terms of Service. X may rate limit, lock or suspend your account.")
                        Point(symbol: "wrench.and.screwdriver.fill", text: "x.com changes its private API often, so this can stop working until LiquidX is updated.")
                        Point(symbol: "lock.fill", text: "Your x.com session is kept only in this device's Keychain. LiquidX never sees your password; you type it into x.com's own page.")
                    }
                    Text("Use it at your own risk. The official API sign-in stays available and is the supported option.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("x.com Sign-In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("I Understand") {
                        dismiss()
                        onContinue()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 440)
        #endif
    }
}

private struct Point: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
