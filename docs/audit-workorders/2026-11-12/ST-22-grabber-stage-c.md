# ST-22 — Stage C Grabber format resolver, job coordinator and UI decomposition

> **Priority:** P3 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
Grabber (~85 KB) mixes source categorization, format menus, Python jobs, cookies, mux retry ladders, materialization and UI, with many catch paths that could hide cleanup/cancellation failures.

- [`lib/tabs/tab_grabber.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/tabs/tab_grabber.dart)
- [`android/app/src/main/python/sovereign_yt/bridge.py`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/python/sovereign_yt/bridge.py)
- [`lib/core/ffmpeg_executor.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/ffmpeg_executor.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)

## Proposed file/interface changes
- `lib/grabber/format_resolver.dart (new)`
- `lib/grabber/grabber_job_queue.dart (new)`
- `lib/grabber/components/site_badges_grid.dart (new)`
- `lib/tabs/tab_grabber.dart`
- `test/grabber_format_selection_test.dart (new)`

## Surgical extraction phases
1. Inventory search/getFormats/download/cancel MethodChannel contracts and target file result shapes, preserving current yt-dlp bridge options exactly.
2. Extract pure format ordering and selection from UI; preserve per-source audio/video feature detection and quality precedence.
3. Define job lifecycle state machine with idempotent cancel, durable output ownership, progress and retry ladder; avoid two independent FFmpeg executor queues.
4. Separate cookie import/validation and secure local storage from format selection UI; use explicit user consent, no export of Netscape cookie bytes.
5. Extract supported-site badges into lazily rendered view instead of materializing 1000+ heavyweight widgets on every update.
6. Retain tab as coordinator for file picker, request IDs, Ghost commands, Forge handoff, status and lifecycle.
7. Ensure yt-dlp updater cannot mutate loaded package during active Grabber job; defer unsafe updater implementation to ST-01.

## Tests and negative conditions
- [ ] Format fixtures covering audio-only, video-only, split formats, fallback mux and malformed metadata.
- [ ] Cancel/retry with live concurrently running mux and cloud import doesn't kill unrelated sessions.
- [ ] Cookies never appear in logs; Forge handoff receives valid path after successful materialization; no duplicate downloads on rebuild.

## Acceptance evidence
- [ ] Same supported source/quality choices and no new silent conversion.
- [ ] UI FPS and memory measured, new queue owned lifecycle explicit.
- [ ] Native Chaquopy/FFmpeg tests and Moto G/BLU smoke.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
ST-01 updater P0, ST-09 FFmpeg session ownership and ST-06 native CI.

## Rollback plan
Retain original UI/queue bridge contract and revert per component if parity fails.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
