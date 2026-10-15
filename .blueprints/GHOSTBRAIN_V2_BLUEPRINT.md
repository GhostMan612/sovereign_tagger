# Blueprint: GhostBrain v2 — Semantic Intent Engine, Voice Loop & Cross-Tab Automation

> **Target Repository:** [GhostMan612/sovereign_tagger](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger)
>
> **Subsystems Affected:** `lib/services/ghost_brain.dart`, `lib/services/ghost_world.dart`, `lib/widgets/ghost_chat_overlay.dart`, `lib/core/voice_input.dart`, `lib/core/whisper_model.dart`, `lib/screens/main_shell.dart` (`SovereignState`), `lib/tabs/tab_grabber.dart`, `lib/tabs/tab_forge.dart`, `lib/tabs/tab_pipeline.dart`, `lib/tabs/tab_workbench.dart`
>
> **Design Constraint:** 100% Local & Offline First (Zero telemetry, zero cloud LLM APIs; must run comfortably alongside `ggml-base.en.bin` on mid-range Android hardware such as Moto G).

## 1. Executive Assessment: Current State vs. Target Capabilities

### 1.1 How `GhostBrain` Works Today

In the current codebase ([lib/services/ghost_brain.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fservices%2Fghost_brain.dart) and [lib/services/ghost_world.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fservices%2Fghost_world.dart)), `GhostBrain` operates as a lexical command parser and FAQ lookup engine:

1. **Pending Choice Resolution (`_resolveChoice`):** Intercepts numeric (`1`, `2`) or title replies when multiple tracks match an earlier query.

2. **Lexical Normalization (`_stem`):** Tokenizes user text, replaces hardcoded aliases, strips stop words, and applies suffix stemming.

3. **Hardcoded Verb Detection:** Matches exact action keywords (`play`, `shuffle`, `queue`, `next`, `pause`, `resume`, `stop`, `grab`, `count`, `help`, `clear`).

4. **Track Ranking (`_rankTitles`):** Matches local tracks by title/artist/album using n-gram and string edit distance.

5. **Knowledge Base Search (`_knowledge`):** Scores internal `KbEntry` docs using a custom **BM25** implementation ($k_1 = 1.2$, $b = 0.75$, $tf \times 2.2$, $+2.5$ title boost, score threshold $\ge 1.2$).

6. **Limited Cross-Tab Handoff (`SovereignState`):**

   * `GhostWorld.grab(String url)` sets `SovereignState.pendingGrabberUrl.value = url` and switches `SovereignState.currentTab.value` to the Grabber tab (`0`), where [tab_grabber.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Ftabs%2Ftab_grabber.dart) only copies the string into `_urlController.text` via `_onSharedUrl()`. It cannot run a natural-language search or auto-trigger `_startDownload()`.

   * `GhostWorld.forgeCurrent()` calls `SovereignState.sendToForge(request)` to switch to the Forge tab (`1`), where [tab_forge.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Ftabs%2Ftab_forge.dart) listens via `_onPendingRequest()` and calls `_mount(req)`. It only loads the file into the UI—it cannot automatically trigger `_searchMetadata()`, `_acrIdentify()`, LRCLIB/Genius lyric scraping, or tag writing.

### 1.2 Why `EmbeddingGemma` Is Beneficial (and What It Cannot Do Alone)

| Model / Engine | Architecture & Size | Quantized Active RAM | Primary Role in `sovereign_tagger` | Key Limitation | 
| ----- | ----- | ----- | ----- | ----- | 
| **Current Custom BM25** ([ghost_brain.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fservices%2Fghost_brain.dart)) | Lexical TF-IDF scorer (0 MB weights) | <1 MB | Exact keyword matching for technical terms (`ReplayGain`, `TXXX`, `ID3`) and fast deterministic commands | Fails on natural/spoken paraphrases (*"pull the words for this song"*) and Whisper homophones | 
| [**EmbeddingGemma 1 (308M)**](https://www.google.com/search?q=https%3A%2F%2Fai.google.dev%2Fgemma%2Fdocs%2Fembeddinggemma) ([google/embeddinggemma-300m](https://www.google.com/search?q=https%3A%2F%2Fhuggingface.co%2Fgoogle%2Fembeddinggemma-300m)) | Gemma 3 encoder, 308M params (100M backbone + 200M embedding), 2K context, MRL (768 $\to$ 128 dims) | \~180–200 MB (int4/int8 QAT) | Semantic intent routing (<22 ms on NPU), fuzzy voice command matching, semantic lyric/vibe library search | Encoder-only: outputs a vector (`Float32List`), **not** structured JSON arguments or multi-step plans | 
| [**EmbeddingGemma 2 (270M Core / 740M Full)**](https://www.google.com/search?q=https%3A%2F%2Fblog.google%2Finnovation-and-ai%2Ftechnology%2Fdevelopers-tools%2Fembeddinggemma-2%2F) | Gemma 4 modular encoder: 270M text/code core (+ optional 300M audio / 170M vision), 8K context, MRL | \~191 MB (text-only core) / \~567 MB (full multimodal) | Text-only 270M core drops right into [LiteRT-LM](https://www.google.com/search?q=https%3A%2F%2Fdevelopers.google.com%2Fedge%2Flitert-lm) with lower RAM than v1; optional 300M audio encoder enables audio-to-audio similarity | Full 740M multimodal setup (567 MB) + Whisper (141 MB) is heavy for 4–6 GB RAM devices | 
| [**FunctionGemma (270M)**](https://www.google.com/search?q=https%3A%2F%2Fdevelopers.googleblog.com%2Fon-device-function-calling-in-google-ai-edge-gallery%2F) ([google/functiongemma-270m-it](https://www.google.com/search?q=https%3A%2F%2Fhuggingface.co%2Fgoogle%2Ffunctiongemma-270m-it)) | Gemma 3 270M instruction-tuned for native tool/function calling | \~220–260 MB (int4 GGUF / LiteRT) | Translates multi-step natural language commands into structured Dart tool calls (`grab_search(query, format)`, `forge_extract(lyrics: true)`) | Slower than pure embedding lookup (\~120–300 ms generation vs. \~20 ms embedding) and not designed for vector similarity search over thousands of tracks | 

#### Verdict on EmbeddingGemma

**Yes — integrating `EmbeddingGemma` (specifically the quantized 308M v1 or 270M v2 text-only core truncated to 256 Matryoshka dimensions) is highly beneficial**, provided you use it for what dense embeddings excel at and pair it with a deterministic slot parser (or optional `FunctionGemma-270M` tool caller):

1. **Paraphrase-Proof Voice Intent Routing:** Spoken commands transcribed by `ggml-base.en.bin` often contain conversational filler or varied phrasing (*"hey ghost can you rip the audio for Lorn Acid Rain"* vs. *"use grabber to download Acid Rain by Lorn"*). Cosine similarity against 256-dim tool exemplars resolves the intent (`GRABBER_SEARCH_AND_DOWNLOAD`) in \~20 ms without requiring rigid keyword syntax.

2. **Semantic Library & Lyric Search ("Vibe & Line Search"):** Pre-computing a 256-dim embedding (1 KB per track) over each track's `Title + Artist + Genre + Mood + LRC Lyrics` lets users ask *"play that synthwave track about neon rain"* or *"queue dark industrial tracks"* completely offline.

3. **Hybrid RRF Knowledge Base:** Combining your existing BM25 score with EmbeddingGemma cosine similarity via Reciprocal Rank Fusion (RRF) makes `_knowledge` answer both exact technical queries and conceptual workflow questions.

## 2. Target System Architecture: Hybrid Semantic Router + Reactive Command Bus

### 2.1 End-to-End Voice & Chat Execution Pipeline

```
[User Voice (Mic)] ──► PcmRecorderBridge.kt (48kHz/16-bit WAV)
                            │
                            ▼
                WhisperModel (ggml-base.en.bin)
                            │  (Raw Transcript)
                            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ GhostBrain v2 Hybrid NLU Pipeline (lib/services/ghost_brain.dart)       │
│                                                                         │
│  Stage 0: Pending Choice / Confirmation Interceptor (_resolveChoice)    │
│  Stage 1: Fast Exact Command & Regex Fast-Path (0 ms, pause/next/url)   │
│  Stage 2: Hybrid Semantic Intent Router (EmbeddingGemma 256-d + BM25)   │
│           - Cosine similarity against Canonical Intent Exemplars        │
│           - Multi-intent splitting ("... and then ...")                 │
│  Stage 3: Deterministic Slot & Entity Extractor (GhostSlotParser)       │
│           - Extracts query, artist, title, format (mp3/flac/mp4),       │
│             target source (currently playing vs. loaded vs. search),    │
│             and flags (fetchLyrics, runAcr, autoApply, runWhisper)      │
└─────────────────────────────────────────────────────────────────────────┘
                            │
                            ▼  (Structured GhostAction / List<GhostAction>)
┌─────────────────────────────────────────────────────────────────────────┐
│ GhostWorld v2 Orchestrator (lib/services/ghost_world.dart)              │
│  - Dispatches typed Command payloads via SovereignState ValueNotifiers  │
│  - Subscribes to Future/Completer callbacks to report live progress     │
│    back into GhostChatOverlay ("Searching LRCLIB... Found synced LRC!") │
└─────────────────────────────────────────────────────────────────────────┘
        │                   │                    │                  │
        ▼                   ▼                    ▼                  ▼
  [GrabberTab]         [ForgeTab]         [WorkbenchTab]     [PipelineTab]
 (Search/Download)  (Mount/Tag/Lyrics)  (Whisper/DSP/EQ)   (Batch Buckets)

```

### 2.2 Memory & Resource Governance (Moto G Safety Gate)

Running `ggml-base.en.bin` (141 MB) + `EmbeddingGemma` (\~190 MB) + `FFmpegKit` + `Chaquopy` simultaneously without lifecycle management can trigger Android's Low Memory Killer (LMK). Enforce a **Shared Native Model Lifecycle Manager** (`lib/core/model_lifecycle.dart`):

* **Lazy Load & Idle Unload:** Keep `EmbeddingGemma` quantized weights (`int4` / `q4_0`, \~180 MB) mapped only when `GhostChatOverlay` is expanded or indexing is running; unload after 5 minutes of chat inactivity, or keep resident if device total RAM $\ge 6\text{ GB}$ (`ActivityManager.MemoryInfo`).

* **Mutual Exclusion During Heavy DSP/Whisper Runs:** When `WorkbenchTab` runs full-track Whisper lyric transcription or `FFmpegExecutor` runs video merge/DSP encoding, temporarily release the `EmbeddingGemma` interpreter if free RAM drops below 500 MB.

* **Matryoshka Truncation (`d = 256`):** Truncate [EmbeddingGemma](https://www.google.com/search?q=https%3A%2F%2Fai.google.dev%2Fgemma%2Fdocs%2Fembeddinggemma) output vectors from `768` to `256` dimensions and L2-normalize. A 5,000-track library index + 200 command exemplars + 100 KB entries consumes just **\~5.3 MB** in SQLite/binary cache (`ghost_vectors.bin`), scanned via dot-product in **<2 ms** in a Dart `Isolate`.

## 3. Upgrading `SovereignState`: Typed Cross-Tab Command Bus

Currently, `SovereignState` in [lib/screens/main_shell.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fscreens%2Fmain_shell.dart) only exposes `pendingGrabberUrl` (`ValueNotifier<String?>`) and `pendingForge` (`ValueNotifier<ForgeRequest?>`), which merely populate inputs without executing workflows.

Upgrade `SovereignState` with rich, actionable request payloads and completion callbacks so `GhostBrain` can drive every tab end-to-end and report results back to the chat overlay:

### 3.1 Proposed `SovereignState` Command Payloads (`lib/core/models/ghost_commands.dart`)

```
import 'dart:async';

enum GrabberMediaMode { audioOnly, videoMerge, bestAudioFlac, bestAudioMp3 }

class GrabberCommand {
  final String queryOrUrl;          // URL or natural search query ("Lorn Acid Rain")
  final bool isSearchQuery;         // true = run bridge.py search first; false = direct URL
  final GrabberMediaMode mode;      // audioOnly, videoMerge, etc.
  final bool autoDownloadTopResult; // true = automatically pick #1 search hit & call _startDownload()
  final bool sendToForgeWhenDone;   // Chained workflow: auto-open downloaded file in Forge!
  final Completer<String>? onResult;// Reports status message back to GhostChatOverlay

  const GrabberCommand({
    required this.queryOrUrl,
    this.isSearchQuery = true,
    this.mode = GrabberMediaMode.bestAudioMp3,
    this.autoDownloadTopResult = false,
    this.sendToForgeWhenDone = false,
    this.onResult,
  });
}

enum ForgeTaskType {
  mountOnly,
  searchMetadata,     // Calls _searchMetadata() across iTunes, Deezer, MusicBrainz, LRCLIB
  fetchLyricsOnly,    // Queries LRCLIB + Genius via spider.py / MetadataSources
  acrIdentify,        // Calls _acrIdentify() 15s audio fingerprint
  fullAutoTagAndLrc,  // Runs ACR/Metadata search -> attaches cover + synced LRC -> opens _review() or auto-saves
}

class ForgeCommand {
  final String? filePath;           // null = operate on currently mounted Forge file (or current playing track)
  final ForgeTaskType task;
  final String? overrideQuery;      // Optional custom search string ("Artist - Title")
  final bool autoApplyBestMatch;    // false = open MetadataReviewSheet (_review()); true = write ID3 immediately
  final Completer<String>? onResult;

  const ForgeCommand({
    this.filePath,
    required this.task,
    this.overrideQuery,
    this.autoApplyBestMatch = false,
    this.onResult,
  });
}

enum WorkbenchTaskType {
  transcribeLyricsWhisper, // Runs local ggml-base.en.bin to generate synced LRC
  analyzeReplayGain,       // Calculates ReplayGain and writes TXXX frames
  applyEqPreset,           // Applies named EQ / DSP preset
}

class WorkbenchCommand {
  final String? filePath;
  final WorkbenchTaskType task;
  final String? presetName;
  final Completer<String>? onResult;

  const WorkbenchCommand({
    this.filePath,
    required this.task,
    this.presetName,
    this.onResult,
  });
}

```

### 3.2 Wiring the Tabs to Execute `GhostBrain` Commands

#### A. Grabber Tab (`lib/tabs/tab_grabber.dart`)

1. Add `static final pendingGrabberCommand = ValueNotifier<GrabberCommand?>(null);` to `SovereignState` (keeping `pendingGrabberUrl` as a legacy wrapper).

2. In `_GrabberTabState.initState`, register `_onGhostGrabberCommand()`:

   * If `cmd.isSearchQuery == false` (it is a URL): populate `_urlController.text = cmd.queryOrUrl`, set the format chips (`cmd.mode`), and if `cmd.autoDownloadTopResult == true`, immediately invoke `_startDownload()`.

   * If `cmd.isSearchQuery == true` (e.g., *"use Grabber to search and download Perturbator Future Club"*):

     * Populate the search bar with `cmd.queryOrUrl` and invoke the Chaquopy `sovereign_yt/bridge.py` search routine.

     * If `cmd.autoDownloadTopResult == true`: automatically select the top result (or return the top 3 results to `GhostBrain`'s `_resolveChoice` disambiguation menu so the user can say *"download number 1"*!), start `_startDownload()`, and if `cmd.sendToForgeWhenDone == true`, dispatch a `ForgeCommand` as soon as the download completes.

#### B. Forge Tab (`lib/tabs/tab_forge.dart`)

1. Extend `ForgeRequest` (or replace with `ForgeCommand`) in `SovereignState.pendingForge`.

2. In `_ForgeTabState._onPendingRequest()`:

   * **Step 1 (Target Resolution):** If `cmd.filePath != null`, await `_mount(cmd.filePath)`. If `cmd.filePath == null` and no file is currently mounted in Forge, automatically resolve `AudioService`'s currently playing track (or most recently downloaded Grabber file) and mount it!

   * **Step 2 (Action Execution):**

     * `ForgeTaskType.searchMetadata`: Await `_searchMetadata(customQuery: cmd.overrideQuery)`.

     * `ForgeTaskType.fetchLyricsOnly`: Query `MetadataSources` (LRCLIB synced lyrics first, fallback to Genius via `spider.py`), populate the lyrics controller, and notify `cmd.onResult`.

     * `ForgeTaskType.acrIdentify`: Trigger `_acrIdentify()`, then automatically chain into `_searchMetadata()` using the recognized ACRCloud title/artist.

     * `ForgeTaskType.fullAutoTagAndLrc`: Run `_searchMetadata()` + LRCLIB lyric lookup; if `cmd.autoApplyBestMatch == true` and confidence $\ge 0.85$, write tags via `Id3Tagger.kt` (`tag_io.dart`) and complete `cmd.onResult` with `"Tagged & embedded synced LRC for <Title>"`; otherwise open `MetadataReviewSheet` (`_review()`) so the operator can confirm with one tap.

#### C. Workbench & Pipeline Tabs (`lib/tabs/tab_workbench.dart`, `lib/tabs/tab_pipeline.dart`)

* **Workbench:** Allow `GhostBrain` to mount the current track and kick off on-device Whisper LRC generation (`WorkbenchTaskType.transcribeLyricsWhisper`) or ReplayGain calculation (`WorkbenchTaskType.analyzeReplayGain`).

* **Pipeline:** Allow `GhostBrain` to queue an album or folder into `tab_pipeline.dart` batch buckets and start automated ACR/Genius/LRCLIB batch tagging.

## 4. Designing the Smarter `GhostBrain` NLU Engine (`lib/services/ghost_brain.dart`)

### 4.1 The 3-Layer Intent & Slot Architecture

Instead of replacing your fast deterministic code, wrap it in a **3-Layer Cascade**:

#### Layer 1: Deterministic Fast-Path (<1 ms)

* Handles single-word playback controls (`pause`, `resume`, `stop`, `next`, `prev`, `shuffle`), numbered choice selections (`1`, `2`, `3`), and pasted HTTP(S) URLs.

#### Layer 2: Hybrid Semantic Intent Router (`EmbeddingGemma` + BM25, \~15–25 ms)

* **Intent Catalog (`assets/models/ghost_intents.json`):** Define \~35 structured intents across 6 domains, each with 5–10 natural language exemplars:

| Intent ID | Example Spoken / Typed Utterances | Target Method in `GhostWorld` | 
| ----- | ----- | ----- | 
| `GRAB_SEARCH` | *"search grabber for...", "look up on youtube...", "find video or audio for..."* | `world.grabSearch(query)` | 
| `GRAB_DOWNLOAD` | *"download this song...", "rip the audio for...", "grab and download..."* | `world.grabAndDownload(query, mode)` | 
| `GRAB_AND_FORGE` | *"download ... and auto tag it", "grab ... and send to forge"* | `world.grabThenForge(query)` | 
| `FORGE_LOAD_CURRENT` | *"load current song in forge", "open this track in the tagger", "edit tags for what's playing"* | `world.forgeCurrent()` | 
| `FORGE_EXTRACT_METADATA` | *"extract metadata for loaded file", "find tags and album art", "auto tag this file"* | `world.forgeExtractMetadata()` | 
| `FORGE_FIND_LYRICS` | *"find the lyrics for this track", "pull synced LRC lyrics", "get the words for the loaded song"* | `world.forgeFetchLyrics()` | 
| `FORGE_ACR_FINGERPRINT` | *"identify this song with ACR", "fingerprint the loaded audio", "what song is this file"* | `world.forgeAcrIdentify()` | 
| `WORKBENCH_WHISPER_LRC` | *"transcribe lyrics with whisper", "generate karaoke lrc from audio"* | `world.workbenchWhisperTranscribe()` | 
| `WORKBENCH_REPLAYGAIN` | *"normalize volume", "scan replaygain for this track"* | `world.workbenchReplayGain()` | 
| `PLAY_SEMANTIC_VIBE` | *"play something dark and synthwave", "queue tracks about cyberspace"* | `world.playSemanticSearch(query)` | 

* **Scoring Formula (Reciprocal Rank Fusion + Thresholding):**
  

  $$
  \text{Score}(q, \text{intent}) = 0.70 \cdot \max_{e \in \text{Exemplars}} \cos(\vec{v}_q, \vec{v}_e) + 0.30 \cdot \text{BM25}_{\text{norm}}(q, \text{intent})
  $$

  * If $\text{Score} \ge 0.68$: Execute intent.

  * If $0.50 \le \text{Score} < 0.68$: Ask a one-tap clarification in `GhostChatOverlay` with suggestion chips.

  * If $\text{Score} < 0.50$: Route to Hybrid Knowledge Base (`_knowledge`) or semantic library search.

#### Layer 3: Deterministic Slot & Chained-Command Parser (`GhostSlotParser`)

Because `EmbeddingGemma` is an encoder, `GhostSlotParser` extracts parameters after the intent is selected:

1. **Multi-Step Clause Splitter:** Splits compound commands on conjunctions (`" and then "`, `" then "`, `" and also "`, `" and extract "`, `" and find "`) into a sequential `List<GhostIntentMatch>` queue!

   * *Example:* `"Use Grabber to download Lorn Acid Rain and then open it in Forge and find the lyrics"` $\to$

     1. `GRAB_DOWNLOAD(query: "Lorn Acid Rain", autoDownload: true)`

     2. `FORGE_LOAD_CURRENT(target: lastDownloadedFile)`

     3. `FORGE_FIND_LYRICS(target: loadedForgeFile)`

2. **Prefix/Template Stripping for Search Queries:** Strips conversational prefixes (*"hey ghost"*, *"use grabber tab to search and download"*, *"in flac"*) using token masks and n-gram alignment against the matched exemplar to isolate the clean artist/track query (`"Lorn Acid Rain"`).

3. **Contextual Pronoun Resolution (`GhostContextMemory`):** Maintains a lightweight state object tracking:

   * `lastMentionedTrack` (`GhostTrack?`)

   * `lastDownloadedFilePath` (`String?`)

   * `currentlyMountedForgeFile` (`String?`)

   * `currentlyPlayingTrack` (`GhostTrack?`)
     So when the user says *"extract metadata for the loaded file and find the lyrics"*, `"the loaded file"` resolves automatically to `currentlyMountedForgeFile ?? currentlyPlayingTrack`.

## 5. Voice Control Upgrade (`VoiceInput` + `WhisperModel` + Hands-Free Loop)

Your repo already has the hardest native building blocks in place: `PcmRecorderBridge.kt` (48kHz/16-bit WAV capture), `lib/core/whisper_model.dart` (`assets/models/ggml-base.en.bin`), and `lib/core/voice_input.dart` wired to `_voice.toggle()` in [lib/widgets/ghost_chat_overlay.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fwidgets%2Fghost_chat_overlay.dart).

Here is how to turn that push-to-talk button into a seamless **Voice-Controlled Operator Experience**:

### 5.1 Auto-Submit + Voice Activity Detection (VAD) End-of-Speech

* Currently, voice recording requires manual toggling or fixed windows. Add simple RMS energy-based **Silence Detection (VAD)** inside `PcmRecorderBridge.kt` (or `pcm_recorder.dart`):

  * Once speech starts ($\text{RMS} > \text{threshold}$ for $200\text{ ms}$), automatically stop recording after $1.2\text{ seconds}$ **of trailing silence**.

  * Immediately pass the PCM buffer to `WhisperModel`, populate `_inputController`, and **auto-submit** into `_handleUserInput()` without requiring a second tap.

### 5.2 Whisper Prompt Conditioning for Domain Vocabulary

* Whisper `ggml-base.en.bin` frequently misspells app-specific terms (*"Forge"*, *"Grabber"*, *"LRCLIB"*, *"ReplayGain"*, *"ACRCloud"*, *"ID3"*).

* Pass an `initial_prompt` string into the native Whisper inference call:

  ```
  "GhostBrain voice command for Sovereign Tagger: Grabber, Forge, Pipeline, Workbench, Theater, Library, ID3, LRCLIB, Genius, ACRCloud, ReplayGain, FLAC, MP3."
  
  ```

  This biases Whisper's decoder toward your exact tab and feature names at zero extra latency!

### 5.3 Floating Global Mic Gesture & Optional Local TTS Readback

* **Long-Press `GhostAvatar` anywhere:** In [lib/widgets/ghost_avatar.dart](https://www.google.com/search?q=https%3A%2F%2Fgithub.com%2FGhostMan612%2Fsovereign_tagger%2Fblob%2Fmain%2Flib%2Fwidgets%2Fghost_avatar.dart), bind `onLongPress` on the floating ghost avatar to immediately trigger `_voice.startListening()` with a neon pulse shader effect—allowing voice control from *any* tab without opening the full chat keyboard first.

* **Audio Ducking During Mic Capture:** When `_voice` starts recording, call `GhostWorld` to duck `AudioService` playback volume to `15%` (or pause if recording ACRCloud fingerprint) so the song playing from the speaker doesn't pollute the Whisper transcript, then restore volume as soon as recording stops.

## 6. Native Integration Path for `EmbeddingGemma` in `sovereign_tagger`

You have two clean integration paths that fit your existing architecture (`MainActivity.kt` MethodChannels or Chaquopy Python):

| Integration Route | How It Fits `sovereign_tagger` | Pros | Cons | 
| ----- | ----- | ----- | ----- | 
| **Route A: Native Kotlin MethodChannel via [Google AI Edge LiteRT](https://www.google.com/search?q=https%3A%2F%2Fdevelopers.google.com%2Fedge%2Flitert-lm) (Recommended)** | Add `EmbeddingGemmaBridge.kt` in `android/app/src/main/kotlin/com/sovereigntagger/` alongside `AcrCloudBridge.kt` and `Id3Tagger.kt`, exposed over MethodChannel `'com.sovereign.tagger/embeddings'`. Uses LiteRT `.tflite` / `.litertlm` quantized model (`embeddinggemma-300m-int4.tflite` or `embeddinggemma-2-270m-int4.litertlm`). | Hardware-accelerated via Android GPU/NPU delegates (<20 ms latency); lowest RAM overhead (\~190 MB); independent of Python GIL. | Requires adding LiteRT Maven dependencies in `android/app/build.gradle` and bundling or on-first-run downloading the \~170 MB `.tflite` file. | 
| **Route B: Shared C++/GGUF Runtime with Whisper (`llama.cpp` / `ggml`)** | Since `whisper_model.dart` already uses GGML, run `embeddinggemma-300m-Q4_K_M.gguf` via `llama.cpp` FFI in Dart. | Zero new Android Gradle SDKs; pure C++/FFI across platforms; uses \~185 MB GGUF file. | CPU/Vulkan only (no Android NPU delegate unless configured). | 

> **APK Size Tip (`acr_installer.py` Pattern):** Since `assets/models/ggml-base.en.bin` is already 141 MB, bundling another 180 MB model directly inside `assets/models/` will push the APK over \~320 MB. Consider storing the quantized `embeddinggemma` model in external app storage (`/sdcard/Android/data/com.sovereigntagger/files/models/`) with a one-tap offline import or fetch helper in `StorageBridge.kt` / `updater.py`, while pre-bundling the pre-computed `ghost_intents_256d.bin` exemplar vectors (only \~40 KB!) directly in `assets/models/`.

## 7. Phased Implementation Roadmap (Verification-Gated)

Following `.blueprints/RULES.md`, each phase is independently testable via `/analyze` (`flutter analyze --no-pub`) and physical device smoke tests:

### Phase 1: Reactive Cross-Tab Command Bus (Zero New Dependencies)

* **Files:** `lib/core/models/ghost_commands.dart` (new), `lib/screens/main_shell.dart` (`SovereignState`), `lib/services/ghost_world.dart`, `lib/tabs/tab_grabber.dart`, `lib/tabs/tab_forge.dart`.

* **Deliverables:**

  1. Replace string-only `pendingGrabberUrl` and mount-only `pendingForge` with `GrabberCommand`, `ForgeCommand`, and `WorkbenchCommand` `ValueNotifier` streams with `Completer<String>` status callbacks.

  2. Wire `tab_grabber.dart` to execute search queries via `bridge.py` and auto-trigger `_startDownload()`.

  3. Wire `tab_forge.dart` to auto-mount the current/target file and invoke `_searchMetadata()`, `_acrIdentify()`, or LRCLIB/Genius lyric extraction automatically.

* **Smoke Gate:** Typing `grab search Lorn Acid Rain` or `forge extract lyrics` in `GhostChatOverlay` switches tabs, executes the pipeline, and posts the completion result back in chat.

### Phase 2: Voice UX Polish & Whisper Domain Conditioning

* **Files:** `lib/core/voice_input.dart`, `lib/core/whisper_model.dart`, `lib/widgets/ghost_chat_overlay.dart`, `lib/widgets/ghost_avatar.dart`.

* **Deliverables:**

  1. Add `AudioService` volume ducking when mic recording starts and restore on stop.

  2. Add VAD trailing-silence auto-stop ($1.2\text{ s}$) and auto-submit in `VoiceInput`.

  3. Add domain vocabulary `initial_prompt` to `WhisperModel` so *"Forge"*, *"Grabber"*, *"LRCLIB"*, and *"ReplayGain"* transcribe cleanly.

  4. Add long-press voice trigger directly on `GhostAvatar`.

### Phase 3: `EmbeddingGemma` Native Bridge & Hybrid Semantic Router

* **Files:** `android/app/src/main/kotlin/com/sovereigntagger/EmbeddingGemmaBridge.kt` (new), `MainActivity.kt` (8th MethodChannel), `lib/core/embedding_service.dart` (new), `lib/services/ghost_brain.dart`.

* **Deliverables:**

  1. Implement `EmbeddingGemmaBridge.kt` using quantized `EmbeddingGemma` (256-dim Matryoshka output + L2 normalization).

  2. Add hybrid RRF scoring ($0.70 \cdot \text{Cosine} + 0.30 \cdot \text{BM25}$) + `GhostSlotParser` multi-intent chaining in `ghost_brain.dart`.

  3. Add background MediaStore + LRC lyric vector indexing (`ghost_vectors.bin`) for semantic track/vibe playback.