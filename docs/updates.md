# In-app updates (Mac)

The Mac app checks LiquidX's GitHub releases and installs newer versions itself.
The design follows MatterMac's (its decision 0034). iPhone and iPad builds aren't
distributed through GitHub, so they have no updater.

## Constraints

- No third-party dependencies, so no Sparkle.
- The app is sandboxed, and a sandboxed process can't replace its own bundle in
  `/Applications`.
- Other processes can't read the app's sandbox container either.

## Design

- **Feed.** Every notarized release carries `update.json` and
  `LiquidX-<label>.zip`, the notarized and stapled app (`release.yml`,
  `build-dmg.yml`). Unnotarized releases get neither, so the app never offers
  them. `GitHubUpdateFeed` (`XKit/Updates`) lists `dfrnoch/liquidX` releases
  through GitHub's unauthenticated API. It skips drafts, and pre-releases on the
  Stable channel, then picks the highest `build` above the running
  `CFBundleVersion`. Manifests are size-bounded, and their file names and
  digests are validated.
- **Preparation, in the sandboxed app.**
  - The ZIP is downloaded into `Caches/LiquidXUpdates` through an ephemeral,
    cache-free `URLSession`, bounded by the manifest size and 400 MiB.
  - Its SHA-256 is checked, and `ditto` unpacks it.
  - `UpdateSupport.validate` checks the unpacked app: bundle ID
    `dev.frnoch.liquidx`, a newer build, the minimum macOS, and the requirement
    "Developer ID of team ZJ37A69485, notarized".
  - Only then does the "Restart to Update" banner appear.
- **Installation, in the XPC service `LiquidXUpdateInstaller`** (`UpdateInstaller/`).
  The service is embedded in `Contents/XPCServices`, isn't sandboxed and uses
  the hardened runtime. It:
  - accepts connections only from code that satisfies the LiquidX team
    requirement;
  - receives the ZIP as an open `FileHandle`, because it can't read the
    container;
  - copies the archive (bounded), checks the SHA-256 again, unpacks it, and
    repeats the validation;
  - checks that the installed copy is the team's LiquidX;
  - swaps the bundle with `FileManager.replaceItemAt`;
  - spawns a detached `/bin/sh` that waits for the app's process to exit, then
    runs `open -n` with the same arguments.

  The app then quits normally.
- **Fallback.** If the app runs from a translocated or disk-image copy, or the
  install fails, it shows the reason and offers the release's DMG in the browser.
- **Settings ▸ Updates.** Automatic checks are on by default. The channel
  defaults to Nightly for nightly builds and Stable otherwise. Both settings are
  saved in `UserDefaults` (`LiquidX.checksForUpdates`, `LiquidX.updateChannel`).
  **LiquidX ▸ Check for Updates…** checks now. Checks run 20 seconds after launch
  and then every six hours.
- Development builds (`-dev` label) and UI tests (`-LiquidXUITesting`) have no
  updater, unless `-LiquidXUpdateFeed` is passed.

The checks shared by the app and the installer are in the dependency-free
`LiquidUpdateSupport` target, which both link, so the two can't diverge.

## Testing locally

`swift test --package-path Packages/LiquidKit` covers release selection,
malformed manifests, checksum and signature checks, the bundle swap and the
updater's states. It uses ad hoc signed test bundles and a fake HTTP client.

End to end, with two Debug builds signed by the team's Apple Development
certificate:

```sh
for build in 100 101; do
  xcodebuild -project LiquidX.xcodeproj -scheme LiquidX -destination 'platform=macOS' \
    -derivedDataPath build-$build CURRENT_PROJECT_VERSION=$build \
    LIQUIDX_VERSION_LABEL=0.1.1-nightly.20261104.$build \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" DEVELOPMENT_TEAM=ZJ37A69485 build
done
```

1. Zip build 101 with `ditto -c -k --sequesterRsrc --keepParent`.
2. Write `update.json` for it, and a GitHub-shaped `releases.json` that points
   at both files.
3. Serve them on `http://localhost:<port>/`.
4. Launch a copy of build 100 with
   `-LiquidXUpdateFeed http://localhost:<port>/releases.json -LiquidXUpdateAutoInstall YES -LiquidXUITesting YES -LiquidXDemo YES`.
   Each step is written to stderr.

Debug builds accept updates signed by the team's Apple Development certificate.
Release builds require Developer ID and notarization.

## Verified (2026-11-04)

On this Mac, with builds 100 → 101 made as above, a local feed and the real
embedded service:

- download, checksum, unpacking and signature checks work inside the sandbox;
- the installer swapped in build 101, the old process exited, and build 101
  started with the same arguments;
- the swapped bundle passes `codesign --verify --deep --strict`.

Not verified yet: a Developer ID, notarized update end to end from GitHub. That
needs two published releases that both contain the updater. Releases before
this change (0.1.0 and earlier nightlies) don't update themselves; install the
first one that does from its DMG.
