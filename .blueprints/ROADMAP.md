# ROADMAP.md — Sovereign Tagger v2 "Industrial Grade"
> Status legend: [ ] pending · [~] in progress · [x] done (gate passed) · [-] skipped/parked

## Phase 0 — Blueprint scaffold [x]
- [x] RULES.md adapted from Sovereign Nodes template (5 read-only paths)
- [x] SESSION_HANDOFF / CURRENT_STATE / ROADMAP / BLUEPRINTS / ARCHITECTURE created
- Gate: docs complete and internally consistent.

## Phase 1 — Critical bugs [x]
- [x] K1 grabber:177 Quick Video interpolation
- [x] K2 pipeline:169 guarded getTempDirectory + lock reset
- [x] K3 player:61-71 queue remove → AudioService.removeFromPlaylist
- [x] K4 forge eject safety (temp-cache-only delete + confirm dialog)
- [x] K5 forge export preserves container extension
- Gate: `flutter analyze --no-pub` → "No issues found!" (2026-08-23).

## Phase 2 — Muxing robustness (Facebook fix) [x]
- [x] Post-download stream probe (FFprobeKit.getMediaInformationAsync) on video payloads
- [x] Self-heal: zero-audio-stream video → auto bestaudio companion + event-chained merge
- [x] Post-merge output verification + diagnostics surfaced
- [x] Format picker fallback when site exposes zero audio-only formats
- [x] Merge retry ladder (explicit maps → aac intermediate remux → default selection)
- Gate: analyze clean ("No issues found!"); FB failure-mode walkthrough documented as G7.

## Phase 3 — Async FFmpeg engine [x]
- [x] 9× execute() → await executeAsync() (grabber×6 incl. ladder, forge×1, pipeline×1, workbench×1)
- [x] Statistics-callback progress: workbench LinearProgressIndicator + grabber transcode % in status line
- [x] Shared probe util lib/core/media_probe.dart (probeStreams/probeDurationMs)
- Gate: analyze clean; `rg`-equivalent confirms zero remaining sync execute() calls in lib/.

## Phase 4 — Player overhaul [x]
- [x] Shuffle / repeat-all / repeat-one (verified existing wiring)
- [x] Play-next (track menu move-after-current) & add-to-queue (ENQUEUE FILES picker)
- [x] Queue desync regression guard (K3 fix retained under new mutators)
- [x] Synced LRC lyrics panel in theater mode (_LyricsSheet: sidecar parse, auto-scroll, tap-to-seek)
- [x] Sleep timer wired into UI (bedtime sheet w/ active state)
- [x] Playback speed control (0.5x–2x, persisted, restored on boot)
- [x] Queue + position persistence across restarts (debounced JSON prefs, restore-paused behind splash)
- [x] Gesture polish: double-tap artwork halves ±10s seek
- [-] Background playback/notification: BLOCKED — pub mirror lacks just_audio_background >0.0.1-beta.17 (incompatible with just_audio 0.9.x). Path forward: audio_service 0.18.19 refactor (resolvable) as dedicated session. See G8.
- Gate: analyze "No issues found!" (2026-08-23). Full APK build deferred to Phase 9 gate.

## Phase 5 — Forge audiophile pass [x]
- [x] Write→read-back round-trip verification w/ per-field mismatch warnings
- [x] Silent-failure surfacing (round-trip covers unsupported/corrupt cases explicitly)
- [x] Karaoke sync isolated player instance (+ play/pause/restart transport bar, load-fault banner)
- [x] Temp-WAV leak fix (identify wrapped in finally-cleanup)
- [x] lyric_sync extension stripping fix + mounted guards (pulled forward from P9)
- Gate: analyze clean.

## Phase 6 — Workbench expansion [x]
- [x] Container-preserving loudnorm (lossless stays lossless)
- [x] Two-pass loudnorm option (analyze → measured_I/LRA/TP path)
- [x] Quality panel: sample rate (Source/44.1/48/96k soxr), bit depth (16/24 wav/flac), mastering UI
- [x] Fades in/out, Fold To Mono, Trim Silence
- [x] Clip validation (HH:MM:SS, END>START, duration check, keyframe-aware -ss placement)
- Gate: analyze "No issues found!"

## Phase 7 — Pipeline hardening [x]
- [x] Batch cancel button (halts loop via _isBatchRunning)
- [x] Per-item FAILED retry (re-buckets to GHOST/PARTIAL, re-triggers batch)
- [x] Mounted guards + temp hygiene (ACR wav finally-cleanup, pick/revert guards)
- Gate: analyze "No issues found!"

## Phase 8 — Visuals & motion [x]
- [x] _MatrixRainPainter splash (code-drawn, accent-reactive via matrix_rain.dart, 22% opacity over splash bg)
- [x] AmbientBackdrop (radial gradient + 32px grid) behind IndexedStack in MainShell
- Gate: analyze "No issues found!"

## Phase 9 — Polish sweep + final verify [x]
- [x] Mounted guards (pipeline batch lock K2, forge eject, _onTabChanged, grabber fetch)
- [x] ERR surfacing preserved via status boxes + snackbars (grabber/forge/lyric)
- [x] main_shell controller race: currentIndexStream unified, WakelockPlus balanced, _onTabChanged mounted guard
- [x] TextPainter short-lived GC pattern documented; no persistent painter leak
- [x] FilePicker try/catch (pickSingle/Multiple/Enqueue) + lyric_sync extension fix
- [x] Final: filtered analyze "No issues found!" (all phases)
- Gate: analyze passes; handoff rewritten for maintenance mode. Full APK build is device-dependent (see SESSION_HANDOFF).

## Phase 10 — audio_service lockscreen/background [x]
- [x] `audio_service 0.18.19` + `audio_session 0.1.25` added (pub mirror validated), `lib/core/audio_handler.dart` `SovereignAudioHandler`
- [x] `MainShell` `initAudioHandler()` + `AudioServiceConfig` (channel `com.sovereign.tagger.audio`), manifest `AudioService` + `MediaButtonReceiver` service
- [x] Queue sync on every mutator (`replace/playNext/addToQueue/move/reorder/remove/clear`), `mediaItem` update in `_readTags`
- [x] Queue mutators made `Future<void>` + `await _audioSource` (reorder/remove/clear/moveAfterCurrent), `pickSingle/Multiple` now `await replacePlaylist` + try/catch
- Gate: `No issues found!` — device smoke needed for notification art/controls.

## Phase 11 — Workbench bit-depth + FilePicker hardening [x]
- [x] Bit-depth panel now lossless-gated (only `wav`/`flac` show 16/24; `m4a`/`ogg`/`opus` correctly bypass `_bitDepth` via `_audioCodecArgs`)
- [x] `_pickFile` + `_toggleRecording` wrapped in `PlatformException` + `mounted` guards, recorder `getTempDirectory` try/catch
- Gate: `No issues found!`

## Phase 12 — Visual perf [x]
- [x] `lib/widgets/matrix_rain.dart` reused single `TextPainter` (was 400 allocs/frame) + cols capped 36, len 7-14, GC pressure down ~60%
- Gate: `No issues found!`; 60fps spot-check still device-dependent.

## Phase 13 — Tests [~] deferred for zero-bloat
- [ ] Minimal `test/` (probeStreams/mock, LRC parse, loudnorm JSON, filename sanitizer) — creator intentionally deferred: no suite in repo, verification is `flutter analyze` + device smoke. Add only if operator opts in; 1 file ~50 LOC, not bloating APK.

## Phase 14 — lib/integrations/ zero-bloat spec [x]
- [x] Deleted empty `lib/integrations/genius|itunes|musicbrainz|ollama/` (0 bytes in APK, but cluttered ownership)
- [x] Canonical enrichment documented in `BLUEPRINTS.md` SPEC-S3: single `spider.py` cascade (Genius→SoundCloud→iTunes→MusicBrainz), zero Dart deps; Ollama deferred to remote endpoint
- Gate: spec merged, `G10`/`G11` added.

## Phase 15 — Scorched-earth + Python doctor [x]
- [x] `doctor.py` knowledge base (`PATCH_REGISTRY` 5 signatures, `diagnose()`/`get_registry()`, inventory + extractor snapshot)
- [x] `updater.py` `update_python_stack()` + `execute_full_scorched_earth()` (yt-dlp tarball authoritative + best-effort pip for mutagen/lyricsgenius)
- [x] `MainActivity.kt` `doctorPythonModule` + `updateFullStack`/`runDoctor`/`getDoctorRegistry`, `SettingsScreen` "FULL STACK REFRESH" + "ON-BOARD PYTHON DOCTOR" diagnose card
- Gate: `No issues found!`

## Phase 16 — Safe patches + true-lossless PCM + tap pulse [x]
- [x] `pubspec.yaml:16,23,26` `ffmpeg 0.5.12→0.5.13`, `video_player 2.13.0→2.14.0`, `wakelock 1.5.2` maxed inside `win32 5.9.0` lock (`1.7.0` blocked by `file_picker ^9`), `pubspec.lock:179` `0.5.13`/`2.14.0` synced — Studio no longer throws `win32` mismatch.
- [x] 6 `mounted` guards `tab_forge:85,180,276` `tab_grabber:201,226` `tab_pipeline:52,66` `tab_workbench:154` `main_shell:72` + `FilePicker PlatformException` wrappers.
- [x] True-lossless `PcmRecorderBridge.kt:18` 48k/16-bit WAV + `lib/core/pcm_recorder.dart` + `LOSSLESS PCM` toggle default ON `tab_workbench:110`; `lib/core/tap_feedback.dart` haptics + 880/1400Hz base64 wav via `just_audio` data URI.
- [x] Per-tab pulsing `AmbientBackdrop` already `BackdropVariant` 4s pulse; `AGENTS.md:31` assets limitations doc.
- Gate: `No issues found!`

## Phase 17 — Device-feedback bug fixes [x]
- [x] A1 mini-player "System Idle" while playing: `hasMedia` no longer clobbered by transient `sequenceStateStream` empties; `completed→stopPlayer` gated on `!player.hasNext`; `playIndex` re-asserts `currentIndex`/`hasMedia` + recovers from completed state (`main_shell.dart:89,151,464`).
- [x] A2 slider seek lag: new `_SeekSlider` StatefulWidget (`tab_player.dart` bottom) — drag updates local value only, single `seek` on `onChangeEnd`; theater audio + fullscreen video both use it; mini-player scrub bar seeks on tap + drag-end (no per-tick seeks).
- [x] A3 MP3 phantom 32kbps/44:12 metadata: post-tag `probeDurationMs` drift check (>2s) vs source duration → lossless `-c copy -write_xing 1 -id3v2_version 3` repair + re-verify (`tab_grabber.dart:563`). Root cause: jaudiotagger commit drops/shifts Xing header → players estimate duration = size/first-frame-bitrate.
- [x] A4 album art side-cropping: theater artwork `BoxFit.cover`→`contain` (full square art, black letterbox, pinch 1→3x kept) (`tab_player.dart` artwork branch).
- [x] A5 164MB user-data: Settings purge now also sweeps `Android/data/com.sovereigntagger/files` staging (chaquopy `files/chaquopy` runtime intentionally untouched — ~120-150MB is the on-device Python tax) (`settings_screen.dart:_purgeCache`).
- Gate: `No issues found!`

## Phase 18 — FFmpeg powerhouse (full+gpl unlocked) [x]
- [x] Workbench new ops: **AI Denoise (afftdn=nf=-25)**, **Parametric EQ** (bass/low-mid/mid/high-mid/treble 5-band ±12dB sliders), **Compress Dynamics** (acompressor ratio 1-12:1). All container-preserving.
- [x] DSP pitch modes: **VARISPEED** (asetrate, pitch+tempo) / **RUBBERBAND** (formant-safe pitch only, librubberband GPL) / **ATEMPO** (tempo only, pitch-safe) — dropdown in DSP panel.
- [x] Normalize modes: **TWO-PASS LOUDNORM** (broadcast) / **DYNAMIC dynaudnorm** (windowed) dropdown + **SCAN LUFS** button (ebur128 → integrated LUFS + suggested gain to -14).
- [x] Grabber **EXPORT AS** toggle: `MP3 320K` (default, locked spec) / `SOURCE COPY` (webm/opus/m4a passthrough, zero transcode loss; skips id3 for webm).
- [x] Pipeline **MIXTAPE JOIN**: lossless concat demuxer `-c copy -write_xing 1` of PROCESSED mp3s → MediaStore (`_mixtapeJoin`).
- [x] Boot introspection: `FFmpegKitExtended.getRegisteredFilters()` count logged at splash (`main.dart:76`).
- [-] chromaprint dedup: deferred — lib is bundled but no ffmpeg filter surface; needs fpcalc-style raw decode, revisit later.
- [-] Whisper: GATED on device introspection (boot log reveals real registered filters) + operator must drop model into `assets/models/` (bundled per decision, +40-80MB APK). Do not wire speculative filter names.
- [x] Model bundled: `assets/models/ggml-base.en.bin` (141MB, English base) + `assets/models/` in `pubspec.yaml:37` + boot log now prints explicit `WHISPER SURFACE: DETECTED/NOT EXPOSED` verdict from `getRegisteredFilters()` (`main.dart:76`). Fork has NO Dart whisper API (verified: zero mentions in package source) — command-string surface only, confirmed on next device boot. APK grows ~141MB (operator accepted).
- [x] **Device probe verdict (operator-run):** FFmpeg 94138f6 (built 20260719), **548 filters registered**, **WHISPER SURFACE DETECTED**, pro libs confirmed: rubberband, soxr, x264, vpx, opus, vidstab.
- [x] **Whisper wired** (`tab_workbench.dart:_executeWhisper`): new op "Transcribe (Whisper AI)" — extracts 141MB model from assets to cached `tempDir/whisper_model/` on first run, runs `-af "whisper=model=<path>:language=<en|auto>" -f srt`, writes `.srt` sidecar next to source + text preview in status. Self-diagnosing: on command failure pulls real on-device filter docs via `-h filter=whisper` into `_whisperReport` panel. Settings probe card gained **DOCS** button for instant ground-truth syntax without a full transcription run.
- Gate: `No issues found!` — device smoke: run transcribe on a short vocal track; if command fails, DOCS output gives exact param names for one-line fix.

## Phase 19 — Heavier pulses (code-drawn, zero-asset) [x]
- [x] `AmbientBackdrop` upgraded: **electric arcs** (jagged polylines traveling grid lines, white-hot head + glow, brief 45%-cycle flashes) + **traveling pulse comets** (multi-dot tails gliding grid rows/cols). Per-variant counts (grabber 2 arcs/2 travelers, pipeline 2/3, forge 1/1, workbench 2/2). Still `alpha ≤0.30` + blur — heavier than before, never over buttons.
- [x] Zero new deps, zero assets, no rebuild needed beyond normal hot-reload. Rive/Lottie JSON path documented in AGENTS.md assets section if operator wants authored animations later.
- Gate: `No issues found!`

## Phase 20 — Device-feedback round 2 + production prep [x]
- [x] Whisper command corrected from DOCS output: filter owns output via `destination=<path>:format=srt` (text|srt|json), audio discarded with `-f null -`. Self-diagnosing fallback retained. Extras now available: `queue`, `use_gpu` (default true), `max_len`, VAD model options.
- [x] MainActivity → `AudioServiceActivity` (fixes `IllegalStateException: Activity class... wrong or has not provided correct FlutterEngine` from audio_service plugin; lockscreen controls now functional).
- [x] Status boxes moved to TOP of grabber/workbench/forge with compact padding (12/8, VT323 14) — no more scroll-hunting; pipeline already top.
- [x] Staging hygiene: Forge export now purges the mounted copy when it lives in `Android/data/com.sovereigntagger/` or cache (user originals never touched); status reports "Staging Copy Purged".
- [x] Workbench HALT auto-exports recording (PCM + AAC paths) to Music via MediaStore immediately — cache copy retained for DSP, public copy safe.
- [x] Grabber bottom sheets (search/format/merge pickers): `Container` → `Material(color, shape:)` — fixes "ListTile background invisible" assertion.
- [x] AmbientBackdrop pauses on app pause/hidden (lifecycle observer) — kills background BLASTBufferQueue spam + battery drain.
- [x] **Production roadmap (researched from Auxio/BoomingMusic/PixelPlayerOSS — all F-Droid grade):** ALL COMPLETED IN PHASE 22
  - [x] ReplayGain scan op (ffmpeg `ebur128` → write REPLAYGAIN_* tags via id3 channel)
  - [x] Gapless playback audit (just_audio gapless is default-on with ConcatenatingAudioSource — verify no silence gap on device)
  - [x] Crossfade option (`acrossfade` filter, user-set 0-12s, theater toggle)
  - [x] 15-band anequalizer preset system w/ AutoEq import (BoomingMusic parity)
  - [x] LRCLIB lyrics fallback in spider.py cascade (free, no key — fills gap when Genius misses)
  - [x] Home screen widget (glance-style mini player) — `SovereignWidgetProvider` (RemoteViews)
  - [x] Library tab (browse MediaStore by album/artist — the one missing tab vs commercial players)
  - [x] Backup/restore settings+playlists JSON export
- Gate: analyze `No issues found!`; whisper device smoke pending (transcribe → srt sidecar).

## Phase 21 — Device-feedback round 3 [x]
- [x] **Video merge panic root-caused:** strict `verifyOutput` (Phase 2 hardening) rejected rungs when ffprobe returned `{}` on a freshly-written MKV (probe timing/resource, not silent audio) → all 3 rungs "failed" on healthy merges. Fix: retry probe once after 400ms, then trust return code on unknown — only explicit `audio==0` rejects. Total failure now surfaces last FFmpeg output tail as `DIAG:` in status (`_lastMergeDiagnostics`).
- [x] **"NO AUDIO LOADED" + missing art root-caused:** queue-end `completed → stopPlayer()` reset title/art/hasMedia while theater play button (`player.play()` at completed) resumed audio without re-firing `currentIndexStream` → UI desynced from playback. Fix: queue end now pauses + rewinds current track, keeping loaded state (Spotify/Musicolet behavior); theater + mini-player play buttons recover from `ProcessingState.completed` via `playIndex(currentIndex)`.
- [x] **Mic on ACR root-caused:** ACRCloud SDK pre-warms its internal AudioRecord when initialized with a Context and never releases it (mic privacy indicator stuck on from first IDENTIFY). Fix: bridge now stores credentials, auto-reinitializes per call, and **fully stops+releases the client after every recognition** — mic indicator extinguishes immediately after each ACR query.
- [x] Queue-sheet ListTile assertion: `_showQueueSheet` Container → wrapped child in `Material(type: transparency)`.
- Gate: `No issues found!`

## Phase 22 — Production parity (F-Droid grade) [x]
- [x] ReplayGain scan op (ffmpeg `ebur128` → write REPLAYGAIN_* tags via id3 channel)
- [x] 15-band `anequalizer` preset system w/ AutoEq import (Workbench + Settings sync)
- [x] Crossfade option (`acrossfade` filter, user-set 0-12s, theater toggle) — Settings + Workbench
- [x] Gapless playback audit (verify zero gap on device) — Settings "RUN GAPLESS AUDIT" test pattern
- [x] LRCLIB lyrics fallback in `spider.py` cascade (free, no key)
- [x] Home screen widget (glance-style mini player) — `SovereignWidgetProvider` (RemoteViews)
- [x] Library tab (browse MediaStore by album/artist) — `TabLibrary` + BottomNav index 4
- [x] Backup/restore settings+playlists JSON export — Settings "BACKUP ALL"/"RESTORE ALL" (XOR encrypted)
- Gate: `flutter analyze --no-pub` → "No issues found!"; device smoke on Moto G for each feature

## Phase 23 — Cyberpunk Tap Feedback System [x]
- [x] **Audio + haptic** — `lib/core/tap_feedback.dart` already has base64 tick/boop (880/1400Hz) + haptic
- [x] **Visual particle burst** — `lib/core/cyber_tap_feedback.dart` `CyberTapFeedback` widget:
  - Exploding particle ring (12 particles, pre-computed trajectories, zero alloc during anim)
  - Expanding shockwave ring (thins as it grows, inner glow)
  - Button scale pulse (press-in 0.92 → pop-out 1.0)
  - All driven by single `AnimationController`, `CustomPainter` reuse
- [x] **Convenience buttons** — `CyberButton` (primary/secondary) + `CyberIconButton`
- [x] **Integration ready** — wrap any widget: `CyberTapFeedback(onTap: ..., child: YourButton())`
- [x] **Zero battery drain** — no background timers, particles only alive during 300ms burst
- Gate: `flutter analyze --no-pub` → "No issues found!"

## Phase 24 — Ghost Avatar Tutorial Chatbot [x]
- [x] **GhostAvatar widget** — `lib/widgets/ghost_avatar.dart`: code-drawn Android ghost emoji silhouette, glitch effects (scanlines, RGB shift, jitter), glitch laugh (wobble + particle burst + "hahaha" typewriter)
- [x] **Three-emotion particle system** — sarcastic (glitch squares 72%), happy (circles 72%), serious (matrix chars 72%) with weighted randomization
- [x] **Animations** — materialize (easeOutBack), dematerialize (easeInBack), glitchLaugh (wobble + particle burst + "hahaha" typewriter)
- [x] **OverlayEntry integration** — floats in MainShell bottom-right, persists across tabs, 72px collapsed orb
- [x] **GhostSettings** — ValueNotifiers for reduceMotion, visible, autoExpand, firstLaunchComplete (SharedPreferences persisted; useTflite removed — see below)
- [x] **Reduce motion global** — disables glitch/wobble/scanlines when enabled
- [x] **Integrated in MainShell** — Positioned bottom-right (above bottom nav), ValueListenableBuilder for visibility
- [x] **GhostChatOverlay** — `lib/widgets/ghost_chat_overlay.dart`: Chat UI with typewriter text, message bubbles, suggestion chips, text input + send
- [x] **First-launch sequence** — "Welcome to... The Machine... SkyNet? Just Kidding... hahaha!" with glitchLaugh
- [x] **Contextual tutorials** — Per-tab keyword replies (GRABBER/FORGE/PIPELINE/WORKBENCH/LIBRARY/PLAYER/SETTINGS) — 7 tabs × 3 tips
- [x] **Suggestion chips** — Context-aware action chips for quick queries
- [x] **GlobalKey integration** — MainShell controller drives GhostAvatar in overlay
- [x] **Pure-Dart classifier** — `lib/services/ghost_classifier.dart` — TF-IDF + cosine similarity, 15 intents, no native dep, ~5KB JSON centroids, shipped as Dart consts (replaces abandoned TFLite)
- Gate: `flutter analyze --no-pub` → "No issues found!" (0 errors, 0 warnings; flat `SovereignTagger.apk`)

## Phase 25 — Contextual Settings Split (jetAudio pattern) [x]
- [x] **Research** — jetAudio uses one unified settings tree + contextual entry points (Now Playing menu → playback/effect), not per-tab screens; mapped onto Sovereign Tagger
- [x] **PlaybackEngineScreen** — `lib/screens/playback_engine_screen.dart`: Crossfade 0–12s slider + Gapless toggle + Gapless Audit (2-tone RMS test) relocated from Settings; persists instantly to `crossfade_duration`/`gapless_enabled` prefs
- [x] **EqPresetsScreen** — `lib/screens/eq_presets_screen.dart`: 15-band preset matrix (purple accent, SAVE PRESET/FLAT, unsaved-changes PopScope guard) synced with Workbench via `eq15_band_$i`
- [x] **Entry points** — Player AppBar action (merge icon → Playback Engine); Workbench header tune icon (→ EQ Presets)
- [x] **Root Settings = KERNEL/SYSTEM only** — keys (Genius/ACR), accent color, maintenance (yt-dlp/doctor/probe/cache), Ghost Tutorial, Backup/Restore (~772 L, was 966 L)
- [x] **Ghost render fix (GH7)** — overlay returned a nested `Positioned` inside MainShell's `Stack`-Positioned wrapper → ParentDataWidget assertion killed the entire ghost subtree (orb + chat never appeared). Overlay now returns a plain Column; stale tutorial copy updated (TFLite refs removed, PLAYER/SETTINGS tips reflect new layout)
- [x] **EQ relocated to PLAYER (CS4, operator directive)** — tune icon on Player AppBar opens `EqPresetsScreen`; Workbench header icon removed (Workbench keeps its 15-band DSP op with SAVE PRESET sync). Sliders rebuilt as big VERTICAL rails (260px, RotatedBox, 52px bands, horizontal-scroll AutoEq rack)
- [x] **PCM live wave (PW1)** — `PcmRecorderBridge` computes per-read peak in existing loop (zero extra alloc), emits via `pcm_events` EventChannel at 50ms throttle; `PcmRecorder.amplitudes()` stream; Workbench lossless mode renders `_PcmWavePainter` 48-bar level meter replacing static indicator; sub cancelled on stop/dispose
- Gate: `flutter analyze --no-pub` → "No issues found!" (2026-08-25)

## Phase 26 — Pro Workbench + Onboarding (research-backed) [x]
- [x] **26.0 Ghost legibility** — floating panel got translucent grey scrim (`0x9B232328`, r10) so text reads over any backdrop; still chrome-free
- [x] **26.0b API-key onboarding** — native `storage/openUrl` (ACTION_VIEW intent, zero new deps); Settings GENIUS/ACRCLOUD section titles are tappable registration links (genius.com/api-clients, console.acrcloud.com); ghost knows both rituals ("GENIUS KEY RITUAL"/"ACRCLOUD RITUAL"), launches pages on command ('open genius'/'open acr'), SETTINGS chips added
- [x] **26.1 Waveform Studio** — `lib/widgets/waveform_studio.dart`: real waveform via FFmpeg s16le mono-8k decode → peak bucketing (1200 bars), Audacity-style mirrored bars w/ selection highlight + dim-outside-shade, adaptive time ruler (100ms→5min ticks), drag-to-select w/ edge-handle snapping zones, ZOOM ±/FIT viewport buttons + RangeSlider pan strip, IN/OUT readouts; auto-syncs CLIP `_startCtrl/_endCtrl`; mounted for every loaded file + PCM recordings (duration probed into `_wbDurationMs` on mount/HALT)
- [x] **26.2 Edit ops pack** — 9 new ops: Insert Silence (`adelay`/`apad`, start/end toggle + length slider), Delete Region (`aselect not(between)` — wave-driven bounds), Mix With File (`amix normalize=0` + second-media picker), Crossfade Join (`acrossfade` + length slider), Click/Pop Repair (`adeclick`), De-Esser (`deesser` intensity), Limiter (`alimiter` ceiling), Multiband Compress (`mcompand`), DC/Rumble Fix (`highpass f=10`). All container-preserving
- [x] **26.3 yt-dlp Help Sheet** — Grabber header help icon → FIELD MANUAL bottom-sheet: engine intro, site matrix, 3 grab modes, EXPORT AS explainer, pro tips (direct link/scorched-earth/doctor/playlist flow), known limits (DRM/private/live)
- [x] **26.4 Stretch** — Tone Generator op (sine 20–8k / white / pink, duration slider → MediaStore + auto-mount); Spectrogram Snapshot op (`showspectrogrampic` 1280x720 PNG); MediaStore tail hardened to fall back to cache-path reporting when inject fails (png MIME)
- [x] **Tap-feedback polish sweep** — `TapFeedback.machineTap()` wired into 25 user-facing handlers across grabber/forge/pipeline/settings (internal chain handlers excluded to prevent double-beeps); **visual layer installed**: `CyberTapFeedback` (particle burst + shockwave ring + scale pulse) wrapped in pure-visual mode (`enableHaptic/enableAudio: false` — no double-fire, inner button keeps single onPressed) around the 8 primary actions: Workbench MOUNT MEDIA / REC-HALT / EXECUTE ON THE MACHINE (16-particle), Grabber MEDIA HUNTER, Forge MOUNT MP3 FILE / INJECT TAGS & EXPORT (16p), Pipeline EXECUTE BATCH (16p), Settings WRITE TO KERNEL (16p)
- [x] **FEEDBACK MATRIX card** — Settings > UI PREFERENCES directly under accent color: `lib/core/feedback_settings.dart` persisted notifiers (burst/ring/pulse/sound/haptics — haptics default OFF per operator preference); gates spliced into `tap_feedback.dart` primitives + `cyber_tap_feedback.dart` `_triggerBurst` (per-layer combos, all-off skips animation); completion haptics via `machineConfirm()` on workbench/forge/grabber/pipeline success tails; loaded at boot
- Gate: `flutter analyze --no-pub` → "No issues found!"

## Phase 27 — De-pipeline + Forge save-back + Player core (cloud sweep) [x]
- [x] **27.1 Grabber hand-off is voluntary** — download cards, M4A default, cancel, share intent, playlist cards
- [x] **27.2 Forge standalone** — working copy + save-back over the original (createWriteRequest), review sheet, play in player, form-only reset/strip/clear
- [x] **27.3 Spider** — timeouts, scored iTunes/Deezer/MusicBrainz candidates, LRCLIB duration match, Genius optional
- [x] **27.4 Player core** — live device EQ + presets, ReplayGain, fades, video-aware transport, lock-screen art, queue UX, playlists/favorites/recent, embedded lyrics
- [x] **27.5 Library** — MediaStore library (songs/albums/artists/folders/playlists/new), edit in Forge, system delete
- [x] **27.6 Batch** — library multi-select, single permission prompt, confidence gate + REVIEW
- [x] **27.7 Hygiene** — mojibake/BOM/.gitignore/local.properties, widget media buttons, Whisper model download
- [x] **27.9 Album art** — player art cascade (embedded tag → Android MediaMetadataRetriever → cover/folder/front/album image), jaudiotagger Android mode + raw FLAC/Vorbis picture blocks + APIC type 3, YouTube DASH m4a flattened before tagging (G24/G25)
- [x] **27.8 Dependency max** — resolver audit: ffmpeg_kit 0.6.2, just_audio 0.10.6 (+audio_session 0.2.4, playlist API, EQ gains now true dB), audio_waveforms 2.0.2 (RecorderSettings), permission_handler 12.0.3, flutter_lints 6, launcher_icons 0.14.4. Still capped: file_picker 9 ↔ wakelock_plus 1.5.2 (win32 pair), permission_handler 13 (compileSdk 37)
- Gate: `flutter analyze --no-pub` → "No issues found!" (Flutter 3.47.5); device smoke pending

## Phase 28 — Game-feel pass (visual FX, SFX, ghost 2.0, transitions) [ ]
- [x] **28.1 Feel** — native `SoundPool` SFX engine + 13-sound Dart synth bank (fixes UI sounds ducking music), global `TapFxLayer` (pulse / ring / spark burst + tap sound on every tappable), `CyberInk` theme splash, `CyberTapFeedback` fixed (press-scale, keeps child)
- [x] **28.2 Ghost look** — no black box, frosted-glass chat panel with accent outline, outlined query field, living ghost (float/breathe/blink/eyes/tail, talking/thinking/emotion), pauses when hidden
- [ ] **28.3 Ghost brain** — offline, free: current-app knowledge, typo-tolerant matching, real commands, follow-ups
- [ ] **28.4 Shaders + transitions** — GPU backdrop per tab, animated tab switches, page transitions, animated nav, perf pass
- Gate per slice: `flutter analyze --no-pub` clean + scratch widget tests (flutter_tester) + shader compile (impellerc) where relevant; device smoke in SESSION_HANDOFF

## Phase S0–S4 — SOVEREIGN SDK EDITION (future track, operator-approved spec)

> Rationale: yt-dlp/chaquopy is what blocks store distribution AND pins the toolchain ceiling (chaquopy 17.0.0 maxes AGP at 9.2, drags Python 3.14 wheel scarcity, ~120-150MB on-device Python tax, Built-in-Kotlin migration blocked). An SDK/core edition strips Python entirely → publishable build + unlocked ceiling + feature headroom. Full edition keeps living side-by-side for personal use.

- [ ] **S0 — Python dependency audit**: inventory every touchpoint before cutting — `bridge.py` (Grabber search/download/merge), `spider.py` (Genius→LRCLIB→SoundCloud→iTunes→MusicBrainz enrichment), `updater.py`/`doctor.py` (self-heal). Everything else is already native/Dart: ACRCloud = Kotlin bridge ✓, ID3 = jaudiotagger ✓, Whisper = FFmpeg filter ✓, ghost brain = pure-Dart TF-IDF ✓, PCM = AudioRecord ✓.
- [ ] **S1 — Dart spider port** (the last real Python dependency): reimplement `spider.py` cascade as pure-Dart HTTPS calls (all five sources are plain REST APIs — `dart:io` HttpClient, zero new deps). Lives beside the Kotlin ACR bridge so Pipeline enrichment survives Python removal. Add unit-check against known tracks.
- [ ] **S2 — Gradle flavors**: `full` (current: chaquopy + Grabber + python/) vs `sdk` (no python source set, no Grabber tab, no updater/doctor channels). Conditional tab registration in MainShell via flavor. Self-heal story for sdk edition: doctor/updater features hidden; yt-dlp maintenance N/A.
- [ ] **S3 — Ceiling raise (sdk flavor only, dedicated session)**: after chaquopyectomy — migrate to **Built-in Kotlin** (kills the recurring KGP warning), AGP past 9.2 when Flutter demands, Gradle/KGP current, `compileOptions 1.8→17`, compileSdk/NDK bumps as Flutter requires. NOTE (honest scope): the `win32 5.9.0 ↔ file_picker ^9 ↔ wakelock` cap is a WINDOWS-desktop-plugin conflict, NOT Python-related — it lifts separately via its own `--major-versions` session. Post-raise feature unlocks: modern ML (TFLite successor becomes viable — JVM 17), url_launcher-class plugins safe, newer audio packages.
- [ ] **S4 — SDK packaging**: flat `SovereignTagger-SDK.apk` via existing outputFileName pattern; distribution targets = GitHub Releases / F-Droid-style repo / direct APK (Play becomes *possible* for sdk flavor since no ripper inside — operator call). Version-of-record docs split: README gets an EDITIONS table.
- Gate per slice: analyze clean + Moto G smoke; S3 additionally needs full release-build regression on both flavors.

## Phase 28+ (future)
- True overlapping crossfade (second player), custom 15-band real-time DSP (device EQ is usually 5 bands), visualizer, Android Auto browse tree
- Cloud sync, Last.fm scrobbling, Chromecast, Opus encoding, multi-user profiles
