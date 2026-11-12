# ST-25 — Validate pCloud OAuth deep-link ownership and live US/EU sign-in

> **Priority:** P1 · **Status:** SPEC-ONLY / NOT IMPLEMENTED · **Audit commit:** `0253a994`

## Verified risk / scope
Merged OAuth state/header/region fixes have green Dart CI but live US/EU sign-in, custom-scheme callback hijack behavior, replay and user-unlock/back stack are not exercised on Android devices.

- [`lib/core/cloud_pcloud.dart:42-95`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_pcloud.dart)
- [`lib/screens/settings_screen.dart:140-230`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/settings_screen.dart)
- [`android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt:185-194`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt)
- [`android/app/src/main/AndroidManifest.xml`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/AndroidManifest.xml)
- [`docs/audit-workorders/pcloud-oauth-and-token-hardening.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/pcloud-oauth-and-token-hardening.md)

## Intended code and artifact surfaces
- `android/app/src/main/AndroidManifest.xml`
- `MainActivity.kt`
- `lib/screens/settings_screen.dart`
- `lib/core/cloud_pcloud.dart`
- `test/cloud_host_security_test.dart`
- `android/app/src/androidTest/** (new)`

## Ordered detailed work order
1. Document authoritative pCloud authorization URL, response_type=token, exact redirect URI, returned state, access_token, hostname and locationid from official docs. Do not invent code flow/PKCE support.
2. Audit Android intent-filter exported status, host/path/scheme matching, onNewIntent behavior, single pending redirect semantics and loss of redirect across process death.
3. Threat-model custom scheme interception by other apps and malicious intent injection; compare verified App Links feasibility or app-specific callback control without assuming pCloud accepts a new redirect.
4. Bind nonce to exactly one active sign-in attempt and expire it on timeout, activity close and restart; if persistent pending state is needed, store it securely and clear after single consumption.
5. Test rejection of fragment/query pollution, wrong host/region, duplicate state, malformed URI, callback-replay, redirects from different packages and user's manual raw-token fallback.
6. Verify HTTPS bearer authentication against pCloud US/EU userinfo, listfolder and media retrieval with disposable credentials; redact all tokens and filenames from public artifacts.
7. Validate local sign-out, remote revocation behavior where API supports, stale token recovery and offline UX. Restrict raw pasted token to explicit operator selection.

## Test matrix, failure injection and safety cases
- [ ] Android intent injection tests: wrong path, stale nonce, duplicate redirect, wrong origin and background restore.
- [ ] Live pCloud US and EU disposable accounts: login, reconnect, logout, list, download; errors on expired/invalid token are actionable.
- [ ] Ensure browser callback never loses control when app is already alive or process was killed; no unverified login success.

## Required closeout evidence
- [ ] Document real on-device sign-in both pCloud regions; no state bypass or bearer leakage.
- [ ] Explicit supported and unsupported deep-link assurance boundaries.
- [ ] No production credentials or personal cloud content in CI/test reports.
- [ ] Separate code PR reviewed, exact SHA documented, CI and applicable native/device tests independently observed.
- [ ] No security or performance claims upgraded from inferred to verified without real measurement or upstream docs.

## Dependency chain
Merged PRs #39/#40/#41 are code baseline; ST-02 Keystore vault and ST-13 HTTPS redirects require follow-up integrated smoke.

## Rollback/compatibility
Retain current strict state validation; revert only a new callback mechanism if live provider mismatch.

## Scope control
This PR is a reviewed specification, not an implemented repair. Follow the project artifact chain and keep any unproven deletions, network changes, or data-sensitive behavior out of the first mechanical implementation slice. Maintain history and explicit test provenance.
