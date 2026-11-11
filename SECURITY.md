# SECURITY POLICY & THREAT MODEL

> **Sovereign Tagger (`com.sovereigntagger`)**  
> **Classification:** Unclassified / Public Technical Documentation  
> **Audience:** Operators, Security Auditors, F-Droid Packagers

---

## 1. Core Security Philosophy

Sovereign Tagger was engineered under the **Air-Gapped Local Autonomy** doctrine:
1. **Zero Cloud Dependencies:** The application must remain fully functional with all network interfaces disabled.
2. **Zero Telemetry & Tracking:** No crash reporters, analytics SDKs, user identifiers, or behavioral probes exist in the codebase.
3. **Explicit User Consent for Filesystem Alterations:** Sovereign Tagger never silently overwrites or purges original media without explicit user confirmation and platform permission prompts.
4. **Decoupled Key Storage:** Commercial API keys and cryptographic secrets are stored exclusively in device-private sandboxes or user-encrypted vault backups.

---

## 2. Threat Model & Sandbox Boundaries

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ANDROID OS APPLICATION SANDBOX                  │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     DART / FLUTTER RUNTIME                       │  │
│  │  - SovereignState Event Bus      - In-Memory Chat History        │  │
│  │  - FFmpegExecutor Serializer     - GhostVectorIndex (RAM/Disk)   │  │
│  └──────────────────┬───────────────────────────────┬───────────────┘  │
│                     │ MethodChannels & JNI          │                  │
│  ┌──────────────────▼───────────────────────────────▼───────────────┐  │
│  │                     NATIVE ANDROID / C++ KERNEL                  │  │
│  │  - Chaquopy Python 3.14 Sandbox  - LiteRT XNNPACK Worker Thread  │  │
│  │  - AudioRecord Lossless Stream   - Cactus Whistle NDK Engine     │  │
│  │  - Hardware AudioFX Pipeline     - Jaudiotagger Storage Engine   │  │
│  └──────────────────┬───────────────────────────────┬───────────────┘  │
│                     │ Scoped Storage Permissions    │ MediaStore APIs  │
└─────────────────────┼───────────────────────────────┼──────────────────┘
                      ▼                               ▼
       /storage/emulated/0/Music        /storage/emulated/0/Movies
```

### 2.1 File System & Scoped Storage
- **Android Scoped Storage Compatibility:** Sovereign Tagger strictly adheres to Android 11+ (API 30–36) scoped storage laws.
- **In-Place Mutation Security:** When editing existing media via **The Forge** or **The Batch Pipeline**, the application leverages Android's system `createWriteRequest` / `MediaStore.createWriteRequest` API. Android's system dialog is presented directly to the operator.
- **Fail-Safe Working Copies:** All tag edits and audio DSP operations are executed on temporary working copies staged within the app-private cache (`context.cacheDir` or `${getApplicationSupportDirectory()}`). The original file is touched only after a successful read-back verification pass. If a crash or error occurs, the working copy is discarded and the original file remains byte-exact and untouched.

### 2.2 Memory Safety & Process Isolation
- **LiteRT RAM Guarding:** On devices with `< 6 GB` of total RAM (such as budget devices like the Moto G), the `ModelLifecycle` watchdog automatically releases the 300M-parameter `EmbeddingGemma` flatbuffer from RAM after 5 minutes of idle time.
- **Emergency Heap Purge (`beforeExecuteHook`):** Prior to initiating intensive multi-gigabyte FFmpeg operations (such as two-pass loudnorm or spectrogram rendering) or Whisper transcription, `FFmpegExecutor` checks device free RAM. If free RAM falls below `650 MB`, any loaded neural interpreter in `EmbeddingGemmaBridge` is forcefully evicted to prevent Android Low Memory Killer (LMK) aborts.
- **Buffer Overflow Protections:** Native audio capture buffers (`PcmRecorderBridge.kt` and `sovereign_whistle.cpp`) use fixed direct `ByteBuffer` allocations with bounds-checking and explicit LE/BE byte ordering.

---

## 3. Cryptographic Storage & Vault Export

### Vault Architecture (`.bin` files)
Operators can backup their application preferences, custom 15-band EQ presets, favorite playlists, and third-party API keys (Genius / ACRCloud / Hugging Face tokens) using the **Kernel Vault Export** feature.

- **Storage Format:** Staged as an encrypted binary blob (`.bin`).
- **Cryptographic Scheme:** Symmetric XOR cipher keyed against fixed project salt `0x53` coupled with Base64 framing and strict JSON schema version verification (`backup['version'] == 1`).
- **Threat Mitigation:** Prevents casual discovery of API keys and personal playlists by third-party file scanning utilities on external storage.

---

## 4. Network Communications & Leakage Audit

Sovereign Tagger initiates network requests **only** in the following explicit user-triggered scenarios:

1. **The Grabber (yt-dlp Extraction & Ingestion):**
   - Connects directly to the user-supplied URL (YouTube, SoundCloud, Bandcamp, etc.).
   - Employs randomized desktop/mobile User-Agents and localized HTTP clients to minimize fingerprinting.
2. **Metadata & Lyrics Search (The Spider):**
   - Connects to public, open metadata endpoints (iTunes Search API, Deezer API, MusicBrainz API, and LRCLIB).
   - If configured by the operator, queries the official Genius API and ACRCloud audio fingerprinting cloud.
3. **Model Weight Downloads:**
   - Downloads `whistle.cact` or `whisper.bin` or `embeddinggemma-300M` directly from official Hugging Face / ModelScope mirrors.
   - Any operator Hugging Face Bearer Token is used strictly for authentication against `huggingface.co` and is stripped automatically before following external CDN redirects.

**Zero outbound network connections occur during playback, local tagging, library browsing, equalizing, or Ghost offline chat.**

---

## 5. Vulnerability Reporting

If you discover a security vulnerability in Sovereign Tagger, please report it privately to the project maintainers via GitHub Security Advisories or by creating an issue tagged `[SECURITY]`.
