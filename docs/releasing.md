# Releasing

The Mac app is distributed as a DMG attached to a GitHub release.
`.github/workflows/release.yml` publishes both channels and builds with the
reusable `.github/workflows/build-dmg.yml`. iPhone and iPad builds aren't
distributed this way, because iOS can't install apps from a download.

## Versions

| Item | Source | Example |
| --- | --- | --- |
| Next production version | `MARKETING_VERSION` in `Config/Shared.xcconfig` | `0.1.0` |
| Build number (`CFBundleVersion`) | the Release workflow's run number | `12` |
| Nightly label | `<version>-nightly.<UTC yyyymmdd>.<build>` | `0.1.0-nightly.20261104.12` |
| Production label and tag | `<version>`, tag `v<version>` | `0.1.0`, `v0.1.0` |

`CFBundleShortVersionString` stays numeric (`0.1.0`), as macOS expects. The full
label is in the Info.plist key `LXVersionLabel`, which Settings ▸ About shows
("0.1.0-nightly.20261104.12 (12)"). Local builds show `<version>-dev` with build
number 1. `Tools/ReleaseVersion.swift` reads, computes and bumps versions; CI
runs it with `swift`.

```sh
swift Tools/ReleaseVersion.swift current             # 0.1.0
swift Tools/ReleaseVersion.swift nightly 12 20261104 # 0.1.0-nightly.20261104.12
swift Tools/ReleaseVersion.swift next minor          # 0.2.0
swift Tools/ReleaseVersion.swift set 0.2.0           # rewrites Config/Shared.xcconfig
```

## Nightly

- **Schedule:** 02:17 UTC every day. A scheduled run is skipped when `main` still
  points at the newest nightly tag's commit. **Run workflow** with channel
  `nightly` always builds.
- **Release:** a GitHub pre-release, never marked latest, titled
  `LiquidX <label>`. It carries `LiquidX-<label>.dmg` and its `.sha256`, with
  release notes listing the commits since the previous nightly.
- **Pruning:** only the newest 14 nightly releases are kept; older ones are
  deleted together with their tags.

## Production

1. Make sure `main` is green and `MARKETING_VERSION` is the version to ship.
2. **Actions ▸ Release ▸ Run workflow** with:
   - channel `production`;
   - optionally `version`, to ship a different `MAJOR.MINOR.PATCH`;
   - `next` (patch, minor or major) for the development version afterwards.
3. The workflow fails before building if the tag already exists. It then:
   - builds the DMG (and notarizes it when the secrets below are set);
   - creates the release `v<version>` at the built commit, marked latest, with the
     commits since the previous production release as notes;
   - commits `chore(release): start <next> after <version>` to `main` through
     GitHub's contents API, so the commit is signed by GitHub and shows as
     Verified.

From the command line:

```sh
gh workflow run release.yml -f channel=production -f next=patch
gh workflow run release.yml -f channel=nightly
```

The version commit needs `contents: write` for `GITHUB_TOKEN`. If branch
protection requires pull requests, allow GitHub Actions to push, or change
`MARKETING_VERSION` by pull request after the release; the release itself is
already published. Commits made with `GITHUB_TOKEN` don't trigger CI.

## Signing and notarization

The bundle ID is `dev.frnoch.liquidx`. Without secrets, releases are signed ad
hoc and not notarized: macOS blocks them on first open until the user chooses
**System Settings ▸ Privacy & Security ▸ Open Anyway**, and the release notes say
so.

With these four repository secrets, `build-dmg.yml` signs the app with David
Frnoch's Developer ID (team `ZJ37A69485`), notarizes and staples the app and the
DMG, and checks that Gatekeeper accepts both:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: the exported Developer ID Application
  identity, as base64-encoded PKCS#12.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: the PKCS#12 export password.
- `APPLE_ID`: the developer Apple Account email.
- `APPLE_APP_SPECIFIC_PASSWORD`: a dedicated app-specific password for
  notarization.

Set all four or none; a partial set fails the build.

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_BASE64
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
```

The workflow keeps the identity and notarization credentials in a temporary
runner Keychain and deletes it afterwards. Never store the account's normal
password in GitHub. See
[GitHub's certificate setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
