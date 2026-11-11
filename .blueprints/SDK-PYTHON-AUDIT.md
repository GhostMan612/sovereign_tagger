# SDK-PYTHON-AUDIT.md — S0 Python dependency audit (SDK Edition)

> **Scope:** S0 of the parked SDK Edition (`SDK-EDITION-SPEC.md`, `ROADMAP.md`
> Phase S0–S4). Read-only inventory at main `15e866ae` (11 Nov 2026). Every
> claim below was verified against the code at that head; doc-sourced claims
> are marked as such. Nothing here changes any behaviour.

## 1. How Python gets into the app

| Piece | Location | Verified value |
|---|---|---|
| Chaquopy Gradle plugin | `android/build.gradle:14` (classpath) | `com.chaquo.python:gradle:17.0.0`, maven `https://chaquo.com/maven` |
| Python version | `android/app/build.gradle` `python {}` block | `3.14`, with an in-file comment: 3.14 is bleeding edge, few wheels, flip to `3.11` if pip fails |
| pip installs | `android/app/build.gradle` `pip {}` block | `yt-dlp`, `mutagen`, `lyricsgenius` — **all unpinned, no versions anywhere**; no `requirements.txt`, `pyproject.toml`, or pip config exists in the repo |
| Bootstrap | `android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt:72-80` | `Python.start(AndroidPlatform(this))` lazily; four modules loaded lazily via `pythonEngine.getModule(...)` |
| ABI cost | `android/app/build.gradle` `abiFilters` | `arm64-v8a`, `x86_64` only (Python 3.12+ is 64-bit only) |

## 2. On-device Python touchpoints

| # | File | What it does | Dart/Kotlin entry | pip deps used | Dart/native replacement exists? |
|---|---|---|---|---|---|
| P1 | `android/app/src/main/python/sovereign_yt/bridge.py` | Grabber: `search_media` (ytsearch15/scsearch15), `get_available_formats`, `download` (splits `vid+aud` into two `YoutubeDL` runs; `extractor_args player_client=android,web,ios` + `player_skip` on downloads), `cancel`, `fetch_thumbnail`, `capabilities` | `MainActivity.kt` `com.sovereign.tagger/ytdlp` channel (`searchMedia`/`getFormats`/`getCapabilities`/`downloadMedia`/`cancelDownload`); called from `lib/tabs/tab_grabber.dart` and `lib/services/ghost_world.dart` | `yt_dlp` (imported line 6); stdlib only otherwise | **No.** yt-dlp has no Dart equivalent. This is the one hard Python dependency and the reason S2 needs a flavour split rather than a port. |
| P2 | `android/app/src/main/python/sovereign_yt/spider.py` | Enrichment cascade: `scrape_metadata` (iTunes + Deezer + MusicBrainz, scored candidates, dedupe, top 10, Deezer details for top 3), `fetch_lyrics` (LRCLib get → search → search, then Genius fallback), `fetch_artwork` (GET + base64, 2 attempts, 8 MB cap); plus `clean_title`/`clean_artist`/`split_artist_title`/`similarity`/`score_candidate` helpers | `MainActivity.kt` `com.sovereign.tagger/spider` channel (`scrape`/`fetchLyrics`/`fetchArtwork` → `spiderPythonModule.callAttr(...)`); called from `lib/core/metadata_sources.dart` (`MetadataSources.search`/`fetchLyrics`/`fetchArtworkBase64`), used by Forge, Pipeline, Player, GhostWorld, MetadataReviewSheet | `lyricsgenius` (only inside `_genius_lyrics`); stdlib `urllib` otherwise — all five sources are plain REST/JSON | **Yes — built in this PR (S1).** `lib/core/dart_spider.dart` reimplements the cascade in pure Dart (`dart:io` HttpClient, zero new deps), wired as a parallel path behind a default-OFF flag (`dart_spider` in SharedPreferences, toggle in Settings → Core Engine Maintenance). Python spider stays the live path. |
| P3 | `android/app/src/main/python/sovereign_yt/updater.py` | Self-heal: `execute_scorched_earth` (pull latest yt-dlp tarball from GitHub releases API, wipe the `yt_dlp` dir, copy the new one in, reload modules), `execute_full_scorched_earth`, `update_python_stack` (upgrades only `mutagen` + `lyricsgenius`, not yt-dlp) | `MainActivity.kt` `ytdlp` channel (`updateCore`/`updateFullStack`); called from `lib/screens/settings_screen.dart` | None directly (stdlib `urllib`/`tarfile`/`shutil`); operates on the pip-installed `yt_dlp` package dir | **No.** Meaningless without Python/yt-dlp on device. In an `sdk` flavour these Settings actions are hidden (S2), not ported. |
| P4 | `android/app/src/main/python/sovereign_yt/doctor.py` | Diagnostics: `PATCH_REGISTRY` (5 rules: YouTube Android blocked, impersonate removed, 403/throttle, Genius 429, outdated extractor), `diagnose(errorLog)`, `get_registry()` | `MainActivity.kt` `ytdlp` channel (`runDoctor`/`getDoctorRegistry`); called from `lib/screens/settings_screen.dart` | None (stdlib `json`/`os`/`re` only) | **Partial.** The registry is data, portable to Dart as a constant — but its hotfixes reference Python files (`bridge.py`, `spider.py`, `updater.py`). A Dart doctor would need its own rules; not built in this PR. In an `sdk` flavour the Doctor UI is hidden (S2). |
| P5 | `android/app/src/main/python/sovereign_yt/__init__.py` | Package marker only | — | — | N/A. Empty apart from the Genesis header. |

## 3. The unused pip dependency

**`mutagen` is installed by pip but imported by no on-device Python file.**
Verified by grep across `android/app/src/main/python/`, `lib/`, and
`android/app/src/main/kotlin/`: the only mentions are `updater.py:101`
(`update_python_stack` upgrades it) and `settings_screen.dart:232` (UI text
"Full Stack Refresh: yt-dlp + mutagen/lyricsgenius..."). Tagging on device is
done by jaudiotagger over the native `id3` channel, never by mutagen, and
yt-dlp does not depend on it. It is dead weight in the pip install: harmless
today, but the first thing to drop if the pip block is ever tightened. It is
deliberately left installed in this PR — removing a pip package is a build
change, not an audit change.

## 4. Already native / Dart (no Python involved)

| Subsystem | Implementation | Verified |
|---|---|---|
| ACRCloud fingerprinting | Kotlin bridge (`com.sovereign.tagger/acrcloud` channel; native SDK installed into `android/app/libs` + `jniLibs` by host script `acr_installer.py`) | `metadata_sources.dart: acrIdentify` → `_acr` channel; `MainActivity.kt` |
| ID3 tagging | jaudiotagger `3.0.1` over native `id3` channel | `android/app/build.gradle` deps; `lib/core/` TagIO path |
| Whisper STT | Custom FFmpeg `whisper` filter (no Python) | `lib/core/speech_to_text.dart`, Workbench |
| Whistle STT | C++ NDK `libneedle.a` + `assets/models/whistle.cact` (16.9 MB) via `WhistleBridge.kt` JNI; assets fetched by host script `download_whistle_assets.py` | `android/app/src/main/cpp/`, `lib/core/whistle_model.dart` |
| GhostBrain | Pure-Dart BM25 + deterministic commands; semantic routing via LiteRT EmbeddingGemma Kotlin bridge | `lib/services/ghost_brain.dart`, `EmbeddingGemmaBridge.kt` |
| PCM capture | `PcmRecorderBridge.kt` (AudioRecord 48k/16-bit WAV) | `lib/core/pcm_recorder.dart` |
| FFmpeg DSP | `ffmpeg_kit_extended_flutter 0.6.2`, `full` + GPL, FFmpeg 9.0.1 | `pubspec.yaml`, `lib/core/ffmpeg_executor.dart` |
| Embeddings model download | Pure-Dart `HttpClient` with redirect following | `lib/core/embedding_model.dart` (the pattern `dart_spider.dart` mirrors) |

## 5. Host-side Python scripts (never shipped on device)

| File | Purpose | Shipped? |
|---|---|---|
| `acr_installer.py` | Downloads the ACRCloud SDK zip from GitHub master, copies `.jar`/`.so` into `android/app/libs` + `jniLibs` | No — run on the host, once |
| `download_whistle_assets.py` | Downloads `libneedle.a` + `whistle.cact` from Hugging Face with SHA-256 logging | No — run on the host, once |
| `ghostbrain_tab_patcher.py` | Optional one-time patcher wiring GhostBrain hooks into Grabber/Forge tabs | No — run on the host, once, if ever |

## 6. What S1 changes and what it does not

- **Changes:** adds `lib/core/dart_spider.dart` (pure-Dart port of `spider.py`)
  and a default-OFF `dart_spider` flag (SharedPreferences, Settings toggle)
  that routes `MetadataSources.search` / `fetchLyrics` / `fetchArtworkBase64`
  through the Dart cascade. Python `spider.py` is untouched and remains the
  live path.
- **Does not change:** `bridge.py` (yt-dlp), `updater.py`, `doctor.py`,
  `build.gradle` pip block, Chaquopy config, or any default behaviour.
- **Known port deltas** (all documented in `dart_spider.dart`'s report):
  `lyricsgenius` has no Dart equivalent, so Genius lyrics go through the
  Genius search API + HTML lyric-container extraction instead of the Python
  library's scraper; NFKD unicode normalisation is approximated with a
  Latin diacritic table (Dart has no built-in NFKD); `difflib`
  `SequenceMatcher` is reimplemented as gestalt matching-blocks in Dart.
  All five sources, their order, scoring weights, bonuses, thresholds, and
  the LRCLib/Genius fallback order are otherwise identical to `spider.py`.

## 7. What is still missing for an `sdk` flavour (S2+ work, not this PR)

1. **P1 (yt-dlp) has no port** — the Grabber tab, the `ytdlp` channel, and the
   updater/doctor Settings actions must be hidden behind a flavour guard (S2),
   not reimplemented.
2. **P3/P4 have no Dart equivalents** — updater/doctor are Python-only by
   nature; S2 hides them.
3. **MusicBrainz rate limit** (1 req/s) is not throttled in either
   implementation — Python never throttled it either; parity, not a fix.
4. **AGP ceiling** (spec: AGP 9.0.1, Chaquopy supports 7.3–9.2) is
   doc-sourced from `AGENTS.md` toolchain notes and was not re-verified in
   this audit; `compileOptions` in `android/app/build.gradle` already reads
   Java 17, not the 1.8 the spec/AGENTS.md still mention — doc drift, the
   executable file wins.
5. **No device verification** — the Dart cascade has not run against the live
   APIs on the Moto G; `flutter analyze` could not run on the build VM.
   Verify against known tracks with the flag ON before trusting it.
