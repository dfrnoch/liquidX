# Contributing to LiquidX

Thanks for helping! LiquidX aims to feel like an app Apple could have shipped:
native controls, Liquid Glass where it belongs, and no lag while scrolling.

## Getting started

1. Read [docs/architecture.md](docs/architecture.md).
2. Build and run with `-LiquidXDemo YES` enabled in the scheme. You don't need an
   X account for most UI work.
3. Run the tests before opening a pull request:

   ```sh
   swift test --package-path Packages/LiquidKit
   xcodebuild -project LiquidX.xcodeproj -scheme LiquidX -destination 'platform=macOS' build
   xcodebuild -project LiquidX.xcodeproj -scheme LiquidX -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
   ```

## Guidelines

- **Swift 6, zero warnings.** Warnings are errors in the app target. Keep
  strict concurrency clean without `@unchecked Sendable` or
  `nonisolated(unsafe)`.
- **No third-party dependencies** and no web views.
- **Prefer system components.** Use `TabView`, `NavigationStack`, toolbars,
  `.glassEffect`, `.buttonStyle(.glass)` and `GlassEffectContainer`; avoid custom
  blur imitations. Put glass on controls and navigation, not on content.
- **Keep rows cheap.** Do parsing and formatting in `XKit` when models are
  built, not in `body`. Observe the smallest object possible (see
  `PostEngagement`).
- **Respect the API budget.** X bills reads per post. Don't add polling or
  speculative prefetching without a setting.
- **Accessibility:** every icon-only button needs a label. Check Dynamic Type and
  VoiceOver.
- **Demo data is fictional.** Never use real people's names, photos or posts.
- **Never commit secrets.** Client IDs and signing teams go in the git-ignored
  `Config/Local.xcconfig`.

## Commits and pull requests

Use [Conventional Commits](https://www.conventionalcommits.org):
`feat(profile): add media grid`, `fix(feed): keep scroll position on refresh`,
`docs: clarify OAuth setup`. Keep pull requests focused, and include screenshots
(light and dark) for visual changes. The UI test tour produces them for you.
