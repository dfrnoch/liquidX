# Architecture

```
App/ (composition root)      LiquidXApp → RootView + LiquidCommands + Settings
        │
LiquidUI (SwiftUI, @MainActor by default)
  AppModel ── phase: launching → signedOut → signedIn(Session)
  Session  ── service, me, feeds (home, mentions, bookmarks), routers per section,
              EngagementStore, composer / media viewer / toast state
  Shell    ── PhoneShell (TabView, sidebarAdaptable) | MacShell (rail + column + trends)
  Screens  ── Feed, Post, Profile, Search, Compose, Settings, Media
        │
XKit (Sendable, nonisolated)
  XService protocol ── XClient (actor, X API v2) | DemoService (actor, offline)
  Wire + Assembler   ── v2 JSON → XPost / XUser / XMedia (rich text pre-rendered)
  OAuth              ── PKCE authorize request, token redeem/refresh/revoke, Keychain
  ImagePipeline      ── URLCache bytes → ImageIO thumbnails → bounded LRU of CGImages
  Updates (Mac)      ── GitHub release feed, download and checks → AppUpdater (LiquidUI)
        │
LiquidUpdateSupport  ── signature/bundle checks + swap, shared with
                        UpdateInstaller/ (unsandboxed XPC service in the Mac app)
```

## Data flow

- A `FeedStore` wraps one paginated source through a `@Sendable` fetch closure.
  `refresh()` requests `since_id` = the newest item on screen. If X returns a full
  page (`next_token` present), there may be a gap, so the list is replaced
  instead of prepended. Older pages load when a row within 6 of the end appears.
- The home feed is cached as JSON in Caches (`FeedCache`, 80 items). It shows
  immediately on launch, and the first refresh asks only for newer posts.
- Likes, reposts and bookmarks change a per-post `@Observable PostEngagement`
  immediately, call the service in the background, and roll back on failure.
  The API v2 timeline doesn't say whether *you* liked a post, so that state
  starts as "not liked".
- Rich text (links, mentions, hashtags, cashtags) is built once, in `XKit`, as an
  `AttributedString`. In-app destinations are `liquidx://` URLs, routed by an
  `OpenURLAction` on each `NavigationStack` (`RoutedStack`).

## API compatibility

`XClient` first requests a "rich" set of fields (`note_tweet`,
`profile_banner_url`, media of referenced posts). If X answers 400, it switches
to the long-standing "basic" set for the rest of the session. Wire types accept
both the `tweet` and the newer `post` spellings of keys.

## Performance notes

- Rows observe only their own `PostEngagement`. Timeline text and counts are
  precomputed.
- `RemoteImage` reads the memory cache synchronously in `init`, so recycled rows
  never flash a placeholder. Decoding uses `CGImageSourceCreateThumbnailAtIndex`
  at the displayed pixel size, in a `@concurrent` function.
- Identical in-flight image requests are coalesced.
