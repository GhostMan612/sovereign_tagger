# pCloud credential-at-rest migration — Android Keystore work order

**Status:** SPECIFICATION ONLY — no credential storage code has changed in this PR.
**Code baseline:** `main` at `64e088ebfde33356c64bccc4c75342038320c8d1`.
**Related implementation drafts:** [#39](https://github.com/GhostMan612/sovereign_tagger/pull/39) OAuth state binding; [#40](https://github.com/GhostMan612/sovereign_tagger/pull/40) bearer-header authentication; [#41](https://github.com/GhostMan612/sovereign_tagger/pull/41) region consistency.
**Provider references:**
- https://docs.pcloud.com/methods/oauth_2.0/authorize.html — mobile token flow, state, hostname/locationid
- https://docs.pcloud.com/methods/oauth_2.0/ — bearer header and OAuth token expiry policy
- https://docs.pcloud.com/methods/intro/global_parameters.html — `access_token` distinct from older `auth`
- https://docs.pcloud.com/methods/oauth_2.0/oauth2_token.html — confidential `client_secret` required for code-flow exchange; PKCE not documented there

## Problem, evidence, threat model

`CloudSettings.setToken()` persists `pcloud_token` using `SharedPreferences.setString`; `CloudSettings.load()` reads it as plaintext. The token is long-lived according to provider documentation and authenticates access to the user's files. Local SharedPreferences are private to the app under normal Android sandbox rules, but may be included in device backups or accessible on compromised devices. Do not promise Keystore encryption protects a rooted runtime or a malicious app with the user's process privileges.

Existing `StorageBridge.encryptConfig()` implements `SOV2:K` via Android Keystore AES-GCM. This **demonstrates an existing primitive**, not that the generic config channel is the correct permanent credential API. Never append OAuth tokens to normal settings backups, passphrase config exports or generic recovery manifests.

## Security requirements and proposed architecture

**C1 — Dedicated native token vault.** Add a purpose-specific Android MethodChannel contract `pcloudCredentialStore` with `save`, `read`, `delete`, and `status` operations, or a similarly narrow storage abstraction. Keep access to the cleartext token limited to the authentication request boundary. Use a dedicated Android Keystore AES-256-GCM alias and random per-record nonce, authenticated ciphertext format/version, and strict field lengths. Fail closed on decryption error; never log plaintext, ciphertext payloads, auth headers or token substrings.

**C2 — Durable encrypted record and backup policy.** Persist only encrypted credential bytes in app-private storage (or encrypted preferences); ensure that ciphertext is excluded from cross-device Auto Backup/device transfer unless a correctly defined restore-rekey mechanism exists. Add version-appropriate backup/data-extraction exclusions for Android 6–12+ as applicable and test both cloud backup and device-to-device restore. After a restore without the matching Keystore key, treat credentials as unavailable and request sign-in; never fall back to plaintext persistence.

**C3 — One-way, failure-safe migration from legacy preferences.**
1. Read existing `pcloud_token`, `pcloud_api_host`, `pcloud_location_id` only from the previous local record.
2. Validate host against the two allowed pCloud domains and check ID 1/2 consistency (PR #41).
3. Write token to the encrypted store, re-read/decrypt to confirm equality without logging.
4. Persist an authenticated or non-secret migration-complete marker; only **after confirmed durable storage**, remove plaintext `pcloud_token`.
5. If any step fails, do not erase the only usable credential. Return an explicit status requiring operator action; do not silently resume remote operations with unverified storage. Avoid repeated plaintext copies or plaintext export.
6. Handle crash/restart after each individual step; migration is idempotent and cannot permanently strand an account. Consider opting for an explicit reconnect if atomic preservation and fail-closed requirements cannot both be met.

**C4 — API integration and lifetime.** `CloudSettings` should expose connection status and host/region metadata without eagerly exposing the raw token to UI and log surfaces. The pCloud HTTP client retrieves the token only for an authorized request, applies `Authorization: Bearer`, and keeps it out of URI strings, analytics, crash reports, and debugger-visible settings widgets. Sign-out should attempt provider revocation then wipe device state; network failure must still permit local credential deletion with a clear status.

**C5 — Sensitive UI.** Existing Settings manual raw-token entry is an explicit operator route, not an OAuth callback bypass. Do not save token text in ordinary preferences or show token in screenshots after submit. Clear its controller regardless of success/failure after the selected operator action. A pasted custom-scheme redirect should require a matching active `state` and never silently revert to manual mode.

## Acceptance tests: separate child implementation PR

- `save` + `read` + `delete` + `status` with a disposable fake token, across process restart, no plaintext file on disk.
- Existing plaintext-token migration succeeds, removes legacy string, preserves selected pCloud region/scope, and still performs authorized `userinfo`.
- Inject exceptions before encrypted write, after encrypted write but before legacy deletion, after legacy deletion, key invalidation, malformed ciphertext, and device restore; operator receives actionable state, not a phantom "connected" badge.
- Non-matching host/location, untrusted callbacks, and corrupted ciphertext never reach the HTTP client.
- Android device/emulator API 26, 29, 33+ and current target; OEM hardware verification on both devices if feasible.
- Verify Auto Backup + Android 12+ `dataExtractionRules` exclusions; check no pCloud token in config export, logs, URL query strings, shared backups or screenshots.
- Explicit evidence for restored/migrated token availability, logout/revocation behavior and fail-closed handling.

## Ordering / integration with other OAuth drafts

1. Merge #39–#41 individually after CI and provider smoke tests; preserve the public mobile token flow.
2. Implement C1–C3 in a **separate code PR** with isolated native crypto tests and resilient migration; do not make this specification appear to close the actual security problem.
3. Implement C4–C5 as a follow-up integration PR if keeping the token resident in `CloudSettings` complicates migration.
4. Verify backup exclusions, device restore, and real pCloud US/EU API calls before final sign-off.

**No credential extraction, plaintext logging, direct GitHub secret upload, or live-account access is required to validate this specification.**
