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

**Date:** 2026-11-11
**Phase:** 0–36 implementation + PR #1–#4 MERGED (Sentinel Slice 1 included), full documentation suite (`README.md`, `LICENSE`, `LICENSES.md`, `SECURITY.md`, `CONTRIBUTING.md`), `impellerc` shader (`GLES`/`Vulkan`/`SkSL`), analyzer, and Android ARM64 APK build gates VERIFIED; zero stubs remaining. F-Droid ready.
- `flutter analyze --no-pub` -> `No issues found!`.
- `flutter test` -> `All 6 tests passed!`.
- `impellerc` -> `shaders/backdrop.frag` & `shaders/ghost.frag` compile cleanly across GLES, Vulkan, and SkSL.
- `flutter build apk --debug --target-platform android-arm64` -> `LiteRT 1.4.0` + `EmbeddingGemmaBridge.kt` + `SentencePieceTokenizer.kt` + `shaders/ghost.frag` compile cleanly.
- **Motorola Moto G (2025) Hardware Smoke Test (Android 16 / API 36, Device ID `ZT4222BMWN`): ALL PASS** — `FlutterTextureView` (`RenderMode.texture`) eliminated BLASTBufferQueue frame saturation; native hardware Equalizer/LoudnessEnhancer attached cleanly without NPE; live 256-D neural self-test verified via LiteRT; GhostBot decoupled `ValueNotifier` chat history verified without red `ErrorWidget` boxes.
**Branch:** `main` is the single canonical branch.

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
