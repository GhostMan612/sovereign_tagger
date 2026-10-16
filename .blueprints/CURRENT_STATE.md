# CURRENT_STATE.md — Sovereign Tagger v2 (post-Phase 31)
> Snapshot as of 2026-10-15 — Phases 0–30 COMPLETE; Phase 31 Implementation & Build VERIFIED; Device Verification PENDING. `flutter analyze --no-pub` -> `No issues found!`. `flutter build apk --debug --target-platform android-arm64` -> `app-debug.apk` built cleanly in 320.2s with `libsovereign_whistle.so` (7.78MB, ARM64 NDK/JNI).
>
> **Phase 31 deltas (Whistle Native STT Migration + Voice/Playback Reliability):**
> - **Whistle Native STT Engine**: Integrated Cactus Compute's 16.9 MB `whistle.cact` model as the preferred offline speech-to-text engine (`WhistleEngine`). Linked prebuilt `libneedle.a` (Android ARM64) via JNI/C++ bridge (`needle.h`, `sovereign_whistle.cpp`, `WhistleBridge.kt`). Unsupported ABIs (`x86_64` emulators) gracefully fall back to stub implementation returning `UNSUPPORTED_ABI` without build failures (G44). Both `arm64-v8a` and `x86_64` targets compiled and verified via ELF symbol table inspection. Whisper FFmpeg engine remains available as testable fallback.
> - **Model Distribution & Validation**: Bundled `whistle.cact` in `assets/models/whistle.cact` (16,919,407 bytes, SHA-256 `b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb`) with lazy extraction and HF fallback via `lib/core/whistle_model.dart`. Audio normalization: deterministic native PCM16 to Float32 conversion in [-1.0, 1.0] without passing WAV headers into the inference model.
> - **Voice Lifecycle & Auto-Stop Repair**: Fixed `PcmRecorderBridge.kt` thread join race by stopping `AudioRecord` *before* joining writer thread and confirming `writerFinished` before writing WAV header. Fixed 12-second auto-stop to deliver transcript to query field via `VoiceInput.onTranscript` broadcast stream.
> - **Audio Focus & Notification Resume**: Disabled `just_audio` automatic interruption handling (`handleInterruptions: false` on `AudioPlayer`) to prevent dual-controller race conditions (G45); `SovereignAudioHandler` explicitly manages `session.interruptionEventStream` and `becomingNoisyEventStream` to capture effective `_preDuckVolume` prior to ducking, duck volume to 25% of pre-duck volume (`_preDuckVolume * 0.25`), and restore exact pre-duck volume upon completion. Automatically resumes playback when focus returns only if `wantPlaying` was true (manual pause prevents auto-resume).
> - **Ghost Chatbot Rendering & SFX Jank**: Resolved Logcat `BLASTBufferQueue` frame acquisition saturation warnings by isolating typewriter text updates into `ValueNotifier<String>` + `ValueListenableBuilder<String>` on chat bubbles (G46); throttled typing SFX and avatar mouth animation to every 4th character.

## App identity

Sovereign Tagger — autonomous Android media pipeline: yt-dlp (chaquopy Python 3.14), FFmpeg DSP (`ffmpeg_kit_extended_flutter 0.6.2 full+gpl`), ACRCloud fingerprinting, Genius spider, ID3 jaudiotagger, `audio_service` lockscreen notification, PCM lossless `AudioRecord` wav, TapFeedback boops, **Cactus Compute Whistle native STT engine (`whistle.cact` 16.9MB ARM64 NDK/JNI)** + Whisper AI fallback, **ReplayGain scanner (EBU R128 -> TXXX tags)**, **15-band anequalizer (AutoEq-compatible, 25Hz–16kHz)**, **Crossfade (0–12s) + Gapless toggle**, **Gapless Audit test**, **LRCLIB lyrics fallback**, **Home screen widget (RemoteViews)**, **Library tab (MediaStore browse)**, **Backup/Restore (XOR encrypted JSON)**, **Cyberpunk Tap Feedback (particle burst + shockwave + haptic + 880/1400Hz audio)**, **Ghost Avatar Tutorial Chatbot (code-drawn ticker-driven glitch ghost with moods, glass chat panel, `GhostBrain` offline BM25 command brain over `AppGhostWorld` — no native dep, no API, no key)**, **Contextual Settings Split (PlaybackEngineScreen via Player, EqPresetsScreen via Workbench — jetAudio pattern; root Settings = kernel/system only)**, **Game-feel layer (global `TapFxLayer` tap FX + `CyberInk` + native `SoundPool` SFX bank, `CyberBackdrop` GPU shader, `AnimatedTabStack`, `CyberNavBar`, `CyberPageTransitionsBuilder`, Hero cover-art transitions)**. Cyberpunk, accent-color themable, zero-bloat (no `test/`).

## Architecture map (verified)

### Dart layer (`lib/`, 51 files)

- **main.dart**: loads `accent_color` -> `SplashScreen` (`FFmpegKitExtended.initialize` + XOR `0x53` auto-import + `MatrixRain` overlay `lib/widgets/machine_rain.dart`) -> `MainShell`.
- **screens/main_shell.dart**: `SovereignState` bus; `AudioService` owns `just_audio` `player` (created with `handleInterruptions: false` for explicit audio_session handling), `playlist`/`currentIndex`/`videoController`/`repeatMode`/`isShuffle`/`sleepTimerMinutes`/`speedFactor` + `SovereignAudioHandler` (`lib/core/audio_handler.dart`).
- **core/speech_to_text.dart**: `SpeechEngine` abstraction; `WhistleEngine` (native ARM64 C++ bridge, single-thread serialized execution, keyword biasing via `WhistleKeywords`) + `WhisperFfmpegEngine` fallback.
- **core/whistle_model.dart**: `WhistleModel` asset extraction to cache directory and lazy HuggingFace download fallback.
- **core/voice_input.dart**: `VoiceInput` state machine (`idle, preparing, listening, stopping, modelLoading, transcribing, completed, failed, canceled`), 12s cap, WAV capture, `onTranscript` broadcast stream.
- **core/audio_handler.dart**: `SovereignAudioHandler` with authoritative interruption & becoming noisy listeners: captures `_preDuckVolume`, ducks to `_preDuckVolume * 0.25`, restores `_preDuckVolume`; transient loss pause with auto-resume on interruption end (gated on `wantPlaying`); safe pause on noisy (headphone disconnect).
- **widgets/ghost_chat_overlay.dart**: Frosted glass panel with decoupled `ValueNotifier<String>` typewriter text updates; throttled typing SFX and avatar mouth animation to every 4th character; wired to `VoiceInput.onTranscript` for manual and auto-stop voice queries.

### Native layer (`android/app/src/main/`)

- **C++ NDK (`cpp/`)**:
  - `CMakeLists.txt`: Links `libneedle.a` on `arm64-v8a`; compiles stub on unsupported ABIs.
  - `needle.h`: Cactus Compute Needle 3 / Whistle native C header.
  - `sovereign_whistle.cpp`: JNI bridge implementing `nativeLoadModel`, `nativeTranscribe`, `nativeUnloadModel`, and `nativeIsSupported`.
- **Kotlin (`kotlin/com/sovereigntagger/`)**:
  - `WhistleBridge.kt`: Thread-safe serialized native executor; WAV PCM16 to Float32 sample normalization; JSON transcript parser.
  - `PcmRecorderBridge.kt`: Lossless 16 kHz & 48 kHz PCM AudioRecord capture; synchronized stop-first lifecycle to avoid writer thread race before WAV header finalization.
  - `MainActivity.kt`: MethodChannel wiring for `com.sovereign.tagger/whistle`, `pcm_recorder`, `sfx`, `ytdlp`, `id3`, `storage`, `acrcloud`, `spider`.

## Known-issue registry (all gated `No issues found!`)

| ID | Site | Original issue | Phase | Status |
|----|------|---------------|-------|--------|
| K1 | `grabber:184` | literal `$_quickVideoRes` | 1 | **FIXED** `\"$...\"` |
| K2 | `pipeline:66` | unguarded `getTempDirectory` -> batch lock | 1 | **FIXED** `try/catch` + `if(!mounted)` |
| K3 | `player:moveAfterCurrent` | `playlist` mutated w/o `_audioSource` | 1->10 | **FIXED** `await move/insert` inside `_withQueueLock` + `UUID` |
| K4 | `forge:121` | eject deleted original | 1 | **FIXED** cache-only `deleteSync` + confirm dialog |
| K5 | `forge:267` / `pipeline:267` | export hardcoded `.mp3` | 1 | **FIXED** `srcExt` preserve `mp3/flac/wav/m4a/ogg/opus` |
| WS1 | `core/speech_to_text.dart` | `WhistleEngine` extended `SpeechEngineNotWired` and threw `UnsupportedError` | 31 | **FIXED** Implemented real `WhistleEngine` conforming to `SpeechEngine`, calling native `WhistleBridge` via MethodChannel. |
| WS2 | `cpp/CMakeLists.txt` | `libneedle.a` ARM64-only failed build on `x86_64` emulators | 31 | **FIXED** ABI conditional in CMake and `#if WHISTLE_ARM64_SUPPORTED` in C++ returns `UNSUPPORTED_ABI` cleanly without crash. |
| WS3 | `PcmRecorderBridge.kt` | Thread join executed before stopping `AudioRecord`, causing writer race before WAV header finalize | 31 | **FIXED** `audioRecord.stop()` called first to unblock loop, verified `writerFinished` before writing WAV header. |
| WS4 | `core/voice_input.dart` | 12-second auto-stop called `_stopAndTranscribe()` without delivering result to Ghost overlay | 31 | **FIXED** Refactored completion delivery via `VoiceInput.onTranscript` broadcast stream. |
| WS5 | `core/audio_handler.dart` | `just_audio` automatic interruption handling failed to resume after transient notifications | 31 | **FIXED** Passed `handleInterruptions: false` to `AudioPlayer`, captured `_preDuckVolume`, and centralized ducking/resume in `SovereignAudioHandler`. |
| WS6 | `widgets/ghost_chat_overlay.dart` | Typewriter loop called per-char `setState`, causing `BLASTBufferQueue` queue saturation warnings | 31 | **FIXED** Decoupled text updates via `ValueNotifier<String>` + `ValueListenableBuilder<String>`; throttled typing SFX to 1/4 cadence. |
