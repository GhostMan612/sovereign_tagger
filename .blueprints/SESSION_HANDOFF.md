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

**Date:** 2026-11-12
**Phase:** Phase 38.3: Defensive Hardening & Native Test Verification — Draft PR #23 conditionally approved; final operational revision applied (unconditional startup self-test removed from splash boot to eliminate 21s delay; converted to on-demand diagnostic action in Settings > Crash Recovery Vault). Branch `hardening/phase-38.3-defensive` remains isolated; canonical `main` untouched at `57d368a`.

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
