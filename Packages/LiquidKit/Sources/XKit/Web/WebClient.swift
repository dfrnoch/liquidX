import Foundation

/// Talks to x.com's own (unofficial) web API with a signed-in browser session.
///
/// This is what the x.com website does from your browser, so it needs no
/// developer account and no API credits. It is not sanctioned by X's terms,
/// can break when x.com changes, and may get the account rate limited or
/// locked. See docs/web-session.md.
public actor WebClient: XService {
    public nonisolated let isDemo = false
    public nonisolated var connection: ConnectionKind { .webSession }
    public nonisolated var homeFeeds: [HomeFeed] { [.forYou, .following] }

    private static let pageSize = 20
    private static let configCache = URL.cachesDirectory.appending(path: "LiquidXWeb/config.json")

    private var credentials: WebCredentials
    private let store: any WebCredentialStore
    private let session: URLSession
    private var config: WebAPIConfig?
    private var cachedMe: XUser?
    /// Read operations x.com only accepts as POST. It has been moving queries
    /// from GET to POST one by one, so a GET that 404s is retried as POST and
    /// remembered here (verified 2026-11-03: SearchTimeline, UserTweetsAndReplies).
    private var postOperations: Set<String> = ["HomeTimeline", "HomeLatestTimeline", "SearchTimeline", "UserTweetsAndReplies"]

    public init(credentials: WebCredentials, store: any WebCredentialStore) {
        self.credentials = credentials
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    // MARK: - Reads

    public func me() async throws -> XUser {
        if let cachedMe { return cachedMe }
        var me: XUser?
        if let data = try? await graphQL("Viewer", variables: ["withCommunitiesMemberships": true]),
           let result = data.object("data.viewer.user_results.result") {
            me = GraphQLParser.user(result)
        }
        if me == nil {
            // Fallback: the classic settings endpoint names the signed-in account.
            let settings = try await rest("GET", "1.1/account/settings.json")
            guard let screenName = settings.string("screen_name") else { throw XAPIError.unauthorized }
            me = try await user(username: screenName)
        }
        guard let me else { throw XAPIError.decoding("account") }
        cachedMe = me
        return me
    }

    public func homeTimeline(_ page: PageRequest, filter: HomeFilter) async throws -> TimelinePage {
        var variables: JSONObject = [
            "count": Self.pageSize,
            "includePromotedContent": false,
            "latestControlAvailable": true,
            "requestContext": "launch",
            "withCommunity": true,
        ]
        if case .older(let cursor) = page { variables["cursor"] = cursor }
        let operation = filter.feed == .forYou ? "HomeTimeline" : "HomeLatestTimeline"
        var result = try await timeline(operation, variables: variables, method: "POST", page: page)
        result.items.removeAll { item in
            (filter.hideReposts && item.repostedBy != nil) || (filter.hideReplies && !item.post.replyingTo.isEmpty)
        }
        return result
    }

    public func posts(of userID: String, _ page: PageRequest, includeReplies: Bool) async throws -> TimelinePage {
        var variables: JSONObject = [
            "userId": userID,
            "count": Self.pageSize,
            "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true,
            "withVoice": true,
        ]
        if case .older(let cursor) = page { variables["cursor"] = cursor }
        return try await timeline(includeReplies ? "UserTweetsAndReplies" : "UserTweets", variables: variables, page: page)
    }

    /// x.com's notifications API is not GraphQL; mentions come from search.
    public func mentions(_ page: PageRequest) async throws -> TimelinePage {
        let me = try await me()
        return try await search("@\(me.username)", page)
    }

    public func bookmarks(_ page: PageRequest) async throws -> TimelinePage {
        var variables: JSONObject = ["count": Self.pageSize, "includePromotedContent": false]
        if case .older(let cursor) = page { variables["cursor"] = cursor }
        return try await timeline("Bookmarks", variables: variables, page: page)
    }

    public nonisolated var searchKinds: [SearchKind] { [.top, .latest, .people, .media] }

    public func search(_ query: String, kind: SearchKind, _ page: PageRequest) async throws -> TimelinePage {
        try await timeline("SearchTimeline", variables: searchVariables(query, kind: kind, page: page), page: page)
    }

    public func searchUsers(_ query: String, _ page: PageRequest) async throws -> UserPage {
        let data = try await graphQL("SearchTimeline", variables: searchVariables(query, kind: .people, page: page))
        let (users, cursor) = GraphQLParser.users(data)
        return UserPage(users: users, nextCursor: users.isEmpty ? nil : cursor)
    }

    public func searchSuggestions(_ query: String) async throws -> SearchSuggestions {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchSuggestions() }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "src", value: "search_box"),
            URLQueryItem(name: "result_type", value: "events,users,topics"),
        ]
        let data = try await rest("GET", "1.1/search/typeahead.json?\(components.percentEncodedQuery ?? "")")
        return GraphQLParser.suggestions(data)
    }

    private func searchVariables(_ query: String, kind: SearchKind, page: PageRequest) -> JSONObject {
        var variables: JSONObject = [
            "rawQuery": query,
            "count": Self.pageSize,
            "querySource": "typed_query",
            "product": kind.rawValue,
        ]
        if case .older(let cursor) = page { variables["cursor"] = cursor }
        return variables
    }

    public func replies(to post: XPost) async throws -> [XTimelineItem] {
        let data = try await graphQL("TweetDetail", variables: [
            "focalTweetId": post.id,
            "with_rux_injections": false,
            "rankingMode": "Relevance",
            "includePromotedContent": false,
            "withCommunity": true,
            "withQuickPromoteEligibilityTweetFields": true,
            "withBirdwatchNotes": true,
            "withVoice": true,
        ])
        let items = GraphQLParser.timeline(data).items
        // Ancestors come before the focal post; replies after it.
        guard let focal = items.firstIndex(where: { $0.post.id == post.id }) else {
            return items.filter { $0.post.id != post.id }
        }
        return Array(items[(focal + 1)...])
    }

    public func post(id: String) async throws -> XPost {
        let data = try await graphQL("TweetResultByRestId", variables: [
            "tweetId": id,
            "withCommunity": false,
            "includePromotedContent": false,
            "withVoice": false,
        ])
        guard let result = data.object("data.tweetResult.result"), let item = GraphQLParser.item(fromTweet: result) else {
            throw XAPIError.notFound
        }
        return item.post
    }

    public func user(username: String) async throws -> XUser {
        let data = try await graphQL("UserByScreenName", variables: ["screen_name": username, "withGrokTranslatedBio": false])
        guard let result = data.object("data.user.result"), let user = GraphQLParser.user(result) else {
            throw XAPIError.notFound
        }
        return user
    }

    public func trends() async throws -> [XTrend] { [] }

    // MARK: - Writes

    public func setLiked(_ liked: Bool, postID: String) async throws {
        _ = try await graphQL(liked ? "FavoriteTweet" : "UnfavoriteTweet", variables: ["tweet_id": postID], method: "POST")
    }

    public func setReposted(_ reposted: Bool, postID: String) async throws {
        if reposted {
            _ = try await graphQL("CreateRetweet", variables: ["tweet_id": postID, "dark_request": false], method: "POST")
        } else {
            _ = try await graphQL("DeleteRetweet", variables: ["source_tweet_id": postID, "dark_request": false], method: "POST")
        }
    }

    public func setBookmarked(_ bookmarked: Bool, postID: String) async throws {
        _ = try await graphQL(bookmarked ? "CreateBookmark" : "DeleteBookmark", variables: ["tweet_id": postID], method: "POST")
    }

    public func setFollowing(_ following: Bool, userID: String) async throws {
        _ = try await rest("POST", following ? "1.1/friendships/create.json" : "1.1/friendships/destroy.json", form: ["user_id": userID])
    }

    public func createPost(text: String, replyingTo: String?) async throws -> XPost {
        var variables: JSONObject = [
            "tweet_text": text,
            "dark_request": false,
            "media": ["media_entities": [Any](), "possibly_sensitive": false],
            "semantic_annotation_ids": [Any](),
        ]
        if let replyingTo {
            variables["reply"] = ["in_reply_to_tweet_id": replyingTo, "exclude_reply_user_ids": [Any]()]
        }
        let data = try await graphQL("CreateTweet", variables: variables, method: "POST")
        if let result = data.object("data.create_tweet.tweet_results.result"),
           let post = GraphQLParser.post(from: result, allowQuote: true) {
            return post
        }
        throw XAPIError.decoding("new post")
    }

    /// Forgets the session in LiquidX. The x.com login itself stays valid until
    /// it expires or is logged out at x.com/settings/sessions.
    public func signOut() async {
        store.delete()
    }

    // MARK: - Plumbing

    private func timeline(_ operation: String, variables: JSONObject, method: String = "GET", page: PageRequest) async throws -> TimelinePage {
        let data = try await graphQL(operation, variables: variables, method: method)
        let (items, cursor) = GraphQLParser.timeline(data)
        // There is no since_id here: a refresh reads the first page and keeps
        // what is newer than the newest post already on screen.
        if case .newest(let since?) = page {
            if let index = items.firstIndex(where: { $0.id == since }) {
                return TimelinePage(items: Array(items[..<index]), nextCursor: nil)
            }
            return TimelinePage(items: items, nextCursor: cursor, mayHaveGap: true)
        }
        return TimelinePage(items: items, nextCursor: items.isEmpty ? nil : cursor)
    }

    private func loadConfig(refresh: Bool) async throws -> WebAPIConfig {
        if !refresh, let config { return config }
        if !refresh, let data = try? Data(contentsOf: Self.configCache),
           let cached = try? JSONDecoder().decode(WebAPIConfig.self, from: data),
           Date.now.timeIntervalSince(cached.fetchedAt) < 24 * 3_600 {
            config = cached
            return cached
        }
        let fresh = try await WebAPIConfig.discover(observed: credentials.observed, credentials: credentials, session: session)
        config = fresh
        try? FileManager.default.createDirectory(at: Self.configCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(fresh).write(to: Self.configCache, options: .atomic)
        return fresh
    }

    private func graphQL(_ name: String, variables: JSONObject, method requested: String = "GET", isRetry: Bool = false) async throws -> JSONObject {
        let method = postOperations.contains(name) ? "POST" : requested
        let config = try await loadConfig(refresh: isRetry)
        guard let operation = config.operation(name) else { throw XAPIError.server(status: 0, message: "Unknown x.com operation \(name).") }

        func json(_ value: Any) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
        }
        var components = URLComponents(string: "https://x.com/i/api/graphql/\(operation.queryId)/\(name)")!
        var request: URLRequest
        if method == "GET" {
            var items = [URLQueryItem(name: "variables", value: json(variables))]
            if !operation.features.isEmpty { items.append(URLQueryItem(name: "features", value: json(operation.featuresJSON))) }
            if !operation.fieldToggles.isEmpty { items.append(URLQueryItem(name: "fieldToggles", value: json(operation.fieldTogglesJSON))) }
            components.queryItems = items
            request = URLRequest(url: components.url!)
        } else {
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            var body: JSONObject = ["variables": variables, "queryId": operation.queryId]
            if !operation.features.isEmpty { body["features"] = operation.featuresJSON }
            if !operation.fieldToggles.isEmpty { body["fieldToggles"] = operation.fieldTogglesJSON }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            return try await send(request, bearer: config.bearer)
        } catch XAPIError.notFound where method == "GET" {
            // The operation may have moved to POST.
            postOperations.insert(name)
            return try await graphQL(name, variables: variables, method: "POST", isRetry: isRetry)
        } catch XAPIError.notFound where !isRetry {
            // Query IDs rotate with x.com deployments: rediscover and retry once.
            return try await graphQL(name, variables: variables, method: method, isRetry: true)
        }
    }

    private func rest(_ method: String, _ path: String, form: [String: String] = [:]) async throws -> JSONObject {
        let config = try await loadConfig(refresh: false)
        var request = URLRequest(url: URL(string: "https://x.com/i/api/\(path)")!)
        request.httpMethod = method
        if !form.isEmpty {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return try await send(request, bearer: config.bearer)
    }

    private func send(_ request: URLRequest, bearer: String) async throws -> JSONObject {
        var request = request
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("en", forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://x.com/home", forHTTPHeaderField: "Referer")
        request.setValue("https://x.com", forHTTPHeaderField: "Origin")
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw XAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw XAPIError.transport("No HTTP response") }
        absorbCookies(from: http)

        let body = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
        let errors = body?.objects("errors") ?? []
        let codes = Set(errors.compactMap { $0.int("code") })
        let message = errors.first?.string("message")

        let status = http.statusCode
        #if DEBUG
        if !(200..<300).contains(status) || !errors.isEmpty {
            // Operation name and status only; never request or response content.
            let operation = request.url?.lastPathComponent ?? "?"
            FileHandle.standardError.write(Data("LiquidX web: \(request.httpMethod ?? "GET") \(operation) -> \(status) codes=\(codes.sorted())\n".utf8))
        }
        #endif
        if (200..<300).contains(status), body?["data"] != nil || errors.isEmpty {
            return body ?? [:]
        }
        if status == 401 || !codes.isDisjoint(with: [32, 89, 215]) {
            throw XAPIError.unauthorized
        }
        if status == 429 || codes.contains(88) {
            let reset = http.value(forHTTPHeaderField: "x-rate-limit-reset").flatMap(TimeInterval.init)
            throw XAPIError.rateLimited(resetsAt: reset.map(Date.init(timeIntervalSince1970:)))
        }
        if codes.contains(326) {
            throw XAPIError.forbidden(String(localized: "X has temporarily locked your account. Open x.com in a browser to unlock it."))
        }
        if status == 403, body == nil {
            throw XAPIError.forbidden(String(localized: "x.com blocked the request. Try again later, or sign in again."))
        }
        if status == 404 {
            throw XAPIError.notFound
        }
        throw XAPIError.server(status: status, message: message)
    }

    /// x.com rotates cookies (notably `ct0`) via Set-Cookie; keep the session current.
    private func absorbCookies(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        var changed = false
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where !cookie.value.isEmpty {
            if credentials.cookies[cookie.name] != cookie.value {
                credentials.cookies[cookie.name] = cookie.value
                changed = true
            }
        }
        if changed { store.save(credentials) }
    }
}
