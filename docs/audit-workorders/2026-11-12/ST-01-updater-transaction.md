# ST-01 — Transactional yt-dlp updater and honest diagnostics

> **Priority:** P0  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
Live target yt_dlp is deleted with shutil.rmtree before staged replacement is verified; module reload errors are swallowed and dependency updater reports top-level success on partial failure. Network/download/extract paths lack bounded transactional constraints.

- [android/app/src/main/python/sovereign_yt/updater.py:15-129](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/python/sovereign_yt/updater.py#L15-L129)
- [android/app/src/main/python/sovereign_yt/doctor.py](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/python/sovereign_yt/doctor.py)
- [android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt:225-231](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt#L225-L231)
- [docs/audit-workorders/python-updater-transaction-safety.md](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/python-updater-transaction-safety.md)

## Intended implementation touch surfaces
- `sovereign_yt/updater.py`
- `sovereign_yt/doctor.py`
- `MainActivity.kt`
- `SettingsScreen`
- `test/python/test_updater.py`

## Detailed work order
1. Phase 1 fail closed: disable CURRENT destructive update button and direct user to pinned APK build while transactional path is developed; preserve doctor diagnostics.
2. Introduce UpdateManifest(version, release identity, source digest, expected layout, stage dir, target dir, previous snapshot, state); reject requests while Grabber/FFmpeg work is active.
3. Resolve and pin allowlisted GitHub release metadata; enforce HTTPS, finite connect/read timeouts, transfer-size limits, archive entry-count and total-expanded-size limits, and safe tar members/symlinks. Confirm Python 3.14 extraction-filter behavior but never rely on it alone.
4. Stage under unique writable app-private directory instead of altering package-installed site-packages; validate required yt_dlp modules, matching release identity and smoke-test extractors in isolated environment without touching live target.
5. Activate with versioned directory/pointer or two-phase rename and durable journal; keep last known-good version and rollback on any failed activation or restart. Handle inability to reload Python modules by requiring explicit app restart.
6. Return a structured update result with downloaded, validated, activated, rolledBack, partial and failed states; reflect per-package pip/Chaquopy support honestly, not blanket success.
7. Define an explicit operator recovery command; never use 'Scorched Earth Complete' unless replacement and post-activation self-test succeed.

## Negative and regression test matrix
- [ ] Disposable fake target: malformed archive, path traversal, oversized tar, no network, wrong modules, failed import, file-permission failure and interrupted rename preserve previous live version.
- [ ] Cancellation and concurrent download jobs reject activation; failed dependency upgrade yields partial/failed status.
- [ ] Crash/restart at each journal transition resumes or rolls back deterministically; no real production updater exercised in CI.

## Acceptance criteria and evidence required
- [ ] No deletion of active yt_dlp before a verified successor is durably staged.
- [ ] Old working version restorable after injected failures; bounded network and archive handling.
- [ ] Native Chaquopy compatibility + Android device smoke; operator-visible status accurately distinguishes partial failure.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
None. Block risky runtime update entry point before further releases.

## Rollback / failure policy
Revert feature flag or return to immutable APK-bundled yt-dlp; preserve immutable installed package and rollback snapshot.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
