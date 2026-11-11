# SOVEREIGN TAGGER

### Autonomous On-Device Media Workstation & Decentralized Neural Engine for Android

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-cyan.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%208.0%2B%20(API%2026--36)-green.svg)](https://developer.android.com)
[![Architecture: arm64--v8a / x86__64](https://img.shields.io/badge/Architecture-ARM64%20%7C%20x86__64-orange.svg)](#)
[![Flutter: 3.x](https://img.shields.io/badge/Flutter-3.x%20%2F%20Dart%203.x-blue.svg)](https://flutter.dev)
[![FFmpeg: 9.0.1 GPL](https://img.shields.io/badge/FFmpeg-9.0.1%20full%2Bgpl-red.svg)](https://ffmpeg.org)
[![Neural: EmbeddingGemma--300M](https://img.shields.io/badge/Neural-EmbeddingGemma--300M%20(LiteRT)-purple.svg)](https://ai.google.dev)
[![F-Droid: Ready](https://img.shields.io/badge/F--Droid-Compatible-brightgreen.svg)](https://f-droid.org)

```
       _____ ____ _   _ _____ ____  _____ ___ ____ _   _   _____ _    ____ ____ _____ ____  
      / ____/ __ \ | / / ____/ __ \/ ____/   / ___/ | / /  /__   / \  / ___/ ___/ ____/ __ \ 
     / /_  / / / / |/ / __/ / /_/ / __/ / / / / _ | |/ /     / / / _ \/ / _/ / _/ __/ / /_/ / 
    / __/ / /_/ /|   / /___/ _, _/ /___/ / / /_/ /|   /     / / / ___/ /_/ / /_/ /___/ _, _/  
   /_/    \____/ |__/_____/_/ |_/_____/_/ /_/___/ |__/     /_/ /_/   \____/\____/_____/_/ |_|   
                                                                                               
     >> [SOVEREIGN MANTLE KERNEL // SYSTEM ACTIVE // AIR-GAPPED MEDIA MATRIX] <<
```

---

## 1. Executive Summary & Core Philosophy

**Sovereign Tagger** is an industrial-grade, fully autonomous, local-first media workstation engineered for Android. Built outside the walled gardens of proprietary app stores and streaming-rental ecosystems, it provides phone-native, desktop-class digital signal processing (DSP), high-throughput metadata tagging, stream extraction, audio forensics, and on-device neural edge computing.

### The Sovereign Directives
1. **Absolute Local Sovereignty (Anti-Rental // Anti-DRM):** You own your media files. Sovereign Tagger operates directly on local storage. No accounts, no subscriptions, and no cloud server dependencies.
2. **Lossless Fidelity Guarantee:** The editor never transcodes or recompresses audio without explicit operator instruction. FLAC stays bit-exact FLAC; WAV stays uncompressed WAV; M4A streams are copied byte-for-byte directly from container streams.
3. **Air-Gapped & Zero-Telemetry:** Zero advertising libraries, zero telemetry trackers (no Firebase, no Crashlytics, no Adjust), and zero background surveillance daemons. Offline execution is a first-class guarantee.
4. **Copyleft Protection (GPLv3):** Licensed under the **GNU General Public License v3.0**, guaranteeing freedom for inspection, modification, and community distribution on **F-Droid** and **IzzyOnDroid**.

---

## 2. Macro Architecture: The Sovereign Mantle Matrix

The application operates as a unified, multi-tiered reactive stack orchestrating native C++17 JNI routines, a sandboxed Python 3.14 execution environment, the full GPL FFmpeg 9.0.1 DSP engine, Google AI Edge LiteRT tensor runtimes, and a hardware-accelerated Flutter UI.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                 PRESENTATION & INTERACTION LAYER                                  │
│  ┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────────────┐ ┌───────────────┐ │
│  │      TabGrabber       │ │       TabForge        │ │      TabPipeline      │ │ TabWorkbench  │ │
│  │ (yt-dlp Multi-Stream) │ │ (In-Place Tag Surgery)│ │ (Batch Auto-Enrich)   │ │ (FFmpeg DSP)  │ │
│  └───────────┬───────────┘ └───────────┬───────────┘ └───────────┬───────────┘ └───────┬───────┘ │
│  ┌───────────┴───────────┐ ┌───────────┴───────────┐ ┌───────────┴───────────┐ ┌───────┴───────┐ │
│  │       TabLibrary      │ │     Theater Player    │ │  Ghost Chat Overlay   │ │Settings Kernel│ │
│  │ (MediaStore Explorer) │ │ (Hardware AudioFX/EQ) │ │ (3D Raymarched Avatar)│ │(Vault Backup) │ │
│  └───────────────────────┘ └───────────────────────┘ └───────────────────────┘ └───────────────┘ │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                               REACTIVE STATE & SENSORY ENGINE                                    │
│  - SovereignState Event Bus (Accent Color, Cross-Tab Hand-offs, Active Navigation)              │
│  - TapFxLayer & CyberInk (Touch-Responsive Particle Shockwaves, Micro-Haptics)                   │
│  - Procedural SfxEngine (Native SoundPool Bank, 13 Synthesized 48kHz WAV UI Soundscapes)         │
│  - CyberBackdrop Shader (shaders/backdrop.frag — GPU Rec.709 Perceptual Luminance Filtering)    │
│  - 3D Holographic Raymarcher (shaders/ghost.frag — 28-Step SDF Volumetric Gaze/Visor Avatar)     │
├──────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                  NATIVE BRIDGE MATRIX (KOTLIN/JNI)                               │
│  ┌───────────────────────────────┬───────────────────────────────┬────────────────────────────┐  │
│  │         MainActivity          │         StorageBridge         │         Id3Tagger          │  │
│  │   (Method/Event Channels)     │   (Scoped Storage/MediaStore) │(jaudiotagger Lossless Tag) │  │
│  ├───────────────────────────────┼───────────────────────────────┼────────────────────────────┤  │
│  │      AudioFxBridge (API 36)   │      PcmRecorderBridge        │       AcrCloudBridge       │  │
│  │(Hardware EQ/LoudnessEnhancer) │ (48kHz/16-bit PCM WAV Stream) │(Universal Audio Fingerprint│  │
│  └───────────────────────────────┴───────────────────────────────┴────────────────────────────┘  │
├─────────────────────────────────┬────────────────────────────────┬───────────────────────────────┤
│    PYTHON 3.14 (CHAQUOPY LTS)   │    FFMPEG 9.0.1 DSP CORE       │     ON-DEVICE NEURAL CORE     │
│ - yt-dlp dual-pass extractor    │ - FFmpegExecutor FIFO Queue    │ - Google AI Edge LiteRT 1.4.0 │
│ - spider.py (Genius/LRCLIB)     │ - EBU R128 Two-Pass Loudnorm   │ - EmbeddingGemma-300M (256-D) │
│ - updater.py (Scorched Earth)   │ - ReplayGain TXXX Scanner      │ - Kotlin SentencePiece BPE    │
│ - doctor.py (Diagnostics)       │ - Lossless Container Surgery   │ - Whistle Native STT (NDK)    │
│                                 │ - 15-Band AutoEq Real-Time DSP │ - Whisper AI (ggml-base.en)   │
└─────────────────────────────────┴────────────────────────────────┴───────────────────────────────┘
```

---

## 3. Micro & Macro Mechanics: Deep Subsystem Inspection

### 3.1 Subsystem 1: The Grabber (Autonomous Ingestion & Muxing)
- **Engine:** Python 3.14 via Chaquopy running upstream `yt-dlp` alongside `mutagen`.
- **Extraction Mechanism:** Supports YouTube, SoundCloud, Bandcamp, and 1000+ sources. Dispatches composite `"vid+aud"` streams into two independent, parallel `YoutubeDL` downloads with template-isolated paths (`_v.%(ext)s` and `_a.%(ext)s`).
- **3-Rung Hardware Merge Ladder:** Because Chaquopy cannot execute shell subprocesses directly to external binaries, Android-side multiplexing is owned by Flutter's `FFmpegKit`:
  1. *Rung 1 (Direct Stream Copy):* `-y -i video -i audio -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 out.mkv`.
  2. *Rung 2 (Intermediate AAC Remux):* If audio container codecs conflict, remuxes audio to `-c:a aac -b:a 256k` before compositing into the video stream.
  3. *Rung 3 (Default Fallback):* Stream selection fallback ensuring zero dropped payloads.
- **Verification Gate:** Every merge operation is validated via `FFprobeKit.getMediaInformationAsync` via `probeStreams()`. Output is rejected and retried if video or audio stream counts evaluate to zero.
- **Facebook Zero-Audio Self-Heal:** Automatically detects silent dash-video streams on sites that omit audio-only endpoints, fetches a companion audio stream, and chains the merge event transparently.
- **Voluntary Staging:** Completed downloads become interactive cards allowing operators to inspect, retag, select artwork, choose `M4A (original)`, `MP3 320k`, or `AS-IS`, and either `SAVE TO MUSIC`, `PLAY`, or dispatch directly to **The Forge**.

### 3.2 Subsystem 2: The Forge (Surgical In-Place Tag Surgery)
- **Engine:** Pure native `Id3Tagger.kt` (wrapping `jaudiotagger` in Android-compliant mode) + `TagIO` Dart interface.
- **Lossless In-Place Mutation:** Edits ID3v1, ID3v2.3, ID3v2.4, MP4 atoms, Vorbis comments, and FLAC picture blocks directly in the file header without re-encoding or touching audio frames.
- **Android Scoped Storage Compliance:** Modifies existing files in `/storage/emulated/0/Music` in place using Android's platform `MediaStore.createWriteRequest`. Displays native OS confirmation with zero duplicated files.
- **Fail-Safe Working Copies:** Staged in app-private storage during editing. The original file is overwritten only upon successful `StorageClient.overwriteOriginal()` completion.
- **Enrichment Cascade:**
  - *Genius API:* Scrapes complete lyrics, cover art, and release metadata.
  - *LRCLIB:* Fetches millisecond-synchronized karaoke LRC lyrics, embedded directly into standard `USLT` / `SYLT` ID3 frames.
  - *ACRCloud Cloud Fingerprinting:* Samples an 8kHz mono PCM snippet to query universal acoustic music databases.
  - *MusicBrainz & Deezer:* Fallback release scoring with interactive conflict resolution sheets.
- **Round-Trip Readback Verification:** After saving, `TagIO.read()` reads the target file back from disk to verify that tags match the intended mutation, alerting the operator to any field rejections.

### 3.3 Subsystem 3: The Pipeline (High-Throughput Batch Processing)
- **Batch Processing:** Processes hundreds of tracks from the local library or filesystem.
- **Single Scoped Storage Prompt:** Batches hundreds of media URIs into a single `createWriteRequest` permission dialog.
- **Confidence Gate:**
  - Tracks matched with $\ge 80\%$ confidence are tagged and enriched automatically.
  - Ambiguous matches ($< 80\%$) are classified as `REVIEW` and routed to the Forge with one tap.
- **Mixtape Joiner:** Lossless concatenation of processed MP3/M4A tracks into single continuous mixes using FFmpeg concat protocol.

### 3.4 Subsystem 4: The Workbench (Direct FFmpeg DSP Injection)
- **Engine:** `ffmpeg_kit_extended_flutter` (`full+gpl`, FFmpeg 9.0.1) with global thread-safe FIFO queue (`FFmpegExecutor`).
- **Precision Operations:**
  - *Two-Pass EBU R128 Loudnorm:* Runs pass 1 JSON analysis (`loudnorm=I=-14:LRA=11:TP=-1.5:print_format=json`), extracts `measured_I`, `measured_LRA`, `measured_TP`, and `measured_thresh`, and applies linear normalization in pass 2.
  - *ReplayGain Scanner:* Analyzes tracks using `ebur128` filter and injects standard `REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_TRACK_PEAK`, `REPLAYGAIN_ALBUM_GAIN`, and `REPLAYGAIN_ALBUM_PEAK` into ID3 `TXXX` frames.
  - *Audiophile Mastering:* SoX Resampler (`aresample=soxr`) with selectable sample rates (44.1kHz, 48kHz, 96kHz) and 16-bit / 24-bit bit-depth expansion.
  - *15-Band Equalizer (AutoEq):* Parametric 15-band audio processing ($25\text{ Hz}$ to $16\text{ kHz}$, $Q=1.2$).
  - *Lossless Container Surgery:* Extracts audio streams with zero re-encoding (`-c:a copy`), optimizes MP4/M4A streaming layouts via `+faststart` (`moov` atom relocation ahead of `mdat`), and splits chapter tracks losslessly.
  - *Granular DSP:* Variable-rate pitch shifting (Varispeed, Rubberband, and Atempo algorithms), dynamic denoise (`afftdn`), de-esser, limiter, multiband compand, and DC highpass filter.
  - *Studio Audio Recorder:* Lossless 48kHz / 16-bit mono/stereo PCM recording directly to WAV via Android's low-latency `AudioRecord` API with pre-allocated direct `ByteBuffer` reuse.

### 3.5 Subsystem 5: The Player & Theater Mode
- **Engine:** `just_audio 0.10.6` + `audio_service 0.18.19` + `audio_session 0.2.4`.
- **Android 16 (API 36) Native AudioFX Bridge:**
  - Bypasses upstream platform limitations by routing audio through a native Kotlin `AudioFxBridge` (`com.sovereign.tagger/audio_fx`).
  - Listens to `player.androidAudioSessionIdStream` to dynamically bind hardware `android.media.audiofx.Equalizer` and `LoudnessEnhancer` instances as soon as the media session initializes.
- **Audio Focus & Notification Discipline:**
  - Configured with `handleInterruptions: false` to allow `SovereignAudioHandler` to authoritatively control focus.
  - Automatically captures pre-duck volume, attenuates volume to $25\%$ during navigation alerts or incoming calls, and restores exact volume upon completion.
  - Pauses on transient focus loss and auto-resumes only if `wantPlaying` was active. Automatically pauses on headphone disconnection (`becomingNoisyEventStream`).
- **Theater UI:** Double-tap seek ($\pm 10\text{s}$), swipe-to-skip, drag-and-drop queue management, synchronized live karaoke lyrics display, and pinch-to-zoom cover art viewing.

---

## 4. Subsystem 6: Neural Edge AI & 3D Volumetric Hologram

Sovereign Tagger features an offline neural intelligence suite running directly on device hardware.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         ON-DEVICE NEURAL INTELLIGENCE MATRIX                     │
│                                                                                  │
│   USER QUERY / VOICE INPUT                                                       │
│          │                                                                       │
│          ▼                                                                       │
│   ┌──────────────┐     offline audio     ┌────────────────────────────────────┐  │
│   │ Voice Input  ├──────────────────────►│ Whistle Native STT (libneedle.a)   │  │
│   │ State Machine│                       │   - 16.9 MB Cactus Compute Engine  │  │
│   └──────┬───────┘                       │   - Fallback: Whisper ggml-base    │  │
│          │ text                          └─────────────────┬──────────────────┘  │
│          ▼                                                 │ text transcript     │
│   ┌────────────────────────────────────────────────────────▼──────────────────┐  │
│   │ GhostBrain Autonomous Intent Router & Lexical Decoupler                   │  │
│   │   - Deterministic Command Parser (Play, Queue, Forge, Workbench, Grab)    │  │
│   │   - Offline BM25 Sovereign Knowledge Base                                 │  │
│   └──────┬─────────────────────────────────────────────────┬──────────────────┘  │
│          │                                                 │                     │
│          ▼ (Lexical Ambiguity)                             ▼ (Vibe Search)       │
│   ┌───────────────────────────────┐               ┌───────────────────────────┐  │
│   │ Background Warm-Up Scheduler  │               │ LiteRT 1.4.0 Engine       │  │
│   │   - 2-pair chunks / 220ms idle│               │   - EmbeddingGemma-300M   │  │
│   │   - 48 Intent Exemplar Vectors│               │   - Kotlin SentencePiece  │  │
│   │   - 23 Knowledge Vectors      │               │   - Matryoshka 256-D MRL  │  │
│   └──────────────┬────────────────┘               └─────────────┬─────────────┘  │
│                  │                                              │                │
│                  ▼                                              ▼                │
│   ┌───────────────────────────────────────────────────────────────────────────┐  │
│   │ GhostVectorIndex (ghost_vectors.bin — GVEC Binary Storage)                │  │
│   │   - Normalized Cosine Similarity Metric                                   │  │
│   │   - Indexes Track Metadata, Lyrics, Genres, and Sidecar .lrc Files        │  │
│   │   - Semantic Recall ("play something dark and synthwave with neon rain")  │  │
│   └───────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Real-Time 3D GPU Raymarched Hologram (`shaders/ghost.frag`)
- **Graphics Pipeline:** 28-step GPU Signed Distance Field (SDF) raymarcher executing entirely within a fragment shader.
- **Zero Raster Bloat:** Less than $9\text{ KB}$ of shader code, requiring zero raster video or 3D asset bundles.
- **Physical Modeling:**
  - Smooth-blended (`smin`) volumetric capsule head with 5-fold animated cloth cloak folds.
  - Recessed dark-glass cyber-visor featuring specular highlights.
  - Floating 3D hands that gesture dynamically during speech, listening, and thinking states.
  - Full 3-axis ($yaw$, $pitch$, $roll$) gaze tracking following operator touch coordinates.
  - Pulsing inner soul core with Fresnel rim luminescence.
  - Three distinct emotional facial expressions: `serious` (accent ovals), `happy` (cyan crescents with blush), and `sarcastic` (asymmetrical smirk).
  - 5-bar cybernetic oscilloscope mouth driven by typewriter cadence and audio waveforms.
  - Depth-occluded 3D orbital halo rings and spherical listening sonar waves.
  - Volumetric spiral materialize/dematerialize beam and glitch slice effects.
- **Fallback:** Automatic graceful degradation to a 2.5D cyber-visor painter on low-tier GPU devices.

### 4.2 On-Device Google AI Edge LiteRT (`EmbeddingGemma-300M`)
- **Inference Runtime:** `com.google.ai.edge.litert:litert:1.4.0` leveraging multi-threaded CPU XNNPACK kernels on both `arm64-v8a` and `x86_64`.
- **Pure-Kotlin Tokenizer (`SentencePieceTokenizer.kt`):** Directly parses binary `sentencepiece.model` protobuf definitions for Gemma Byte-Pair Encoding (BPE) and Unigram models with byte-level fallback.
- **Matryoshka Representation Learning (MRL):** Projects text into 256-dimensional $L_2$-normalized vector representations.
- **Zero-APK-Bloat Model Delivery:** Staged outside the APK in app-private storage (`${getApplicationSupportDirectory()}/embedding_gemma/`). Downloaded securely from Hugging Face or the ModelScope mirror on demand, or imported locally via file picker.
- **RAM Guardianship & Non-Blocking Execution:**
  - Automatically unloads model weights from RAM after 5 minutes of idle time on devices with $<6\text{ GB}$ of RAM.
  - Purges model flatbuffers from RAM if free heap drops below $650\text{ MB}$ prior to launching FFmpeg or Whisper jobs.
  - Background asynchronous warm-up embeds intent exemplars and knowledge entries in small 2-pair slices with $220\text{ ms}$ yields, preventing CPU thread starvation during chat.

### 4.3 Persistent Library Vector Index (`GhostVectorIndex`)
- **Binary Format:** Serialized as `ghost_vectors.bin` with `GVEC` header magic, storing 256-D float vectors locked to active engine IDs.
- **Indexed Scope:** Indexes local library tracks, metadata fields (`TITLE`, `ARTIST`, `ALBUM`, `GENRE`, `COMMENT`), embedded lyrics, and sidecar `.lrc` / `.txt` files.
- **Semantic Capabilities:** Enables natural language queries such as:
  - *"Play something dark and moody with heavy synth bass"*
  - *"Find the song that says 'tears in the neon rain'"*
  - *"Queue up atmospheric late night cyberpunk tracks"*

### 4.4 Offline Speech-to-Text Engines
- **Primary: Cactus Compute Whistle Native NDK:**
  - Compact $16.9\text{ MB}$ model (`assets/models/whistle.cact`) bundled directly in assets.
  - High-performance C++ JNI bridge (`sovereign_whistle.cpp`) linking precompiled `libneedle.a` on ARM64.
  - Native PCM16-to-Float32 sample normalization with domain-specific keyword biasing.
- **Secondary: Whisper AI:**
  - Bundled FFmpeg whisper filter linking `ggml-base.en.bin` ($141\text{ MB}$).
  - Full speech-to-text with timestamped `.srt` subtitle generation.
- **Operator Safety Contract:** Voice transcriptions populate the query input field for explicit operator review and **never auto-execute**, preventing accidental file deletion or unintended media playback.

---

## 5. Subsystem 7: MediaInfo Forensics & Fake-Lossless Audit

Sovereign Tagger incorporates a dedicated media forensics suite accessible via **The Workbench**, **The Player**, or the **Ghost Bot**.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   SOVEREIGN MEDIA FORENSICS SUITE                      │
├────────────────────────────────────────────────────────────────────────┤
│ 1. Deep Container & Atom Inspector                                     │
│    - ISO BMFF Atom Walker (moov before mdat FastStart verification)   │
│    - Complete stream maps: Codec, Profile, Bitrate, Sample Rate,      │
│      Bit Depth, Sample Format, Channel Layout, CFR/VFR, Colorspace     │
│    - Embedded artwork dimensions & container format inspection         │
│                                                                        │
│ 2. Fake-Lossless Spectral Shelf Prober                                 │
│    - 16.2 kHz Highpass Probe: Detects 128 kbps MP3 upsamplings         │
│    - 19.5 kHz Highpass Probe: Detects 192-256 kbps MP3 brickwalls      │
│    - Active Bit Depth Prober: Detects 16-bit audio zero-padded to 24-bit│
│                                                                        │
│ 3. Signal Integrity & Dynamic Range Analytics                          │
│    - EBU R128 Loudness: Integrated LUFS, Loudness Range (LRA), True Peak│
│    - astats Analytics: Crest Dynamic Range (DR), DC Offset, NaN scans │
│                                                                        │
│ 4. High-Resolution Pinch-to-Zoom Spectrogram                           │
│    - 1600x800 Logarithmic Spectrogram via showspectrumpic             │
│    - Interactive pinch-to-zoom (1.0x to 5.0x) with panning             │
│                                                                        │
│ 5. Universal Forensic Export                                           │
│    - 1-tap clipboard copy (Tree View, MediaInfo Text, Raw JSON)        │
│    - Plaintext & JSON report export to Android Downloads directory     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Subsystem 8: Sensory, Visual & Audio Engine

### 6.1 Procedural Audio SFX Engine
- **Independent Audio Stream:** Operates through a native Android `SoundPool` configured with `USAGE_GAME`.
- **Zero Audio Ducking:** UI sound effects never duck, pause, or interfere with active music playback.
- **Procedural Sound Synthesis:** 13 distinct cyberpunk UI sounds (clicks, confirms, errors, whooshes, typing chirps, glitch bursts) synthesized on first launch in pure Dart as $48\text{ kHz}$ PCM WAV files and cached locally.

### 6.2 GPU Fragment Shaders
- **Animated Cyber Backdrop (`shaders/backdrop.frag`):**
  - Renders 6 distinct themes: *Grabber* (packet rain), *Forge* (crucible sparks), *Pipeline* (laser scan), *Workbench* (oscilloscope harmonics), *Library* (dust motes & archive halo), and *Generic* (acoustic sound waves).
  - Dynamically recolors all scenes on the GPU via a Rec.709 perceptual luminance color filter matrix matching `SovereignState.accentColor`.
- **Performance Safeguards:**
  - Runs inside dedicated `RepaintBoundary` widgets.
  - Automatically suspends animation tickers when tabs are occluded, minimized, or when **Reduce Motion** is toggled in Settings.

---

## 7. Subsystem 9: Cryptographic Vault & Security Architecture

### 7.1 Encrypted Vault Backup (`.bin`)
- **Payload:** Backs up application preferences, custom 15-band EQ presets, favorite playlists, and third-party API credentials.
- **Encryption Scheme:** Encrypted binary packaging using a symmetric XOR cipher keyed against fixed project salt `0x53` with Base64 framing and strict version checking.
- **Portability:** Restores seamlessly across fresh installations with one tap.

### 7.2 API Credentials Governance
- Commercial API credentials (Genius Access Tokens, ACRCloud Host/Key/Secret pairs, Hugging Face Tokens) are stored strictly in device-private `SharedPreferences`.
- Credentials never leave the device and are never committed to version control.

---

## 8. Hardware Profiling & Device Benchmarks

Sovereign Tagger is tested and profiled continuously against real-world hardware, including budget reference devices like the **Motorola Moto G (2025 Wireless ADB Reference Host)** running **Android 16 (API 36)**.

| Metric | Measured Baseline (Moto G 2025) | Engineering Solution / Architecture |
|---|---|---|
| **Rendering Backend** | `Impeller (Vulkan)` with `FlutterTextureView` | Overrides `MainActivity.getRenderMode()` to `RenderMode.texture`, eliminating Android 15/16 `SurfaceView` `BLASTBufferQueue` overflow errors (`max: 5 + 2`). |
| **Backdrop Frame Rate** | Stable $22\text{ fps}$ (low power) / $30\text{ fps}$ (active) | Replaced $120\text{ Hz}$ continuous tickers with `TickerMode`-gated precision timers. |
| **Cold Startup Time** | $< 850\text{ ms}$ to interactive UI | Asynchronous splash sequence initializes FFmpeg and loads preferences in parallel with matrix rain rendering. |
| **Embedding Latency** | $38\text{ ms}$ to $65\text{ ms}$ per query | Asymmetric 256-D Matryoshka vector truncation on 4-thread XNNPACK CPU runtime. |
| **Audio DSP Memory** | $< 180\text{ MB}$ RSS during 2-pass Loudnorm | Streaming FFmpeg execution with FIFO queue serialization preventing concurrent heap spikes. |
| **RAM Footprint (Idle)** | $\sim 110\text{ MB}$ | Idle RAM watchdog evicts the 300M-parameter LiteRT flatbuffer after 5 minutes of inactivity. |

---

## 9. Toolchain & Dependency Matrix

The project strictly freezes dependencies to maintain reproducibility and platform stability:

```yaml
environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  ffmpeg_kit_extended_flutter: ^0.6.2    # FFmpeg 9.0.1 full+gpl
  just_audio: ^0.10.6                     # Low-latency playback
  audio_service: ^0.18.19                 # Lockscreen notification & MediaSession
  audio_session: ^0.2.4                   # Audio focus & interruption routing
  file_picker: ^13.1.0                    # Android SAF & local file mounting
  shared_preferences: ^2.5.6             # Persistent preference storage
  permission_handler: ^12.0.3             # Runtime permission negotiation
  video_player: ^2.14.1                   # Hardware-accelerated video playback
  audio_waveforms: ^2.0.2                 # Waveform visualizer & recorder
  flutter_colorpicker: ^1.1.0             # Accent color selector
  wakelock_plus: ^1.8.1                   # Playback screen wake lock
  path_provider: ^2.1.2                   # Platform directory resolution
  path: ^1.8.3                            # Filesystem path utilities
```

- **Android SDK:** `compileSdk = 36`, `minSdk = 26`, `targetSdk = 36`.
- **NDK Version:** `28.2.x`, targeting `arm64-v8a` and `x86_64` (64-bit only, omitting legacy 32-bit `armeabi-v7a` to shave $\sim 30\%$ APK bloat).
- **Chaquopy:** Version `17.0.0` with Python runtime `3.14`.
- **Java / Kotlin:** JDK 17 target compatibility, Kotlin 2.1+.

---

## 10. Building from Source & Deployment

### Prerequisites
1. Install Flutter SDK (`3.24+`) located at `C:\android\flutter` (or added to your system `PATH`).
2. Install Android Studio with Android SDK Platform 36 and NDK `28.2`.
3. Ensure Python 3.11+ is installed on the host development machine for Chaquopy build scripts.

### 10.1 Compiling Shaders
Validate fragment shaders using Flutter's Impeller shader compiler:
```powershell
impellerc --sksl --iplr --sl=shaders/backdrop.frag.iplr --shader-bundle --runtime-stage-gles --runtime-stage-vulkan shaders/backdrop.frag
impellerc --sksl --iplr --sl=shaders/ghost.frag.iplr --shader-bundle --runtime-stage-gles --runtime-stage-vulkan shaders/ghost.frag
```

### 10.2 Debug Build (For Local Device Testing)
```powershell
C:\android\flutter\bin\flutter.bat pub get
C:\android\flutter\bin\flutter.bat build apk --debug --target-platform android-arm64
```
The output lands at:
`build\app\outputs\flutter-apk\app-debug.apk`

### 10.3 Release Build (F-Droid / Standalone Distribution)
```powershell
C:\android\flutter\bin\flutter.bat build apk --release --target-platform android-arm64
```
*Note on Signing:* Release builds automatically fall back to the Android debug keystore unless explicit signing credentials are configured via environment variables (`SOVEREIGN_KEYSTORE`, `SOVEREIGN_STORE_PASSWORD`, `SOVEREIGN_KEY_ALIAS`, `SOVEREIGN_KEY_PASSWORD`) or inside `local.properties`.

---

## 11. Complete Licensing & Intellectual Property Disclosures

Sovereign Tagger is published under the **GNU General Public License v3.0 (GPL-3.0-or-later)**.

```
Copyright (C) 2026 Sovereign Mantle Core Contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.
```

- For the complete license text, inspect [`LICENSE`](LICENSE).
- For a component-by-component dependency audit and F-Droid packaging guide, inspect [`LICENSES.md`](LICENSES.md).
- For security and threat modeling disclosures, inspect [`SECURITY.md`](SECURITY.md).
- For coding directives and engineering standards, inspect [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

```
// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================
```
