# SOVEREIGN TAGGER

An autonomous, decentralized media pipeline for Android. Sovereign Tagger unifies stream ripping (`yt-dlp` via chaquopy Python 3.14), lossless DSP (`FFmpeg` `full+gpl` + global `FFmpegExecutor` queue), PCM studio capture (`AudioRecord` 48k/16-bit WAV), and intelligent metadata injection (`ACRCloud` + `Genius` + `LRCLIB` cascade) into a single cyberpunk matrix.

## ⚠️ Core Philosophy

This application operates completely outside the walled gardens of standard app stores. It was engineered to give users absolute control over local media files, bypassing DRM and streaming-service renting models. Desktop-class tagging, phone-native.

## 🛠 Capabilities

### 1. **The Grabber** — Stream Ripper
- Rip from YouTube/SoundCloud/Bandcamp/1000+ sites; paste a link, **share** one into the app, or hunt by artist + title
- **Nothing is forced**: each finished download becomes a card with editable title/artist/album/track, file name and thumbnail-as-cover, then **PLAY / SAVE TO MUSIC / SEND TO FORGE / DISCARD**
- Audio modes: **M4A ORIGINAL** (default, the site's AAC stream, no re-encode), **MP3 320K**, **AS-IS**
- Parallel downloads with progress + **cancel**; playlists become one card per track + SAVE ALL
- Video: quick-video or per-format picker with 3-rung verified merge ladder; Facebook silent-video self-heal

### 2. **The Forge** — Standalone Tag Editor
- Mount any song (picker, or **Edit in Forge** from Library / Player / Grabber). Edits happen on a private working copy; nothing is written until **SAVE**
- **SAVE & FIX ORIGINAL** rewrites the song in place (Android's modify-permission prompt) — no duplicates; **SAVE AS A NEW COPY** optional; editable file name
- **SEARCH METADATA** (iTunes / Deezer / MusicBrainz candidates, scored) and **IDENTIFY** (ACRCloud) open a review sheet: current vs proposed per field, pick the right release, artwork, synced or plain lyrics
- **PLAY IN PLAYER**, lyrics FIND (LRCLIB) + karaoke SYNC (embedded on save), read-back verification on the final file

### 3. **Batch** — Many Songs At Once
- Load from the Library (multi-select) or files; one permission prompt covers the whole batch; tracks are fixed in place
- Matches ≥80% confidence are applied automatically; the rest land in **REVIEW** and open in the Forge
- ACRCloud fingerprints GHOST tracks when keys are set, otherwise file names are used; Genius is optional
- **Mixtape Join**: lossless concat of PROCESSED mp3s

### 4. **The Workbench** — Direct FFmpeg Injection
- **Extract Audio**, **Clip** (`HH:MM:SS` validated, keyframe-aware `-ss` before `-i` for video), **Convert Format**, **Normalize LUFS -14** (single + **two-pass** `loudnorm` JSON), **Granular DSP** (speed `asetrate`/`aresample`, reverb `aecho`, reverse), **Apply Fades** (`afade` with duration-derived `outStart`), **Fold To Mono** (`pan`), **Trim Silence** (`silenceremove -45dB`)
- **Mastering Quality**: `Source/44.1/48/96k soxr` + `16/24-bit` for `wav/flac`
- **ReplayGain Scan**: `ebur128` → TXXX frames (`REPLAYGAIN_TRACK/ALBUM_GAIN/PEAK`) via `id3` channel
- **15-Band Equalizer (AutoEq)**: 15 bands (25Hz–16kHz, Q=1.2), purple-accent UI, SAVE PRESET/FLAT, persists to `SharedPreferences`, syncs with the dedicated **EQ PRESETS screen** (tune icon in Workbench header)
- **Crossfade/Gapless**: relocated to the **PLAYBACK ENGINE screen** (merge icon in Player AppBar)
- **AI Denoise**: `afftdn=nf=-25`, **Parametric EQ** (5-band ±12dB), **Compress Dynamics** (`acompressor` 1-12:1)
- **DSP Pitch Modes**: VARISPEED / RUBBERBAND / ATEMPO dropdown
- **Whisper AI**: `ggml-base.en.bin` (141MB, downloaded once on first use or bundled from `assets/models/`), `-af "whisper=model=<path>:language=<en|auto>" -f srt`, writes `.srt` sidecar + text preview, self-diagnosing fallback pulls `-h filter=whisper`
- **Studio Recorder**: Toggle `LOSSLESS PCM (48K WAV)` (default, `AudioRecord` 48k/16-bit WAV, header finalize LE, `ByteBuffer` reuse) or fallback `aac 48k/256k 50ms`

### 5. **The Player** — Theater Mode
- Mini-player (art, prev/play/next) + full-screen Now Playing: pinch-zoom art, double-tap ±10s, swipe to skip, favorites
- **Equalizer heard live**: 15-band curve + genre presets mapped onto the phone's EQ; **ReplayGain** (track/album + pre-amp, clip-safe); **fade transitions**
- Queue: titles/artists, drag to reorder, swipe to remove, save as playlist; queue + position survive restarts
- Lyrics: embedded synced (karaoke) or plain lyrics, sidecar `.lrc`, or fetch from LRCLIB
- Lock screen / headset / notification controls with artwork; sleep timer with fade-out or end-of-track; speed 0.5–2x

### 6. **Ghost in the Machine** — Offline Co-Pilot (free, no cloud)
- Living code-drawn ghost: floats, breathes, blinks, glances where you tap, rippling tail, hologram scanlines; listens while you type, thinks, talks in sync with its typing; emotions + glitch laugh
- Frosted-glass chat panel (blurs what's behind it) with accent outline and outlined query field
- **Brain** (`lib/services/ghost_brain.dart`, pure Dart): typo-tolerant understanding + BM25 knowledge base of every screen and fix, and real commands — `play <artist|album|song>`, `play X by Y`, `shuffle everything`, `queue X`, `play X next`, next / previous / pause, shuffle & repeat modes, `sleep in 30 min` / `stop after this song`, `what's playing`, `favorite this`, `fix this song` (Forge), `open forge|library|eq|settings`, `how many songs by X`, paste a link to grab it; "which one?" follow-ups and "more" for deeper answers
- **First-launch sequence** + per-tab tutorial, suggestion chips, Settings: visibility, auto-expand, reduce-motion, reset first-launch
- **Voice query (optional)**: mic button beside SEND — tap to arm, tap again or wait for the 12s cap, and the transcript fills the query field **for you to confirm**. It never auto-sends, because the Ghost can play and delete real media and a misheard command must not execute unreviewed. Runs entirely offline on the same Whisper model the Workbench already uses, so **no extra download and no APK growth**; the first use on a fresh install pulls the 141MB model once with a progress bar. Tap again mid-download or mid-transcription to cancel. Silence is rejected rather than guessed at, including Whisper's stock "Thank you." / "Thanks for watching!" hallucinations
  - Engine is swappable behind one interface (`lib/core/speech_to_text.dart`): `WhisperFfmpegEngine` is live; `WhistleEngine` (Cactus Compute, 16.9MB on-device model) is registered but not wired, since it needs an NDK/CMake/JNI bridge the app does not have yet
- **Rotation**: the app never requests an orientation. There is no `setPreferredOrientations` call anywhere in `lib/` and no `screenOrientation` in the manifest — the device's own rotation setting is the only thing that controls orientation, so nothing here can flip the auto-rotate quick tile

### 7. **Library Tab** — Your Music
- Reads the phone's music library: **Songs, Albums, Artists, Folders, Playlists, New**; live search; sort
- Favorites, Recently Played and your own playlists (reorder, rename, delete)
- Long-press: play next, add to queue, add to playlist, favorite, **Edit in Forge**, delete (system prompt)

### 8. **Home Screen Widget** — RemoteViews
- PREV / PLAY-PAUSE / NEXT drive playback through media buttons; shows the current track

### 9. **Backup/Restore** — XOR Encrypted
- Export/import settings + EQ presets + persisted queue as encrypted JSON binary (XOR `0x53` + `base64`)

### 10. **Visuals** — Code-Drawn Cyberpunk
- `MatrixRain` splash (code-drawn katakana/hex, single `TextPainter` reuse)
- Per-tab GPU `CyberBackdrop` (`shaders/backdrop.frag`, 30 fps, paused in background) — accent nebula + synthwave grid floor, with a per-tab layer: Grabber data streams, Forge embers, Batch scan bands, Workbench waveform. Falls back to the `AmbientBackdrop` painter (pulsing grid + electric arcs + traveling pulse comets) if a device can't load the shader
- `AnimatedTabStack` (fade/slide, tab state + typed text preserved, hidden tabs' tickers paused), `CyberNavBar` (spring pill, icon pop, whoosh), `CyberPageTransitionsBuilder` on every route, Hero cover-art mini-player → player
- **Reduce Motion (Global)**: Disables all glitch/wobble/scanlines when enabled

### 11. **Cyberpunk Tap Feedback** — Audio + Visual
- 13 synthesized 48 kHz UI sounds (tap, select, confirm, back, error, whoosh, open, close, type, message, success, glitch) generated in Dart on first launch, played through native `SoundPool` — never ducks your music
- Every button, list row, chip and switch gets a pulse outline, shockwave ring and spark burst automatically (`TapFxLayer`), plus the `CyberInk` splash inside the button

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
- **Haptics & sound:** Taps fire `TapFeedback` → `Sfx` (native `SoundPool`, synthesized bank, no asset files); haptics follow the Settings toggle.
- **ACRCloud mic stuck:** Fixed — bridge fully stops+releases client after every recognition.

---

## 🎨 Assets & Animation

- **Assets are compile-time:** declared in `pubspec.yaml:34` `assets: - assets/` (`splash-screen-bg.png`, `ShareTechMono`/`VT323`). No runtime `File('assets/...')` writes — generated media goes via `getTempDirectory` + `MediaStore`.
- **Size:** `ffmpeg_kit full+gpl` is ~40MB/ABI (`arm64-v8a,x86_64` only). Prefer code-drawn (`CustomPainter`/`Shader`/`Lottie` ~20KB `json`) over raster video — `MatrixRain`, `AmbientBackdrop` and the `backdrop.frag` shader are all code-drawn (the shader is a few KB of GLSL, no texture).
- **Tap sounds:** No sound assets — `lib/core/sfx_synth.dart` synthesizes the bank at first launch (~0.2 s) and caches the WAVs.
- **Per-tab dramatics:** `CyberBackdrop` runs `shaders/backdrop.frag` on the GPU (30 fps, own `RepaintBoundary`, paused in background): accent nebula + synthwave grid floor, plus a per-tab layer — Grabber data streams, Forge embers, Batch scan bands, Workbench waveform. Falls back to the old `AmbientBackdrop` painter if a device can't load the shader.
- **Motion:** `AnimatedTabStack` slides/fades tabs (state kept, hidden tabs' tickers paused), `CyberNavBar` springs a glowing pill between tabs (whoosh SFX), `CyberPageTransitionsBuilder` rises pages in behind an accent scanline sweep, and cover art flies from the mini-player into the full player (Hero).

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

### Ghost Brain (On-Device, Pure Dart)
- **Engine**: `lib/services/ghost_brain.dart` — `GhostBrain.respond()` routes: link → grab, pending "which one?" choice, "more" follow-up, small talk, commands, then BM25 over ~28 knowledge entries
- **Two views of input**: canonical words (synonyms + edit-distance typo fix) detect intent; raw words drive phrases and library search, so artist names like "Love" or "The Wires" survive
- **App bridge**: `lib/services/ghost_world.dart` (`AppGhostWorld`) implements `GhostWorld` over `AudioService`, `SovereignState`, `PlaylistStore` and MediaStore — the brain itself has no Flutter imports and is unit-tested with a fake world
- **Zero native deps, zero fees**: no model download, no network

### Contextual Tutorials (Per Tab)
| Tab       | Sample Tips                                                                                                                                               |
|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| GRABBER   | "Paste/share a link or HUNT", "Cards: PLAY / SAVE / SEND TO FORGE / DISCARD", "M4A original by default"                                                   |
| FORGE     | "Nothing written until SAVE", "Review sheet for SEARCH/IDENTIFY", "SAVE & FIX ORIGINAL rewrites in place"                                                 |
| BATCH     | "Load from Library, one permission prompt", "≥80% auto-fixed, rest go to REVIEW", "MIXTAPE JOIN lossless concat"                                           |
| WORKBENCH | "15-band EQ (AutoEq), LUFS -14, Whisper, PCM LOSSLESS", "Pitch modes: VARISPEED/RUBBERBAND/ATEMPO", "REPLAYGAIN scan writes TXXX tags"                    |
| LIBRARY   | "Songs/Albums/Artists/Folders/Playlists/New", "PLAY ALL / SHUFFLE", "Long-press → Edit in Forge"                                                         |
| PLAYER    | "Mini-player + Now Playing, pinch-zoom", "Queue drag/swipe, favorites, playlists", "Live EQ, ReplayGain, fades"                                           |
| SETTINGS  | "Genius/ACR keys, color picker, FFmpeg probe, cache purge", "Backup/Restore encrypted JSON", "Ghost Tutorial: reduce-motion, reset first-launch" |

---

## 🔧 Build Notes (Frozen Ceiling)

| Dependency                    | Version                      | Constraint                                                            |
|-------------------------------|------------------------------|-----------------------------------------------------------------------|
| `ffmpeg_kit_extended_flutter` | `^0.6.2`                     | `full`+`gpl`, latest (FFmpeg 9.0.1)                                   |
| `just_audio` / `audio_session`| `^0.10.6` / `^0.2.4`         | Latest; EQ gains are real dB since 0.10 (see G18)                     |
| `audio_waveforms`             | `^2.0.2`                     | Latest (`RecorderSettings` API)                                       |
| `file_picker`                 | `^9.0.0` (9.2.3)             | **Capped** — 10+ needs win32 6.x; 13.x is a full API rewrite          |
| `wakelock_plus`               | `^1.5.2`                     | **Capped** — 1.6.1+ needs win32 6.x (blocked by file_picker 9)        |
| `permission_handler`          | `^12.0.3`                    | **Capped** — 13.x needs compileSdk 37 (root gradle forces 36)         |
| `chaquopy`                    | `17.0.0`                     | Python 3.14 top (few wheels), fallback `"3.11"` in `app/build.gradle` |
| `AGP` / `KGP` / `Gradle`      | `9.0.1` / `2.3.20` / `9.1.0` | At ceiling                                                            |
| `compileSdk` / `NDK` / `JDK`  | `36` / `28.2` / `25`         | `compileOptions 1.8` shim (bump to 17 in dedicated session)           |

> **Note**: The only dependency ceiling is the `file_picker` ↔ `wakelock_plus` win32 pair plus the compileSdk-37 wall on `permission_handler` 13. Do not run `flutter pub upgrade --major-versions`; plain `flutter pub upgrade` is safe.

---

## 📦 Project Structure

```
lib/                                # 44 files (LOC intentionally not asserted — it drifts; see CURRENT_STATE.md)
├── main.dart                      # Entry: accent_color → Splash → MainShell
├── core/
│   ├── audio_handler.dart          # SovereignAudioHandler (audio_service lockscreen)
│   ├── cyber_tap_feedback.dart     # CyberTapFeedback (particle burst + ring + press-scale)
│   ├── eq_mapper.dart              # 15→N-band gain mapping, ReplayGain volume/boost
│   ├── ffmpeg_executor.dart        # Serialized FFmpegExecutor queue
│   ├── feedback_settings.dart      # FeedbackSettings burst/ring/pulse/sound/haptics (prefs)
│   ├── forge_request.dart          # ForgeRequest (cross-tab handoff, user-initiated)
│   ├── ghost_settings.dart         # GhostSettings ValueNotifiers (prefs, first-launch v2)
│   ├── lrc.dart                    # LRC parse/format/active-index + offset
│   ├── media_probe.dart            # probeStreams/probeDurationMs (FFprobeKit)
│   ├── metadata_sources.dart       # Spider/ACR channels → MetaCandidate + lyrics + artwork
│   ├── pcm_recorder.dart           # PcmRecorder MethodChannel + pcm_events amplitudes
│   ├── playback_fx.dart            # PlaybackFx pipeline (AndroidEqualizer/loudness, EQ state)
│   ├── playlists.dart              # Playlists/favorites/recent, debounced persist
│   ├── sfx.dart                    # Sfx/SfxId — SoundPool bank, volume+jitter, 60ms dedupe
│   ├── sfx_synth.dart              # 13-sound 48kHz bank synthesized in Dart
│   ├── storage_client.dart         # MediaStore query/write/overwriteOriginal/loadArtwork
│   ├── tag_io.dart                 # TagIO write→read-back verify + DASH-moof flatten
│   ├── tap_feedback.dart           # TapFeedback — haptic + Sfx.play only (no just_audio)
│   ├── title_cleaner.dart          # Messy-title normalization
│   ├── speech_to_text.dart         # SpeechEngine interface + WhisperFfmpegEngine + WhistleEngine (unwired)
│   ├── voice_input.dart            # VoiceInput: mic permission, capture, 12s cap, transcription, cleanup
│   └── whisper_model.dart          # First-use Whisper ggml model extraction to cache
├── screens/
│   ├── main_shell.dart             # AudioService, GhostChatOverlay, CyberBackdrop, AnimatedTabStack, CyberNavBar
│   ├── settings_screen.dart        # KERNEL/SYSTEM — keys, accent, maintenance, ghost, backup
│   ├── playback_engine_screen.dart # Crossfade/Gapless/Audit (Player AppBar entry)
│   ├── eq_presets_screen.dart      # 15-band presets (Player tune-icon entry)
│   └── lyric_sync_screen.dart      # Karaoke isolated player
├── tabs/
│   ├── tab_grabber.dart            # Search/format/download/merge
│   ├── tab_forge.dart              # ID3 editor, karaoke, export
│   ├── tab_pipeline.dart           # Batch buckets, ACR/Genius/LRCLIB
│   ├── tab_workbench.dart          # DSP, Whisper, ReplayGain, live EQ editor
│   ├── tab_player.dart             # Theater, mini-player, queue
│   └── tab_library.dart            # MediaStore browse
├── widgets/
│   ├── animated_tab_stack.dart     # AnimatedTabStack (uniform wrapper chain, G32)
│   ├── cyber_backdrop.dart         # CyberBackdrop — GPU shader, AmbientBackdrop fallback
│   ├── cyber_ink.dart              # CyberInk theme splash factory
│   ├── cyber_nav_bar.dart          # CyberNavBar — spring pill, icon pop, whoosh
│   ├── cyber_page_transitions.dart # CyberPageTransitionsBuilder
│   ├── ghost_avatar.dart           # GhostAvatar — ticker-driven living ghost + moods
│   ├── ghost_chat_overlay.dart     # Glass chat panel, chips, bubbles, first-launch
│   ├── machine_rain.dart           # MatrixRain + AmbientBackdrop (painter fallback)
│   ├── metadata_review_sheet.dart  # current vs proposed metadata review
│   ├── playlist_picker.dart        # Playlist selection sheet
│   ├── tap_fx_layer.dart           # TapFxLayer — global tap FX for every tappable
│   └── waveform_studio.dart        # Waveform peaks/select/zoom
└── services/
    ├── ghost_brain.dart            # GhostBrain — offline BM25 commands + knowledge base
    └── ghost_world.dart            # AppGhostWorld bridge to AudioService/SovereignState

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

# Build APK — allowed on this host (RULES §1.5). End-of-plan only; it takes minutes.
flutter build apk --release
# Release signing falls back to the DEBUG keystore unless SOVEREIGN_KEYSTORE is set,
# so the output is NOT Play-ready. Install/run on the Moto G via Android Studio.
```

---

## 📝 License

Proprietary — sovereign by design. No telemetry, no cloud, no accounts.

---

*Built for the sovereign operator. The machine serves you.*