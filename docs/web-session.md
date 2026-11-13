# x.com session sign-in (unofficial)

LiquidX has two ways to connect:

| | Official X API (default) | x.com session (optional, unofficial) |
| --- | --- | --- |
| Needs | Your X developer app and paid API credits | Your normal x.com login |
| Cost | Pay per use (about $0.005 per post read) | Free |
| Feeds | Following | For you and Following |
| Allowed by X | Yes | **No**: against X's Terms of Service |
| Stability | Versioned, documented | Breaks when x.com changes |

## Risks

- Using x.com's private API from another app is not permitted by X's Terms of
  Service. X can rate limit, lock or suspend the account.
- x.com changes its private API without notice. LiquidX rediscovers query IDs
  and feature flags automatically, but larger changes need an app update.
- Use it at your own risk. LiquidX labels it as unofficial everywhere.

## How it works

1. **Sign-in.** An embedded web view (`WKWebView`, with a private, non-persistent
   data store) loads `https://x.com/i/flow/login`. You type your password into
   x.com's own page; LiquidX never sees it. Once x.com sets the `auth_token` and
   `ct0` cookies, LiquidX copies the x.com cookies to the Keychain and discards
   the web view.
2. **Discovery.** A small script on the login page reports the API bearer and
   GraphQL query IDs the site uses (request metadata only). LiquidX also reads
   x.com's public `main.js` bundle for each operation's required feature switches.
   The result is cached for 24 hours, and an unknown-query error (404) triggers
   rediscovery and one retry. `Sources/XKit/Web/WebDefaults.swift` holds fallbacks.
3. **Requests.** `WebClient` calls `https://x.com/i/api/graphql/<queryId>/<Operation>`
   with the session cookies, the `x-csrf-token` header (= `ct0`) and the web
   bearer, like the browser does. Cookies that x.com rotates via `Set-Cookie`
   are saved back to the Keychain.
4. **Parsing.** `GraphQLParser` maps x.com's timeline instructions to LiquidX's
   models, skipping promoted entries and tombstones, and reading both the
   current and the older user field layouts.

Operations used: `HomeTimeline`, `HomeLatestTimeline`, `UserByScreenName`,
`UserTweets`, `UserTweetsAndReplies`, `TweetDetail`, `TweetResultByRestId`,
`SearchTimeline` (also for mentions), `Bookmarks`, `Viewer`, `GenericTimelineById`
(the Explore "trending" timeline, for trends) with `ExploreSidebar` as a fallback, `FavoriteTweet`,
`UnfavoriteTweet`, `CreateRetweet`, `DeleteRetweet`, `BookmarkAdd` and
`BookmarkDelete` (x.com's new web client; `CreateBookmark` and `DeleteBookmark`
when x.com doesn't know them), `CreateTweet`, plus REST `friendships/create|destroy`
and `2/grok/translation.json` (below).

"Translate post" uses the Grok translation x.com's own "Show translation" uses.
x.com's new web client (x-web) sends `POST https://api.x.com/2/grok/translation.json`
with `{"content_type":"POST","id":"<post id>","dst_lang":"<language>"}` and reads
the answer as newline-delimited JSON: each line is
`{"result":{"content_type":"POST","text":"…","entities":{…}}}` with the next piece
of the text, or `{"error":{"code":…,"message":"…"}}` (read from its bundle on
2026-11-13). `WebClient` sends the same request with the session headers,
retries on `x.com/i/api/2/grok/translation.json` if api.x.com answers 404, and
shows the text as it streams in. `dst_lang` is the reader's language code
("en", "cs"). This hasn't been tried with a live session yet. If it fails before
any text arrives, the post is translated on the device instead.

"For you" is ranked, so refreshing it can't stop at the newest post on screen.
`HomeTimeline` gets the posts it has already served this launch as
`seenTweetIds`, the variable that open-source x.com clients send. A refresh adds only the
posts that aren't on screen yet. Whether x.com ranks differently because of
`seenTweetIds` hasn't been verified. If x.com rejects the variable, `WebClient`
stops sending it.

## Signing out

Sign Out deletes the session from the Keychain. The x.com login itself remains
valid until it expires; end it at x.com → Settings → Security → Sessions.

## Verified (2026-11-03)

- `SearchTimeline` and `UserTweetsAndReplies` now only accept POST (GET returns 404);
  `WebClient` retries any 404ing GET as POST and remembers it.
- From a browser context, `HomeTimeline` answers 200 without the
  `x-client-transaction-id` header that x.com's own client sends.
- Field names and response shapes match the parser fixtures in
  `Tests/XKitTests/Fixtures/web_home_timeline.json`.
- (2026-11-04) Requests from the native Mac client succeed. `GenericTimelineById`
  with the trending timeline ID returns 30 `TimelineTrend` items with `name` and
  `trend_metadata.domain_context`, but no post counts. `ExploreSidebar` returns
  the sidebar's few trends, also without counts. REST `2/guide.json` returns none.
