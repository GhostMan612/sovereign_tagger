# ST-07 — Explicit cloud folder traversal limits, cancellation, and completeness

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
Folder enumeration silently returns at depth >3 or after 500 eligible files, then displays a completion-shaped callback with no indication that descendants were omitted.

- [`lib/core/cloud_download.dart:78-117`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_download.dart)
- [`lib/core/cloud_pcloud.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_pcloud.dart)
- [`docs/audit-workorders/model-and-media-integrity.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/model-and-media-integrity.md)

## Files and API contract touch surfaces
- `lib/core/cloud_download.dart`
- `lib/core/cloud_source.dart`
- `lib/widgets/cloud_folder_view.dart`
- `test/cloud_folder_traversal_test.dart (new)`

## Ordered implementation plan
1. Introduce CloudTraversalReport(files, foldersVisited, rejected, truncated, reason, failedPaths, continuation) preserving existing CloudDownloadSummary compatibility via adapters.
2. Implement bounded iterative traversal with visited folder IDs, stable file-ID deduplication, explicit max depth/count/time budgets and one cancellable pagination/continuation cursor; document default policy.
3. Distinguish selection/scan phase from download phase and propagate cancel signals through both; never convert cancellation into generic per-file failures.
4. Render partial-success and omitted-items notices, offer resume from saved cursor and clearly identify limits before downloading hundreds of media files.
5. Propagate listing errors with folder context; handle shared folders, cycles, empty directory, permission loss and API pagination safely.
6. Keep filenames sanitized and never use cloud-supplied path fields for arbitrary local FS writes.

## Failure injection and regression suite
- [ ] Nested depth 4–8 and 501+ audio files produce explicit truncation and resumability.
- [ ] Cycle/shared-folder IDs do not loop or duplicate file exports; interruption at N preserves counts.
- [ ] Failure within one subfolder is shown with path and actionable retry; no false 100% completion.

## Approval criteria / evidence packet
- [ ] No silent omission; success counters only include verified saved items.
- [ ] Cloud listing avoids unbounded network/resource use and cancellation is deterministic.
- [ ] US/EU cloud API smoke test, fake source tests in CI.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
Independent of OAuth changes already merged; precedes full folder-playlist UX.

## Safe rollback
Preserve legacy capped behavior behind explicit limited mode with warning; never silently return complete.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
