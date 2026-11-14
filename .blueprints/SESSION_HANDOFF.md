# SESSION_HANDOFF.md — Sovereign Tagger v2
> Read this FIRST every session. Updated Phase 31 build-verified 2026-10-15.

## DOCUMENT MAP — cold-start hooks (read top-to-bottom)

| # | File | Holds | When to read |
|---|------|-------|--------------|
| 0 | `AGENTS.md` (root) | Auto-injected into every session by opencode — the true guaranteed entry point; compact ramping guide + laws table | automatic |
| 0a | `COLD_START.md` (root) | **Handoff for a fresh agent**: environment + device IDs, laws, standing operator directives, active P1 voice task with reproduction commands and captured evidence | every session start / when handing a new agent the work |
| 1 | `.blueprints/RULES.md` | **CANONICAL** operating law: read-only paths, git discipline, §3 technical laws incl. **§3.1 POWERSHELL MOJIBAKE BAN** | EVERY session, before any edit |
| 2 | THIS FILE | Latest session deltas (\"What shipped\"), Next actions queue, Open decisions, toolchain notes | EVERY session |
| 3 | `.blueprints/CURRENT_STATE.md` | Verified per-file architecture map (51 Dart files), known-issue registry (`K/A/V/GH/CS/EQ/PW/AR/FX/UI/WS` rows — check before touching grabber/pipeline/workbench/player/ghost/settings), frozen-ceiling toolchain notes | before writing code |
| 4 | `.blueprints/ROADMAP.md` | Phase tracker (Phases 0–31, `[x]/[~]/[ ]/[-]`) with per-phase verification gates | when planning/phases |
| 5 | `.blueprints/BLUEPRINTS.md` | Design specs + **append-only GOTCHA REGISTRY** (SPEC-S* ids, G1–G46) | before novel features |
| 6 | `.blueprints/ARCHITECTURE.md` | Boot flow + data-flow reference diagrams | structural changes |
| 7 | `.blueprints/ARCHITECTURE_DECOMPOSITION.md` | 6-file modularization blueprint (Workbench, Settings, Ghost, Grabber, Shell, StorageBridge) | refactoring/modularization |
| — | `README.md` (root) | Operator-facing capabilities/API-keys/maintenance docs (kept synced with reality) | release/closeout/doc work |
| — | `pubspec.yaml`, `android/app/build.gradle`, `gradle.properties` | **Executable truth**: frozen dep ceiling pins, `SOVEREIGN_TAGGER.apk` name, debug-signing fallback, chaquopy/python version, builtInKotlin opt-out | any dependency/signing/build question |

Conflict law: RULES.md > other docs; executable files > prose.
Session-end law: update rows 2–4 every session (+ row 5 when a new gotcha is learned).

## Where we are

### Latest delta — PR #87 transactional updater rollback & isolated Moto G acceptance (2026-11-14)

- PR #87 (`fix/p0-updater-crash-window-serialization`, open and unmerged) completes transactional rollback evidence preservation and isolated Moto G acceptance on top of merged PR #86 (`f48b865`). App code and tests were committed cleanly at `1c9bae7a9c55fd22837c693f61d389ac14257edf`; follow-up build fix `80d85462b4fb848657936a733850d5128d950e0d` gated `create("updaterAcceptance")` in `android/app/build.gradle` behind `-PupdaterAcceptanceTest=true` after Android CI (`Flutter 3.50.0`) flagged `applicationIdSuffix` propagation into `:android_file_picker`.
- `updater.py` now checks `shutil.rmtree` errors during `_recover()`, verifies live target integrity before removing backup/staging/journal files, retains backup and journal with `recovery_required: true` / `recovery_error` when recovery fails, propagates core recovery status through `execute_full_scorched_earth()`, and surfaces `RECOVERY REQUIRED:` in `SettingsScreen` for both `updateCore` and `updateFullStack`.
- `MainActivity.kt` delegates `updateCore`/`updateFullStack` through `CoreUpdaterBridge` (production implementation in `src/production/kotlin`; fail-closed isolated acceptance implementation in `src/updaterAcceptance/kotlin` compiled only when `-PupdaterAcceptanceTest=true` for `com.sovereigntagger.updateracceptance`).
- Verified local gates at `80d8546`: Python `unittest` **37/37** passed (`24` in `test_transactional_updater.py`; **15/15** stress runs clean at `1c9bae7` base); `flutter analyze --no-pub` clean; `flutter test --no-pub` **213/213** passed (`7` in `test/updater_settings_test.dart`); `flutter build apk --debug --no-pub --target-platform android-arm64` built cleanly (`app-debug.apk` SHA-256 `9ced77fa...`); `./gradlew.bat :app:testDebugUnitTest` passed.
- Clean-provenance (`source_dirty: false`) Moto G (`ZT4222BMWN`) acceptance at `1c9bae7a9c55fd22837c693f61d389ac14257edf` (APK SHA-256 `a95e424d5d96970104fc07ff5e2ee0654a4cf204f9fb0088cff150e94d95b507`) passed `failure` (`pid: 28002`) -> `am force-stop` -> `restart` (`pid: 29049`) and `all` (`pid: 29955`), proving backup SHA-256 (`e902e556...`) and journal preservation across process restart, `"RECOVERY REQUIRED"` UI surfacing, retry recovery/upgrade, untouched Chaquopy runtime (`yt_dlp` `2026.10.26`), and untouched `com.sovereigntagger` (`appId=10821`). Acceptance packages were uninstalled afterward; see [transactional-updater-acceptance.md](../docs/transactional-updater-acceptance.md) for verified evidence and fixture/pip/release/commit-delta limitations.

### Earlier delta — PR #86 atomic Save recovery (2026-11-14, merged at `f48b865`)

- PR #86 remains open, ready for review and unmerged. The atomic Save amendment was recovered from local edits on `feat/p1-independent-15-band-dsp` at baseline `825978e027263b138613bc4dadd97452b1fafaec`. Exact pushed commit and CI evidence are recorded in the PR description. Remote `main` was verified at `b8d5c29a07bf1f75563250f3356def5369537bbd`.
- Baseline Dart run `43577428020` and Android native run `43577428018` passed at `825978e`. The amendment's local end-of-phase gates also passed: Genesis/comment/mojibake checks, strict Flutter analysis, **206/206 Flutter tests** (zero skips), and **5/5 executed Android JVM tests** (zero skips). The 12 added Save regressions include both post-Save interleavings, repeated Saves, pending Discard, failed preference writes/retry, final-write acknowledgement, native failure and disposal. No new device smoke was performed.
- The recorded live-slider Save/Discard re-smoke used source commit `152a5e5280cfd9ea046e38151adb6ee258a3f64a`; `825978e` only updates `docs/independent-15-band-eq.md`. Physical tests used local clean debug APKs, not downloaded CI artifacts. External acoustic/loopback measurement, wired/Bluetooth route switching, release-build acceptance, and physical API 26–27 fallback remain unverified.
- Recovered the uncommitted immutable-snapshot FIFO and four regression cases without resetting or discarding local work. Save commands cannot coalesce; native application and all fifteen preference writes use the tap-time snapshot. Only confirmed persistence advances `_saved`; later edits remain dirty. Checked writes roll back prior preferences on failure and report failed rollback; native-apply failure is reported separately from successful persistence.
- Added pending-Save navigation protection, frozen editing during Discard, correct committed-baseline restoration, and mounted checks for asynchronous completion. Expanded deterministic tests cover overlapping Saves, pending Discard, preference failure/retry, final-write confirmation, and disposal.
- Source/diff review found only intended EQ source, tests and documentation changes; original edits were preserved. The next milestone is the merge decision after the new-head CI evidence linked in PR #86 is green. Do not merge in this session. PR #87 transactional updater acceptance remains separate.

### Earlier session context

**Date:** 2026-11-13
**Phase:** All 15 draft PRs (#71–#85) reconciled, merged to main, and closed. `flutter analyze` 0 issues; `flutter test` 183/183 passed; Python 22/22 passed. P1 device-acceptance pass on the Moto G (`ZT4222BMWN`) complete: voice fallback 7/7, transactional updater test-verified, Keystore/MediaStore/Workbench gates green.

**Standing operator directives (2026-11-13, still in force):** Complete Implementation PRs only — source change + regression tests + integration + CI + acceptance evidence; containment fixes and CI-only PRs do not qualify. Disposable test media and credentials only; never overwrite the real Genius/ACRCloud credentials during device testing. Do not record private audio contents in logs.

## What shipped — P1 Device Acceptance: Grabber FFmpeg bridge, Keystore, MediaStore, Voice Fallback (2026-11-13)

1. **Grabber FFmpeg capability false-negative fixed (PR #85, branch `fix/p1-ffmpegkit-ffi-bridge` @ `10f8e52`)**:
   - Root cause: `capabilities()` imported `com.arthenica.ffmpegkit.*`, which is absent from the
     APK — `ffmpeg_kit_extended_flutter` is an FFI package (empty 22-byte `classes.jar`; the only
     Java class is `com.akashskypatel.ffmpegkit.FFplayKitAndroid`; `libffmpegkit.so` exports 114
     C symbols).
   - Fix: load `libffmpegkit.so` via ctypes and bind the C API (`ffmpeg_kit_execute`,
     `ffprobe_kit_execute`, session getters). Only a successful patch is cached so transient
     failures retry; failures still surface in `capabilities()`.
   - Tests: `test/python/test_ffmpegkit_bridge.py` (+7). CI green (arm64 7m41s, x64 8m7s, Dart 1m34s).
   - Device: Moto G reports `GRABBER CAPABILITIES: {"ffmpeg": true, "ffmpegkit": true, "ffmpegkit_version": "9d4ca21"}`.
2. **Keystore P0 — PASS on device.** Disposable `hf_token` saved via WRITE TO KERNEL; vault
   `sovereign_credentials_v1.xml` gained `hf_token` with zero plaintext residue in
   `FlutterSharedPreferences.xml`; restart + relaunch showed the field masked (retrieval PASS).
3. **MediaStore + Workbench P0 — PASS on device.** EXECUTE ON THE MACHINE (EXTRACT AUDIO /
   VIDEO TO MP3) published `workbench_1794552462031.mp3` (6,510,013 B, `is_pending=0`, valid
   ID3v2.4). `StorageBridge.kt:141-242` commits `IS_PENDING=1` → copy → readback digest compare
   → `IS_PENDING=0`, deleting the row on mismatch.
4. **Workbench pending-import recovery — PASS on device.** Staged payload + manifest carrying the
   real digest in `files/workbench_pending_imports/`; RECOVER PENDING LIBRARY IMPORTS → RETRY
   IMPORT produced a digest-identical MediaStore entry and emptied the pending dir.
5. **Voice fallback — 7 of 7 criteria PASS on device.** Whistle transcript; controlled Whistle
   failure (model removed + directory read-only + restart) drove the Whisper fallback, which
   returned `forge workbench. playlist equalizer ghost.`; the WAV reached the fallback intact;
   cancel mid-Whisper published nothing; post-restart Whistle transcription worked; corrupt/missing
   models → actionable error; evidence hygiene — no private audio in logs.
6. **Transactional updater rollback (PR #82) — implementation complete and test-verified.** The transactional updater stages the release tarball beside the live package, verifies structure/version/byte-compilation, then swaps with atomic renames and a durable state file. The live package is never deleted before its replacement is verified. Crash recovery via `recover()` rolls back an interrupted swap (backup restored) or completes a committed one (backup dropped). `execute_scorched_earth()` auto-recovers any dangling transaction before starting. `update_python_stack()` records installed versions before upgrade and reinstalls previous versions if pip fails. Settings screen re-wired to the `ytdlp` channel (`updateCore` / `updateFullStack`) with honest status reporting including the `partial` outcome. 9 transactional Python tests + 2 doctor tests pass; 190 Dart tests pass; `flutter analyze --no-pub` clean. **On-device verification deferred per operator constraint** (avoid destructive updater tests against the installed runtime; Chaquopy filesystem behavior, GitHub reachability, and atomic-rename semantics on Android storage would need a device smoke but are not required for merge).
7. **Known finding:** the Whisper fallback is slow on the Moto G — roughly two minutes for a
   ~7 second clip (pure CPU inference on a 147 MB model). Correct, but not quick.

## What shipped — Stage B.8–B.10: Executor Hook Race Closure, Pre-Publication MediaStore SHA-256 & Concurrency Suite (2026-11-12)

1. **FFmpeg Startup Cancellation Window & Lifecycle (B.8)**:
   - In `FFmpegExecutor._drain()`, closed the startup cancellation race window by checking `_canceledDescriptions` across three distinct checkpoints: before awaiting `beforeExecuteHook`, immediately after `await hook()`, and immediately following `FFmpegSession.create()`. If cancellation is requested while `beforeExecuteHook` is in-flight, the job aborts immediately without launching the FFmpeg binary.
   - In `TabWorkbench.dispose()`, added `_activeQueue?.cancel(); _activeQueue = null;` to ensure active batch tasks are cancelled immediately upon tab departure or widget unmount, preventing orphaned processes and background MediaStore insertions.

2. **Pre-Publication MediaStore SHA-256 Verification & Rollback Logging (B.9)**:
   - In native `StorageBridge.addToMediaStore()`, added cryptographic stream hash verification (`destSha == srcSha`) *prior* to setting `IS_PENDING = 0` for Android Q+, asserting that the destination stream bytes match the source file SHA-256 before the media becomes visible to the OS or third-party players.
   - Added destination SHA-256 validation for legacy Android < Q prior to scanning.
   - Replaced silent error swallowing with structured warning and error logging (`android.util.Log.w` / `Log.e`) if `contentResolver.delete(uri)` returns `<= 0` during rollback.
   - Formalized transactional boundary: cancellation prior to `mediaStoreInjector` halts immediately and deletes staged temporary files; once MediaStore publication succeeds, the media is committed and the temporary copy is purged; if a failure occurs during native insertion, the destination entry is rolled back and the staged file is retained in cache.

3. **Real Concurrency Regression Tests (B.10)**:
   - In `test/workbench_queue_test.dart`, implemented a Completer-controlled `beforeExecuteHook` test proving that cancellation during hook execution aborts before `FFmpegSession` starts.
   - Implemented real executor-backed test proving that cancelling a Workbench batch task leaves unrelated concurrent tasks (e.g. forensics, grabber) untouched in the queue.
   - Implemented queue lifecycle cancellation test verifying that `WorkbenchQueue.cancel()` immediately halts the active job and skips all remaining jobs with `BatchJobStatus.skipped`.
   - Verified 145/145 Flutter unit and widget tests passing cleanly.

## What shipped — Stage B.5–B.7: Scoped Cancellation, Verified Import Commit & Monotonic Invariants (2026-11-12)

1. **Scoped Cancellation & Async Boundary Checks (B.5)**:
   - Tagged each Workbench FFmpeg job with a unique scoped descriptor (`workbench_${job.id}`), passing it to `FFmpegExecutor.execute(..., description: jobDesc)`.
   - In `WorkbenchQueue.cancel()`, invokes `FFmpegExecutor.cancelCurrent(description: _currentJobDescription)`, ensuring cancellation interrupts only the active Workbench task and never disturbs concurrent background sessions (forensics, grabber muxing, or audio audits).
   - Added `handleCancellationIfRequested` checkpoints across all asynchronous boundaries: loop start, post-`durationProbe`, post-`streamProbe` input check, post-`commandBuilder`, pre- and post-`FFmpegExecutor.execute`, post-`streamProbe` output check, and pre-`mediaStoreInjector`.
   - Cancellation at any point marks the job `BatchJobStatus.skipped` (with explicit reason `'Batch cancelled by user.'`), purges any staged temporary output immediately, and halts subsequent batch processing without misreporting cancellation as an execution failure.

2. **Verified Import Commit & Destination Readback (B.6)**:
   - In `WorkbenchQueue.execute()`, strictly validated the destination URI string returned by `mediaStoreInjector`.
   - If `mediaStoreInjector` returns null, whitespace, or throws, the queue checks if the staged file exists on disk: if present, it preserves the file in cache, records `outputUri = outPath`, and logs `CACHE ONLY ${job.fileName}: $outPath` without deleting the generated audio/video. If missing, it fails fast.
   - Only when a non-empty, valid content URI is returned is the staged temporary file purged from disk.
   - In native `StorageBridge.addToMediaStore()`:
     - Checked that `contentResolver.update(uri, values, null, null)` returns affected rows `> 0`.
     - Added independent destination readback assertion: opens `contentResolver.openInputStream(uri)`, counts readback bytes, and asserts `readbackBytes == file.length()`.
     - On short read or update failure, cleans up the MediaStore entry and throws `IOException`, guaranteeing transactional commit.

3. **Monotonic Progress & Expanded Test Suite (B.7)**:
   - Clamped batch progress calculation with `_maxReportedOverall = max(_maxReportedOverall, calculatedOverall)`, guaranteeing strictly non-decreasing progress even if FFmpeg stats events arrive out-of-order or with erratic timestamps.
   - Expanded unit test suite in `test/workbench_queue_test.dart` from 34 to **44 tests** (144 total repository tests) with fault-injection coverage:
     - Scoped cancellation description matching and active cancellation of Workbench sessions.
     - Early cancellation aborts at duration probe, stream probe, command builder, and output stream probe.
     - Preserving staged output as `CACHE ONLY` on null or empty MediaStore responses.
     - Automatic deletion of staged output only upon verified MediaStore commit.
     - Verification of monotonic progress across simulated out-of-order stats timestamps.
     - Unrelated active FFmpeg tasks remain unaffected by Workbench cancellation.

## What shipped — Stage B: Workbench Models & Batch Queue Hardening (2026-11-12)

1. **Output Contract & Format Override Fix (B.1)**:
   - Passed user-selected audio (`_targetFormat`) and video (`_targetVideoFormat`) formats to `WorkbenchQueue.execute()`, preventing default `.mp3` / `.mp4` overrides on batch conversions.
   - Refined `DspOperation` with `producesVideoOutput`, `producesAudioOutput`, and `requiresVideoInput`.
   - Fixed `Extract Audio (Video to M4A)` output verification: correctly asserts audio stream presence (`(outStreams['audio'] ?? 0) > 0`) instead of expecting a video stream on audio output.
2. **Native MediaStore Commit Safety (B.2)**:
   - In `StorageBridge.addToMediaStore()`, explicitly rejected null `openOutputStream(uri)` with `IOException`.
   - Verified that total bytes copied matches source file length (`bytesCopied == file.length()`), preventing 0-byte ghost imports.
   - On copy failure or short write, immediately purges incomplete MediaStore URI before throwing, guaranteeing staged files remain intact for cache recovery.
3. **Queue Lifecycle, Cancellation & Centralized Cleanup (B.3)**:
   - Wired active `_activeQueue` in `TabWorkbench` with an on-screen `CANCEL BATCH` action while running.
   - In `WorkbenchQueue.cancel()`, invokes `FFmpegExecutor.cancelCurrent()`, instantly interrupting running GPU/CPU FFmpeg sessions and skipping remaining queued jobs.
   - Wrapped per-job staging in `try-finally` with automatic cleanup for non-cached temporary outputs, eliminating temporary directory leakage across unhandled exceptions or cancellations.
4. **Monotonic Progress & Test Expansion (B.4)**:
   - Mapped batch progress as `overallProgress = (i + jobProgress) / totalJobs`, guaranteeing strictly non-decreasing progress across multi-file queues.
   - Expanded `test/workbench_queue_test.dart` to cover format override resolution (WAV, FLAC, WebM), M4A extraction classification, MediaStore injection failures with cache preservation, and monotonic progress calculation.
5. **Decoupled Data Structures & Enums (`lib/workbench/workbench_models.dart`)**:
   - Extracted `MixTrack` with path validation, gain, and pan bounds checking and `copyWith`.
   - Extracted `DspOperation` with centralized operation registries (45 total, 20 chainable, 8 video, 3 forensic, 20 preserve), categorization predicates (`isBatchable`, `isVideoOp`, `isForensicOp`, `isPreserveOp`), and lossless-preserving output extension resolver.
   - Extracted `BatchJob` and `BatchJobStatus` enum (`pending`, `running`, `completed`, `failed`, `skipped`) with filename extraction, status summaries, and execution tracking.
   - Extracted `MasteringTarget` with preconfigured presets for streaming (-14 LUFS), broadcast (-23 LUFS), podcast (-16 LUFS), and dynamic compression.
   - Extracted `AudioInspectResult` holding structured volume, silence, ReplayGain, and LUFS scan metrics.
6. **TabWorkbench Refactored**:
   - Replaced all inline batch loops and data models in `lib/tabs/tab_workbench.dart` with `WorkbenchQueue` and `workbench_models.dart`, removing obsolete `_MixTrack` class and duplicated operation lists.

## What shipped — Stage A: Workbench Pure DSP Modularization & Hardening (2026-11-12)

1. **100% Pure Audio DSP Command Builders (`lib/workbench/dsp_builders.dart`)**:
   - Extracted 100% of pure audio filter generators from `lib/tabs/tab_workbench.dart` into `lib/workbench/dsp_builders.dart`, adding 12 new pure builder functions: `buildMonoFoldFilter`, `buildInsertSilenceFilter`, `buildDeclickFilter`, `buildDeEsserFilter`, `buildLimiterFilter`, `buildMcompandFilter`, `buildHighpassFilter`, `buildTrimSilenceFilter`, `buildChorusFilter`, `buildCompandFilter`, `buildDenoiseFilter`, and `buildCompressorFilter`.
2. **Centralized Media Path & Time Parameter Validation**:
   - Added `validateMediaPath` enforcing non-empty and rejecting control characters (`\u0000`, `\n`, `\r`).
   - Added `validateTimeHms` enforcing strict `HH:MM:SS` format.
   - Enforced strict numerical bounds across limiters, compressors, de-essers, gains, pans, and filter parameters.
3. **Hardened Sequential Stream & Metric Parsers**:
   - Replaced naive index-based silence parsing with sequential state-machine parsing handling unclosed `silence_start` at EOF (`end: null`), consecutive starts, and boundary edge cases.
   - Hardened `parseLoudnormMeasurements` against missing `input_i` and malformed JSON payloads.
4. **Automated DSP Unit Test Suite (`test/workbench_dsp_test.dart`)**:
   - Added synthetic 44-byte RIFF/WAVE header + PCM16 sample generator (`createSyntheticWavBytes`) and verified format compatibility.
   - Added realistic integration probe fixtures for `volumedetect` (mean/max volume, headroom, sample count) and `ebur128` (Integrated LUFS, True Peak, ReplayGain delta).
   - Added comprehensive parameter validation and unclosed silence boundary test suites, expanding the test suite from 81 to 99 passing unit tests.
5. **TabWorkbench Refactored**:
   - Replaced all 13 inline filter cases in `_filtersForOperation` with the new builder functions; 100% of audio and video DSP operations in `tab_workbench.dart` now route through pure, standalone builders. Pruned 5 redundant private helper methods.

## What shipped — Phase 39 Audit Code-Fix Integrations (2026-11-12)

1. **OAuth Host Validation (P0 — PR #30)**:
   - Validates pCloud OAuth callback `hostname` against allowlisted `CloudRegion` hosts before saving tokens or sending authenticated API requests, eliminating host substitution risk. Added `test/cloud_host_security_test.dart`.
2. **Atomic Offline Cloud Cache (P1 — PR #24)**:
   - Preserves existing offline pCloud cache on replacement failures by staging to `.part` and atomically renaming upon verification. Added `test/cloud_cache_test.dart`.
3. **Isolated Cloud Download Staging (P1 — PR #25)**:
   - Isolates concurrent pCloud file downloads inside unique OS temporary directories (`Directory.createTemp`), preventing temporary file collision and truncation.
4. **Truncated Download Rejection (P1 — PR #32)**:
   - Enforces `Content-Length` verification on pCloud file downloads; rejects and purges partial media when received bytes do not match expected length.
5. **Fail-Closed Crash Recovery Scanning (P1 — PR #27)**:
   - Propagates platform-channel recovery scan errors rather than rendering an empty list; surfaces explicit error state and sentinel `-1` indicator in UI.
6. **UUID-Backed Recovery Transaction Identifiers (P1 — PR #29)**:
   - Appends random UUIDs to millisecond timestamps in `StorageBridge.overwriteMedia` backup/journal naming (`sov_rec_${time}_${uuid}.bak`), eliminating collision risk across concurrent writes.
7. **Documentation Drift & Dead Code Pruning (P3 — PR #26, #28, #37)**:
   - Pruned dead `SentinelNamingPolicy` wrappers (`stripNoiseAndNormalizeFeat`, `toTitleCase`).
   - Corrected documentation drift across `AGENTS.md`, `ARCHITECTURE.md`, `README.md`, `LICENSES.md`, `SECURITY.md`, and `CONTRIBUTING.md`.
8. **6-Module Architecture Decomposition Blueprint Authored**:
   - Authored `.blueprints/ARCHITECTURE_DECOMPOSITION.md` defining 3-stage modularization plans for `tab_workbench.dart`, `settings_screen.dart`, `ghost_brain.dart`, `tab_grabber.dart`, `main_shell.dart`, and `StorageBridge.kt`.
9. **Permanent Audit Register & Work Orders Landed (PR #31, #33, #34, #35, #36, #38)**:
   - Landed `docs/remote-audit-2026-11-12.md` and five dedicated work-order specifications in `docs/audit-workorders/` covering Python updater rollback safety, pCloud OAuth state/Keystore token storage, voice fallback, media integrity verification, and Sentinel/native dead-ends.

## What shipped — Phase 38.3 PR #23 Review Hardening & Revisions (2026-11-12)

1. **Disallow Blind Trust in `STATUS=COMMITTED`**:
   - In `StorageBridge.recoverPendingOverwrites()`, requires a fresh live stream hash readback from MediaStore matching `srcSha` (`currentDestSha == srcSha`) before classifying any backup as `COMMITTED_PRE_CLEANUP`.
   - If the destination hash does not match or the destination URI is unreadable, it is assigned `DESTINATION_HASH_UNVERIFIED` and retains full operator `RESTORE` and `DISCARD` controls in the UI.
2. **Discard Success & Incomplete Status Validation**:
   - In `SettingsScreen._discardPendingMedia()`, verifies the boolean return of `StorageClient.discardPendingOverwrite()`.
   - Surfaces explicit failure notice (`> ERR: DISCARD INCOMPLETE — UNABLE TO PURGE ALL VAULT FILES.`) if any vault artifact fails to delete, preventing false-positive purge confirmation.
3. **Idempotent Discard Cleanup & Orphan Sweeping**:
   - In `StorageBridge.discardPendingOverwrite()`, logs partial deletion failures and flags orphaned `.meta` files if `.bak` was deleted.
   - In `StorageBridge.recoverPendingOverwrites()`, automatically sweeps orphaned `.meta` files whose corresponding `.bak` binary is absent, guaranteeing recovery idempotence.
4. **Collision-Safe Native Self-Test Files & Guaranteed Cleanup**:
   - In `StorageBridge.runNativeSecuritySelfTest()`, replaced fixed `sov_rec_999999.bak` / `.meta` with collision-safe unique filenames (`sov_rec_selftest_${System.currentTimeMillis()}_$randomSuffix.bak`) wrapped in guaranteed `try-finally` cleanup.
   - Surfaces `discard_cleanup_success` and `discard_atomic_success` verification assertions.
5. **Gated On-Demand Diagnostic Self-Test & Startup Latency Elimination**:
   - Removed unconditional `StorageClient.runNativeSecuritySelfTest()` from `SplashScreen._bootSequence()` in `lib/main.dart`, eliminating the 21-second startup delay.
   - Converted self-test to an on-demand diagnostic action in `SettingsScreen` (`CRASH RECOVERY VAULT` > `RUN SECURITY & INTEGRITY SELF-TEST`) with live structured readout.
   - Verified physical hardware execution on BLU View 5 (`7040016025040287`, Android 14 / API 34): all 9 assertions pass (`all_passed: true`).
6. **Expanded Cryptographic & Recovery Test Suite**:
   - Added unit tests in `test/backup_crypto_test.dart` for unverified destination hash handling (`DESTINATION_HASH_UNVERIFIED`), incomplete discard failure preservation, and cleanup assertions, expanding test suite to 49 unit tests.
   - Added unit tests in `test/backup_crypto_test.dart` for unverified destination hash handling (`DESTINATION_HASH_UNVERIFIED`), incomplete discard failure preservation, and cleanup assertions, expanding test suite to 49 unit tests.

## What shipped — Phase 38.3: Defensive Hardening & Native Test Verification (2026-11-12)

1. **Path Traversal Confinement**:
   - Added `validateRecoveryFile(backupPath: String): File` in `StorageBridge.kt` enforcing canonical directory containment within `context.filesDir/sov_recovery`.
   - Rejects any traversal attempt (`../`, `/data/system/`, external storage) with `SecurityException` and restricts file names strictly to `sov_rec_*.bak`.
2. **Strict Discard Atomicity**:
   - Updated `discardPendingOverwrite` to require both backup binary and metadata file deletion (`bOk && mOk`), preventing misleading partial success reports.
3. **Interrupted Write Disambiguation**:
   - In `overwriteMedia`, commits `STATUS=COMMITTED\nSRC_SHA=$srcSha\nDEST_SHA=$destSha\n` immediately upon successful SHA-256 verification before cleanup.
   - In `recoverPendingOverwrites()`, resolves status to `COMMITTED_PRE_CLEANUP` when destination matches `srcSha` or status is `COMMITTED`.
   - In `SettingsScreen`, surfaces distinct `[PURGE (LANDED)]` action for completed writes, preventing redundant restore confusion.
4. **Bounded PBKDF2 Iterations**:
   - Bounded iteration counts in `decryptConfig` to `1,000 <= iterations <= 2,000,000`. Rejects out-of-bounds or malformed iteration counts with `IllegalArgumentException`.
5. **Native Security Self-Test & Expanded Test Coverage**:
   - Implemented `StorageBridge.runNativeSecuritySelfTest()` exercising envelope format, roundtrip decryption, tamper rejection, iteration bounds, legacy Phase 38 fallback, traversal rejection, and atomic discard.
   - Expanded `test/backup_crypto_test.dart` to 47 unit tests covering self-test integration, `COMMITTED_PRE_CLEANUP` state preservation, and traversal bubbling.
6. **Security Documentation Synchronized**:
   - Updated `SECURITY.md` Section 3 with full documentation of AES-256-GCM authenticated storage, KDF bounding, StrongBox/TEE Keystore mode, the migration role and plaintext caveat of `LEGACY_PHASE38_SECRET`, and the `sov_recovery` safety model.

## What shipped — Phase 38.2: Reliability & Vault Verification Closeout (2026-11-12)

1. **Operator-Visible Crash Recovery Workflow**:
   - Surfaced an actionable **Crash Recovery Vault** UI card in `SettingsScreen` displaying all uncommitted pre-overwrite backups from `sov_recovery`.
   - Implemented 1-tap **RESTORE** to MediaStore with byte-for-byte SHA-256 verification readback, alongside **DISCARD** (purge) actions.
   - Integrated startup scanning in `lib/main.dart` with a top-level amber alert banner in `MainShell` and badge counter on the Settings icon whenever pending backups exist.
2. **Cryptographic SHA-256 Content Verification**:
   - Replaced pure byte-count checks in `StorageBridge.overwriteMedia` with streaming SHA-256 digest computation before and after overwrite.
   - MediaStore destination stream is re-read and hashed directly via `contentResolver.openInputStream(uri)`; overwrite is declared verified only when `destSha == srcSha`.
   - Restore fallback asserts both byte length and `restoredSha == bakSha` before marking restore verified and purging backup files.
3. **Legacy Phase 38 SOV2 Migration Compatibility**:
   - Added seamless decryption support for intermediate Phase 38 `SOV2:<salt>:<iv>:<cipher>` envelopes in `StorageBridge.decryptConfig`.
   - Automatically falls back to `LEGACY_PHASE38_SECRET` (`"SovereignVault::KernelMasterKey::v2"`) if user passphrase is omitted or fails.
4. **Stronger Key Stretching & Explicit KDF Envelope**:
   - Upgraded default PBKDF2 iterations to 250,000 for portable passphrase backups.
   - Parameterized format as `SOV2:P:<iterations>:<salt>:<iv>:<cipher>` with backward compatibility for legacy 10,000-iteration envelopes (`SOV2:P:<salt>:<iv>:<cipher>`).
   - Android KeyStore initialization attempts `setIsStrongBoxBacked(true)` with graceful fallback to standard TEE.
5. **Test Suite Expansion**:
   - Expanded `test/backup_crypto_test.dart` to cover iteration parameter parsing, Phase 38 legacy fallback envelope delegation, vault reports parsing, restore execution with verification, and discard operations.

## What shipped — Phase 38.1: Security & Data Integrity Corrections (2026-11-11)

1. **Elimination of Static Master Secret & Operator Passphrase / Keystore Cryptography (P0 Fixed)**:
   - Completely eradicated static key string `SovereignVault::KernelMasterKey::v2` from `StorageBridge.kt`.
   - Portable backup exports derive AES-256 keys via PBKDF2WithHmacSHA256 (10,000 iterations, 16-byte random salt, 12-byte IV, 128-bit authentication tag) yielding `SOV2:P:` envelopes with an operator-prompted passphrase.
   - Device-local exports lock to Android hardware via `AndroidKeyStore` (`SovereignLocalVaultKey`) yielding `SOV2:K:` envelopes.
2. **Rejection of Silent Fallback & Strict Tag Enforcement (P0 Fixed)**:
   - Eliminated silent XOR fallback on catch blocks in `StorageBridge.kt` and `StorageClient.dart`. Failed encryption throws `StateError` immediately.
   - Decryption of `SOV2:` envelopes bubbles `AEADBadTagException` / authentication errors and never falls back to XOR. Legacy XOR `0x53` is strictly isolated to backwards-compatible migration of legacy payloads that do not start with `SOV2:`.
3. **Fail-Safe Media Overwrite, Verified Byte Restoration & Crash Recovery Vault (P0 Fixed)**:
   - Enforced fail-fast pre-overwrite backup in `StorageBridge.overwriteMedia`: if staging to `.sov_recovery/sov_rec_*.bak` fails or returns 0 bytes, write-back aborts immediately before destination streams open.
   - Destination streams open with `"rwt"` (with `"wt"` fallback).
   - On write failure or short write, restoration is attempted and strictly verified by byte length. If restoration cannot be verified, backup files are retained permanently in the recovery vault and never deleted in `finally`.
   - Added `StorageBridge.recoverPendingOverwrites()` called during `_bootSequence` in `main.dart` to discover and report any previous crash remnants.
4. **Photo Orientation Geometry & Cryptographic Tests**:
   - Added explicit regression test suites in `test/photo_geometry_test.dart` for Orientations 5 (`transpose=0`) and 7 (`transpose=3`).
   - Expanded `test/backup_crypto_test.dart` with passphrase forwarding, `SOV2` envelope enforcement, error bubbling, and authentication tag rejection.

## What shipped — Phase 38: Integration Hardening & Runtime Verification (2026-11-11)

1. **Security & Data Integrity (Authenticated AES-256-GCM Backups & Recovery Protection)**:
   - Migrated configuration and credential backups from legacy XOR `0x53` obfuscation to authenticated AES-256-GCM (`SOV2` envelope format) in `StorageBridge.kt` and `StorageClient.dart` utilizing PBKDF2-HMAC-SHA256 (10,000 iterations), 16-byte random salt, 12-byte random IV, and 128-bit authentication tag.
   - Preserved seamless backward compatibility in `StorageBridge.decryptConfig` and splash boot (`main.dart` `autoImportConfig`) to automatically detect and decode legacy XOR `0x53` backup files.
   - Implemented pre-truncate failure recovery in `StorageBridge.overwriteMedia`: stages `.sov_recover_*.tmp` backup files in the app cache before opening `openOutputStream("rwt")`, and automatically restores the original file content if an I/O error or short write occurs.
2. **Photo Viewer EXIF Orientation**:
   - Integrated native EXIF orientation detection in `_PhotoPageState` (`lib/screens/photos_screen.dart`) via `StorageClient.photoOrientation`.
   - Applied `PhotoEditGeometry` rotation matrices and dimension swaps around `Alignment.center` to ensure portrait and rotated photos render upright in the full-screen photo viewer.
3. **Automated Test Suite Expansion (33/33 Tests Passing)**:
   - Added `test/backup_crypto_test.dart` validating legacy XOR roundtrips, authenticated AES-256-GCM fallback, and error handling for malformed data.
   - Added `test/photo_geometry_test.dart` verifying EXIF orientation matrices (1, 2, 3, 4, 6, 8), dimensions swapping, crop calculation (`largestCenteredRect`), and crop boundary rotations.
   - Added `test/sentinel_policy_test.dart` validating Sentinel Title Case normalization, canonical `ft.` formatting, and illegal filename character sanitization.
   - Added `test/dart_spider_test.dart` verifying bracket noise removal, channel noise stripping, and diacritic preservation for artist names.
   - Expanded unit test coverage from 6 to 33 passing tests (plus 2 Python doctor tests) with 0 static analyzer issues.

## What shipped — PR #8 through #22 Full PR Suite Sweep (2026-11-11)

1. **Workbench Video & Advanced Audio (PR #18, #15)**:
   - 8 new video operations in `TabWorkbench`: frame-accurate Video Trim (Re-Encode), Rotate / Flip (`transpose` chain), Scale / Resize (1080p/720p/480p), Center Crop (16:9, 4:3, 1:1, 9:16), Mute Video (`-c:v copy`), Extract Audio (`.m4a`), Container Convert (`.mp4`/`.mkv`/`.webm`), and Video + Audio Mux with container-safe re-encoding and `-shortest`.
   - Advanced audio: silence splitting, audio op chains, and batch processing queue with `FileType.video`/`FileType.audio` multi-file execution.
2. **Grabber Sources, Auth & FFmpegKit Bridge (PR #14, #12)**:
   - Source badges for 1000+ sites and secure Netscape `cookies.txt` import for age-gated/member content. Fixed `FilePicker.pickFile` API compatibility.
   - Popen redirection of yt-dlp `ffmpeg`/`ffprobe` invocations directly through `com.arthenica.ffmpegkit.FFmpegKit.executeWithArguments` with quiet mode on json probe calls.
3. **Cloud Streaming & Storage (PR #11)**:
   - Native pCloud integration in player: OAuth authentication flow, multi-region API hosts (US/EU), folder tree browser, direct audio streaming, offline song/folder caching to MediaStore Music, and cloud settings card.
4. **Photo Editor Suite (PR #10)**:
   - `PhotoEditorScreen`: interactive crop box, 90° rotation, horizontal/vertical flip, contrast/brightness/saturation/unsharp adjustments, and non-destructive copy-only export to `Pictures/Sovereign Tagger/`. Fixed constructor key, `decodeImageFromList`, and `Matrix4.scaleByDouble`.
5. **Sentinel Policy Migration & Workflow (PR #19, #13)**:
   - Slice 2: full hit-list filtering, sticky status resolution, `RadioGroup` Flutter 3.32 compatibility, and 1-tap handoffs to Forge/Pipeline.
   - Slice 2b: `TitleCleaner.buildSentinelFileName` shape engine, automatic policy formatting across Forge, Pipeline, and Grabber downloads, and the Sentinel screen `MIGRATION` view.
6. **SDK & Pure-Dart Cascade (PR #9)**:
   - Pure-Dart `DartSpider` (`lib/core/dart_spider.dart`) implementing the complete metadata cascade (iTunes, Deezer, MusicBrainz, LRCLIB, Genius) using `dart:io` `HttpClient` only, with parallel experimental toggle in Settings.
7. **Python & Doctor Maintenance (PR #8, #20)**:
   - Hard build-time pins for `yt-dlp==2026.10.26`, `mutagen==1.48.1`, and `lyricsgenius==3.15.0`.
   - Fixed `doctor.py` release string parsing via `from yt_dlp.version import __version__` and added Python unit tests (`test/python/test_doctor.py`).
8. **Documentation, Security & Audits (PR #16, #17, #21, #22)**:
   - Disclosed unencrypted `.bin` export warnings across UI and documentation.
   - Checked in Sentinel Slice 5 auto-apply spec and remote audit report.
   - Updated `AGENTS.md` toolchain and test status.

## What shipped — PR #7 Grabber Choices: Sorted Format Picker, Audio Quality, Embed Toggles, Playlist Range, Player Client (2026-11-11)

1. **Format & Quality Selection (`lib/tabs/tab_grabber.dart`, `android/app/src/main/python/sovereign_yt/bridge.py`)**:
   - Sorted format picker categorized by audio/video resolution and bitrate.
   - User-configurable audio quality preference (best, 320k, 256k, 192k, 128k).
   - Player client override (`android`, `web`, `ios`, `mweb`, `tv`).
2. **Embed Toggles & Playlist Range (`lib/tabs/tab_grabber.dart`)**:
   - Toggles for embedding subtitles, chapters, and rich metadata.
   - Playlist item range selector (`playlist_items` start/end index).
   - Fixed deprecated Flutter 3.31 `Switch.activeColor` -> `Switch.activeThumbColor`.

## What shipped — PR #6 Workbench Audio Suite Core: Readouts, Ducking, New DSP, Multitrack Mix, Wave-Region Delete (2026-11-11)

1. **Audio DSP Suite Core (`lib/tabs/tab_workbench.dart`)**:
   - Live waveform and audio readouts (LUFS, RMS, True Peak).
   - Sidechain audio ducking DSP processor.
   - Multi-track mixing engine with time offsets and gain staging.
   - Waveform region deletion and non-destructive slice excision.
   - Cleaned unused analyzer variables (`meanDb`) and normalized `_MixTrack` constructor.

## What shipped — PR #5 Photo Viewer: MediaStore Grid, Full-Screen Viewer, EXIF, Share/Save (2026-11-11)

1. **Photo Inspection & Viewer (`lib/screens/photos_screen.dart`)**:
   - Device MediaStore photo asset grid and full-screen viewer.
   - Double-tap and pinch-to-zoom interactive viewer using upgraded `Matrix4.translateByDouble(..., 0.0, 1.0)` and `Matrix4.scaleByDouble(scale, scale, 1.0, 1.0)`.
   - Detailed EXIF metadata inspector, image sharing, and direct export.

## What shipped — PR #4 Sentinel Slice 1: Policy Engine, Two-Tier Scanner, Hit-List Store, Scan UI (2026-11-11)

1. **Policy Engine (`lib/core/sentinel_policy.dart`, `lib/core/sentinel_names.dart`)**:
   - Canonical locked filename format `TT - Album Artist · Song Title.ext` with formal name dictionary (`SentinelNames`), Title Case normalization with formal-name exceptions, canonical `ft. X & Y`, and 16-issue audit (`NAME_MISMATCH`, `TITLE_CASE_DRIFT`, `FEAT_NOT_CANONICAL`, `MISSING_*`).
2. **Two-Tier Scanner (`lib/core/sentinel_scanner.dart`)**:
   - MediaStore triage to TagIO verdict with 5% sample of clean files, artwork/lyrics confirmation for candidates only, batches of 10, cancel/resume, incremental skip, and collision detection pass.
3. **Store & Issue Architecture (`lib/services/sentinel_store.dart`)**:
   - Unified `SentinelNamingPolicy` delegation to `SentinelPolicy`, expanded `SentinelIssue` constants (`artistAlbumArtistMismatch`, `nameCollision`, `unreadableTags`, `featNotCanonical`, `titleCaseDrift`), atomic persistence (`sentinel_hits.json`), and status transitions (`in_forge`, `in_pipeline`, `uncompletable`, `ignored`, `stale`).
4. **Scan Screen & Library Entry (`lib/screens/sentinel_screen.dart`, `lib/tabs/tab_library.dart`)**:
   - Dedicated cyber-styled Sentinel screen with severity + issue counts, scan/resume/cancel controls, and 1-tap "Open in Forge" routing; shield action button in `TabLibrary` header.
5. **Test Suite Verification (`test/ghost_foundations_test.dart`)**:
   - Aligned unit tests with the canonical middle-dot formatting and verified clean test suite (`6/6 passed`) and static analysis (`No issues found!`).

## What shipped — Phase 36 Zero-Stub Finalization & Comprehensive Documentation / Licensing Overhaul (2026-11-10)

1. **Complete Documentation Suite & Architectural White Paper**:
   - Overhauled `README.md` into an exhaustive, highly-detailed classified architectural white paper detailing micro and macro mechanics across all 9 subsystems (Grabber, Forge, Pipeline, Workbench, Player, Ghost AI & 3D Hologram, MediaInfo Forensics, Sensory Engine, and Cryptographic Vault).
   - Authored official `LICENSE` (GNU General Public License v3.0, GPL-3.0-or-later) ensuring copyleft compliance with the bundled FFmpeg GPL build.
   - Authored `LICENSES.md` with complete dependency license matrix, neural model governance (Whistle, Whisper, EmbeddingGemma), and F-Droid inclusion pathways (IzzyOnDroid / Self-Hosted repo vs F-Droid main repository).
   - Authored `SECURITY.md` detailing the air-gapped threat model, Scoped Storage safety, zero-telemetry guarantee, and XOR `0x53` encrypted vault format.
   - Authored `CONTRIBUTING.md` outlining the Sovereign Directives: Genesis header, zero-comments-after-line-4, shell gate, explicit git staging, and async UI mounted checks.
   - Updated `.blueprints/ARCHITECTURE.md` with the full modern platform channel and subsystem matrix.
2. **Full-Repository Static Audit & Hygiene**:
   - Audited all 75 source files across Dart, Kotlin, C++, Python, and GLSL.
   - Normalized Genesis headers and ensured zero comments after line 4 across all files.
   - Verified 100% `if (!mounted) return;` coverage across all async `setState` paths.

## What shipped — Phase 35 3D Raymarched Volumetric Hologram Ghost & Blender-MCP Bridge (2026-11-02)

1. **Real-Time 3D Volumetric SDF Hologram Ghost (`shaders/ghost.frag` + `lib/widgets/ghost_avatar.dart`)**:
   - Built a 28-step GPU Signed-Distance-Field raymarcher (~9 KB shader, 0 MB raster APK bloat) rendering a 3D capsule head & 5-fold animated cloth cloak, recessed dark-glass cyber-visor with specular highlights, smooth-blended (`smin`) floating 3D hands that gesture during speech/listening/thinking, full 3D `yaw`/`pitch`/`roll` gaze tracking, inner pulsing soul core, Fresnel rim glow, 3 expressions (`serious`, `happy` cyan crescents + blush, `sarcastic` red smirk), 5-bar oscilloscope waveform mouth, depth-occluded 3D orbital thinking halo, listening sonar rings, spiral materialize/dematerialize beam, and RGB slice glitch (G50).
   - `GhostAvatar` caches `FragmentProgram.fromAsset('shaders/ghost.frag')` once across instances with an upgraded 2.5D cyber-visor + floating-hands `CustomPainter` fallback, spring-damped `poke()` recoil, `AudioService.isPlaying` subtle beat sync, shaped vector wisps, and battery-safe ticker throttling.
2. **Full `GhostBrain` Emotion/Laugh/Hide & Live `VoicePhase` Wiring (`lib/widgets/ghost_chat_overlay.dart`, `GH8`) + `blender-mcp`**:
   - Wired `GhostReply.tone` -> `setEmotion`, `GhostReply.laugh` -> `glitchLaugh`, `GhostReply.hide` & red power close -> 3D vortex `dematerialize()` before persisting `GhostSettings.setVisible(false)`, live `VoiceInput.phase` -> `GhostMood.listening` / `GhostMood.thinking`, tap -> `poke()`, and avatar size `64 -> 76`.
   - Registered `"blender-mcp"` (`C:\GitHub\antigravity-blender-mcp\src\mcp-server\dist\index.js`, `127.0.0.1:9876`) in `C:\Users\612co\.gemini\config\mcp_config.json` alongside `"rea"` so live Blender MCP tools are ready whenever Blender's addon socket is active.
3. **`EmbeddingGemma-300M` Download Fix (`lib/core/embedding_model.dart` + `lib/screens/settings_screen.dart`, `EG1`/G51)**:
   - Fixed 3 stacked causes of Hugging Face download failures: (a) corrected case-sensitive upstream `.tflite` filename from `embeddinggemma-300m_seq256_mixed-precision.tflite` -> `embeddinggemma-300M_seq256_mixed-precision.tflite`, (b) replaced default `HttpClient` redirect following with manual hop resolution (`followRedirects = false`) that sends `Authorization: Bearer <token>` only to `huggingface.co` and strips it on pre-signed `xethub.hf.co`/S3 CDN redirects, and (c) added automatic zero-token fallback to the ungated `litert-community/embeddinggemma-300m` ModelScope mirror + 1-tap license/token links and `.bin` config backup/restore for `hf_token` (confirmed installed on Moto G).
4. **Ghostbot Chat History Red `ErrorWidget` Fix (`lib/widgets/ghost_chat_overlay.dart`, `GH9`/G52)**:
   - Fixed `_ChatMessage.copyWith` retaining a disposed `ValueNotifier<String>` (`typingTextNotifier`) after `_typewriterSay` completed, which threw `FlutterError: A ValueNotifier<String> was used after being disposed` inside `ValueListenableBuilder` and replaced previous responses with Flutter's red `ErrorWidget` box. Cleared `typingTextNotifier` in `_finalizeTypingMessage` (`try/finally`), deferred `notifier.dispose()` to `addPostFrameCallback`, gated `ValueListenableBuilder` on `msg.isTyping && msg.typingTextNotifier != null`, and promoted sanitized `_sessionMessages` so previous responses persist across minimize/reopen and visibility toggles.
5. **Android 15 Impeller GLES `BLASTBufferQueue` (`max:5 + 2`) Fix (`MainActivity.kt`, `cyber_backdrop.dart`, `ghost_chat_overlay.dart`, `ghost_avatar.dart`, `shaders/backdrop.frag`, `shaders/ghost.frag`, `GH10`/G53)**:
   - Identified exact upstream Flutter engine bug `#189359` (`[Impeller] BLASTBufferQueue overflow on Android 15 with OpenGL backend`) where `FlutterSurfaceView` overflows `SurfaceView`'s `BLASTBufferQueue` (`max:5 + 2`) on Vulkan-denylisted Adreno/Mali GPUs; overrode `MainActivity.getRenderMode(): RenderMode = RenderMode.texture` so Flutter renders via `FlutterTextureView` (`SurfaceTexture` synchronized with `ViewRootImpl` Choreographer VSync, eliminating `SurfaceView`'s `BLASTBufferQueue` completely).
   - Replaced 90/120Hz `createTicker` loops in `CyberBackdrop` and `GhostAvatar` with `TickerMode`-gated `Timer`s (`45ms`/22fps backdrop, `33ms` active / `50ms` idle Ghost so idle VSyncs never call `PlatformDispatcher.scheduleFrame()`), removed `BackdropFilter(sigma: 16)` + steady-state `Opacity` from `GhostChatOverlay._buildPanel`, cached `ColorFiltered` scene art in `RepaintBoundary`, replaced `sin()` hashes in `shaders/backdrop.frag` with sin-free ALU `fract` hashing, and added analytical sphere culling to `shaders/ghost.frag`.
6. **`EmbeddingGemma-300M` Post-Download Ghostbot Lockup Fix & Live Self-Test (`EmbeddingGemmaBridge.kt`, `SentencePieceTokenizer.kt`, `embedding_service.dart`, `ghost_brain.dart`, `ghost_vector_index.dart`, `model_lifecycle.dart`, `settings_screen.dart`, `EG2`/G54)**:
   - Fixed the 71-pass synchronous CPU lockup where `GhostBrain.respond()` ran 48 exemplar + 23 KB + full-library 300M-parameter transformer forward passes synchronously on the chat path after downloading `EmbeddingGemma-300M`: ordered lexical `_crossTabAutomation` and deterministic `_command` ahead of semantic fallback, made `_activeExemplarsForEngine`/`_activeKbVectorsForEngine`/`GhostVectorIndex.search` non-blocking (background `unawaited(ensureIndexed)` with `chunkSize = 4` + 25ms yield), added 6s timeout on `embedText`, reused direct `ByteBuffer`s in `EmbeddingGemmaBridge.kt`, and added native `selfTest` cosine/latency verification + SnackBar confirmation on download/activation.
7. **Android API 36 `just_audio` `AndroidEqualizer` NPE Fix (`lib/core/playback_fx.dart` + `MainActivity.kt`, `FX1`/G55)**:
   - Fixed `PlatformException(java.lang.NullPointerException: Attempt to invoke virtual method 'short android.media.audiofx.Equalizer.getNumberOfBands()' on a null object reference)` on Moto G Android API 36 (which aborted `setAudioSources` on startup and broke ReplayGain boost) by removing `just_audio`'s `AndroidEqualizer` from `AudioPipeline` and attaching hardware `Equalizer` + `LoudnessEnhancer` via native `com.sovereign.tagger/audio_fx` in `MainActivity.kt` once `player.androidAudioSessionIdStream` emits a valid `sessionId > 0`.
8. **Cross-Tab Automation Stubs & Comment Cleanup (`tab_workbench.dart`, `tab_forge.dart`, `tab_grabber.dart`, `ghost_world.dart`, `ghost_commands.dart`, `GH11`)**:
   - Wired `GhostCommandBus.pendingWorkbenchCommand` in `TabWorkbench` (mounts active file and selects Whisper AI or auto-runs EBU R128 ReplayGain scan), handled `ForgeAutoTask.fullAutoTagAndLyrics` in `TabForge._onPendingRequest`, wired `autoDownloadTopResult` in `TabGrabber._onGhostGrabCommand` (removing the malformed raw channel call in `ghost_world.dart`), and stripped stray inline comments across `lib/` per `RULES.md` §2.2.

## What shipped — Phase 34 Sovereign MediaInfo Deep Inspector, Audio Forensics & Lossless FFmpeg Surgery (2026-11-02)

1. **`MediaInfo`-Class Deep Container & Stream Inspector (`lib/core/media_forensics.dart` + `lib/screens/media_inspector_screen.dart`)**:
   - Inspects container format/profile, exact byte size, duration, bitrate mode (`CBR`/`VBR`), ISO BMFF `moov`-before-`mdat` `FastStart` streamability (`RandomAccessFile` header walk, G49), audio/video/subtitle streams (`codec`, `profile`, `sampleRate`, `bitDepth`, `sampleFormat`, `channelLayout`, `CFR`/`VFR` FPS, `SAR`/`DAR`, `pix_fmt`, HDR color space/transfer/primaries), chapters, embedded cover dimensions (`PNG`/`JPEG`/`WEBP`), and full tag maps.
   - Four interactive views (`TREE`, classic aligned `MEDIAINFO TEXT`, `RAW FFPROBE JSON`, `FORENSICS`), 1-tap clipboard copy, `.txt`/`.json` export to Android `Downloads` (`StorageBridge.exportTextToDownloads`), and `FilePicker` mounting for any external file.
2. **FFmpeg Audio Forensics & Fake-Lossless Detector**:
   - Runs full bitstream decode health check + `astats` + `ebur128=peak=true` (Integrated LUFS, LRA, True Peak `dBTP`, Crest `DR`, DC offset, NaN/Inf count, effective active bit depth catching 16-bit audio zero-padded into 24-bit containers) + `16.2 kHz` / `19.5 kHz` highpass spectral shelf probes to flag upsampled MP3s disguised as FLAC/WAV, paired with a pinch-zoom `1600x800` logarithmic `showspectrumpic` spectrogram (and fixed `TabWorkbench`'s `showspectrogrampic` typo).
3. **Lossless `-c copy` Container Surgery & Full-App Entry Points**:
   - Pure stream-copy (`-c copy`, zero generation loss) audio extractor, MP4/M4A `+faststart` optimizer, and lossless chapter splitter (with in-place `TagIO` chapter numbering + `probeStreams` verification -> `MediaStore`), accessible from `TabLibrary`, `TabForge`, `TheaterScreen`, `TabWorkbench`, and `GhostBrain` (`"open mediainfo"`, `"what bitrate/codec is this?"`, `"is this true lossless?"`).

## What shipped — Phase 33 Native EmbeddingGemma Engine & Semantic Library/LRC Vector Index (2026-11-02)

1. **Native Google AI Edge `LiteRT` + Pure-Kotlin SentencePiece Bridge (`com.sovereign.tagger/embeddings`)**:
   - Added `com.google.ai.edge.litert:litert:1.4.0` (`arm64-v8a` + `x86_64`, XNNPACK 4-thread CPU) in `android/app/build.gradle` + keep rules in `proguard-rules.pro`.
   - Implemented `SentencePieceTokenizer.kt` (pure-Kotlin `sentencepiece.model` protobuf parser for Gemma BPE + Unigram with `<0xXX>` byte fallback) and `EmbeddingGemmaBridge.kt` (serialized worker thread, `MappedByteBuffer` read-only model mmap, asymmetric Gemma prompt templates, 256-D Matryoshka truncation + L2 normalization), wired into `MainActivity.kt` (`onTrimMemory` + `onDestroy`).
2. **External Model Manager & Moto G RAM Lifecycle (`EmbeddingModel` + `ModelLifecycle`)**:
   - `lib/core/embedding_model.dart` stages `embeddinggemma-300m_seq256_mixed-precision.tflite` + `sentencepiece.model` into `${getApplicationSupportDirectory()}/embedding_gemma/` (0 MB APK bloat, safe from `SettingsScreen._purgeCache`), supporting both Hugging Face download (with optional Read Token for Gemma license gate) and local `FilePicker` `.tflite`/tokenizer import via atomic `.part` rename (G39).
   - `lib/core/model_lifecycle.dart` + `lib/core/ffmpeg_executor.dart` (`beforeExecuteHook`) unload the native interpreter after 5 min idle on `< 6 GB` RAM devices (`15 min` on `>= 6 GB`), on Android `onTrimMemory`, and before FFmpeg/Whisper jobs when free RAM `< 650 MB`.
3. **Persistent Library & LRC Vector Index (`GhostVectorIndex`) + `GhostBrain` v2.1 + `SettingsScreen` UI**:
   - `lib/services/ghost_vector_index.dart` indexes library tracks + `GENRE`/`COMMENT`/`LYRICS` tags + `.lrc`/`.txt` sidecars into `ghost_vectors.bin` (`GVEC` binary format, `engineId` vector-space locked per G48).
   - Upgraded `lib/core/embedding_service.dart`, `lib/services/ghost_brain.dart`, `lib/services/ghost_world.dart`, `lib/widgets/ghost_chat_overlay.dart` (`GEMMA`/`256D` reactive badge), and `lib/screens/settings_screen.dart` (`> GHOSTBRAIN EMBEDDINGGEMMA [256-D AI]` kernel & vector index card).

## What shipped — Phase 32 Hybrid Animated Cyberpunk Backdrops (2026-11-02)

1. **Tab Root Occlusion Fix (G47)**:
   - Discovered all 5 main tabs (`TabGrabber`, `TabForge`, `TabPipeline`, `TabWorkbench`, `TabLibrary`) had opaque `Colors.black` root wrappers that completely hid `MainShell`'s `CyberBackdrop`.
   - Switched root wrappers to `Colors.transparent` (preserving exact widget wrapper types for `AnimatedTabStack` per G32) and added dark-glass (`0.80–0.82`) fills on cards, headers, and input fields.
2. **6 Themed 9:16 Cyberpunk Scene Assets + GPU Accent Tinting**:
   - Packaged `assets/backgrounds/bg_{grabber,forge,pipeline,workbench,library,theater}.webp` and registered `assets/backgrounds/` in `pubspec.yaml`.
   - `CyberBackdrop.accentColorFilter` applies a Rec.709 perceptual luminance `ColorFilter.matrix` on the GPU so every background scene (plus `SplashScreen`'s `splash-screen-bg.png`) dynamically recolors to `SovereignState.accentColor` in real time, animated with 30fps Ken Burns drift, breathing glow, and 420ms crossfades.
3. **6-Variant Additive GPU Shader & Full-Screen Coverage**:
   - Expanded `BackdropVariant` with `library` and updated `shaders/backdrop.frag` (`BlendMode.plus` additive compositing) for all 6 variants (`grabber` packet rain, `forge` crucible sparks, `pipeline` laser scan + data streaks, `workbench` dual-harmonic oscilloscope, `library` archive halo + motes, `generic` concentric soundwave rings).
   - Mounted `CyberBackdrop` on `TheaterScreen` (`tab_player.dart`), `SettingsScreen`, `PlaybackEngineScreen`, `EqPresetsScreen`, and `LyricSyncScreen`.
4. **Settings Toggle & Live Intensity Slider**:
   - Added `FeedbackSettings.backdrop` (`ANIMATED CYBER BACKDROP` toggle, stops ticker when disabled) and `FeedbackSettings.backdropIntensity` (`20%–150%` live slider) to `SettingsScreen` + `.bin` vault backup/restore.

## What shipped — Phase 31 Whistle Native STT Migration + Audio Focus Resume (2026-10-15)

Implemented Cactus Compute's **Whistle** offline STT model as Sovereign Tagger's preferred speech engine, completely independent of FFmpeg:

1. **Whistle Native Engine & NDK/JNI Setup**:
   - Upstream headers: `android/app/src/main/cpp/needle.h` from Cactus Compute Needle 3.
   - JNI bridge: `android/app/src/main/cpp/sovereign_whistle.cpp` wrapping `needle_load`, `needle_transcribe`, with mmap, error translation, and `#if WHISTLE_ARM64_SUPPORTED` ABI switch.
   - CMake: `android/app/src/main/cpp/CMakeLists.txt` links prebuilt `libneedle.a` on `arm64-v8a`; compiles stub library on `x86_64` returning `UNSUPPORTED_ABI` error code (G44). Both `arm64-v8a` and `x86_64` targets compiled and linked into `.so` shared libraries without warnings.
   - Kotlin bridge: `android/app/src/main/kotlin/com/sovereigntagger/WhistleBridge.kt` with dedicated single-threaded serialized inference executor, WAV PCM16 to Float32 sample normalization in [-1.0, 1.0], JSON transcript parsing.
   - MethodChannel: `com.sovereign.tagger/whistle` wired into `MainActivity.kt`.

2. **Model Assets & Provenance**:
   - Verified upstream assets:
     - `android/app/src/main/jniLibs/arm64-v8a/libneedle.a` (2,183,854 bytes, SHA-256: `9be8b4b185ef1710f57179e3cc68835ac67fca8470bdbc6915d6966646d95385`, Apache 2.0).
     - `assets/models/whistle.cact` (16,919,407 bytes, SHA-256: `b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb`, Apache 2.0).
   - Created `lib/core/whistle_model.dart` for asset extraction to app-private cache with lazy download fallback.
   - Updated `lib/core/speech_to_text.dart`: `WhistleEngine` preferred when native library is loaded, keeping `WhisperFfmpegEngine` available for fallback/testing. Keyword biasing configured with domain vocabulary (`WhistleKeywords`).

3. **Voice Lifecycle & Auto-Stop Repair**:
   - `PcmRecorderBridge.kt`: `audioRecord.stop()` is now called *first* to cleanly unblock the read loop before `recordingThread.join(1500)`, verifying `writerFinished` before writing the WAV header. Synchronized locks added against concurrent operations.
   - `lib/core/voice_input.dart`: Expanded `VoicePhase` enum (`idle, preparing, listening, stopping, modelLoading, transcribing, completed, failed, canceled`), added broadcast `Stream<String> get onTranscript` to deliver both manual and 12-second auto-stop results to the Ghost query field.

4. **Audio Focus & Notification Resume**:
   - `lib/core/audio_handler.dart`: Updated `SovereignAudioHandler` with `session.interruptionEventStream` and `session.becomingNoisyEventStream` listeners: captures effective pre-duck volume (`_preDuckVolume = player.volume`), ducks volume to 25% of pre-duck volume (`_preDuckVolume * 0.25`), and restores exact `_preDuckVolume` upon completion. Pauses on transient loss and automatically resumes on interruption end only if `wantPlaying` was true (manual pause prevents auto-resume); pauses on headphone disconnect.
   - `lib/screens/main_shell.dart`: Created player with `handleInterruptions: false` to avoid dual-controller conflict (G45) and exposed `wantPlaying` getter to `TransportCallbacks`.

5. **BLASTBufferQueue & Ghost Chatbot Jank**:
   - `lib/widgets/ghost_chat_overlay.dart`: Decoupled typewriter loop from `setState` by using `typingTextNotifier` on `_ChatMessage` with `ValueListenableBuilder<String>` (G46); throttled typing SFX (`SfxId.type`) and ghost talk animation to every 4th character.

Gate: `flutter analyze --no-pub` -> `No issues found!`. `flutter build apk --debug --target-platform android-arm64` -> `app-debug.apk` built.
