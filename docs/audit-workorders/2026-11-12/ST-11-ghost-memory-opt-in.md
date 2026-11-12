# ST-11 — Ghost playback history opt-in, event wiring or explicit retirement

> **Priority:** P2 | **Status:** SPECIFICATION ONLY; no functional fix included | **Reviewed main:** `0253a994` (2026-11-12)

## Provenance and defect
GhostMemory.recordPlay persists artist/track history but has no production playback caller; the system can appear personalized while never observing real plays.

- [`lib/core/ghost_memory.dart:130-161`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/ghost_memory.dart)
- [`lib/core/audio_handler.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/audio_handler.dart)
- [`lib/services/ghost_brain.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_brain.dart)
- [`docs/audit-workorders/voice-ghost-runtime-deadends.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/voice-ghost-runtime-deadends.md)

## Files and API contract touch surfaces
- `lib/core/ghost_memory.dart`
- `lib/core/audio_handler.dart`
- `lib/core/playlists.dart`
- `lib/services/ghost_brain.dart`
- `lib/screens/settings_screen.dart`
- `test/ghost_history_test.dart (new)`

## Ordered implementation plan
1. Make explicit decision: opt-in on-device playback personalization or retire dead memory API. Document data categories, retention and clear control before wiring.
2. If enabled, use one authoritative AudioService playback transition, with dedupe by media item/session completion; never track each widget rebuild or position update.
3. Exclude external cloud URL secrets and private paths from analytics/persistence; keep app-private local history only.
4. Expose Settings toggle default OFF, local clear history, export behavior and data retention cap; no automatic upload into Ghost or provider APIs.
5. Use history only when permission enabled, with explanation of recommendation provenance, and never fabricate play counts from playlist position.
6. If retired, remove unused storage code and tests only after external APIs/dynamic method strings are checked; update Ghost dialogs and docs.

## Failure injection and regression suite
- [ ] Zero records when opt-out; exactly one record per completed track/explicit replay per policy.
- [ ] Skip/seek/auto-advance/background resume do not generate duplicates.
- [ ] History survives restart when enabled, fully clears on opt-out, and is excluded from backup/export by policy.
- [ ] User-visible recommendations depend only on real events; no persistence of private locations.

## Approval criteria / evidence packet
- [ ] Explicit privacy/default and documented data scope, no misleading dormant feature claims.
- [ ] No regressions in audio_service notification or playlist transitions.
- [ ] No data loss when migrating existing historical records.
- [ ] Implementation PR includes exact commit SHA, diff, independently reviewed test logs and native/device evidence when applicable.
- [ ] No blanket success or feature-complete claim merely because this specification merges.

## Ordering / dependencies
Before Ghost v2 memory/recommendation expansion; can be closed by verified deletion if operator declines.

## Safe rollback
Disable recording and preserve existing records until deletion decision; allow user to clear.

## Doc and operator handoff
Record separate statuses SPEC, CODE, DART CI, NATIVE BUILD, DEVICE and RELEASE VERIFIED in the artifact chain. Only update historical progress checkboxes after an implementation PR lands and its verification is independently observed. Preserve user data and avoid introducing unapproved network transfers.
