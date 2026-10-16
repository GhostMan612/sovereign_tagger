# SESSION_HANDOFF.md — Sovereign Tagger v2
> Read this FIRST every session. Updated Phase 31 complete 2026-10-15.

## DOCUMENT MAP — cold-start hooks (read top-to-bottom)

| # | File | Holds | When to read |
|---|------|-------|--------------|
| 0 | `AGENTS.md` (root) | Auto-injected into every session by opencode — the true guaranteed entry point; compact ramping guide + laws table | automatic |
| 1 | `.blueprints/RULES.md` | **CANONICAL** operating law: read-only paths, git discipline, §3 technical laws incl. **§3.1 POWERSHELL MOJIBAKE BAN** | EVERY session, before any edit |
| 2 | THIS FILE | Latest session deltas (\"What shipped\"), Next actions queue, Open decisions, toolchain notes | EVERY session |
| 3 | `.blueprints/CURRENT_STATE.md` | Verified per-file architecture map (51 Dart files), known-issue registry (`K/A/V/GH/CS/EQ/PW/AR/FX/UI/WS` rows — check before touching grabber/pipeline/workbench/player/ghost/settings), frozen-ceiling toolchain notes | before writing code |
| 4 | `.blueprints/ROADMAP.md` | Phase tracker (Phases 0–31, `[x]/[~]/[ ]/[-]`) with per-phase verification gates | when planning/phases |
| 5 | `.blueprints/BLUEPRINTS.md` | Design specs + **append-only GOTCHA REGISTRY** (SPEC-S* ids, G1–G46) | before novel features |
| 6 | `.blueprints/ARCHITECTURE.md` | Boot flow + data-flow reference diagrams | structural changes |
| — | `README.md` (root) | Operator-facing capabilities/API-keys/maintenance docs (kept synced with reality) | release/closeout/doc work |
| — | `pubspec.yaml`, `android/app/build.gradle`, `gradle.properties` | **Executable truth**: frozen dep ceiling pins, `SOVEREIGN_TAGGER.apk` name, debug-signing fallback, chaquopy/python version, builtInKotlin opt-out | any dependency/signing/build question |

Conflict law: RULES.md > other docs; executable files > prose.
Session-end law: update rows 2–4 every session (+ row 5 when a new gotcha is learned).

## Where we are

**Date:** 2026-10-15
**Phase:** 0–31 implementation complete; `flutter analyze --no-pub` -> `No issues found!`.
**Branch:** `main` is the single canonical branch.

## What shipped — Phase 31 Whistle Native STT Migration + Audio Focus Resume (2026-10-15)

Implemented Cactus Compute's **Whistle** offline STT model as Sovereign Tagger's preferred speech engine, completely independent of FFmpeg:

1. **Whistle Native Engine & NDK/JNI Setup**:
   - Upstream headers: `android/app/src/main/cpp/needle.h` from Cactus Compute Needle 3.
   - JNI bridge: `android/app/src/main/cpp/sovereign_whistle.cpp` wrapping `needle_load`, `needle_transcribe`, with mmap, error translation, and `#if WHISTLE_ARM64_SUPPORTED` ABI switch.
   - CMake: `android/app/src/main/cpp/CMakeLists.txt` links prebuilt `libneedle.a` on `arm64-v8a`; compiles stub library on `x86_64` returning `UNSUPPORTED_ABI` error code (G44).
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
   - `lib/core/audio_handler.dart`: Updated `SovereignAudioHandler` with `session.interruptionEventStream` and `session.becomingNoisyEventStream` listeners: ducking volume to 0.25 on notification duck; pausing on transient loss and automatically resuming on interruption end if `wantPlaying` was true; pausing on headphone disconnect.
   - `lib/screens/main_shell.dart`: Created player with `handleInterruptions: false` to avoid dual-controller conflict (G45) and exposed `wantPlaying` getter to `TransportCallbacks`.

5. **BLASTBufferQueue & Ghost Chatbot Jank**:
   - `lib/widgets/ghost_chat_overlay.dart`: Decoupled typewriter loop from `setState` by using `typingTextNotifier` on `_ChatMessage` with `ValueListenableBuilder<String>` (G46); throttled typing SFX (`SfxId.type`) and ghost talk animation to every 4th character.

Gate: `flutter analyze --no-pub` -> `No issues found!`.

## What shipped — American-English sweep, then the canceled contract closed on hardware (2026-10-09)

Two commits, then all five cancel paths were driven on a real device until each one actually printed its string. `flutter analyze --no-pub` -> `No issues found!` (twice); `flutter build apk --release` green; mojibake scan clean over every changed file.

**`ee00d0f` — `Normalize British spellings to American English` (14 files).** Cancel identifiers and user-visible statuses across Dart *and* Python: `cancelled`->`canceled`, `Cancelled`->`Canceled`, `CANCELLED`->`CANCELED`, plus `recognised`->`recognized`, `normalised`->`normalized`, `Grey`->`White54`, and the blueprints. **`df54e53` — `Normalize remaining recognized aliases`** (`speech_to_text.dart`, `voice_input.dart`, `ghost_brain.dart`): `no speech recognised`->`no speech recognized` plus the last Ghost alias rows.

**Every cancel string is now device-proven rather than inferred:**

| Flow | Surface | Exact string observed |
|---|---|---|
| 1 | Grabber, cancelled mid-transfer | `> Download Canceled.` |
| 2 | Batch, MediaStore write denied | `> Batch Canceled. Nothing Was Changed.` |
| 3 | Library delete, denied | `> DELETE CANCELED.` |
| 4 | Forge save, write denied | `> Save Canceled. Tags Are Still In The Working Copy — Nothing Lost.` |
| 5 | Settings restore picker, backed out | `> Restore canceled.` |

Flow 4 resisted four attempts, and the reason it looked like a code bug is now **G43** — stated plainly because the naive staging is genuinely misleading. The first three attempts mounted files the app had itself created, so `requestWriteAccess` returned success with no prompt and the save completed (`> ORIGINAL FIXED ✓`). Revoking `WRITE_EXTERNAL_STORAGE` did **not** change that. The fix was to stage a file the app does not own: `adb shell cp` into `/sdcard/Music`, broadcast `MEDIA_SCANNER_SCAN_FILE`, confirm `owner_package_name=com.android.shell`, mount it via Library -> `EDIT IN FORGE`, then `SAVE & FIX ORIGINAL`. Only then did `com.android.providers.media.PermissionActivity` appear; `Deny` -> `PERMISSION DENIED` -> `CANCEL` produced the string above.

**Two honest limits, both recorded rather than smoothed over.** (1) Batch renders title-case `Batch Canceled`, not uppercase `BATCH CANCELED`; the Library path really is uppercase. Both are American spellings — unifying the casing is a one-line change, not a defect. (2) **There is no bridge-level logcat line and never will be on this path:** `bridge.py:269` returns `{\"status\": \"canceled\", ...}` with no `print`/`log`, and Flow 4's decision is made in Dart (`tab_forge.dart`), which logs nothing either. A process-scoped `logcat -d --pid` across the whole Flow 4 sequence returned 8 lines, none cancel-related. The contract is therefore proven by **UI string plus static read**, not by logcat — do not go hunting for a bridge log line that was never written.

No source change was needed to close any of the five. B160V permissions were restored afterwards (`READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_VIDEO`, `READ_MEDIA_IMAGES` re-granted and re-verified).
