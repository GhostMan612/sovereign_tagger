# ST-13 — pCloud streaming redirect HTTPS and payload-boundary policy

> **Priority:** P2; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
Provider download URLs follow up to ten Location hops through URI.resolve without an explicit HTTPS-only assertion at every redirect; URL construction and content integrity may trust unvalidated endpoint transitions.

- [`lib/core/cloud_pcloud.dart:197-290`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_pcloud.dart)
- [`lib/core/cloud_source.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_source.dart)

## Files proposed for the implementation PR(s)
- `lib/core/cloud_pcloud.dart`
- `lib/core/cloud_download.dart`
- `test/pcloud_download_redirect_test.dart (new)`

## Ordered implementation workchain
1. Inventory actual pCloud getfilelink/download response semantics using official documentation and disposable US/EU test accounts; do not invent CDN host allowlist.
2. Require https URI scheme and no embedded credentials for initial URL and each redirect, reject unsupported URI syntax, invalid ports and unexpected network schemes.
3. Disable implicit HttpClient redirects; manually apply capped redirect resolution, guard against HTTPS-to-HTTP downgrade and network loops.
4. Set strict connect/read and total elapsed timeouts, byte cap, content-length enforcement and optional source digest where provider supplies it; stream into unique .part file.
5. Prevent sending OAuth bearer header to arbitrary media CDN hosts; authenticated API and tokenless CDN download must stay distinct.
6. Ensure failed redirect/downgrade leaves existing cached target untouched, deletes only owned temporary file and surfaces a useful failure reason.
7. Document allowed pCloud host/CDN behavior based on verified provider response instead of broad wildcard trust.

## Negative and regression test plan
- [ ] 301/302/303/307/308 relative and absolute HTTPS redirects work up to limit, then fail closed.
- [ ] HTTPS→HTTP downgrade and redirect containing userinfo rejected; loop, malicious host, transfer timeout and oversized response rejected.
- [ ] US/EU real provider download and Content-Length mismatch preserve previous offline cache.

## Acceptance / evidence gates
- [ ] Every network hop HTTPS with no bearer leakage.
- [ ] No successful status on truncated or unverified download; previous cached media preserved.
- [ ] Provider-contract evidence linked and synthetic HttpServer tests completed.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
After #40 OAuth Bearer patch; integrates with ST-07 cloud folder completeness and ST-08 staged imports.

## Rollback / operator preservation
Retain known-good downloaded cache, reject unsupported provider redirects with actionable retry rather than downgrade.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
