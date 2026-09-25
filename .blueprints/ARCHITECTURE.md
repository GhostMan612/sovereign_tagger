# ARCHITECTURE.md — Sovereign Tagger v2 data flow
> Reference map for every phase. Update when structure changes.

## Boot flow
```
main() ──▶ SharedPreferences(accent_color) ──▶ MaterialApp(dark, seed=accent)
        └─▶ SplashScreen._bootSequence()
              ├─ FFmpegKitExtended.initialize()
              ├─ storage/autoImportConfig (XOR 0x53 .bin keys → prefs)
              └─ pushReplacement ▶ MainShell (Stack → AmbientBackdrop variant per tab → IndexedStack → mini-player)
```

## Global state
```
SovereignState (statics)            AudioService (statics + handler)
├─ currentTab ValueNotifier         ├─ player (just_audio, 48000/256k or PCM wav)
├─ pendingForgePath ValueNotifier   ├─ player playlist API (setAudioSources/insert/move/remove, serialized via _queueLock)
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
| `storage` | `queryAudio` · `loadArtwork` · `resolveMediaUri` · `requestWriteAccess` · `overwriteMedia` · `requestDelete` · `exportToLibrary` · `getTempDirectory` · `addToMediaStore` (now MIME map `flac→flac, wav→wav, m4a→mp4, ogg→ogg, opus→opus, mkv→x-matroska`) · `exportConfig` · `autoImportConfig` | `StorageBridge.kt` `RELATIVE_PATH MUSIC/MOVIES` + `IS_PENDING` |
| `acrcloud` | `initialize` · `identify` | `AcrCloudBridge` |
| `spider` | `scrape` · `fetchLyrics` · `fetchArtwork` | `spider.py` (scored iTunes/Deezer/MusicBrainz candidates + LRCLIB lyrics, Genius optional) |
| `share` (Event) | shared URL strings | `MainActivity` ACTION_SEND |
| `widget` | `update(title, artist, playing)` | `SovereignWidgetProvider.pushState` |
| `pcm_recorder` | `hasPermission` · `startRecording(path, sampleRate, channels)` · `stopRecording` · `isRecording` | `PcmRecorderBridge.kt` `AudioRecord` 48k/16-bit WAV (header placeholder → `finalizeWavHeader` LE, `ByteBuffer` reuse) |
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

## Tagging contract
Forge/pipeline metadata map keys: `TITLE ARTIST ALBUM ALBUM_ARTIST YEAR GENRE DISC_NO TRACK COMMENT COMPOSER PRODUCER LYRICS ENCODER LANGUAGE ARTWORK_BASE64` → `Id3Tagger.kt` `deleteField` on empty else `setField` + `deleteArtworkField` → `commit()`. Export rename preserves source `ext` (`pipeline:267` + `forge:267`), then `addToMediaStore` with correct MIME. Round-trip verify: write→`readTags` → mismatch list surfaced as `WARN`.

## Audio & visuals
- **Player:** edge-to-edge `BoxFit.cover` `InteractiveViewer` pinch 1→3x + bottom scrim + `PINCH TO ZOOM` hint; `_DoubleTapSeek` halves ±10s; theater `ValueListenableBuilder` for `coverArtImage` (FittedBox → DecorationImage `cover`), video `VideoPlayer` with `videoController` disposed before reassign, `_onTabChanged` `mounted` guard.
- **Recorder:** default lossless PCM `PcmRecorder` 48k/16-bit WAV (toggle `LOSSLESS PCM`); fallback `RecorderController` `aac 48k/256k` 50ms wave.
- **Haptics + sound:** `TapFeedback` static `AudioPlayer` plays embedded `880Hz/1400Hz` wav base64 via `data:audio/wav;base64` data URI + `HapticFeedback`; `dispose()` on app `dispose`.
- **Backdrops:** `MatrixRain` splash (single `TextPainter` reuse, 36 cols) + `AmbientBackdrop` `BackdropVariant` per tab pulsing grid (`grabber` vertical, `forge` slow, `pipeline` horizontal, `workbench` mixed) `alpha 0.035/0.18` + blur, 4s `AnimationController`.
