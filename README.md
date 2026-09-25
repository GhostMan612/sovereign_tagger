# SOVEREIGN TAGGER

An autonomous, decentralized media pipeline for Android. Sovereign Tagger unifies stream ripping (`yt-dlp` via chaquopy Python 3.14), lossless DSP (`FFmpeg` `full+gpl` + global `FFmpegExecutor` queue), PCM studio capture (`AudioRecord` 48k/16-bit WAV), and intelligent metadata injection (`ACRCloud` + `Genius` + `LRCLIB` cascade) into a single cyberpunk matrix.

## ⚠️ Core Philosophy

This application operates completely outside the walled gardens of standard app stores. It was engineered to give users absolute control over local media files, bypassing DRM and streaming-service renting models. Desktop-class tagging, phone-native.

## 🛠 Capabilities

### 1. **The Grabber** — Stream Ripper
- Rip from YouTube/SoundCloud/Bandcamp at max quality
- Quick-audio `bestaudio/best` → Forge, quick-video `bestvideo[height<=RES]+bestaudio/best` (fixed interpolation, UUID `jobId`), or **ADVANCED: FETCH ALL FORMATS** → per-format picker with `audio+video` explicit `-map` merge via 3-rung ladder (`-map 0:v:0 -map 1:a:0` → AAC-remux → default, verified via `probeStreams`)
- Facebook DASH silent-video self-heals with companion `bestaudio` fetch (capped 1 attempt)
- `EXPORT AS` toggle: `MP3 320K` (default) / `SOURCE COPY` (webm/opus/m4a passthrough, zero transcode)

### 2. **The Forge** — ID3 Editor
- Edit ID3 in-place via `Id3Tagger` (jaudiotagger, `deleteField` on empty), preserve container (`flac→flac`, `wav→wav`, `m4a→m4a`, `ogg→ogg`, `opus→opus`)
- Write→read-back round-trip verify, high-res art, `LOSSLESS PCM` not transcoded
- `EJECT MEDIA` deletes cache copy only, confirms for originals
- Karaoke mode: isolated `LyricSyncScreen` player with transport bar + tempo warp, LRC sidecar parse + auto-scroll + tap-to-seek

### 3. **The Pipeline** — Autonomous Batch
- ACRCloud fingerprint (20s `8000Hz mono pcm_s16le` via `FFmpegExecutor`) + `spider.py` cascade (Genius→**LRCLIB**→SoundCloud→iTunes→MusicBrainz)
- LRCLIB lyrics fallback (free, no key) after Genius
- Buckets: `GHOST/PARTIAL/PRISTINE/PROCESSED/FAILED` with **Cancel** (halts loop) and **FAILED retry** (re-buckets to GHOST/PARTIAL)
- **Mixtape Join**: lossless concat demuxer `-c copy -write_xing 1` of PROCESSED mp3s → MediaStore
- Correct MIME mapping (`flac/wav/m4a/ogg/opus` via `StorageBridge.kt`)

### 4. **The Workbench** — Direct FFmpeg Injection
- **Extract Audio**, **Clip** (`HH:MM:SS` validated, keyframe-aware `-ss` before `-i` for video), **Convert Format**, **Normalize LUFS -14** (single + **two-pass** `loudnorm` JSON), **Granular DSP** (speed `asetrate`/`aresample`, reverb `aecho`, reverse), **Apply Fades** (`afade` with duration-derived `outStart`), **Fold To Mono** (`pan`), **Trim Silence** (`silenceremove -45dB`)
- **Mastering Quality**: `Source/44.1/48/96k soxr` + `16/24-bit` for `wav/flac`
- **ReplayGain Scan**: `ebur128` → TXXX frames (`REPLAYGAIN_TRACK/ALBUM_GAIN/PEAK`) via `id3` channel
- **15-Band Equalizer (AutoEq)**: 15 bands (25Hz–16kHz, Q=1.2), purple-accent UI, SAVE PRESET/FLAT, persists to `SharedPreferences`, syncs with the dedicated **EQ PRESETS screen** (tune icon in Workbench header)
- **Crossfade/Gapless**: relocated to the **PLAYBACK ENGINE screen** (merge icon in Player AppBar)
- **AI Denoise**: `afftdn=nf=-25`, **Parametric EQ** (5-band ±12dB), **Compress Dynamics** (`acompressor` 1-12:1)
- **DSP Pitch Modes**: VARISPEED / RUBBERBAND / ATEMPO dropdown
- **Whisper AI**: bundled `ggml-base.en.bin` (141MB), `-af "whisper=model=<path>:language=<en|auto>" -f srt`, writes `.srt` sidecar + text preview, self-diagnosing fallback pulls `-h filter=whisper`
- **Studio Recorder**: Toggle `LOSSLESS PCM (48K WAV)` (default, `AudioRecord` 48k/16-bit WAV, header finalize LE, `ByteBuffer` reuse) or fallback `aac 48k/256k 50ms`

### 5. **The Player** — Theater Mode
- Edge-to-edge `BoxFit.contain` with `InteractiveViewer` pinch 1→3x + bottom scrim
- Controls: shuffle/repeat, **sleep timer** (bedtime 15-90m), **speed** `0.5→2.0x` persisted, **ENQUEUE FILES** + **Play Next** (`moveAfterCurrent` via `_queueLock`), **queue persist** (debounced JSON), **LRC Karaoke** sidecar parse (`_LyricsSheet` auto-scroll + tap-to-seek), **double-tap halves** ±10s + swipe prev/next
- **Lockscreen notification** (`audio_service 0.18.19` `SovereignAudioHandler` + `AudioSession`, `FOREGROUND_SERVICE` perms)
- **Crossfade 0–12s** (`acrossfade` filter) + **Gapless** (`ConcatenatingAudioSource` default-on) — configured in the **PLAYBACK ENGINE screen** (AppBar merge icon): instant-persist slider/toggle + **RUN GAPLESS AUDIT** 2-tone RMS test

### 6. **Ghost Avatar Tutorial Chatbot** — In-App Assistant (classifier-first)
- Code-drawn Android ghost emoji silhouette, glitch effects (scanlines, RGB shift, jitter)
- Glitch laugh: wobble + particle burst + "hahaha" typewriter
- Three-emotion particle system: **Sarcastic** (glitch squares 72%), **Happy** (circles 72%), **Serious** (matrix chars 72%)
- **First-launch sequence**: "Welcome to... The Machine... Shall We Activate SkyNet? ... Just Kidding... hahaha!" → glitchLaugh
- **Contextual tutorials**: 7 tabs × 3 tips each — classifier-first routing (`ghost_classifier.dart` TF-IDF, threshold 0.14), keyword fallback
- **Suggestion chips**: Context-aware action chips
- **Settings**: Visibility, auto-expand, reduce-motion (global), reset first-launch
- *Pure-Dart classifier replacing abandoned TFLite: `lib/services/ghost_classifier.dart` — TF-IDF + cosine similarity, 15 intents, no native dep, identifies intent at 0.14 threshold then falls back to keyword routing — fully ceiling-safe.*

### 7. **Library Tab** — MediaStore Browser
- Browse by ALBUM / ARTIST / FOLDER dropdown
- Real-time search filter by title/artist/album
- Tap track → replaces queue, switches to PLAYER tab
- Artwork decoded from base64 tags

### 8. **Home Screen Widget** — RemoteViews
- `SovereignWidgetProvider` (4-button: PREV/PLAY/NEXT/QUEUE)
- Cyberpunk styling (black bg, accent border, `ShareTechMono`/`VT323`)

### 9. **Backup/Restore** — XOR Encrypted
- Export/import settings + EQ presets + persisted queue as encrypted JSON binary (XOR `0x53` + `base64`)

### 10. **Visuals** — Code-Drawn Cyberpunk
- `MatrixRain` splash (code-drawn katakana/hex, single `TextPainter` reuse)
- Per-tab `AmbientBackdrop` pulsing grid (`BackdropVariant` grabber vertical, forge slow, pipeline horizontal, workbench mixed) + electric arcs + traveling pulse comets
- **Reduce Motion (Global)**: Disables all glitch/wobble/scanlines when enabled

### 11. **Cyberpunk Tap Feedback** — Audio + Visual
- Haptics + embedded 880/1400Hz base64 WAV via `just_audio` data URI
- `CyberTapFeedback`: particle burst (12 dots), expanding shockwave ring, button scale pulse (0.92→1.0)

---

## 🔑 System Initialization: API Keys Setup

To fully unlock the autonomous tagging and fingerprinting pipeline, you must acquire two free API keys and input them into the **Universal Kernel Preferences** (Settings) inside the app.

### Part 1: Genius API (Lyrics & Album Art)
1. Go to [Genius API Clients](https://genius.com/api-clients)
2. Log in or create a free account
3. Click **"New API Client"**
4. Fill in an App Name (e.g., `SovereignTagger`) and an App Website URL (can be `http://localhost`)
5. Click **Save**, copy the **"Client Access Token"** into the app's Genius section

### Part 2: ACRCloud API (Audio Fingerprinting)
1. Go to [ACRCloud](https://console.acrcloud.com/) and create a free account
2. Verify email, log in, navigate to **"Audio & Video Recognition"** → **Projects**
3. Click **"Create Project"**, select **"Audio & Video Recognition"**, name it, choose `Recorded Audio`, select `ACRCloud Music` bucket
4. Copy **Host**, **Access Key**, **Access Secret** into the app

### Part 3: Commit to Kernel
Click **"WRITE TO KERNEL"**. Use **Export** button to generate a `.bin` backup (XOR `0x53` + `base64`) of your keys.

---

## 🛑 Maintenance & Troubleshooting

- **YouTube breaks (Google anti-bot):** Settings → **CHECK FOR YT-DLP UPDATE** (`execute_scorched_earth` pulls latest tarball from GitHub, wipes `yt_dlp/` folder, hot-reloads). If that fails, run **ON-BOARD PYTHON DOCTOR** → inventories `*.py`, probes `yt_dlp` version, snapshots `extractor_args player_client=android,web`, surfaces `PATCH_REGISTRY` hits (android blocked / impersonate removed / 403 throttle / genius 429). Then **FULL STACK REFRESH** (`execute_full_scorched_earth` also best-effort upgrades `mutagen`/`lyricsgenius`).
- **Downloads have no audio (Facebook):** Fixed in-app — silent-video probe + companion `bestaudio` self-heal. If still silent after 1 attempt, use **ADVANCED: FETCH ALL FORMATS** and pick a progressive stream.
- **Workbench quality:** Studio toggle `LOSSLESS PCM` = true WAV. Normal DSP preserves container unless you explicitly **Convert Format**. Two-pass loudnorm parses last `{"input_i":…}` JSON.
- **Haptics:** Button taps fire `TapFeedback` (`HapticFeedback` + embedded `880/1400Hz` 0.7–1.3KB base64 wav via `just_audio` data URI) — no asset files.
- **ACRCloud mic stuck:** Fixed — bridge fully stops+releases client after every recognition.

---

## 🎨 Assets & Animation

- **Assets are compile-time:** declared in `pubspec.yaml:34` `assets: - assets/` (`splash-screen-bg.png`, `ShareTechMono`/`VT323`). No runtime `File('assets/...')` writes — generated media goes via `getTempDirectory` + `MediaStore`.
- **Size:** `ffmpeg_kit full+gpl` is ~40MB/ABI (`arm64-v8a,x86_64` only). Prefer code-drawn (`CustomPainter`/`Shader`/`Lottie` ~20KB `json`) over raster video — `MatrixRain` + `AmbientBackdrop` are code-drawn.
- **Tap sounds:** Avoided `assets/sounds/*.wav` (~50KB each) by embedding base64 wavs in `lib/core/tap_feedback.dart`.
- **Per-tab dramatics:** `AmbientBackdrop` `BackdropVariant` pulses per tab at `alpha 0.035/0.18` + blur — subtle, no asset, 60fps via single `TextPainter` + 1 `AnimationController` per backdrop.

---

## 🤖 Ghost Tutorial Chatbot (Phase 24)

### First-Launch Sequence
```
"Welcome to..." [800ms]
"The Machine" [600ms]
"Shall We Activate SkyNet?" [1000ms]
[GLITCH LAUGH: wobble + particle burst + "hahaha" typewriter]
"Just Kidding... hahaha!" [500ms]
→ Contextual tutorial begins
```

### Pure-Dart Intent Classifier (On-Device)
- **Brain**: `lib/services/ghost_classifier.dart` — TF-IDF + cosine similarity, 15 intents, ~5KB centroids shipped as Dart consts
- **Threshold**: 0.14 confidence → intent reply; below → keyword-chain fallback routing
- **Routing order** (`_processUserQuery`): hide/laugh short-circuits → classifier → keyword chains
- **Zero native deps**: replaces the abandoned `tflite_flutter` lane (fatal JVM-target mismatch 1.8 vs 25 under the frozen ceiling)

### Contextual Tutorials (Per Tab)
| Tab       | Sample Tips                                                                                                                                               |
|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| GRABBER   | "Tap SEARCH → type query → pick format → DOWNLOAD", "EXPORT AS: MP3 320K or SOURCE COPY", "Facebook videos auto-heal with bestaudio"                      |
| FORGE     | "Load file, edit tags, EXPORT preserves container", "EJECT = cache-only delete", "KARAOKE isolated player"                                                |
| PIPELINE  | "GHOST→PARTIAL(ACR)→PRISTINE(Genius)→PROCESSED", "CANCEL halts batch", "MIXTAPE JOIN lossless concat"                                                     |
| WORKBENCH | "15-band EQ (AutoEq), LUFS -14, Whisper, PCM LOSSLESS", "Pitch modes: VARISPEED/RUBBERBAND/ATEMPO", "REPLAYGAIN scan writes TXXX tags"                    |
| LIBRARY   | "Browse by ALBUM/ARTIST/FOLDER", "Tap track → replaces queue", "Artwork from base64 tags"                                                                 |
| PLAYER    | "Mini-player + theater, pinch-zoom 1→3x", "Speed 0.5x–2x, sleep timer, shuffle/repeat", "Crossfade 0–12s + Gapless"                                       |
| SETTINGS  | "Genius/ACR keys, color picker, FFmpeg probe, cache purge", "Backup/Restore encrypted JSON", "Ghost Tutorial: reduce-motion, reset first-launch" |

---

## 🔧 Build Notes (Frozen Ceiling)

| Dependency                    | Version                      | Constraint                                                            |
|-------------------------------|------------------------------|-----------------------------------------------------------------------|
| `ffmpeg_kit_extended_flutter` | `^0.5.13`                    | `full`+`gpl`, locked at 0.5.13 (win32 5.9.0 cap)                      |
| `video_player`                | `^2.14.0`                    | Capped (2.15+ needs win32 6.x)                                        |
| `wakelock_plus`               | `^1.5.2`                     | Capped (1.7.0+ needs win32 6.x)                                       |
| `just_audio`                  | `^0.9.36`                    | 0.10.x incompatible with audio_service 0.18.x                         |
| `audio_service`               | `^0.18.19`                   | Locked (0.19+ needs just_audio 0.10+)                                 |
| `chaquopy`                    | `17.0.0`                     | Python 3.14 top (few wheels), fallback `"3.11"` in `app/build.gradle` |
| `AGP` / `KGP` / `Gradle`      | `9.0.1` / `2.3.20` / `9.1.0` | At ceiling                                                            |
| `compileSdk` / `NDK` / `JDK`  | `36` / `28.2` / `25`         | `compileOptions 1.8` shim (bump to 17 in dedicated session)           |

> **Note**: Major version upgrades (`^0.6.0`/`^12.0.0`/`^0.10.6`/`^13.0.1`) need `--major-versions` and break `win32 5.9.0↔6.0.1`. Stay pinned until dedicated session.

---

## 📦 Project Structure

```
lib/                                # ~10.3k LOC, 23 files
├── main.dart                      # Entry: accent_color → Splash → MainShell
├── core/
│   ├── audio_handler.dart         # SovereignAudioHandler (audio_service)
│   ├── cyber_tap_feedback.dart    # CyberTapFeedback (haptic + particle + ring)
│   ├── ffmpeg_executor.dart       # Serialized FFmpegExecutor queue
│   ├── ghost_settings.dart        # GhostSettings ValueNotifiers (prefs)
│   ├── media_probe.dart           # probeStreams/probeDurationMs (FFprobeKit)
│   ├── pcm_recorder.dart          # PcmRecorder MethodChannel wrapper
│   └── tap_feedback.dart          # TapFeedback (haptic + base64 tick/boop)
├── screens/
│   ├── main_shell.dart            # 1091L: AudioService, GhostChatOverlay, tabs, mini-player
│   ├── settings_screen.dart       # 772L: KERNEL/SYSTEM — keys, accent, maintenance, ghost, backup
│   ├── playback_engine_screen.dart# 182L: Crossfade/Gapless/Audit (Player AppBar entry)
│   ├── eq_presets_screen.dart     # 171L: 15-band presets (Workbench tune-icon entry)
│   └── lyric_sync_screen.dart     # Karaoke isolated player
├── tabs/
│   ├── tab_grabber.dart           # 866L: Search/format/download/merge
│   ├── tab_forge.dart             # 632L: ID3 editor, karaoke, export
│   ├── tab_pipeline.dart          # 560L: Batch buckets, ACR/Genius/LRCLIB
│   ├── tab_workbench.dart         # 1445L: DSP, Whisper, ReplayGain, live EQ editor
│   ├── tab_player.dart            # 1091L: Theater, mini-player, queue
│   └── tab_library.dart           # 332L: MediaStore browse
├── widgets/
│   ├── ghost_avatar.dart          # 660L: Code-drawn ghost, glitch, laugh
│   ├── ghost_chat_overlay.dart    # 595L: Chat UI, first-launch, tutorials
│   └── matrix_rain.dart           # 308L: MatrixRain + AmbientBackdrop
└── services/
    └── ghost_classifier.dart      # 339L: Pure-Dart TF-IDF intent classifier

android/
├── app/src/main/kotlin/com/sovereigntagger/
│   ├── MainActivity.kt            # AudioServiceActivity, 7 MethodChannels
│   ├── Id3Tagger.kt               # jaudiotagger + ReplayGain TXXX frames
│   ├── PcmRecorderBridge.kt       # AudioRecord 48k/16-bit WAV
│   ├── AcrCloudBridge.kt          # ACRCloud identify + mic release fix
│   ├── StorageBridge.kt           # MediaStore + config export/import
│   └── SovereignWidgetProvider.kt # Home screen widget (RemoteViews)
└── app/src/main/python/sovereign_yt/
    ├── bridge.py                  # yt-dlp search/download/merge (vid+aud split)
    ├── spider.py                  # Genius→LRCLIB→SoundCloud→iTunes→MusicBrainz
    ├── updater.py                 # Scorched earth + full stack refresh
    └── doctor.py                  # PATCH_REGISTRY diagnose

assets/
├── models/ggml-base.en.bin        # 141MB Whisper model
├── splash-screen-bg.png
├── app-icon.png
└── ShareTechMono/VT323 fonts
```

---

## 🔄 Maintenance Commands

```powershell
# Analyze (gate)
flutter analyze --no-pub

# Get dependencies
flutter pub get

# Build APK (device-dependent - use Android Studio on Moto G)
# flutter build apk --release  # DO NOT RUN HERE
```

---

## 📝 License

Proprietary — sovereign by design. No telemetry, no cloud, no accounts.

---

*Built for the sovereign operator. The machine serves you.*