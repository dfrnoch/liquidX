# AGENTS.md: working rules for LiquidX

LiquidX is a native SwiftUI X client for iOS, iPadOS and macOS (26+), using the
official X API v2 with user-supplied OAuth 2.0 Client IDs.

## Hard rules

- Swift only, no third-party dependencies, no web views. Swift 6 language mode;
  the app target treats warnings as errors. No `@unchecked Sendable`,
  `nonisolated(unsafe)` or `@preconcurrency`.
- Never commit secrets. Personal settings go in `Config/Local.xcconfig` (git-ignored).
- Demo data (`XKit/Demo`) is fictional. Never use real people or real posts.
- Don't claim API behaviour you haven't verified. X's API changes often; keep the
  `rich`/`basic` field fallback in `XClient` working.
- Use Conventional Commits.

## Layout

- `Packages/LiquidKit/Sources/XKit`: models, X API v2 client (`XClient`), wire
  types and `Assembler`, OAuth PKCE and Keychain, `DemoService`, `ImagePipeline`.
  Not main-actor isolated.
- `Packages/LiquidKit/Sources/LiquidUI`: SwiftUI interface, main-actor by default.
  `App/` holds state (`AppModel`, `Session`, `FeedStore`, navigation), `Shell/`
  the iPhone/iPad (`PhoneShell`) and Mac (`MacShell`) layouts.
- `App/`: app target (composition root only), synchronized folder.
- `UITests/`: XCUITest visual tour in demo mode.
- `Config/`: xcconfigs, Info.plist, entitlements.

## Commands (verified)

```sh
swift test --package-path Packages/LiquidKit
xcodebuild -project LiquidX.xcodeproj -scheme LiquidX -destination 'platform=macOS' -derivedDataPath build build
xcodebuild -project LiquidX.xcodeproj -scheme LiquidX -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build -resultBundlePath build/tour.xcresult test
xcrun xcresulttool export attachments --path build/tour.xcresult --output-path build/tour
```

`ScrollPerformanceUITests` measures home-timeline scrolling. The simulator only
reports duration; hitch time ratio needs a physical device.

Debug-only launch arguments: `-LiquidXAutoSignIn YES` starts the OAuth flow on
launch (needs a Client ID); `-LiquidXKeychainSelfTest YES` writes the Keychain
round-trip result to stderr.

Launch arguments: `-LiquidXDemo YES`, `-LiquidXAppearance dark|light|system`,
`-LiquidXSection home|notifications|bookmarks|profile|search`,
`-LiquidXOpenProfile <username>`, `-LiquidXUITesting YES` (in-memory credentials).
UI tests read `LIQUIDX_APPEARANCE` from the environment (pass it as
`TEST_RUNNER_LIQUIDX_APPEARANCE=dark` to `xcodebuild`).
