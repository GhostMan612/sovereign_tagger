# AGENTS.md — Sovereign Tagger

> This file is AUTO-INJECTED into every session — it is the guaranteed cold-start entry point. Read `.blueprints/RULES.md` first every session (canonical; this file is the compact ramping guide). Then `.blueprints/SESSION_HANDOFF.md` — its top carries the **DOCUMENT MAP** table hooking every project doc (RULES → handoff deltas → CURRENT_STATE registry → ROADMAP phases → BLUEPRINTS gotchas → ARCHITECTURE flows → executable truth in `pubspec.yaml`/`build.gradle`). Follow that map; never rely on memory across sessions.

## Workspace

- **Flutter Android app** — `sovereign_tagger` (Sovereign Mantle media engine: yt-dlp via chaquopy Python, FFmpeg DSP, ACRCloud + Genius). Dart ≥3.13, `ffmpeg_kit_extended_flutter: ^0.6.2` (`full`+`gpl`, FFmpeg 9.0.1), `just_audio 0.10.6` + `audio_service 0.18.19` + `audio_session 0.2.4` + `permission_handler 12.0.3` + `video_player 2.14.0` + `wakelock_plus 1.5.2` + `audio_waveforms 2.0.2` + `file_picker 9.2.3`. `minSdk 26 / compileSdk 36 / NDK 28.2`.
- **Writable:** `C:\sovereign_tagger` only (+ `%USERPROFILE%\.gradle`, `pub-cache`, `C:\android` SDK). `lib/**/*.dart` is the main touch surface.
- **READ-ONLY — never write:** `C:\pathfinder_god`, `C:\Recovery for All`, `C:\Sovereign Nodes`, `C:\sovereign_mantle`.
- **Note:** `C:\sovereign_tagger_2` was the disposable playground copy but is now deprecated — all work happens in `C:\sovereign_tagger`.

## Cold start / session discipline

1. `.blueprints/RULES.md` (canonical law) → 2. `.blueprints/SESSION_HANDOFF.md` (deltas + next actions; its top **DOCUMENT MAP** table hooks every doc) → 3. `.blueprints/CURRENT_STATE.md` + `ROADMAP.md` → 4. `BLUEPRINTS.md`/`ARCHITECTURE.md` as needed.
- Session end: update `SESSION_HANDOFF.md` + tick `ROADMAP.md` + refresh `CURRENT_STATE.md`.
- `.blueprints/` is untracked — do not add it to git.
- Stage by explicit path only (`git add lib/tabs/tab_foo.dart`). `git add .` / `git add -A` forbidden. No `force-push` without ask.

## Commands

```powershell
flutter pub get                              # everything maxed except file_picker 9 / wakelock_plus 1.5.2 (win32 pair) and permission_handler 12 (compileSdk 37)
flutter analyze --no-pub 2>&1 | Select-String -Pattern "error •|warning •" | Select-Object -First 20
flutter analyze --no-pub 2>&1 | Select-Object -Last 3   # expect "No issues found!"
# flutter build apk --release  — DO NOT RUN HERE. Device-dependent, Android Studio does Moto G install.
```

- Project slash commands (`.opencode/commands/*.md`): `/analyze` (filtered analyze gate), `/probe <path>` (python line-count preview, no full read), `/smoke` (device matrix checklist, asks before build).
- Filter all terminal output; pipe for failures only. Do not ingest raw JSON / full logs.
- Probe large files with a short Python script, not `cat`/`read` of the whole file.

## Architecture (not obvious from filenames)

- **Entry:** `lib/main.dart` → splash boot (FFmpeg init + `storage/autoImportConfig` XOR `0x53` + `MatrixRain` overlay) → `lib/screens/main_shell.dart` (`Stack` → `AmbientBackdrop` variant per tab + `IndexedStack` + mini-player + `BottomNavigationBar`).
- **Global bus:** `SovereignState` static `ValueNotifier`s (`currentTab`, `pendingForge` (ForgeRequest), `pendingGrabberUrl`, `accentColor`); `AudioService` static singleton owns `just_audio` `player` (0.10 playlist API: `setAudioSources`/`insertAudioSource`/`moveAudioSource`/`removeAudioSourceAt`), `playlist`/`currentIndex`/`videoController`/`repeatMode`/`isShuffle`/`sleepTimerMinutes`/`speedFactor` + `SovereignAudioHandler` (`lib/core/audio_handler.dart`) for `audio_service` lockscreen notification + `_queueLock` for serialized mutators (`replacePlaylist`, `reorderPlaylist`, `removeFromPlaylist`, `playNext`, `addToQueue`, `moveAfterCurrent`). Cross-tab handoff is user-initiated only: `SovereignState.sendToForge(ForgeRequest(...))`; Forge edits a working copy and saves back over the original via `StorageClient.overwriteOriginal`. Mutate queues only via those mutators.
- **Native bridges (MainActivity.kt, Kotlin + chaquopy):** channels `ytdlp` (`searchMedia`/`getFormats`/`downloadMedia`/`cancelDownload`/`updateCore`/`updateFullStack`/`runDoctor`/`getDoctorRegistry`), `ytdlp_events` EventChannel, `id3` (jaudiotagger), `storage`, `acrcloud`, `spider`, `pcm_recorder` (`hasPermission`/`startRecording`/`stopRecording` → `PcmRecorderBridge.kt` AudioRecord 48k/16-bit WAV). Python: `android/app/src/main/python/sovereign_yt/bridge.py` (splits `"vid+aud"` into two `YoutubeDL` runs, `extractor_args player_client=android,web`) + `spider.py` (Genius→SoundCloud→iTunes→MusicBrainz cascade) + `updater.py` (`execute_scorched_earth` + `update_python_stack` + `execute_full_scorched_earth`) + `doctor.py` (`PATCH_REGISTRY` diagnose).
- **Shared helpers:** `lib/core/media_probe.dart` (`probeStreams`, `probeDurationMs` via `FFprobeKit.getMediaInformationAsync` → `info.streams` → `s.type`), `lib/core/ffmpeg_executor.dart` (serialized queue for all `executeAsync`), `lib/core/tap_feedback.dart` (haptics + embedded 880Hz/1400Hz wav base64 via `just_audio` data URI), `lib/core/pcm_recorder.dart` (MethodChannel wrapper). `lib/core/jobs|models` is dead scaffolding — leave alone.
- **Assets:** `assets/splash-screen-bg.png` + `ShareTechMono`/`VT323` (`pubspec.yaml:37`); `lib/widgets/matrix_rain.dart` provides `MatrixRain` (splash, single `TextPainter` reuse) + `AmbientBackdrop` (`BackdropVariant` grabber/forge/pipeline/workbench pulsing grid).

## Asset & Animation Limits (Flutter — what you can/can't do without bloat/rebuild)

- **Assets are compile-time, not runtime:** every file under `assets/` must be declared in `pubspec.yaml:34` `assets: - assets/` and is bundled into the APK at `flutter build`. Android Studio hot-reload cannot add new asset paths without editing `pubspec.yaml` + `flutter pub get` + rebuild. No dynamic `File('assets/...')` writes at runtime — use `getTempDirectory` + `MediaStore` for generated media.
- **Size ceiling:** Play Store warns >150MB APK, `ffmpeg_kit full+gpl` already ~40MB per ABI (`arm64-v8a,x86_64` only, `app/build.gradle:50`). Adding video/GIF assets blows this fast. Prefer **code-drawn** (`CustomPainter`, `Shader`/`FragmentShader`, `Lottie json` ~20KB) over raster video. `MatrixRain` + `PulsingGrid` are code-drawn for that reason (no new PNGs).
- **What you *can* add cheaply:** `Lottie` (json vector), `Rive` (state-machine vector, ~30KB runtime), `rive`/`flare` interactive, `flutter_animate` (implicit), `shaders` (`assets/shaders/*.frag` + `pubspec.yaml: assets: - assets/shaders/`), `AnimatedBuilder` + `CustomPainter` (current `MatrixRain`/`AmbientBackdrop`). All stay under `hooks`/`code_assets` without NDK.
- **What requires a rebuild + permission:** New `assets/images/*.png` → `pubspec.yaml` + rebuild. New `assets/sounds/*.wav` for tap effects would be ~50KB each — we avoided that by embedding 0.7–1.3KB base64 wavs in `tap_feedback.dart`. Adding many luts/LUTs or fonts needs `pubspec.yaml: fonts:` + rebuild.
- **What we chose for per-tab dramatics:** `AmbientBackdrop` `BackdropVariant` already pulses per tab (`grabber` vertical drops, `forge` slow, `pipeline` horizontal flows, `workbench` mixed) at `alpha 0.035/0.18` + blur — subtle, no asset, 60fps via single `TextPainter` + 1 `AnimationController` per backdrop. To go heavier, add `rive` or `lottie` JSON under `assets/animations/<tab>.json` + `pubspec.yaml: assets: - assets/animations/` + rebuild — still <100KB.

## Laws that will break the build if ignored

| Area | Rule |
|------|------|
| FFmpeg | Always `await FFmpegExecutor.execute(...)` (queues `FFmpegKit.executeAsync`). Sync `execute()` freezes UI. Never re-add `FFmpegKit.execute` directly. |
| Muxing | Merge with explicit `-map 0:v:0 -map 1:a:0`; verify output via `probeStreams` (fork uses `FFprobeKit.getMediaInformationAsync` → `info.streams` → `s.type == 'audio'/'video'`; no `FFmpegKit.getMediaInformation` / `getType()`). Chaquopy cannot shell to `ffmpeg` for yt-dlp merges — Flutter-side `FFmpegKit` owns all muxing. Duplicate `jobId` → use `Random().nextInt`+`millis` `_newJobId()`; never pass `""`. |
| Tagging | Use native `id3` channel (jaudiotagger) in-place, never FFmpeg remux. `deleteField` on empty value (not `setField("",v)`), `deleteArtworkField` on empty art. Preserve source extension on export renames; verify with write→read-back. |
| Media | `Duration` has no `isAfter`/`isBefore`; use `<=`/`>=`. |
| UI | `setState` after any `await` needs `if (!mounted) return;` (covers `FilePicker` `PlatformException`). `TextPainter` in `CustomPainter.paint` reuse single instance (`matrix_rain.dart:64`). PCM `ByteBuffer` reuse per `PcmRecorderBridge.kt:60` (no per-loop alloc). |
| Audio | `AudioService` queue mutators must `await` the matching `player.*AudioSource*` call inside `_withQueueLock`; never mutate `playlist.value` alone. `TapFeedback` static `_player` has explicit `dispose()` — call on app `dispose` if added. |
| Source edits | **NEVER edit source via PowerShell text pipelines** (`Get-Content/-replace/Set-Content`, `Out-File`, `Add-Content`). PS 5.1 mis-reads UTF-8 as ANSI → mojibake (`—`→`â€"`) AND silent letter swaps (`setState`→`setYtate`, `Text`→`RextStyle`) — broke multiple sessions (see RULES.md §3.1). Editor tools only; Python `encoding='utf-8'` if scripted; then analyze + signature-grep verify. |

## Toolchain quirks

- **Dependency ceiling (verified by resolver, Phase 27.1)** — only two walls remain. (1) **win32 pair:** `file_picker <12` needs `win32 ^5.9.0`, `wakelock_plus >=1.6.1` needs `win32 ^6.0.1`, so `wakelock_plus` stays `1.5.2` until `file_picker` moves to 13.x (full API rewrite: `FilePicker.platform`/`FilePickerResult` gone, 16 call sites, and Forge write-back depends on `PlatformFile.identifier`) — dedicated session. (2) **compileSdk wall:** `permission_handler 13` pulls `permission_handler_android 14` which uses API 37 (`VERSION_CODES.CINNAMON_BUN`) while root `android/build.gradle` forces plugins to `compileSdk 36`. Everything else is at latest; `flutter pub upgrade --major-versions` would break both walls, so do not run it. `just_audio_background` Beta unresolvable on this mirror — use `audio_service` handler already wired (`MainActivity : FlutterActivity` + manifest `AudioService`/`MediaButtonReceiver` + `FOREGROUND_SERVICE*` perms).
- **Chaquopy** `gradle:17.0.0` supports `AGP 7.3-9.2 / Python 3.10-3.14 / minSdk 24` (`versions.rst`). `python 3.14` is top but has very few wheels — fallback comment in `app/build.gradle:54` says flip to `"3.11"` if `pip` fails. `3.12+` is 64-bit only (`arm64-v8a,x86_64` only, no `armeabi-v7a`). `buildPython` must match runtime `version` `chaquo #991`. `compileSdk 36 / NDK 28.2` / `JDK 25 bundled` (`flutter doctor -v` `jbr/bin/java 25.0.2`) with `compileOptions 1.8` still builds via shim but warns `source 8 obsolete` — bump to `17` only in a dedicated Java session. `AGP 9.0.1 / KGP 2.3.20 / Gradle 9.1.0` are at ceiling.
- No `test/` suite in repo (deferred-zero-bloat); verification is analyzer + device smoke. Background playback, FB muxing, loudnorm two-pass, PCM WAV, and matrix rain perf all require a device/emulator.

## Style

- No comments in code except the Genesis header already on core files. Cyberpunk theme: black, monospace, accent-color reactive (`SovereignState.accentColor`). Lossless guarantee: Forge never transcodes; Workbench preserves container unless operator explicitly converts; Pipeline preserves `flac/wav/m4a` via ext map; Workbench lossless toggle `48k/16-bit WAV` via `PcmRecorderBridge`.
- Synthetic data only in fixtures/tests (`SAMPLE ANCESTOR A`).

## Sources of truth

- Executable > prose. If docs conflict with `pubspec.yaml`, `analysis_options.yaml`, or scripts in `android/app/src/main/python/`, trust the executable.
- Check `.blueprints/CURRENT_STATE.md` known-issue registry (K1–K13 + G1–G12) before touching grabber/pipeline/workbench/forge.
