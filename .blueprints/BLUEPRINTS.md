# BLUEPRINTS.md — Design specs & gotcha registry
> Index of legacy docs + living design specs for v2 work. Gotchas append-only.

## Legacy blueprint archive (pre-existing, preserved)
| File | What it is |
|------|-----------|
| `sovereign_tagger_flutter_blueprints_v1.0.md` / `v2.0.md` / `v2.1.md` | Historical build blueprints of the original app |
| `sovereign tagger master upgrade blu.txt` | Master upgrade notes (13KB) |
| `sovereign_tagger full code base.txt` (102KB) | Full source snapshot — DO NOT read whole; probe if needed |
| `sovereign_tagger build report.txt` | Historical build report |
| `??? THE MASTER BLUEPRINT PHASE 13.txt` | Phase-13 note from prior arc |
| `AI Chatbot's Gradle Build Loop.pdf` | Build-loop reference |

---

## SPEC-S1: Splash falling-code animation (Phase 8)
- `MatrixRainPainter extends CustomPainter`: columns of katakana+hex glyphs falling at varying speeds/alpha trails.
- Layered UNDER existing `assets/splash-screen-bg.png` (bg darkened as today); rain tinted by `SovereignState.accentColor`.
- Single `AnimationController` (vsync), ~24fps effective via tick throttling; glyph set randomized per column head; trail via fade rectangles.
- Boot text/progress UI unchanged on top. Zero new assets. Teardown safe (controller.dispose).

## SPEC-S2: Player overhaul (Phase 4 + 10)
- Background playback: `audio_service 0.18.19` + `audio_session` with `lib/core/audio_handler.dart` `SovereignAudioHandler extends BaseAudioHandler` wrapping the existing `AudioService.player`. Manifest `AudioService` + `MediaButtonReceiver` (foregroundServiceType=mediaPlayback), handler `syncQueue`/`updateNowPlaying` on every playlist mutation and `_readTags`. `MainActivity` stays `FlutterActivity` (no superclass swap).
- Modes: shuffle toggles shuffled order list; repeat off/all/one mapped to just_audio LoopMode.
- Queue ops: "play next" inserts at currentIndex+1 in BOTH playlist + audio source via new AudioService mutators (`moveAfterCurrent` async).
- Theater LRC panel: `lib/tabs/tab_player.dart` `_LyricsSheet` parse `.lrc` sidecar → timestamped lines → auto-scroll active line; tap line = seek. Reuses lyric parser logic extracted from lyric_sync_screen.
- Persistence: queue paths + index + position saved to SharedPreferences (debounced); restored on boot behind splash.
- Gestures: double-tap halves on artwork ±10s (`_DoubleTapSeek`); horizontal drag on artwork = seek scrub preview.

## SPEC-S3: Integrations — Zero-Bloat Decision (Phase 14)
- Empty `lib/integrations/genius|itunes|musicbrainz|ollama/` were 0-byte scaffolding. **Deleted** — they added no bytes to APK but confused ownership.
- Enrichment lives centrally in `android/app/src/main/python/sovereign_yt/spider.py` cascade: Genius (lyrics+art) → SoundCloud thumb fallback → iTunes → MusicBrainz. Single Python HTTP path = 0 extra Dart deps, no duplicate `http`/`dio` bloat, consistent with gated `android/data` file ownership (grabber/forge own the files, spider only enriches paths).
- Ollama (local LLM) deferred: model ≥1-2GB would blow APK and violates near-ZERO bloat. If wanted, run as **remote** Ollama endpoint, still via spider.py, not a Dart integration. Re-create `lib/integrations/` only if you need a Dart-side HTTP client that bypasses Python entirely.

## SPEC-S4: Scorched Earth + On-Board Python Doctor (Phase 15)
- `android/app/src/main/python/sovereign_yt/updater.py`: `execute_scorched_earth()` still wipes `yt_dlp/` folder and tarball-reinstalls from GitHub. New `update_python_stack()` best-effort `pip install --upgrade mutagen lyricsgenius`; `execute_full_scorched_earth()` composes both (yt-dlp authoritative, deps best-effort offline-safe).
- `android/app/src/main/python/sovereign_yt/doctor.py`: explicit knowledge base `PATCH_REGISTRY` (youtube_android_blocked / impersonate_removed / 403 throttle / genius 429 / outdated extractor) with signatures, files/lines, and hotfixes. Exposes `diagnose(error_log)` and `get_registry()` — inventories `*.py` payload, probes `yt_dlp` version, snapshots `extractor_args` from `bridge.py`. Surfaced in Settings via `com.sovereign.tagger/ytdlp` channel methods `runDoctor`/`getDoctorRegistry`/`updateFullStack`.
- Zero-bloat: `doctor.py` is ~4KB, no deps beyond stdlib; it never shells to pip on its own. Hot-patching extractor_args remains manual (edit `bridge.py` via the patch hint) until a future byte-patch writer is added — intentional to avoid self-modifying-code risk on locked Android.

## GOTCHA REGISTRY (append-only; G# referenced from RULES §3)
- G1: `ffmpeg_kit_extended_flutter` fork exposes both execute() (SYNC, blocks platform thread) and executeAsync(). Never ship sync in UI paths.
- G2: yt-dlp split downloads return two files under requested_downloads[0].filepath each; composite `"a+b"` ids must be split Python-side BEFORE ydl runs (bridge.py:140) — Flutter merge assumes exactly two payloads.
- G3: jaudiotagger commits are lossless but throw on unsupported containers (some WAVs); always try/catch and report field-level failures upward.
- G4: MediaStore export needs ~500ms settle after rename on some devices (forge:342 delay exists for this reason — do not remove without device retest).
- G5: chaquopy Python cannot shell out to ffmpeg CLI for yt-dlp merges; Flutter-side FFmpegKit owns ALL muxing.
- G6: fork API surface differs from upstream ffmpeg_kit_flutter — probing is `FFprobeKit.getMediaInformationAsync(path)` → session.getMediaInformation() → `.streams` (List, non-null) with `.type` field (no getType()). No FFmpegKit.getMediaInformation.
- G7: Facebook muxing failure modes (Phase 2 design): (a) FB often exposes zero `audio only` formats → old merge-picker dead-end; progressive streams usually carry audio so single-format download + probe resolves it; (b) DASH video-only picks slip through raw-rename path with no audio → self-heal chain (probe → companion bestaudio fetch → event-chained merge); (c) container/codec quirks defeat explicit-map copy → 3-rung ladder: explicit maps copy / AAC-remuxed companion / default selection, each verified via ffprobe stream counts. Event chaining hazard: companion 'finished' event may arrive before downloadMedia invokeMethod returns — guard via `_companionPendingVideo == null` check after await.
- G8: This machine's pub endpoint does not serve just_audio_background beyond 0.0.1-beta.17 (resolver reports "^0.x doesn't match any versions" for all modern lines). beta.17 is incompatible with just_audio 0.9.x platform interface. audio_service 0.18.19 + audio_session 0.1.25 ARE resolvable — implemented as `lib/core/audio_handler.dart` `SovereignAudioHandler` with manifest service/receiver, no MainActivity superclass swap needed.
- G10: `lib/integrations/` empty scaffolding weighed 0 bytes in APK (dirs not packaged) but confused ownership; canonical enrichment is `spider.py` cascade, not Dart integrations. Delete unless you need a Dart HTTP path.
- G11: `android/data` gated files: grabber/forge own file ownership via `storage` channel `getTempDirectory` + `addToMediaStore`; integrations must not take ownership, only enrich metadata by path.
- G12: `doctor.py` must not auto-mutate `bridge.py`/`spider.py` source on disk (Android lock + signature risk); surface patch hints, let operator trigger `execute_full_scorched_earth` instead.
- G13: jaudiotagger MP3 `commit()` can drop/shift the Xing header → players estimate duration = filesize ÷ first-frame-bitrate (phantom 32kbps/44:12 on a 4:13 track). Every mp3 written via id3 channel after an ffmpeg transcode gets a `probeDurationMs` drift check; >2s drift triggers lossless `-c copy -write_xing 1 -id3v2_version 3` repair (`tab_grabber.dart` audio path).
- G14: `full+gpl` build (FFmpeg 8.1.2) exposes far more than we call: rubberband (formant-safe pitch), afftdn (FFT denoise), dynaudnorm, acompressor, equalizer/bass/treble, ebur128, atempo, concat demuxer, thumbnail/tile, drawtext/ass, x264/x265/vpx/aom. All driven via plain command strings through `FFmpegExecutor.execute` — zero native rebuild. Verify actual availability on-device via the boot `getRegisteredFilters()` log before adding exotic ops.
- G15: `atempo` accepts 0.5-2.0 per instance (chain for wider); `rubberband=pitch=X` keeps tempo, `atempo=X` keeps pitch, `asetrate` moves both — exposed as Workbench DSP "MODE" dropdown.
- G16: Mixtape Join (pipeline) uses concat demuxer `-f concat -safe 0` — requires uniform codec/sample-rate; guarded to PROCESSED `.mp3` items only. Always finish with `-write_xing 1` (G13).
- G17: Whisper transcripts GATED: no verified `whisper` filter surface in ffmpeg 8.1.2 command-space + operator must bundle model into `assets/models/`. Check boot introspection log first; never ship speculative filter strings.
- G9: Duration has no isBefore/isAfter helpers in this SDK — use <=/>= comparisons directly.
- G18: just_audio 0.9.x treated effect gains as bels (×1000 into millibels); 0.10.0 fixed this (×100), so on 0.10.x `AndroidEqualizerBand.setGain`, `AndroidLoudnessEnhancer.setTargetGain` and `minDecibels/maxDecibels` are true dB and `PlaybackFx` passes them straight through. Never reintroduce a ×0.1 factor. `equalizer.parameters` only completes after the player first loads a source.
- G19: file_picker returns a CACHE COPY path; editing it never fixes the user's file. Use `PlatformFile.identifier` → `MediaStore.getMediaUri` (`storage.resolveMediaUri`) and write back through `createWriteRequest` + `openOutputStream(uri, "wt")`. MediaStore Files won't accept non-media (e.g. `.lrc`) under Music/ — embed LRC in LYRICS instead.
- G20: yt-dlp Python API `extractor_args` must be `{ie: {arg: [values]}}`; the list form `{'youtube': ['player_client=...']}` is silently ignored (traverse_obj on a list).
- G21: Python `urllib` rejects URLs containing raw spaces (`InvalidURL`) — always `urllib.parse.quote`/`urlencode` the whole query (the old MusicBrainz lookup failed on every call).
- G22: `appwidget-provider android:configure` makes the launcher wait for a configuration result; without one the widget is cancelled. Don't declare it unless a real config activity exists.
- G23: Script-patching Dart through Python: `\n` inside a non-raw Python string becomes a real newline inside the Dart literal → syntax error. Use `\\n` or raw strings; re-run analyze after every scripted patch.
- G24: jaudiotagger on Android needs `TagOptionSingleton.getInstance().isAndroid = true` (set in `Id3Tagger` init) or artwork objects are `StandardArtwork` (javax.imageio/java.awt). FLAC and Vorbis `createField(Artwork)` call `setImageFromData()` (AWT on desktop, `UnsupportedOperationException` in Android mode), so write their art from raw bytes: `FlacTag.createArtworkField(...)` / `METADATA_BLOCK_PICTURE` = base64 of `MetadataBlockDataPicture.rawContent`. Always set picture type 3 (front cover); the default wrote APIC type 255. Catch `Throwable`, not `Exception`, in native tag calls — an escaping `Error` kills the worker thread and the Dart `MethodChannel` future never completes.
- G26: Since Flutter 3.2x, Material buttons use `adaptiveClickable` cursors (`click` on web/desktop, `basic` on Android) and InkWell declares taps through a `Semantics(onTap:)` node, not `RenderSemanticsGestureHandler`. To detect a tappable under a finger, hit-test and look for `SemanticsAnnotationsMixin.properties.onTap != null` (InkWell/buttons), `RenderSemanticsGestureHandler.onTap` (plain `GestureDetector`) or a `click` cursor.
- G27: Playing UI sounds through `just_audio` activates the audio session/focus and can duck or pause music; per-tap `setAudioSource` also adds 100 ms+ latency. UI sounds belong in `SoundPool` with `USAGE_GAME` (media volume, no focus).
- G28: The old `CyberTapFeedback` replaced its child with `CustomPaint(size: Size.infinite)` while bursting — the button vanished and unbounded parents (Row) threw layout errors, so the effect never showed. Effects that decorate a widget must paint over or around it, never instead of it.
- G29: A `BackdropFilter` inside a fading `Opacity` (or any saveLayer) blurs an empty layer — the glass looks black mid-animation. Fade the glass colors and blur sigma directly and put `Opacity` only on the panel's contents.
- G30: Continuous CustomPainter animation = one `Ticker` + a `ChangeNotifier` passed as the painter's `repaint:`, inside a `RepaintBoundary`; never `setState` every frame or `Future.delayed(16ms)` loops. Clamp dt (≤50 ms) so dropped frames slow the animation instead of jumping it, and stop the ticker when hidden/backgrounded (`GhostAvatar` idles at 30 fps).
- G25: YouTube `.m4a` (itag 140) arrives as fragmented DASH MP4 (`moof` boxes) because Chaquopy yt-dlp has no ffmpeg for its FixupM4a step. jaudiotagger writes it, then throws `CannotWriteException: incorrect offsets written` and reports 0 duration. Grabber always remuxes m4a (`-c:a copy -movflags +faststart`); `TagIO.write` detects `moof`/`mvex` and flattens (`-map 0 -c copy`) before writing, with a flatten-and-retry backstop.
- G17 (update): Whisper model is downloaded on first Transcribe into app support storage (`WhisperModel.ensure`); bundling in `assets/models/` is optional.
