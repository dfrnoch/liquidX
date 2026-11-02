public import Foundation

public struct WebOperation: Codable, Hashable, Sendable {
    public var queryId: String
    public var features: [String]
    public var fieldToggles: [String]

    public init(queryId: String, features: [String], fieldToggles: [String]) {
        self.queryId = queryId
        self.features = features
        self.fieldToggles = fieldToggles
    }
}

/// Everything needed to call x.com's GraphQL API: the public web bearer and,
/// per operation, the query ID plus the feature switches the server expects.
public struct WebAPIConfig: Codable, Sendable {
    public var bearer: String
    public var operations: [String: WebOperation]
    public var fetchedAt: Date

    func operation(_ name: String) -> WebOperation? {
        operations[name] ?? WebDefaults.operations[name]
    }

    /// Reads the current values from x.com's main web bundle (a public file on
    /// abs.twimg.com), layered over the built-in defaults and anything the
    /// login page reported.
    static func discover(
        observed: WebObservations,
        credentials: WebCredentials,
        session: URLSession
    ) async throws -> WebAPIConfig {
        var operations = WebDefaults.operations
        var bearer = observed.bearer

        var mainURL = observed.mainScriptURL
        if mainURL == nil {
            mainURL = try? await findMainScript(credentials: credentials, session: session)
        }
        if let mainURL, let (data, response) = try? await session.data(from: mainURL),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let script = String(data: data, encoding: .utf8) {
            let parsed = parse(script)
            operations.merge(parsed.operations) { _, new in new }
            bearer = bearer ?? parsed.bearer
        }
        // The page's own requests are the most current source of query IDs.
        for (name, queryID) in observed.queryIDs {
            if var operation = operations[name] {
                operation.queryId = queryID
                operations[name] = operation
            } else {
                operations[name] = WebOperation(queryId: queryID, features: WebDefaults.timelineFeatures, fieldToggles: [])
            }
        }
        guard let bearer, !bearer.isEmpty else {
            throw XAPIError.server(status: 0, message: String(localized: "Couldn't read x.com's web client configuration."))
        }
        return WebAPIConfig(bearer: bearer, operations: operations, fetchedAt: .now)
    }

    private static func findMainScript(credentials: WebCredentials, session: URLSession) async throws -> URL? {
        var request = URLRequest(url: URL(string: "https://x.com/home")!)
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, _) = try await session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        guard let match = html.firstMatch(of: /https:\/\/abs\.twimg\.com\/responsive-web\/client-web\/main\.[A-Za-z0-9]+\.js/) else {
            return nil
        }
        return URL(string: String(match.output))
    }

    static func parse(_ script: String) -> (bearer: String?, operations: [String: WebOperation]) {
        let bearer = script.firstMatch(of: /AAAAAAAAAAAAAAAAAAAAA[A-Za-z0-9%]+/).map { String($0.output).removingPercentEncoding ?? String($0.output) }
        var operations: [String: WebOperation] = [:]
        let pattern = /queryId:"([^"]+)",operationName:"([^"]+)",operationType:"[^"]+",metadata:\{featureSwitches:\[([^\]]*)\],fieldToggles:\[([^\]]*)\]/
        for match in script.matches(of: pattern) {
            let strings = { (list: Substring) in list.matches(of: /"([^"]+)"/).map { String($0.output.1) } }
            operations[String(match.output.2)] = WebOperation(
                queryId: String(match.output.1),
                features: strings(match.output.3),
                fieldToggles: strings(match.output.4)
            )
        }
        return (bearer, operations)
    }
}

extension WebOperation {
    var featuresJSON: [String: Bool] {
        Dictionary(uniqueKeysWithValues: features.map { ($0, !WebDefaults.disabledFeatures.contains($0)) })
    }

    var fieldTogglesJSON: [String: Bool] {
        Dictionary(uniqueKeysWithValues: fieldToggles.map { ($0, WebDefaults.fieldToggleValues[$0] ?? false) })
    }
}
