# ARCHITECTURE_DECOMPOSITION.md — Sovereign Tagger Modularization Blueprint
> Canonical architecture decomposition specification for the 6 oversized modules (~611 KB total).
> Authored: 2026-11-12 | Target: Phase 39 Subsystem Decomposition & Decoupling.

---

## 1. Executive Summary & Problem Definition

During the Phase 38–39 architectural audit, six modules were identified as disproportionately large, blending deterministic algorithm builders, device I/O, persistence, platform bridge messaging, and complex stateful UI into monolithic compilation units:

| Module | Location | Size | Approx. Lines | Primary Entanglement |
|---|---|---|---|---|
| **Workbench** | `lib/tabs/tab_workbench.dart` | **193 KB** | ~4,500 | 15+ DSP command builders, FFmpeg execution, waveform UI, batch queue state. |
| **Settings** | `lib/screens/settings_screen.dart` | **109 KB** | ~2,250 | Vault recovery, OAuth forms, credentials, Python updater, diagnostic probes. |
| **Ghost Brain** | `lib/services/ghost_brain.dart` | **98 KB** | ~2,100 | BM25 indexing, SQLite persistence, intent routing, response synthesis. |
| **Grabber** | `lib/tabs/tab_grabber.dart` | **85 KB** | ~1,850 | Format parsing, download queue state, cookie imports, ladder retry loops. |
| **Main Shell** | `lib/screens/main_shell.dart` | **65 KB** | ~1,200 | Mini-player transport, backdrop shader loops, tab stack lifecycle, ghost chat. |
| **Storage Bridge** | `android/.../StorageBridge.kt` | **61 KB** | ~1,150 | MediaStore I/O, AES-GCM crypto, recovery journal, photo EXIF geometry. |

**Goal:** Decompose these six monolithic units into decoupled, single-responsibility files without altering public APIs, breaking widget contracts (`AnimatedTabStack`), or introducing regressions.

---

## 2. Safe 3-Stage Migration Methodology

```
┌────────────────────────────────────────────────────────────────────────┐
│ STAGE A: PURE LOGIC, BUILDERS & VALIDATORS (Safest)                    │
│ • Extract pure mathematical functions, string generators, argument     │
│   builders, and schema parsers.                                        │
│ • Write comprehensive unit tests for extracted classes before moving.  │
│ • Zero state or UI modifications in caller.                            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ STAGE B: STATE MACHINES, SERVICES & REPOSITORIES                       │
│ • Decouple asynchronous queues, storage interactions, and platform      │
│   channel handlers into injectable or singleton service classes.       │
│ • Preserve exact MethodChannel method names and payload schemas.        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ STAGE C: COMPONENT UI DECOMPOSITION (Visual Surface)                   │
│ • Extract sub-panels and modal dialogs into reusable widgets.          │
│ • Keep root screen as a coordinator binding state to child components.  │
│ • Verify widget keys and rebuild performance on physical hardware.     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Modularization Blueprint: 6 Target Decompositions

### 3.1 `tab_workbench.dart` (193 KB → 6 Focused Files)

- **Target Directory:** `lib/workbench/`
- **Component Breakdown:**
  1. `lib/workbench/dsp_builders.dart`: Pure FFmpeg audio filter generators (Loudnorm, Equalizer, Resampler, Pitch/Tempo, Reverb, Compressor, Limiter, Fades, Mono-fold).
  2. `lib/workbench/video_dsp_builders.dart`: Pure FFmpeg video filter generators (Crop, Scale, Rotate, Mute, Mux, Trim).
  3. `lib/workbench/workbench_models.dart`: Data structures (`DspOperation`, `BatchJob`, `MasteringTarget`, `AudioInspectResult`).
  4. `lib/workbench/workbench_queue.dart`: Serialized batch execution runner, pause/cancel state machine, and progress notifications.
  5. `lib/workbench/components/waveform_editor.dart`: Waveform rendering, region drag handles, and selection calculations.
  6. `lib/tabs/tab_workbench.dart` (~35 KB): Clean Flutter UI coordinator consuming the queue and models.

---

### 3.2 `settings_screen.dart` (109 KB → 5 Focused Files)

- **Target Directory:** `lib/screens/settings/`
- **Component Breakdown:**
  1. `lib/screens/settings/recovery_vault_card.dart`: Crash Recovery Vault card, restore verification callbacks, discard actions, and on-demand security self-test runner.
  2. `lib/screens/settings/cloud_account_card.dart`: pCloud OAuth login flow, token management, region picker, and status indicators.
  3. `lib/screens/settings/engine_diagnostics_card.dart`: FFmpeg kernel inspector, Python updater trigger, and system doctor.
  4. `lib/screens/settings/audio_preferences_card.dart`: 15-band EQ presets, crossfade sliders, and backdrop intensity controls.
  5. `lib/screens/settings_screen.dart` (~25 KB): Scaffold, section navigation, and preference persistence coordinator.

---

### 3.3 `ghost_brain.dart` (98 KB → 5 Focused Files)

- **Target Directory:** `lib/ghost/`
- **Component Breakdown:**
  1. `lib/ghost/ghost_bm25_index.dart`: Tokenization, inverse document frequency (IDF) calculation, and vector scoring.
  2. `lib/ghost/ghost_intent_router.dart`: Rule-based and semantic intent matching (playback, tagging, query, lyrics).
  3. `lib/ghost/ghost_history_store.dart`: Serialized SQLite/JSON interaction logs and play history recording.
  4. `lib/ghost/ghost_prompt_templates.dart`: Monospace system prompts, markdown synthesis, and response formatters.
  5. `lib/services/ghost_brain.dart` (~20 KB): High-level façade orchestrating query → retrieval → synthesis.

---

### 3.4 `tab_grabber.dart` (85 KB → 4 Focused Files)

- **Target Directory:** `lib/grabber/`
- **Component Breakdown:**
  1. `lib/grabber/format_resolver.dart`: Format parsing, video/audio stream sorting, and quality tier matching.
  2. `lib/grabber/grabber_job_queue.dart`: Download state machine, ladder retry sequencing, and event channel listener.
  3. `lib/grabber/components/site_badges_grid.dart`: 1000+ supported extractor badges and domain matching.
  4. `lib/tabs/tab_grabber.dart` (~25 KB): Search bar, URL pasteboard listener, format selection sheet, and action transport.

---

### 3.5 `main_shell.dart` (65 KB → 4 Focused Files)

- **Target Directory:** `lib/shell/`
- **Component Breakdown:**
  1. `lib/shell/mini_player_bar.dart`: Compact audio transport controller, gesture progress scrubbing, and track metadata badge.
  2. `lib/shell/shell_backdrop.dart`: Shader animation ticker controller, accent color listener, and repaint boundary wrapper.
  3. `lib/shell/ghost_overlay_manager.dart`: Floating assistant activation, keyboard listener, and screen barrier.
  4. `lib/screens/main_shell.dart` (~20 KB): Root `Stack`, `AnimatedTabStack` host, and top-level lifecycle observer.

---

### 3.6 `StorageBridge.kt` (61 KB → 5 Kotlin Files)

- **Target Directory:** `android/app/src/main/kotlin/com/sovereigntagger/storage/`
- **Component Breakdown:**
  1. `android/.../storage/MediaStoreOps.kt`: Native ContentResolver queries, SAF uri permissions, and metadata resolution.
  2. `android/.../storage/RecoveryJournal.kt`: `filesDir/sov_recovery` transaction lifecycle, UUID generation, SHA-256 stream hashing, and atomic cleanup.
  3. `android/.../storage/CryptoVaultOps.kt`: PBKDF2 key stretching, AES-256-GCM cipher execution, and AndroidKeyStore StrongBox integration.
  4. `android/.../storage/PhotoGeometryOps.kt`: EXIF metadata extraction, orientation matrices, and crop rectangle transforms.
  5. `android/.../StorageBridge.kt` (~15 KB): MethodChannel dispatcher delegating to specific Kotlin engines.

---

## 4. Verification & Non-Regression Contracts

1. **Parity Testing Required Prior to Each Extraction**:
   - For every extracted file, a corresponding unit test file must verify that input/output behavior remains 100% identical.
2. **MethodChannel Contract Invariance**:
   - Channel names (`com.sovereign.tagger/storage`, `com.sovereign.tagger/ytdlp`, etc.) and argument maps must not change.
3. **Flutter Analyzer Cleanliness**:
   - `flutter analyze --no-pub` must report `No issues found!` at every individual step.
4. **Android Build Verification**:
   - `flutter build apk --debug --target-platform android-arm64` must compile cleanly after any Kotlin extraction.
