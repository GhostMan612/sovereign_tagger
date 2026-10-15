# Sovereign Tagger — GhostBrain v2 Overlay Package

Unzip this archive directly into the root of your local `sovereign_tagger` repository:

```powershell
Expand-Archive -Path sovereign_tagger_ghostbrain_v2_overlay.zip -DestinationPath . -Force
```

## Included Files

| File Path | Action | Description |
| :--- | :--- | :--- |
| `lib/core/forge_request.dart` | Updated (Drop-in) | Adds `ForgeAutoTask` enum and `autoTask` field while preserving 100% backwards compatibility with existing `ForgeRequest` callers. |
| `lib/core/ghost_commands.dart` | New File | Defines `GrabberCommand`, `GrabberSearchHit`, `WorkbenchCommand`, and `GhostCommandBus` `ValueNotifier` streams. |
| `lib/core/embedding_service.dart` | New File | Implements `EmbeddingGemmaService`: supports native MethodChannel `'com.sovereign.tagger/embeddings'` for LiteRT `EmbeddingGemma` (256-d Matryoshka vectors) with an automatic zero-dependency 256-d L2-normalized character/word n-gram cosine fallback so semantic routing works immediately out of the box. |
| `lib/core/voice_input.dart` | Updated (Drop-in) | Adds `onRecordingStarted` / `onRecordingStopped` audio-ducking hooks (so speaker playback drops to 18% volume while the mic is listening) and Whisper domain homophone correction (`"forged"` $\to$ `"forge"`, `"grab her"` $\to$ `"grabber"`, `"lrc lib"` $\to$ `"lrclib"`). |
| `lib/services/ghost_world.dart` | Updated (Drop-in) | Adds `searchGrabber()`, `downloadInGrabber()`, and `forgeExtract()` (driving `MetadataSources.search`, `MetadataSources.fetchLyrics`, `MetadataSources.acrIdentify`, and `ForgeRequest.prefill` + `com.sovereign.tagger/ytdlp`). |
| `lib/services/ghost_brain.dart` | Updated (Drop-in) | Adds the Hybrid `EmbeddingGemma` + BM25 Semantic Intent Router, Grabber search/download + numbered choice picker (`1`, `2`, `3`), Forge metadata + synced LRC lyrics + ACRCloud extraction, and Workbench Whisper/ReplayGain triggers. |
| `.blueprints/GHOSTBRAIN_V2_BLUEPRINT.md` | New File | Full architectural blueprint for GhostBrain v2 and native `EmbeddingGemma` LiteRT integration. |
| `ghostbrain_tab_patcher.py` | Optional Helper | Optional Python script (`python ghostbrain_tab_patcher.py`) that adds `GhostCommandBus` search-box sync to `lib/tabs/tab_grabber.dart` and `ForgeAutoTask` follow-up hooks to `lib/tabs/tab_forge.dart`. |

## What You Can Say or Type to GhostBrain Now

- **Grabber Search & Download:**
  - *"use grabber to search for Lorn Acid Rain"* (hunts on YouTube, loads Grabber, and lists the top 3 hits in chat so you can say `"1"`, `"2"`, or `"3"` to download)
  - *"use grabber to search and download Perturbator Future Club"* (hunts on YouTube and immediately starts downloading the #1 audio match in Grabber)
  - *"download https://youtu.be/... in mp3"* (loads the link in Grabber and starts the download)
- **Forge Metadata, Lyrics & ACRCloud Extraction:**
  - *"use forge tab and extract metadata for loaded file"* (queries iTunes, Deezer, MusicBrainz, and LRCLIB, mounts the track in Forge, and prefills all matched ID3 tags + cover art + suggested filename)
  - *"find the lyrics for this song"* / *"extract metadata and find the lyrics"* (fetches synced LRC lyrics from LRCLIB / Genius and populates the `LYRICS` field in Forge)
  - *"identify this song with ACR"* / *"fingerprint loaded file"* (runs 15-second ACRCloud audio fingerprinting and populates the matched tags in Forge)
- **Workbench & Player:**
  - *"transcribe lyrics with whisper"* (switches to Workbench for local GGML Whisper transcription)
  - *"scan replaygain"* (switches to Workbench ReplayGain scanner)

## Verification Gate

After unzipping into your repository root, run:

```powershell
flutter analyze --no-pub
```
