# ST-09 — FFmpeg session ownership, startup cancellation and screen teardown

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
Cancellation can occur after pre-run check but before session registration; widget disposal does not end active Workbench batch, and an unrelated-session test does not start an unrelated session.

- [`lib/core/ffmpeg_executor.dart:35-83`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/ffmpeg_executor.dart)
- [`lib/workbench/workbench_queue.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/workbench/workbench_queue.dart)
- [`lib/tabs/tab_workbench.dart:620-631`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/tabs/tab_workbench.dart)
- [`test/workbench_queue_test.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/test/workbench_queue_test.dart)

## Files and API contract touch surfaces
- `lib/core/ffmpeg_executor.dart`
- `lib/workbench/workbench_queue.dart`
- `lib/tabs/tab_workbench.dart`
- `test/ffmpeg_executor_concurrency_test.dart (new)`

## Ordered implementation plan
1. Represent queue sessions with opaque unique task IDs, owner and lifecycle phase (queued, prehook, starting, running, committing, terminal); keep description for logging only.
2. Recheck cancel atomically after every awaited preflight hook and immediately before FFmpegKit execute; cancellation of queued item must never create a session.
3. Cancel only a matching owner/session; avoid FFmpegKit global cancel for unmatched jobs, especially simultaneous voice/Grabber/Workbench tasks.
4. Wire TabWorkbench dispose and navigation disposal to queue cancellation without setState after unmount; expose explicit completion future and cleanup hook.
5. Define non-cancellable commit phase during MediaStore publish; show 'finishing save' and allow next-batch cancellation without corrupting finalized URI.
6. Avoid duplicate callback completion and ensure every pending completer resolves exactly once under cancellation, exceptions and reentrancy.

## Failure injection and regression suite
- [ ] Barrier-controlled beforeExecuteHook cancellation results in zero native execute calls.
- [ ] Two interleaved owner tasks: cancel Workbench leaves voice/Grabber live and subsequent unrelated work executes.
- [ ] Cancel during active rendering, pre-output probe, import commit and widget dispose cleans owned files and reports accurate status.
- [ ] All queued tasks settle once and no late statistics callbacks mutate disposed UI.

## Approval criteria / evidence packet
- [ ] No cross-feature cancellations or jobs launched after cancellation acknowledgment.
- [ ] Real FFmpeg synthetic-media integration on Android and deterministic Dart executor tests.
- [ ] No temporary-file loss or deadlock at provider commit boundary.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
Coordinates #08 and #10; no global FFmpeg cancellation API changes without channel contract audit.

## Safe rollback
Keep legacy executor behind optional compatibility adapter while tests establish session ID semantics.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
