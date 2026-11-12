# Security work order — pCloud OAuth redirect binding and token storage

**Baseline:** `main` `ba708fe`
**Related immediate fix:** PR #30 merged on main and validates allowed regional API hosts before storing/sending bearer tokens.
**Type:** design and acceptance only; no authentication flow change in this PR.

## O1 — OAuth callback lacks initiation binding (P1)

**Evidence:** `PCloudProvider.buildAuthorizeUrl()` builds an OAuth `response_type=token` request without a `state` nonce. `PCloudProvider.parseAuthRedirect()` accepts an access token if the custom URI scheme and host match. `MainActivity` has an exported launcher activity handling that custom scheme and stores a pending redirect. `SettingsScreen._connectPcloud()` polls for the redirect and saves the token. It does not validate that a callback corresponds to the current sign-in attempt.

**Risk:** another app or an unrelated deep link can provide a syntactically valid callback. API-host allowlisting (PR #30) prevents off-domain token requests, but does not authenticate callback origin or bind it to a user-initiated sign-in.

**Required:**
1. Verify pCloud's currently supported OAuth mobile authorization modes and PKCE support from official provider documentation before changing the protocol.
2. At minimum generate a cryptographically random per-attempt `state`, send it with the authorization request, and verify exact state equality before processing any token; enforce expiry and single use.
3. Associate the response with the initiating account/region and clear pending state on cancellation, timeout or process restart where appropriate.
4. Prefer a system-browser authorization-code-with-PKCE flow if officially supported. If not, document limitations of implicit/custom-scheme flow and consider a verified HTTPS app link.
5. Reject callbacks received without an active sign-in attempt; treat manual token paste as a separately labeled, explicit operator action.
6. Test forged callback, reused state, wrong region, two concurrent sign-ins, timeout, cancellation and resumed process.

## O2 — Access token stored in ordinary preferences (P1 privacy)

**Evidence:** `CloudSettings.setToken()` writes `pcloud_token` using `SharedPreferences.setString`; `CloudSettings.load()` reads it the same way. A bearer token grants access to the configured cloud account. No encryption wrapper is used at that storage boundary.

**Required:**
1. Determine whether Android auto-backup currently includes SharedPreferences; scope credential backup exclusions or use an appropriate device-bound Keystore encryption strategy.
2. Keep the pCloud token out of share/export, logs, crash reports and screenshots. Validate actual export exclusions.
3. Migrate existing tokens without logging or persisting intermediate plaintext copies. Fail closed if key material is unavailable after device restore.
4. Provide revocation/logout and restore behavior with explicit test evidence, including app reinstall or device migration.

## O3 — Redirect location and API host consistency (P2)

PR #30 allowlists `api.pcloud.com` and `eapi.pcloud.com`. Add a consistency check between returned region/location and approved host, with a documented policy for an intentional region switch. Do not accept an unrecognized dynamic hostname as a convenience fallback.

## Evidence gates
- Widget/unit tests for initiation `state` handling and rejection paths.
- Native intent tests for exported deep-link callback injection.
- Physical US/EU pCloud auth smoke test with an authorized test account only.
- Document precise provider assumptions; no production token in test logs.

**Do not merge this specification as an implemented security fix.** Split the protocol and credential-storage changes into separately reviewed runtime PRs.

## Provider-contract decision (2026-11-12)

Official pCloud documentation validates the existing client-only token/implicit flow and its `state` parameter, which is returned in the URI fragment:
https://docs.pcloud.com/methods/oauth_2.0/authorize.html

The documented OAuth API authentication mechanisms are `access_token` (global parameter) and `Authorization: Bearer`, **not** the legacy `auth` token mechanism:
https://docs.pcloud.com/methods/oauth_2.0/
https://docs.pcloud.com/methods/intro/global_parameters.html

pCloud's code-flow token exchange requires a client secret and the provider page does not document PKCE:
https://docs.pcloud.com/methods/oauth_2.0/oauth2_token.html

Therefore do **not** embed a client secret or unverified PKCE logic in this standalone Android APK. Keep the supported mobile token flow pending a verified provider alternative. Track executable drafts separately:
- [PR #39](https://github.com/GhostMan612/sovereign_tagger/pull/39): random per-attempt `state` binding and callback checks
- [PR #40](https://github.com/GhostMan612/sovereign_tagger/pull/40): OAuth Bearer header; remove URL credentials
- [PR #41](https://github.com/GhostMan612/sovereign_tagger/pull/41): strict host + locationid consistency
- [PR #42](https://github.com/GhostMan612/sovereign_tagger/pull/42): Keystore migration spec; **no functional token-at-rest fix yet**

The follow-up Keystore implementation is specified in `docs/audit-workorders/pcloud-keystore-credential-migration.md`. The code drafts are independent branches from the same pre-hardening baseline and should be reviewed/merged with regression tests. Existing findings are kept here as a historical record, not a statement that all work has landed.
