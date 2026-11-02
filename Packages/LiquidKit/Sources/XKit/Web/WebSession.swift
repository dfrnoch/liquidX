public import Foundation

/// A signed-in x.com browser session: the cookies x.com set during login and
/// the user agent of the browser that received them.
///
/// This is the *unofficial* connection method (see docs/web-session.md). It
/// needs `auth_token` (the session) and `ct0` (the CSRF token echoed in the
/// `x-csrf-token` header); other cookies are kept and sent back as a browser
/// would.
public struct WebCredentials: Codable, Hashable, Sendable {
    public var cookies: [String: String]
    public var userAgent: String
    /// API bearer, query IDs and features observed on the login page.
    public var observed: WebObservations

    public init(cookies: [String: String], userAgent: String, observed: WebObservations = WebObservations()) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.observed = observed
    }

    public var isComplete: Bool {
        cookies["auth_token"]?.isEmpty == false && cookies["ct0"]?.isEmpty == false
    }

    var csrfToken: String { cookies["ct0"] ?? "" }

    /// The signed-in account's numeric ID, from the `twid` cookie ("u=123").
    var userID: String? {
        guard let twid = cookies["twid"]?.removingPercentEncoding else { return nil }
        return twid.hasPrefix("u=") ? String(twid.dropFirst(2)) : nil
    }

    var cookieHeader: String {
        cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}

/// What the x.com page itself used while the user signed in.
public struct WebObservations: Codable, Hashable, Sendable {
    public var bearer: String?
    public var mainScriptURL: URL?
    /// Operation name → query ID, e.g. "HomeTimeline" → "fedFLLzmiCAuzPgA8lyh8Q".
    public var queryIDs: [String: String]

    public init(bearer: String? = nil, mainScriptURL: URL? = nil, queryIDs: [String: String] = [:]) {
        self.bearer = bearer
        self.mainScriptURL = mainScriptURL
        self.queryIDs = queryIDs
    }
}

public typealias WebCredentialStore = SecretStore<WebCredentials>

extension KeychainStore where Value == WebCredentials {
    public init(service: String = "dev.frnoch.liquidx") {
        self.init(service: service, account: "x-web-session")
    }
}

public enum WebLogin {
    public static let loginURL = URL(string: "https://x.com/i/flow/login")!
    public static let cookieDomain = "x.com"

    /// A current Safari user agent, so x.com serves its normal web client.
    public static var userAgent: String {
        #if os(iOS)
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        #else
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        #endif
    }

    /// Injected into the login page before any of x.com's scripts run. Reports
    /// the API bearer and GraphQL query IDs the site uses, so LiquidX stays
    /// current when x.com rotates them. It reads request metadata only.
    public static let observerScript = #"""
    (() => {
      const post = (message) => { try { window.webkit.messageHandlers.liquidx.postMessage(message); } catch (e) {} };
      const open = XMLHttpRequest.prototype.open;
      const setHeader = XMLHttpRequest.prototype.setRequestHeader;
      XMLHttpRequest.prototype.open = function (method, url) {
        try {
          const path = new URL(String(url), location.origin).pathname;
          const match = path.match(/\/graphql\/([^/]+)\/([^/]+)$/);
          if (match) post({ kind: 'operation', queryId: match[1], name: match[2] });
        } catch (e) {}
        return open.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        try {
          if (String(name).toLowerCase() === 'authorization' && String(value).startsWith('Bearer ')) {
            post({ kind: 'bearer', value: String(value).slice(7) });
          }
        } catch (e) {}
        return setHeader.apply(this, arguments);
      };
      const report = () => {
        const main = [...document.scripts].map(s => s.src).find(s => /\/client-web\/main\.[^/]+\.js$/.test(s));
        if (main) post({ kind: 'main', url: main });
      };
      document.addEventListener('DOMContentLoaded', report);
      setInterval(report, 2000);
    })();
    """#
}
