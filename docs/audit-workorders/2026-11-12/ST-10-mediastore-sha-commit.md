# ST-10 — MediaStore content identity and prepublication commit verification

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
Native import compares copied and readback lengths but not content digests, and may mark IS_PENDING=false before independent verification.

- [`android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt:167-215`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt)
- [`docs/audit-workorders/model-and-media-integrity.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/model-and-media-integrity.md)

## Files and API contract touch surfaces
- `android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt`
- `android/app/src/androidTest/** (new)`
- `lib/core/storage_client.dart`
- `test/native_mediastore_contract_test.dart (new)`

## Ordered implementation plan
1. Calculate streaming SHA-256 from source and newly written destination using bounded memory, rejecting equal-size altered bytes.
2. Preserve IS_PENDING=1 while verifying by URI wherever supported; explicitly document provider behavior for unavailable readback, permission errors or storage backends.
3. Publish only after verified digest equality and successful update count, returning structured {uri, bytes, sha256, published} contract.
4. On mismatch or failure, delete the pending record and preserve original app-staged file; any failed delete must surface a recoverable orphan report.
5. Integrate native result with Workbench queue committed/pendingImport distinction; no successful status on unverified, empty, truncated or unreadable destination.
6. Avoid main-thread I/O; cancel and lifecycle handling must not expose half-written media to other apps.
7. Protect existing overwrite/recovery vault semantics; imported new files and overwriting old media may need separate policies.

## Failure injection and regression suite
- [ ] Fault-inject null stream, short write, correct-length wrong-content, failed update, unreadable output and delete failure.
- [ ] Android ContentResolver instrumentation API 26, 29, 33+, including scoped storage and app upgrade behavior.
- [ ] Large synthetic streams hash without loading entire file into heap; import idempotent across retry.

## Approval criteria / evidence packet
- [ ] Published URI has matching source and destination SHA-256 or explicit fail-closed unsupported result.
- [ ] Input staging retained when commit not verified; orphan cleanup tracked.
- [ ] Native Android CI and hardware acceptance; no false 'success' on byte-count-only proof.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
#06 CI infrastructure; #08 pending-import recoverability.

## Safe rollback
Never weaken to length-only trust in production; preserve staged file and explicit unresolved state.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
