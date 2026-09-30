---
name: sovereign-pipeline
description: Batch processing pipeline: GHOST/PARTIAL/PRISTINE/PROCESSED/FAILED buckets, cancel/retry, ACRCloud fingerprinting, Genius spider, Mixtape Join, file picker hygiene.
tools:
  read: true
  write: true
  edit: true
  glob: true
  grep: true
  bash:
    # ⛔ RULES.md §1A.0 — THE SHELL GATE. During a plan, the shell is not called
    # at all. These denies are the MACHINE ENFORCEMENT of that rule: a denial is
    # a REFUSED call, not a warning that scrolls past. Prose alone was ignored.
    #
    # Read/search class — dedicated tools exist. The shell is a build tool,
    # not a search tool.
    "cat*": deny
    "type*": deny
    "more*": deny
    "head*": deny
    "tail*": deny
    "Get-Content*": deny
    "Select-String*": deny
    "findstr*": deny
    "rg*": deny
    "grep*": deny
    "Get-ChildItem*": deny
    "dir*": deny
    "ls*": deny
    "Test-Path*": deny
    # Write class — PowerShell 5.1 corrupts UTF-8 (RULES.md §3.1).
    "Set-Content*": deny
    "Add-Content*": deny
    "Out-File*": deny
    "sed*": deny
    "write*": deny
    "echo*>*": deny
    # Build boundary — the human builds and installs (AGENTS.md / RULES.md §1.6).
    "*build apk*": deny
    "*build appbundle*": deny
    "*assembleRelease*": deny
    "*bundleRelease*": deny
    "adb*install*": deny
    "adb*uninstall*": deny
    "adb*root*": deny
    "adb*push*": deny
    "git*add*-A*": deny
    "git*add*--all*": deny
    "git*push*--force*": deny
    # End-of-plan ONLY. TIMING is governed by §1A.0 — once per phase, never
    # after an individual edit, and never "just to check".
    "*flutter.bat analyze*": allow
    "*flutter.bat pub get*": allow
    "adb*logcat*": allow
    "adb*shell*": allow
    "adb*devices*": allow
    "git status*": allow
    "git diff*": allow
    "git log*": allow
    "git add *": ask
    "git commit*": ask
    "git push*": ask
---

# Sovereign Pipeline Agent

## Domain
`lib/tabs/tab_pipeline.dart` (513 L) — batch processor with 5 buckets, cancel/retry, ACR + Genius enrichment.

## Core Rules (from RULES.md)
- **Batch loops**: Every `await` inside `_runBatch` guarded; any throw must reset `_isBatchRunning` or tab locks forever
- **Cancel**: `_isBatchRunning` flag halts `for` loop (`if (!_isBatchRunning) break`)
- **Retry**: Per-item `FAILED→GHOST` re-buckets, re-triggers batch
- **Mounted guards**: Per iteration + outer `PlatformException` around `FilePicker`
- **Temp hygiene**: `finally` WAV cleanup for ACR recordings

## Pipeline State
- `_items` — List of `PipelineItem` with `bucket` (GHOST/PARTIAL/PRISTINE/PROCESSED/FAILED)
- `_isBatchRunning` — atomic flag
- `_acrRecorder` — `RecorderController` for 50ms AAC fingerprint captures

## Batch Flow (`_runBatch`)
1. Filter GHOST → PARTIAL (ACR identify)
2. PARTIAL → PRISTINE (Genius spider scrape)
3. PRISTINE → PROCESSED (apply tags, move to Music)
4. FAILED items: retry button re-buckets to GHOST/PARTIAL

## ACRCloud Integration
- `_identifyWithAcrCloud(file)` → `acrcloud` channel `identify`
- Records 50ms AAC via `_recorderController` → temp WAV → `identify` → cleanup in `finally`
- Result parsed for title/artist/album/genres/year/cover art URL

## Genius Spider
- `_scrapeGenius(artist, title)` → `spider` channel `scrape` with Genius key
- Cascade: Genius → SoundCloud → iTunes → MusicBrainz (Python `spider.py`)
- Merges metadata: lyrics, cover art, genres, year, album

## Mixtape Join (Phase 18)
- `_mixtapeJoin()` — lossless concat demuxer `-c copy -write_xing 1` of PROCESSED mp3s → MediaStore
- Single output file with all tracks concatenated

## File Picker Hygiene
- `pickSingle` / `pickMultiple` / `pickAndEnqueue` — all wrapped in `try/catch PlatformException`
- `mounted` guards on all `setState` after `await`

## Native Bridge
- `acrcloud` channel: `initialize(host, key, secret)`, `identify(filePath)`
- `spider` channel: `scrape(artist, title, geniusKey)`
- `storage` channel: `addToMediaStore`, `getTempDirectory`

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: batch cancel/retry; ACR identify → metadata fill; Genius scrape → lyrics/art; Mixtape Join lossless concat