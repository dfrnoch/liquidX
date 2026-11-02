public import Foundation

/// X API v2 client acting on behalf of one signed-in account.
///
/// Requests are user-context (OAuth 2.0 bearer). Tokens refresh transparently
/// (single flight) and are persisted after every refresh. Reads are kept small
/// on purpose: X bills API reads per post, so refreshes ask only for posts
/// newer than what is already on screen.
public actor XClient: XService {
    public nonisolated let isDemo = false

    private static let base = URL(string: "https://api.x.com/2/")!
    private static let pageSize = 40

    private let clientID: String
    private let store: any CredentialStore
    private let session: URLSession
    private var tokens: OAuthTokens
    private var refreshing: Task<OAuthTokens, any Error>?
    private var cachedMe: XUser?
    /// Downgraded to `.basic` for the rest of the session if the API rejects
    /// one of the newer fields or expansions with a 400.
    private var fields = FieldSet.rich

    public init(credentials: StoredCredentials, store: any CredentialStore) {
        clientID = credentials.clientID
        tokens = credentials.tokens
        self.store = store
        session = Self.makeSession()
    }

    /// Redeems the authorization code from a completed browser sign-in.
    public static func signIn(
        with request: AuthorizationRequest,
        callback: URL,
        store: any CredentialStore
    ) async throws -> XClient {
        let code = try request.code(from: callback)
        let tokens = try await TokenEndpoint.redeem(code: code, for: request, session: makeSession())
        let credentials = StoredCredentials(clientID: request.configuration.clientID, tokens: tokens)
        store.save(credentials)
        return XClient(credentials: credentials, store: store)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Reads

    public func me() async throws -> XUser {
        if let cachedMe { return cachedMe }
        let envelope: WireEnvelope<WireUser> = try await get("users/me", query: [fields.userFields])
        guard let user = envelope.data else { throw XAPIError.decoding("account") }
        let me = Assembler.user(user)
        cachedMe = me
        return me
    }

    public func homeTimeline(_ page: PageRequest, filter: HomeFilter) async throws -> TimelinePage {
        let id = try await me().id
        var exclude: [String] = []
        if filter.hideReplies { exclude.append("replies") }
        if filter.hideReposts { exclude.append("retweets") }
        var query = pageQuery(page)
        if !exclude.isEmpty { query.append(URLQueryItem(name: "exclude", value: exclude.joined(separator: ","))) }
        return try await timeline("users/\(id)/timelines/reverse_chronological", query: query, page: page)
    }

    public func posts(of userID: String, _ page: PageRequest, includeReplies: Bool) async throws -> TimelinePage {
        var query = pageQuery(page)
        if !includeReplies { query.append(URLQueryItem(name: "exclude", value: "replies")) }
        return try await timeline("users/\(userID)/tweets", query: query, page: page)
    }

    public func mentions(_ page: PageRequest) async throws -> TimelinePage {
        let id = try await me().id
        return try await timeline("users/\(id)/mentions", query: pageQuery(page), page: page)
    }

    public func bookmarks(_ page: PageRequest) async throws -> TimelinePage {
        let id = try await me().id
        // The bookmarks endpoint has no since_id; always read the first page.
        var query = pageQuery(page)
        query.removeAll { $0.name == "since_id" }
        return try await timeline("users/\(id)/bookmarks", query: query, page: page)
    }

    public func search(_ query: String, _ page: PageRequest) async throws -> TimelinePage {
        var items = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "sort_order", value: "recency")]
        // Search pages with `next_token`, not `pagination_token`.
        items += pageQuery(page).map { $0.name == "pagination_token" ? URLQueryItem(name: "next_token", value: $0.value) : $0 }
        return try await timeline("tweets/search/recent", query: items, page: page)
    }

    public func replies(to post: XPost) async throws -> [XTimelineItem] {
        let conversation = post.conversationID ?? post.id
        let page = try await timeline(
            "tweets/search/recent",
            query: [
                URLQueryItem(name: "query", value: "conversation_id:\(conversation)"),
                URLQueryItem(name: "max_results", value: "50"),
            ],
            page: .newest(since: nil)
        )
        return page.items.filter { $0.post.id != post.id }.sorted { $0.post.createdAt < $1.post.createdAt }
    }

    public func post(id: String) async throws -> XPost {
        let envelope: WireEnvelope<WireTweet> = try await get("tweets/\(id)", query: fields.postQuery)
        guard let tweet = envelope.data else { throw XAPIError.notFound }
        return Assembler(envelope.includes).post(tweet)
    }

    public func user(username: String) async throws -> XUser {
        let path = "users/by/username/\(username)"
        let envelope: WireEnvelope<WireUser>
        do {
            envelope = try await get(path, query: [fields.userFields(including: "connection_status")], downgradeOnBadRequest: false)
        } catch XAPIError.server(status: 400, _) {
            envelope = try await get(path, query: [fields.userFields])
        }
        guard let user = envelope.data else { throw XAPIError.notFound }
        return Assembler.user(user)
    }

    public func trends() async throws -> [XTrend] {
        let envelope: WireEnvelope<[WireTrend]> = try await get("users/personalized_trends", downgradeOnBadRequest: false)
        return (envelope.data ?? []).compactMap { trend in
            guard let name = trend.trend_name ?? trend.name else { return nil }
            return XTrend(name: name, category: trend.category, postCount: trend.post_count ?? trend.tweet_count)
        }
    }

    // MARK: - Writes

    public func setLiked(_ liked: Bool, postID: String) async throws {
        let id = try await me().id
        if liked {
            try await write("POST", "users/\(id)/likes", body: ["tweet_id": postID])
        } else {
            try await write("DELETE", "users/\(id)/likes/\(postID)")
        }
    }

    public func setReposted(_ reposted: Bool, postID: String) async throws {
        let id = try await me().id
        if reposted {
            try await write("POST", "users/\(id)/retweets", body: ["tweet_id": postID])
        } else {
            try await write("DELETE", "users/\(id)/retweets/\(postID)")
        }
    }

    public func setBookmarked(_ bookmarked: Bool, postID: String) async throws {
        let id = try await me().id
        if bookmarked {
            try await write("POST", "users/\(id)/bookmarks", body: ["tweet_id": postID])
        } else {
            try await write("DELETE", "users/\(id)/bookmarks/\(postID)")
        }
    }

    public func setFollowing(_ following: Bool, userID: String) async throws {
        let id = try await me().id
        if following {
            try await write("POST", "users/\(id)/following", body: ["target_user_id": userID])
        } else {
            try await write("DELETE", "users/\(id)/following/\(userID)")
        }
    }

    public func createPost(text: String, replyingTo: String?) async throws -> XPost {
        struct Body: Encodable, Sendable {
            struct Reply: Encodable, Sendable { var in_reply_to_tweet_id: String }
            var text: String
            var reply: Reply?
        }
        let author = try await me()
        let body = Body(text: text, reply: replyingTo.map(Body.Reply.init))
        let data = try await send("POST", "tweets", body: body)
        guard let created = try? JSONDecoder.xAPI.decode(WireEnvelope<WireID>.self, from: data).data else {
            throw XAPIError.decoding("new post")
        }
        return XPost(id: created.id, author: author, createdAt: .now, text: RichText.make(text))
    }

    public func signOut() async {
        await TokenEndpoint.revoke(tokens.accessToken, clientID: clientID, session: session)
        store.delete()
    }

    // MARK: - Plumbing

    private func pageQuery(_ page: PageRequest) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "max_results", value: String(Self.pageSize))]
        switch page {
        case .newest(let since?): query.append(URLQueryItem(name: "since_id", value: since))
        case .newest(nil): break
        case .older(let cursor): query.append(URLQueryItem(name: "pagination_token", value: cursor))
        }
        return query
    }

    private func timeline(_ path: String, query: [URLQueryItem], page: PageRequest) async throws -> TimelinePage {
        let envelope: WireEnvelope<[WireTweet]> = try await get(path, query: query + fields.postQuery, extendsFields: true)
        let items = Assembler(envelope.includes).items(envelope.data ?? [])
        let isSinceRequest = if case .newest(.some) = page { true } else { false }
        return TimelinePage(
            items: items,
            nextCursor: envelope.meta?.next_token,
            mayHaveGap: isSinceRequest && envelope.meta?.next_token != nil
        )
    }

    private func get<Payload: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        extendsFields: Bool = false,
        downgradeOnBadRequest: Bool = true
    ) async throws -> WireEnvelope<Payload> {
        do {
            let data = try await send("GET", path, query: query)
            return try decode(data)
        } catch XAPIError.server(status: 400, _) where downgradeOnBadRequest && fields == .rich {
            fields = .basic
            let rebuilt = query.map { item in fields.replacement(for: item) ?? item }
            return try decode(try await send("GET", path, query: rebuilt))
        }
    }

    private func decode<Payload: Decodable>(_ data: Data) throws -> WireEnvelope<Payload> {
        let envelope: WireEnvelope<Payload>
        do {
            envelope = try JSONDecoder.xAPI.decode(WireEnvelope<Payload>.self, from: data)
        } catch {
            throw XAPIError.decoding(String(describing: Payload.self))
        }
        if envelope.data == nil, let problem = envelope.errors?.first {
            if problem.type?.hasSuffix("resource-not-found") == true { throw XAPIError.notFound }
            throw XAPIError.server(status: 200, message: problem.summary)
        }
        return envelope
    }

    private func write(_ method: String, _ path: String, body: [String: String]? = nil) async throws {
        _ = try await send(method, path, body: body)
    }

    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
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

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where !isRetry:
            // The access token may have been revoked or expired early.
            _ = try await refreshedTokens(force: true)
            return try await send(method, path, query: query, body: body, isRetry: true)
        case 401:
            throw XAPIError.unauthorized
        case 429:
            let reset = http.value(forHTTPHeaderField: "x-rate-limit-reset").flatMap(TimeInterval.init)
            throw XAPIError.rateLimited(resetsAt: reset.map(Date.init(timeIntervalSince1970:)))
        case 402, 403:
            throw XAPIError.forbidden(problemMessage(data) ?? String(localized: "Your X developer app doesn't have access to this feature."))
        case 404:
            throw XAPIError.notFound
        default:
            throw XAPIError.server(status: http.statusCode, message: problemMessage(data))
        }
    }

    private func problemMessage(_ data: Data) -> String? {
        struct Body: Decodable {
            var title: String?
            var detail: String?
            var errors: [WireProblem]?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return body.detail ?? body.errors?.first?.summary ?? body.title
    }

    // MARK: - Tokens

    private func accessToken() async throws -> String {
        if tokens.isExpired() {
            return try await refreshedTokens(force: false).accessToken
        }
        return tokens.accessToken
    }

    private func refreshedTokens(force: Bool) async throws -> OAuthTokens {
        if let refreshing { return try await refreshing.value }
        guard force || tokens.isExpired() else { return tokens }
        guard let refreshToken = tokens.refreshToken else { throw XAPIError.unauthorized }
        let clientID = clientID
        let session = session
        let task = Task { try await TokenEndpoint.refresh(refreshToken, clientID: clientID, session: session) }
        refreshing = task
        defer { refreshing = nil }
        let fresh = try await task.value
        tokens = fresh
        store.save(StoredCredentials(clientID: clientID, tokens: fresh))
        return fresh
    }
}

/// Field and expansion sets requested with posts. `.rich` adds newer fields
/// (long-post text, banners, media of referenced posts); `.basic` is the
/// long-standing v2 set every app has access to.
private enum FieldSet: Equatable {
    case rich, basic

    private static let commonTweetFields = "created_at,author_id,public_metrics,attachments,entities,referenced_tweets,conversation_id,in_reply_to_user_id,lang"
    private static let commonUserFields = "name,username,profile_image_url,verified,verified_type,protected,description,public_metrics,created_at,location,url,entities"
    private static let mediaFields = "url,preview_image_url,type,width,height,alt_text,variants,duration_ms"
    private static let commonExpansions = "author_id,attachments.media_keys,referenced_tweets.id,referenced_tweets.id.author_id,in_reply_to_user_id"

    private var tweetFields: String { self == .rich ? Self.commonTweetFields + ",note_tweet" : Self.commonTweetFields }
    private var userFieldList: String { self == .rich ? Self.commonUserFields + ",profile_banner_url" : Self.commonUserFields }
    private var expansions: String {
        self == .rich ? Self.commonExpansions + ",referenced_tweets.id.attachments.media_keys" : Self.commonExpansions
    }

    var userFields: URLQueryItem { URLQueryItem(name: "user.fields", value: userFieldList) }

    func userFields(including extra: String) -> URLQueryItem {
        URLQueryItem(name: "user.fields", value: userFieldList + "," + extra)
    }

    var postQuery: [URLQueryItem] {
        [
            URLQueryItem(name: "expansions", value: expansions),
            URLQueryItem(name: "tweet.fields", value: tweetFields),
            URLQueryItem(name: "user.fields", value: userFieldList),
            URLQueryItem(name: "media.fields", value: Self.mediaFields),
        ]
    }

    func replacement(for item: URLQueryItem) -> URLQueryItem? {
        switch item.name {
        case "expansions": URLQueryItem(name: item.name, value: expansions)
        case "tweet.fields": URLQueryItem(name: item.name, value: tweetFields)
        case "user.fields": URLQueryItem(name: item.name, value: userFieldList)
        default: nil
        }
    }
}
