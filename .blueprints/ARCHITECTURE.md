# ARCHITECTURE.md — Sovereign Tagger v2 data flow
> Reference map for every phase. Update when structure changes.

## Boot flow
```
main() ──▶ SharedPreferences(accent_color) ──▶ MaterialApp(dark, seed=accent)
        └─▶ SplashScreen._bootSequence()
              ├─ FFmpegKitExtended.initialize()
              ├─ storage/autoImportConfig (device-local SOV2:K AES-GCM, legacy XOR migration → prefs)
              └─ pushReplacement ▶ MainShell (Stack → CyberBackdrop shader variant per tab → AnimatedTabStack → mini-player → CyberNavBar)
```

## Global state
```
SovereignState (statics)            AudioService (statics + handler)
├─ currentTab ValueNotifier         ├─ player (just_audio, 48000/256k or PCM wav)
├─ pendingForge ValueNotifier   ├─ player playlist API (setAudioSources/insert/move/remove, serialized via _queueLock)
└─ accentColor ValueNotifier        ├─ playlist ValueNotifier<List<File>>
                                    ├─ currentIndex ValueNotifier<int>
                                    ├─ videoController ValueNotifier<VideoPlayerController?>
                                    ├─ repeatMode / isShuffle / sleepTimerMinutes / speedFactor
                                    ├─ _audioHandler SovereignAudioHandler (audio_service BaseAudioHandler, queue sync on every mutator)
                                    └─ _persist debounce (SharedPreferences JSON) + restore
Cross-tab handoff (user-initiated only): SovereignState.sendToForge(ForgeRequest{path, origin, originUri, prefill}) sets pendingForge + currentTab=1; TabForge mounts a working copy. Shared links: pendingGrabberUrl.
RULE: mutate queues ONLY via AudioService mutators inside _withQueueLock (replacePlaylist, reorderPlaylist, removeFromPlaylist, playNext, addToQueue, moveAfterCurrent, clearPlaylist).
```

## Platform channels (MainActivity.kt + Kotlin bridges + chaquopy python)
| Channel | Methods | Native impl |
|---------|---------|-------------|
| `ytdlp` | `searchMedia` · `getFormats` · `downloadMedia(jobId UUID)` · `cancelDownload` · `updateCore` · `updateFullStack` · `runDoctor` · `getDoctorRegistry` | `bridge.py` (`job_id` templated `_v/_a.%(ext)s`, split `"vid+aud"` into two `YoutubeDL` runs with `extractor_args player_client=android,web`, orphan `temp_v` cleanup) + `updater.py` + `doctor.py` |
| `ytdlp_events` | `EventChannel` progress JSON `{jobId,status,percent,speed,eta,current_file}` | `bridge.py` `create_hook` |
| `id3` | `readTags` · `writeTags` (now `deleteField` on empty, `deleteArtworkField` on empty art) | `Id3Tagger.kt` jaudiotagger lossless in-place |
| `storage` | `queryAudio` · `loadArtwork` · `resolveMediaUri` · `requestWriteAccess` · `overwriteMedia` · `requestDelete` · `exportToLibrary` · `getTempDirectory` · `addToMediaStore` (now MIME map `flac→flac, wav→wav, m4a→mp4, ogg→ogg, opus→opus, mkv→x-matroska`) · `exportConfig` · `autoImportConfig` · `encryptConfig` · `decryptConfig` · `recoverPendingOverwrites` · `restorePendingOverwrite` · `discardPendingOverwrite` · `runNativeSecuritySelfTest` | `StorageBridge.kt` `RELATIVE_PATH MUSIC/MOVIES` + `IS_PENDING` |
| `acrcloud` | `initialize` · `identify` | `AcrCloudBridge` |
| `spider` | `scrape` · `fetchLyrics` · `fetchArtwork` | `spider.py` (scored iTunes/Deezer/MusicBrainz candidates + LRCLIB lyrics, Genius optional) |
| `share` (Event) | shared URL strings | `MainActivity` ACTION_SEND |
| `widget` | `update(title, artist, playing)` | `SovereignWidgetProvider.pushState` |
| `pcm_recorder` | `hasPermission` · `startRecording(path, sampleRate, channels)` · `stopRecording` · `isRecording` | `PcmRecorderBridge.kt` `AudioRecord` 48k/16-bit WAV (header placeholder → `finalizeWavHeader` LE, `ByteBuffer` reuse) |
| `audio_fx` | `attachSession` · `applyEq` · `applyLoudness` | `MainActivity.kt` Android 16 hardware `Equalizer` & `LoudnessEnhancer` dynamic attachment |
| `embeddings` | `loadModel` · `unloadModel` · `embed` · `embedBatch` · `selfTest` | `EmbeddingGemmaBridge.kt` Google AI Edge LiteRT 1.4.0 + `SentencePieceTokenizer.kt` |
| `whistle` | `loadModel` · `transcribe` · `unloadModel` · `isSupported` | `sovereign_whistle.cpp` JNI + `WhistleBridge.kt` (Cactus Compute Needle 3 `libneedle.a`) |
| `permissions` (implicit) | via `permission_handler` Dart | `audio`/`videos`/`storage` `READ_MEDIA_*` runtime request before `autoMountMusicFolder` |

## Download/mux pipeline (grabber)
```
URL ─▶ getFormats ─▶ picker ┐
  audio-only id             ├─▶ downloadMedia(formatId + jobId UUID, "v+a") 
  video id ─▶ audio-picker ─┘      │ bridge.py runs TWO YoutubeDL passes with job_id templating
                                   ▼ ytdlp_events: finished{filePath,audioPath,isSplit,jobId}
        _processMediaPipeline:
          split ──▶ FFmpegExecutor queue → 3-rung ladder (-map 0:v:0 -map 1:a:0 → AAC-remux → default, each verified via probeStreams) → MediaStore
          single video ──▶ probeStreams (FFprobeKit) → if silent + _selfHealAttempts<1 → companion bestaudio jobId UUID → event-chained merge → progressive else rename
          audio  ──▶ FFmpegExecutor 320k transcode → writeTags(id3) → Forge handoff (pendingForgePath)
```

## DSP surfaces (all via FFmpegExecutor queue)
- `grabber` `MediaProbe + Executor` — playlist transcode, 3-rung merge, single transcode (progress via `probeDurationMs` → `onStatistics` → status %)
- `forge` — ACR 20s snippet `FFprobe snack 8kHz mono pcm_s16le` via `Executor`, finally-cleanup
- `pipeline` — same snippet, batch loop with `finally` wav delete
- `workbench` `lib/tabs/tab_workbench.dart:174` — `_executeOperation` builds `command` preserving container (`ext` = `srcExt` if preserved else `flac`), `MASTERING QUALITY` (`aresample=soxr` + `16/24-bit`), `TWO-PASS LOUDNORM` (regex `input_i` last JSON), `Apply Fades` (`afade` with `totalSec`), `Fold To Mono` (`pan`), `Trim Silence` (`silenceremove -45dB`), clip `HH:MM:SS` validated + keyframe-aware `-ss` before `-i` for video, `Executor` with `probeDurationMs` → `LinearProgressIndicator`
- `media_forensics` — `FFprobeKit` full properties walk, BMFF ISO `moov`/`mdat` atom inspection, `astats` + `ebur128=peak=true` decode error scan, active bit depth, 16.2 kHz / 19.5 kHz spectral shelf analysis, and logarithmic `showspectrumpic` spectrogram rendering

## Tagging contract
Forge/pipeline metadata map keys: `TITLE ARTIST ALBUM ALBUM_ARTIST YEAR GENRE DISC_NO TRACK COMMENT COMPOSER PRODUCER LYRICS ENCODER LANGUAGE ARTWORK_BASE64` → `Id3Tagger.kt` `deleteField` on empty else `setField` + `deleteArtworkField` → `commit()`. Export rename preserves source `ext` (`pipeline:267` + `forge:267`), then `addToMediaStore` with correct MIME. Round-trip verify: write→`readTags` → mismatch list surfaced as `WARN`.

## Audio & visuals
- **Player:** edge-to-edge `BoxFit.cover` `InteractiveViewer` pinch 1→3x + bottom scrim + `PINCH TO ZOOM` hint; `_DoubleTapSeek` halves ±10s; theater `ValueListenableBuilder` for `coverArtImage` (FittedBox → DecorationImage `cover`), video `VideoPlayer` with `videoController` disposed before reassign, `_onTabChanged` `mounted` guard. Hardware EQ + LoudnessEnhancer attached natively via Android 16 `audio_fx` bridge.
- **Recorder:** default lossless PCM `PcmRecorder` 48k/16-bit WAV (toggle `LOSSLESS PCM`); fallback `RecorderController` `aac 48k/256k` 50ms wave.
- **Haptics + sound:** `TapFeedback` → `Sfx` → `com.sovereign.tagger/sfx` channel → `SfxEngine.kt` (`SoundPool`, `USAGE_GAME`, 8 streams, no audio focus). The 13-sound bank (`SfxId`) is synthesized in pure Dart by `SfxSynth` (48 kHz WAV) in an isolate on first launch and cached under app support `sfx_v1/`.
- **Tap FX:** `TapFxLayer` wraps every route via `MaterialApp.builder`; on pointer-down it hit-tests for a tappable and draws a pulse outline, on tap-up a shockwave ring + spark burst + tap sound (own `Ticker`, runs only while effects live, `RepaintBoundary`). `CyberInk` is the theme splash factory; `CyberTapFeedback` is a press-scale wrapper.
- **Backdrops:** `MatrixRain` splash (single `TextPainter` reuse, 36 cols) + `CyberBackdrop` running `shaders/backdrop.frag` on the GPU at 30 fps in its own `RepaintBoundary` (accent nebula + synthwave grid floor, per-tab layer: Grabber data streams / Forge embers / Batch scan bands / Workbench waveform / Library motes / Generic acoustic waves) with Rec.709 perceptual luminance color filtering dynamically tinting all tabs and screens to `SovereignState.accentColor`.
- **Ghost 3D Hologram:** `shaders/ghost.frag` 28-step GPU raymarched Signed Distance Field (SDF) 3D volumetric hologram with animated cloth cloak folds, dark-glass cyber-visor, floating 3D gesture hands, 3D gaze tracking, soul core pulse, Fresnel rim glow, 3 emotional states (`serious`, `happy`, `sarcastic`), 5-bar oscilloscope mouth, orbital halo, and listening sonar waves.
- **On-Device Neural Engine:** `EmbeddingGemma-300M` running on Google AI Edge LiteRT (`com.google.ai.edge.litert:litert:1.4.0`) with pure-Kotlin `SentencePieceTokenizer.kt`, Matryoshka 256-D L2-normalized vectors, idle RAM guardianship (<650MB purge boundary), and persistent binary `ghost_vectors.bin` (`GVEC`) library vector index.
