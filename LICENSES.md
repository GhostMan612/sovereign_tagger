# LICENSES & INTELLECTUAL PROPERTY GOVERNANCE

> **Project:** Sovereign Tagger (`com.sovereigntagger`)  
> **Primary License:** GNU General Public License v3.0 (GPL-3.0-or-later)  
> **Target Distribution:** F-Droid, IzzyOnDroid, Self-Hosted APK  
> **Effective Date:** November 2026

---

## 1. Executive Licensing Architecture

Sovereign Tagger is an autonomous, decentralized media workstation engineered for Android. It operates under the **GNU General Public License v3.0 (GPLv3)**.

### Why GPLv3 is Mandatory for Sovereign Tagger
Sovereign Tagger incorporates `ffmpeg_kit_extended_flutter` configured in its `pubspec.yaml` with:
```yaml
ffmpeg_kit_extended_config:
  type: "full"
  gpl: true
```
This flag links a complete FFmpeg build including GPL-licensed libraries (such as `libx264` and GPL-gated DSP filters). Under §5(c) and §6 of the GNU General Public License, any combined work linking GPL object code must be conveyed as a whole under the terms of the GPL. Sovereign Tagger embraces this copyleft protection to guarantee that every user retains full freedom to inspect, modify, run, and redistribute the application.

---

## 2. Component & Dependency License Inventory

The following table provides an exhaustive breakdown of every subsystem, runtime, library, and asset bundled into or referenced by Sovereign Tagger:

| Component / Subsystem | Source / Upstream | Stated License | Compatibility with GPLv3 |
|---|---|---|---|
| **Sovereign Tagger Source** (`lib/`, `shaders/`) | Sovereign Mantle Core | **GPL-3.0-or-later** | Native |
| **FFmpeg Extended Kit** (`ffmpeg_kit_extended_flutter: ^0.6.2`) | FFmpeg / FFmpegKit Extended | **GPL-3.0** (`full` + `gpl: true`) | Identical |
| **Chaquopy Python SDK** (`gradle:17.0.0`) | Chaquo Ltd. | **Chaquopy Open-Source / Dual-License** | Free for non-commercial & open-source builds |
| **yt-dlp Subsystem** (`yt-dlp` in Python 3.14) | yt-dlp Team | **The Unlicense** (Public Domain) | Permissive / GPL-compatible |
| **Mutagen Audio Metadata** (`mutagen`) | Quod Libet Team | **GPL-2.0-or-later** | Compatible with GPLv3 |
| **LyricsGenius** (`lyricsgenius`) | John W. Miller | **MIT License** | Compatible with GPLv3 |
| **Cactus Compute Whistle Engine** (`libneedle.a`, `needle.h`, `whistle.cact`) | Cactus Compute | **Apache License 2.0** | Compatible with GPLv3 (§7 notice) |
| **LiteRT Edge Inference Engine** (`com.google.ai.edge.litert:litert:1.4.0`) | Google AI Edge / TensorFlow Lite | **Apache License 2.0** | Compatible with GPLv3 |
| **SentencePiece Tokenizer** (`SentencePieceTokenizer.kt`) | Google / Sovereign Tagger Kotlin port | **Apache License 2.0** | Compatible with GPLv3 |
| **jaudiotagger Android Port** (`Id3Tagger.kt`) | Paul Taylor / jaudiotagger | **LGPL-2.1-or-later** | Compatible with GPLv3 |
| **just_audio & audio_service** | Ryan Heise | **MIT License** | Compatible with GPLv3 |
| **audio_session** | Ryan Heise | **MIT License** | Compatible with GPLv3 |
| **video_player** | Flutter Community / Google | **BSD-3-Clause** | Compatible with GPLv3 |
| **audio_waveforms** | Simform Solutions | **MIT License** | Compatible with GPLv3 |
| **file_picker** | Miguel Ruivo | **MIT License** | Compatible with GPLv3 |
| **permission_handler** | Baseflow | **MIT License** | Compatible with GPLv3 |
| **shared_preferences / path_provider** | Flutter Team | **BSD-3-Clause** | Compatible with GPLv3 |
| **flutter_colorpicker** | mchome | **MIT License** | Compatible with GPLv3 |
| **wakelock_plus** | CreativeCreatorORM | **BSD-3-Clause** | Compatible with GPLv3 |
| **ACRCloud Universal SDK** (`AcrCloudBridge.kt`) | ACRCloud | **Proprietary / Free Evaluation** | *See Section 3 for F-Droid isolation* |
| **Font: ShareTechMono** | Carrois Type Design | **SIL Open Font License 1.1** | Freely embeddable |
| **Font: VT323** | Peter Hull | **SIL Open Font License 1.1** | Freely embeddable |

---

## 3. F-Droid & Free Software Distribution Matrix

### The F-Droid Policy
F-Droid has strict inclusion criteria:
1. All applications must be built 100% from source using the F-Droid build server.
2. No non-free binary blobs or proprietary tracking libraries may be present in the build tree.
3. Network calls to third-party proprietary services must be optional and user-configured.

### Distribution Paths for Sovereign Tagger

#### Option 1: IzzyOnDroid & Self-Hosted F-Droid Repository (Recommended Path)
- **Status:** **Ready immediately.**
- **Mechanism:** IzzyOnDroid and self-hosted F-Droid repositories accept signed release APKs (`SOVEREIGN_TAGGER.apk`) generated directly from GitHub Releases.
- **Payload:** Bundles the complete matrix: Chaquopy Python 3.14, prebuilt ARM64 `libneedle.a`, embedded `whistle.cact` model weights, and the ACRCloud Universal binary bridge.
- **User Experience:** Seamless updates via the official F-Droid client app with zero feature degradation.

#### Option 2: Official F-Droid Main Repository Build
To be accepted into the official F-Droid main repository (which compiles everything from source on GitLab CI without internet access during build), two constraints must be handled:
1. **ACRCloud SDK:** The proprietary ACRCloud `.aar` library cannot be compiled from source. In Sovereign Tagger, the ACRCloud integration is already completely decoupled behind `AcrCloudBridge.kt` and `MetadataSources.acrConfigured()`. When keys are not supplied, Sovereign Tagger gracefully falls back to local file-name heuristics, Genius, LRCLIB, and MusicBrainz. For a pure F-Droid main build, this bridge can be excluded via Gradle flavor.
2. **Chaquopy & Python Toolchain:** F-Droid build environments often restrict precompiled Python wheels. The repository already contains an architectural specification for a pure Dart/Kotlin SDK edition (`.blueprints/SDK-EDITION-SPEC.md`, Phase S0–S4) where YouTube/SoundCloud enrichment is performed via native HTTPS and FFmpeg, allowing full headless compilation in standard F-Droid builders.

---

## 4. Artificial Intelligence & Neural Model Weight Governance

Sovereign Tagger incorporates cutting-edge on-device neural edge computing. The licensing of model weights and runtime graphs is defined below:

### 1. Whistle Speech-to-Text Model (`assets/models/whistle.cact`)
- **Author:** Cactus Compute
- **Size:** 16,919,407 bytes (16.9 MB)
- **License:** Apache License 2.0
- **Distribution:** Embedded directly in application assets. Fully offline, no server communication.

### 2. Whisper Speech Recognition (`ggml-base.en.bin`)
- **Author:** OpenAI / Georgi Gerganov (whisper.cpp)
- **Size:** ~141 MB
- **License:** MIT License
- **Distribution:** On-demand download from Hugging Face or user-mounted. Not packaged inside the APK to preserve initial download footprint.

### 3. Google AI Edge EmbeddingGemma-300M
- **Runtime:** `com.google.ai.edge.litert:litert:1.4.0` (Apache 2.0)
- **Weights:** `embeddinggemma-300M_seq256_mixed-precision.tflite`
- **Tokenizer:** `sentencepiece.model` (Google SentencePiece, Apache 2.0)
- **Model Terms:** Governed by the **Gemma Terms of Use**. Freely redistributable and usable for commercial and non-commercial research and development.
- **Distribution:** Stored in app-private external storage (`${getApplicationSupportDirectory()}/embedding_gemma/`). Downloaded securely from Hugging Face or the ModelScope mirror on user demand, or imported locally via `.tflite` file picker. Never bundled into the raw APK (0 MB APK growth).

---

## 5. User Privacy & Zero-Telemetry Covenant

Sovereign Tagger contains:
- **NO** advertising frameworks (AdMob, Unity Ads, etc.).
- **NO** telemetry, analytics, or behavioral tracking SDKs (Firebase Analytics, Crashlytics, Adjust, AppsFlyer).
- **NO** background reporting daemons.
- **NO** third-party user data synchronization.

All operations, including audio transcription, vector search, equalizing, tagging, and neural intent parsing, execute locally on the host device's CPU and GPU.
