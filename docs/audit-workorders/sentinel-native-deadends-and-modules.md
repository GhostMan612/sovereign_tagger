# Audit work order — Dead native/Sentinel entry points and size-driven modularization

**Baseline:** `main` at `ba708fe`
**Scope:** native MethodChannel inventory, Sentinel scan architecture, oversized Dart modules.
**Status:** specification only. Verify dynamic/reflection call sites before deleting any public bridge method.

## D1 — Duplicate but disconnected Sentinel scan (P2 correctness / maintenance)

**Evidence:** `SentinelStore.sentinelScan(trackProvider:)` in `lib/services/sentinel_store.dart` is not called from current Dart app/tests under symbol search. `lib/screens/sentinel_screen.dart` drives the `SentinelScanner` instead. The store method constructs `SentinelTagSnapshot` primarily from a MediaStore map, whereas `SentinelScanner` performs the authoritative scan and tag inspection.

**Risk:** if the store's dormant API is connected later, scans may disagree with the UI over missing metadata, because their evidence and update semantics differ.

**Remediation work order:**
1. Identify whether the Ghost-Sentinel artifact-chain contract still requires an executable `sentinelScan` method on the store.
2. Select one authoritative scan orchestrator. Prefer delegating to `SentinelScanner` if Ghost needs a store-facing API; otherwise remove the unused store implementation.
3. Keep scan progress, cancellation, status transitions and persisted hit IDs deterministic.
4. Add parity tests with metadata present in ID3 but absent from MediaStore, cancellation, and partially read media.
5. Remove obsolete wrappers and dead data flow only after the caller contract is decided. The two unused naming wrappers are handled independently in Draft PR #28.

## D2 — Uncalled Android MethodChannel entry points (P3 dead surface)

**Evidence:** `MainActivity.kt` handles `getDoctorRegistry`, `describeMedia` and `scanFile`; the audit's exact-symbol search finds no direct Dart invocations in the current app. `doctor.py:get_registry` is thereby present but not reachable through the current UI.

**Remediation work order:**
1. Inventory channel method strings from all Dart sources, tests, and any supported scripts or external clients.
2. Decide per handler: wire a documented UI caller if useful, or remove the handler and update `.blueprints/ARCHITECTURE.md`.
3. Preserve native `StorageBridge.describe` and `scan` internal methods that still have Kotlin callers; deleting a MethodChannel case does not imply deleting the actual native helper.
4. Add a static cross-language channel-contract test that fails on unexpected orphaned or missing public handlers.
5. Treat ABI and integration extension compatibility as a review gate.

## D3 — Large cross-cutting files increase regression risk (P3 optimization)

**Observed tracked sizes from the current Git tree:** `lib/tabs/tab_workbench.dart` ~193 KB, `lib/screens/settings_screen.dart` ~109 KB, `lib/services/ghost_brain.dart` ~98 KB, `lib/tabs/tab_grabber.dart` ~85 KB, `lib/screens/main_shell.dart` ~65 KB, `StorageBridge.kt` ~61 KB.

**Optimization plan:** extract pure operation builders, payload validators, and codec/model parsers first; retain existing widgets and native channel contracts. Build golden/widget tests for control visibility and state persistence, operation-level tests for FFmpeg argument construction and result handling, and reproducible startup/lifecycle profiles. Use mechanical moves with no behavior changes in separate PRs before any rewrite.

## Acceptance and review boundaries

No source code is removed in this planning PR. An actual deletion requires a verified zero-caller scan and corresponding tests; a method that is intentionally parked for a future SDK must be labeled *deferred* rather than incorrectly described as implemented.
