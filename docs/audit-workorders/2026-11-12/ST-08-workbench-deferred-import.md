# ST-08 — Durable Workbench pending-import state and recovery

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
On failed MediaStore import the rendered media remains under temporary storage and BatchJobStatus.completed increments OK, although the output is not durable in library.

- [`lib/workbench/workbench_queue.dart:275-335`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/workbench/workbench_queue.dart)
- [`lib/tabs/tab_workbench.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/tabs/tab_workbench.dart)
- [`lib/core/cloud_cache.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_cache.dart)
- [`docs/audit-workorders/model-and-media-integrity.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/model-and-media-integrity.md)

## Files and API contract touch surfaces
- `lib/workbench/workbench_models.dart`
- `lib/workbench/workbench_queue.dart`
- `lib/tabs/tab_workbench.dart`
- `lib/core/storage_client.dart`
- `lib/workbench/pending_import_store.dart (new)`
- `test/workbench_queue_test.dart`

## Ordered implementation plan
1. Introduce explicit pendingImport status separate from completed/failed/skipped; reserve completed for validated durable URI.
2. Move failed staged media into app-private durable recovery storage before reporting recoverable; atomically store manifest job ID, input/output names, checksum, byte count, creation time and retry status.
3. Do not store unrecoverable cache paths as success; treat missing stage as failure without deleting unrelated files.
4. Expose operator recovery UI: pending import list, retry, export via SAF, open, and confirmed discard; never purge automatically as ordinary cache.
5. Use unique names and hashed source IDs to prevent collisions and overwrites; implement crash-safe manifest/record journal with status transitions.
6. After successful MediaStore import, verify durable readback and remove staging/manifest transactionally; do not double-create outputs on retries.
7. Update batch progress and counts to distinguish committed, pending recovery, failed and cancelled.

## Failure injection and regression suite
- [ ] Null/blank/exceptional MediaStore response retains file and durable manifest; restart still sees it.
- [ ] Two identical filenames, retry after crash, no-space-on-device and missing temp are accounted correctly.
- [ ] Cache clear and normal eviction cannot delete pending imports; explicit discard deletes exact artifact only.
- [ ] Successful retry yields exactly one saved MediaStore asset and no staging leak.

## Approval criteria / evidence packet
- [ ] 'X/Y saved' excludes pending-import cases; recovery always operator-visible.
- [ ] No data loss on cache purge, app restart, cancellation or failed import.
- [ ] Native MediaStore instrumentation gate plus Dart unit tests.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
Coordinate #10 MediaStore integrity and #09 cancellation semantics.

## Safe rollback
Never roll back by deleting pending outputs; provide migration for existing cache-only paths when present.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
