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
- **Cryptographic Scheme (SOV2 Authenticated Encryption):**
  - **Portable Mode (`SOV2:P:<iterations>:<salt>:<iv>:<cipher>`):** AES-256-GCM authenticated cipher with 128-bit authentication tag, 16-byte cryptographically secure random salt, and 12-byte random IV. Key derivation utilizes `PBKDF2WithHmacSHA256` with a calibrated baseline of **250,000 iterations**. KDF parameters are strictly bounded at the native boundary (`1,000 <= iterations <= 2,000,000`) to prevent computational denial-of-service from malformed payloads.
  - **Device-Locked Mode (`SOV2:K:<iv>:<cipher>`):** AES-256-GCM keys generated and held in hardware via `AndroidKeyStore` (`SovereignLocalVaultKey`) with hardware StrongBox backing where available, falling back to standard TEE hardware.
  - **Strict Authentication Enforcement:** All `SOV2` decryptions enforce cryptographic tag validation (`AEADBadTagException`). Failed authentications and corrupt envelopes throw immediate errors and never fall back to plaintext or legacy XOR.
  - **Historical Migration Fallback (`LEGACY_PHASE38_SECRET`):** A fixed derivation secret (`SovereignVault::KernelMasterKey::v2`) is retained strictly as an immutable, read-only fallback to allow operators to restore intermediate backups created during early Phase 38 development. New exports NEVER use this secret. Operators are advised that historical Phase 38 backups are decryptable by anyone with access to the source code and should be re-exported with a user passphrase.
  - **Legacy XOR Fallback:** Pre-Phase 38 legacy backups (XOR `0x53`) are supported for read-only migration if the input does not start with `SOV2:`.

### Pre-Overwrite Media Safety Vault (`sov_recovery`)
When writing updated audio tags or metadata directly to MediaStore content URIs in-place:
1. **Pre-Truncate Staging:** The original file stream is copied to an isolated app-internal backup (`filesDir/sov_recovery/sov_rec_<timestamp>.bak`) and SHA-256 hashed before destination file descriptors open with `"rwt"` or `"wt"`.
2. **Path Traversal Confinement:** All recovery operations validate canonical file paths against `filesDir/sov_recovery` and enforce strict filename format rules (`sov_rec_*.bak`), rejecting any path traversal or arbitrary filesystem access.
3. **Cryptographic Destination Readback:** Overwrites are declared verified only when the destination content URI is re-read and its SHA-256 hash matches the source hash.
4. **Transaction State Disambiguation:** Overwrites record transaction states (`PENDING`, `COMMITTED`, `RETAINED_FAILED_RESTORE`) with source and destination hashes, distinguishing interrupted cleanup from uncommitted writes.
5. **Atomic Discard:** Purging a recovery backup requires full deletion of both the backup binary and its associated metadata file (`bOk && mOk`).

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
