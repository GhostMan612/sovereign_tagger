# ST-12 — Unify Sentinel scan orchestrator and resolve dead bridge surface

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
SentinelStore.sentinelScan(trackProvider:) duplicates scanning yet has no production caller identified; active scans use SentinelScanner, risking divergent metadata fidelity, cancellation and persistence.

- [`lib/services/sentinel_store.dart:565-650`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/sentinel_store.dart)
- [`lib/core/sentinel_scanner.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/sentinel_scanner.dart)
- [`lib/screens/sentinel_screen.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/sentinel_screen.dart)
- [`docs/audit-workorders/sentinel-native-deadends-and-modules.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/sentinel-native-deadends-and-modules.md)

## Files and API contract touch surfaces
- `lib/services/sentinel_store.dart`
- `lib/core/sentinel_scanner.dart`
- `lib/screens/sentinel_screen.dart`
- `lib/services/ghost_world.dart`
- `test/sentinel_scan_parity_test.dart (new)`

## Ordered implementation plan
1. Inventory every Dart caller, native MethodChannel label, GhostWorld façade, reflection string and future SDK contract before deleting or retargeting scanner.
2. Choose SentinelScanner as authoritative producer with an injectable track provider; keep SentinelStore responsible for persistence, status transitions, recovery and reporting.
3. Replace duplicate scanner with forwarding façade only if external Ghost/SKD API needs it; otherwise remove after no-caller evidence.
4. Align scan cancellation, immutable snapshots, all status and issue codes, tag sources and checkpoint/resume behavior.
5. Reconcile path vs content-URI metadata, particularly ID3 fields present locally but not in MediaStore.
6. Codify a machine-readable Dart↔Kotlin method-name contract and surface any orphan handlers for explicit keep/delete decision.
7. Update architectural diagrams and document why any intentionally parked SDK entry point remains.

## Failure injection and regression suite
- [ ] Two scanner paths on identical fixtures yield identical policy, findings and issue severity.
- [ ] Cancellation preserves previous valid store; failed metadata source cannot silently erase results.
- [ ] Track ID collisions, stale items, duplicate songs and missing MediaStore tags handled consistently.
- [ ] MethodChannel orphan scan covers exact native+Flutter code references.

## Approval criteria / evidence packet
- [ ] Exactly one authoritative scanner; no dead unowned duplicate behavior.
- [ ] Ghost/Sentinel API has explicit supported semantics or is deliberately removed.
- [ ] Parity tests and Android media fixture gate.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
Coordinate Ghost UI extraction and #23 native bridge contract tests.

## Safe rollback
Keep compatibility façade until all callers verified; do not silently delete history.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
