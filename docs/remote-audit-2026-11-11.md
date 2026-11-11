# Critical Audit — Sovereign Tagger remote

**Date:** 11 November 2026
**Base:** main `15e866ae` (33,055 lines, `lib/` + Android)
**Scope:** main plus all 8 open draft PR branches (#8–#15), each judged against main.
**Method:** read-only. Fresh clone, every finding verified by reading the surrounding code, not by grep alone. No Flutter/Dart toolchain exists on the build VM, so `flutter analyze` and `flutter test` could not be run and no device behaviour was verified.

## Counts

- **Stubs in code: 0.** Zero `UnimplementedError`, zero `TODO`/`FIXME`/`XXX`/`HACK` (word-boundary grep), zero empty callbacks, zero "coming soon" screens. The Phase 36 "zero-stub" claim holds for code.
- **Errors: 6** (2 blocker, 4 should-fix).
- **Dead ends: 9** (dead code, dead handlers, dead helpers, stale docs).
- **Security: 2 notes** (1 misleading "encryption" label, 1 plaintext-token pattern).
- **PR conflicts: 2 real** (both small, mechanical), out of 28 pairs.

## BLOCKER

### B1 — No automatic Whisper fallback, and the README still advertises one

`VoiceInput` (`lib/core/voice_input.dart:205-215, 232-248`) fails closed: if Whistle `prepare()` or `transcribe()` throws, it returns null with `MODEL LOAD FAILED` / `TRANSCRIBE ERROR` — no retry with the other engine. `VoiceInput.useEngine()` (`voice_input.dart:70-77`) exists but has **zero callers in `lib/`** and no Settings UI, so Whisper is reachable only in code, never by the user. Meanwhile `README.md:151` (diagram) says "Fallback: Whisper ggml-base" and §4.4 presents Whisper as the secondary engine. This is audit finding #2 from 3 Nov, still open. Fix: either wire a real fallback in `VoiceInput` (try Whistle, fall back to Whisper on failure) or correct the README to say Whisper is manual-only.

### B2 — Photo viewer mis-displays mirrored photos

`StorageBridge.applyExifRotation` (`android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt:264-281`) handles only ROTATE_90/180/270; orientations 2/4/5/7 (flips/transposes) fall through to `else -> 0f`, so mirrored photos render wrong in the viewer. PR #10's editor works around it with a full 8-value map, but the viewer stays wrong. Fix: apply the same 8-value map in `applyExifRotation`.

## SHOULD-FIX

### S1 — `SentinelStore.sentinelScan` is dead code, and it is the weaker of two scan entry points

`lib/services/sentinel_store.dart:576-660` has **zero callers** in `lib/` + `test/` (verified). The screen uses `SentinelScanner.run` (`lib/core/sentinel_scanner.dart:152`, two-tier MediaStore→TagIO verdict). The store's version audits only MediaStore-provided fields — it never reads real tags, so if anyone ever wires it, it will produce false `MISSING_*` issues for files whose MediaStore columns are empty but whose tags are fine. Fix: delete it, or delete the scanner and wire the store's — pick one; do not keep both. Note: PR #13 wires the store's *transition* methods but not `sentinelScan`, so this stays dead after #13 merges.

### S2 — Four more dead store methods on main

`sentinelOpenInForge`, `sentinelSendToPipeline`, `sentinelMarkUncompletable`, `sentinelIgnore` (`sentinel_store.dart:665-710`) — zero callers on main. PR #13 wires all four, so this resolves on merge; flagging only so nobody "fixes" it twice.

### S3 — Three dead Kotlin channel handlers (no Dart caller)

`getDoctorRegistry` (`MainActivity.kt:203`), `describeMedia` (`:341`), `scanFile` (`:359`). Consequence: `doctor.py:get_registry` is reachable only through the dead `getDoctorRegistry` handler. Fix: delete the handlers (and `get_registry` if nothing else uses it) or wire a Dart caller. Note: `similarity` at `EmbeddingGemmaBridge.kt:470` looks similar but is a task-dispatch string, not a channel method — not dead.

### S4 — `SentinelNamingPolicy.stripNoiseAndNormalizeFeat` + `toTitleCase` are dead

`sentinel_store.dart:264-272`, zero callers. The live path calls `SentinelPolicy` directly (`sentinel_scanner.dart:246,356,388,431,459`). The wrapper itself is a clean delegation (no drift — PR #4 did this right), but these two extra methods are unused. Fix: delete them.

### S5 — `GhostMemory` / `GhostPlayRecord` have zero app callers

`lib/core/ghost_memory.dart` is referenced only by `test/ghost_foundations_test.dart:83-94`. Play history exists as a class, but nothing records a play — GhostBrain T4 (play history) is not actually wired in the app. Fix: wire `recordPlay` into the player, or delete the class.

### S6 — `CloudSource` interface is dead on main

`lib/core/cloud_source.dart` — the abstract class has no implementation and no app caller; only `test/ghost_foundations_test.dart` references its enums. PR #11 implements it. Resolves on merge.

### S7 — `doctor.py` reports the `yt_dlp.version` module, not a version string

`android/app/src/main/python/sovereign_yt/doctor.py:90`: `getattr(yt_dlp, 'version', ...)` returns the `yt_dlp.version` submodule (not callable, so the `callable()` guard at :91 doesn't fire), and `:109` stringifies it into `"ytdlp_version": "<module 'yt_dlp.version' ...>"`. PR #8 does not fix this. Fix: use `yt_dlp.version.__version__` with the `__version__` fallback first.

### S8 — AGENTS.md is stale in three places

- `:104` "No `test/` suite in repo" — `test/` exists with 2 test files (`ghost_foundations_test.dart`, `tagger_web_screen_test.dart`).
- The "win32 pair" wall (Phase 27.1): claims `file_picker <12` / `wakelock_plus 1.5.2`, but `pubspec.yaml` has `file_picker ^13.1.0` (lock: 13.1.0) and `wakelock_plus ^1.8.1`, and the code already uses the file_picker 13 static API (`FilePicker.pickFiles`, 12 call sites) — the migration the wall says is a "dedicated session" already happened.
- Toolchain quirks: claims `compileOptions 1.8`, but `android/app/build.gradle:32-34` already reads Java 17.
Fix: update AGENTS.md to match the executable files.

## SECURITY / PRIVACY

### SEC1 — The `.bin` vault backup is not encrypted; the UI says it is

`settings_screen.dart:96-100` `_encrypt` is single-byte XOR `0x53` + base64; `main.dart:111-115` decodes it the same way. The backup contains `genius_key`, `acr_host`, `acr_key`, `acr_secret`, `hf_token` (`settings_screen.dart:110-116`) and is exported to Downloads as `sovereign_config.bin` with the message "BACKUP COMPLETE ✓ Encrypted binary written to Downloads." Anyone with the file recovers all five keys trivially. Fix: relabel it honestly ("obfuscated backup") or switch to real encryption (e.g. EncryptedSharedPreferences / Tink). Severity: should-fix — the keys are the user's own and the file stays on their device, but the label is a misrepresentation.

### SEC2 — Tokens live in plaintext SharedPreferences

pCloud token in PR #11 (`cloud_settings.dart:111` `prefs.setString('pcloud_token', ...)`) follows the app's existing pattern (HF/Genius/ACR tokens are also in prefs + the `.bin` backup), so this is not a new hole — but there is no encrypted storage anywhere in the app. Note only.

**Clean:** no hardcoded secrets anywhere in `lib/`, Android, or Python (grep); no token/cookie/password logging in main or in any PR diff (PR #14's diff has zero `print`/`debugPrint`); HF token is sent only to `huggingface.co` (`embedding_model.dart:347`).

## Verified clean (checked, not assumed)

- All 14 `MethodChannel`/`EventChannel` names match exactly Dart↔Kotlin; every Dart-invoked method has a Kotlin handler.
- No deprecated Flutter APIs: the `activeColor` hits are all `Slider`/`CheckboxListTile`, not `Switch` (PR #7 fixed the one `Switch` case).
- No direct `FFmpegKit.execute` in Dart — the AGENTS.md law holds on main.
- All pubspec deps are imported; all 7 screens are reachable from UI/Ghost; no write-only SharedPreferences keys (`fx_backdrop_*` are written via `FeedbackSettings` const keys).
- `bridge.py` now really does pass `player_client=android,web,ios` (`bridge.py:59,219`) — the old stale AGENTS.md claim is fixed.
- CI (`dart.yml`) runs `flutter test` when test files exist; the red-at-`Install dependencies` failure since 25 Oct 2026 is pre-existing and unchanged by any of this.

## PR-branch findings (each judged against main)

- **#8 python-pins** — clean. Pins verified, `doctor.py` reports `pinned_versions`. Does not fix S7 above. No conflicts with any other PR (touches `build.gradle`/`doctor.py`/`docs/` only).
- **#9 sdk-s0s1** — clean, with disclosed deltas. Wiring verified: `metadata_sources.dart` flag-gates all three calls (`search`/`fetchLyrics`/`fetchArtworkBase64`) behind `dart_spider`, default OFF, Python path untouched. One risk carried as disclosed: Genius HTML extraction uses a non-greedy per-container regex (`dart_spider.dart:616`) — nested-div containers may truncate lyrics.
- **#10 photo-editor** — clean. `StorageBridge.photoOrientation` / `exportPhotoFileToPictures` mirror existing patterns; EXIF dropped on export by design (orientation baked in). Confirms B2 (the viewer bug) rather than causing it.
- **#11 pcloud** — clean, no `debugPrint` in the diff. Notes: token in plaintext prefs (SEC2); token-paste field is plain text; `testConnection` lists drive root, not the music root; upload-back dropped as decided. No conflicts.
- **#12 ffmpeg-chaquopy** — sound, one quirk. The `Popen.run` patch returns the correct 3-tuple `(stdout, stderr, rc)` and fails closed when the bridge is missing; `capabilities()` is idempotent. Two notes: (1) `FFmpegKit.getOutput()` merges stdout+stderr, and the patch copies that merged string into *both* stdout and stderr slots — any yt-dlp code that reads stderr gets stdout content too; (2) the patch intercepts *any* `ffmpeg`/`ffprobe` argv process-wide, not just yt-dlp's. Also a deliberate, documented deviation from the AGENTS.md FFmpeg law (sync `executeWithArguments` from Python on a background thread) with the AGENTS.md note updated.
- **#13 sentinel-slice-2** — clean. Verified the wiring: `onSendToPipeline` is assigned in Pipeline's `initState` and nulled in `dispose`; the screen handles the not-yet-opened case explicitly (`'ERR: PIPELINE HANDOFF NOT AVAILABLE — OPEN THE PIPELINE TAB ONCE, THEN RETRY'`). Stickiness fix and `sentinelMarkUncompletable` signature (String reason consts) check out.
- **#14 grabber-sources** — clean. Cookie file stored app-private, validated, removable; no cookie contents logged or displayed. Note: Generic-extractor catch-all means any http URL gets a DIRECT LINK badge even for sites yt-dlp can't handle; failure surfaces at FETCH FORMATS.
- **#15 audio-advanced** — clean, refactor verified order-preserving for the direct path. Filter strings compared main-vs-branch: the only difference is `resampleFilter` moved from `filters.add` to `filters.insert(0, ...)`; final order stays `[loudnorm, resample, opFilters]` in both (main `:1122` and branch `:1305` both `insert(0, loudnormFilter)`). Chain-path ordering not fully verified — new code, needs the device smoke, not a regression.

## Pairwise PR-conflict table (28 pairs; only file-overlapping pairs listed)

| Pair | Result |
|---|---|
| #11 pcloud × #9 sdk-s0s1 | **CONFLICT** — `lib/screens/settings_screen.dart:94-104`: both add lines inside the same `_loadKeys` block (pCloud controller loads vs `_dartSpider` flag load). Small, mechanical: keep both. |
| #12 ffmpeg-chaquopy × #14 grabber-sources | **CONFLICT** — `lib/tabs/tab_grabber.dart:1444-1450`: same help-text `_b(...)` string; #12 rewrites the ffmpeg sentence ("runs it through the bundled FFmpegKit library"), #14 keeps the old sentence and adds a COOKIE LOGIN section right after. Small, mechanical: keep #12's sentence + #14's section. `bridge.py` merges clean. |
| #10 photo-editor × #11 pcloud | Clean (both touch `MainActivity.kt`, different regions) |
| #10 photo-editor × #14 grabber-sources | Clean (`MainActivity.kt`, different regions) |
| #11 pcloud × #14 grabber-sources | Clean (`MainActivity.kt`, different regions) |
| #11 pcloud × #13 sentinel-slice-2 | Clean (`main_shell.dart`, different regions) |
| All other pairs | No shared files — no conflict |

Suggested merge order: merge #12 before #14 and #11 before #9 (or the reverse in each pair), resolving the two one-hunk conflicts; every branch is based on main `15e866ae`, so each subsequent merge wants a rebase. #8 and #15 conflict with nothing.

## What the audit could NOT check

- No Flutter/Dart toolchain on this VM: `flutter analyze` and `flutter test` could not be run; the 2 test files' pass/fail is unverified.
- No device behavior: Whistle on the Moto G, EXIF orientations on real photos, cookie import on Android 13/14, pCloud OAuth flow, `getfilelink` URLs through just_audio.
- No CI run observed; Dart-vs-Kotlin parity was verified statically only.
- Whether `sentinelScan` was ever invoked dynamically (no static callers exist; dynamic invocation is not used anywhere in the codebase).
