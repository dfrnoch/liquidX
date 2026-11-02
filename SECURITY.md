# Security policy

LiquidX is under active development. There is no stable release line yet, and
fixes target the latest commit on `main`.

## Reporting a vulnerability

Use GitHub's [private vulnerability reporting](https://github.com/dfrnoch/liquidX/security/advisories/new).
Don't open a public issue for security problems.

Include the affected commit, the OS version, reproduction steps and the impact.
Never send OAuth tokens, Keychain exports or access to a live account.

## Security model

- LiquidX is a public OAuth 2.0 client using PKCE (S256) and a random `state`.
  It ships no client secret. Each user supplies the Client ID of their own X
  developer app.
- Tokens are stored only in the Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and sent only to
  `api.x.com` as a bearer header, never in URLs.
- API requests use an ephemeral `URLSession` with no cookies, credential
  storage or URL cache.
- On macOS the app runs in the App Sandbox with outgoing network access only.
- Sign Out revokes the access token with X and deletes the tokens and cached
  content. If revocation fails (for example offline), the token stays valid at
  X until it expires.
