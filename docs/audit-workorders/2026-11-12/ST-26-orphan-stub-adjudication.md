# ST-26 — Cross-language dead ends, stubs, placeholders, and unused ABI inventory

> **Priority:** P2 · **Status:** SPEC-ONLY / NOT IMPLEMENTED · **Audit commit:** `0253a994`

## Verified risk / scope
Keyword scans cannot prove whether a no-op default, unused native handler, dormant Sentinel/Ghost API or apparent placeholder is genuinely dead; deleting them without dynamic usage inventory risks silent SDK and plugin breakage.

- [`lib/services/ghost_brain.dart:46-95`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_brain.dart)
- [`lib/services/sentinel_store.dart:565-650`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/sentinel_store.dart)
- [`android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)
- [`docs/audit-workorders/sentinel-native-deadends-and-modules.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/sentinel-native-deadends-and-modules.md)

## Intended code and artifact surfaces
- `scripts/audit/channel_contract_scan.py (new)`
- `docs/audit-workorders/orphan-disposition-register.md (new)`
- `test/channel_contract_test.dart (new)`
- `lib/services/ghost_world.dart`
- `android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt`

## Ordered detailed work order
1. Build reproducible source inventory across Dart/Kotlin/Python/C++/JNI and XML, including generated MethodChannel names, invokeMethod strings, Python callAttr, ELF exports, reflection/manifest, test-only references and dynamic event handlers.
2. Classify every hit as active, compatibility shim, intentionally deferred SDK surface, unreachable, safe-to-prune, or needs runtime trace; include owner and proof reference.
3. Compare native handler names/arguments/return envelopes to Dart callers; fail CI for newly orphaned or mismatched declarations while supporting known intentional exceptions.
4. Inspect GhostWorld default no-op methods against real GhostWorld implementation and ensure user-facing replies never claim a successful operation if fallback returns null/false.
5. Determine whether SentinelStore.sentinelScan or GhostMemory history are reached by non-obvious dynamic/plugin consumers before deletion; keep explicit API deprecation schedule.
6. Identify unused copies of ACRCloud binaries/Whisper asset placeholders and obsolete UI strings, but do not call unsupported-ABI stubs dead when they are valid compatibility surfaces.
7. Propose bite-sized cleanup PRs per independently proven orphan, with unit and native contract tests; preserve Genesis header and operator docs ownership policy.

## Test matrix, failure injection and safety cases
- [ ] Static scanner finds deliberately injected unused handler and missing Dart method.
- [ ] Dynamic consumer fixture prevents removal of a handler that is invoked through a string constant.
- [ ] No-op Ghost method cannot generate 'download succeeded' reply without verified action result.
- [ ] JNI x86_64 unsupported implementation is intentionally retained and documented, not blindly deleted.

## Required closeout evidence
- [ ] Each removal has a zero-caller evidence record and rollback instructions.
- [ ] No runtime bridge ABI loss or unsupported feature mislabeling.
- [ ] Reduced dead surface quantified without inventing counts from lexical TODO scans.
- [ ] Separate code PR reviewed, exact SHA documented, CI and applicable native/device tests independently observed.
- [ ] No security or performance claims upgraded from inferred to verified without real measurement or upstream docs.

## Dependency chain
ST-12 Sentinel, ST-11 Ghost history, ST-18 verification gates, ST-24 Kotlin decomposition.

## Rollback/compatibility
Keep compatibility aliases and warn/deprecate rather than remove if any supported dynamic consumer remains.

## Scope control
This PR is a reviewed specification, not an implemented repair. Follow the project artifact chain and keep any unproven deletions, network changes, or data-sensitive behavior out of the first mechanical implementation slice. Maintain history and explicit test provenance.
