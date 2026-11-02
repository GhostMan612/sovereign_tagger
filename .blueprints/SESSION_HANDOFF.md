# SESSION_HANDOFF.md — Sovereign Tagger v2
> Read this FIRST every session. Updated Phase 31 build-verified 2026-10-15.

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

**Date:** 2026-11-02
**Phase:** 0–32 implementation & analyzer/shader gates VERIFIED; ready for Moto G hot-reload / APK install smoke test.
- `flutter analyze --no-pub` -> `No issues found!`.
- `impellerc` -> `shaders/backdrop.frag` 6-variant shader compiles cleanly.
**Branch:** `main` is the single canonical branch.

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
