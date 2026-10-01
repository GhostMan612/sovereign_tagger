---
name: sovereign-native
description: "Kotlin/chaquopy bridges: MethodChannels (ytdlp, id3, storage, acrcloud, spider, pcm_recorder), Python modules (bridge, updater, spider, doctor), FFmpeg introspection, ACRCloud mic release fix."
tools:
  read: true
  write: true
  edit: true
  glob: true
  grep: true
permission:
  bash:
    # Broad fallback FIRST. opencode evaluates the LAST matching rule, so this
    # only catches shell commands nobody classified: those ask instead of
    # silently running. The narrow rules below override it.
    "*": ask
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
    # ⛔ NARROW DENIES MUST BE LAST — the engine is LAST-MATCH-WINS. These three
    # used to sit up in the build-boundary block, where the broad "git add *" /
    # "git push*" asks below re-matched them and silently downgraded deny to a
    # prompt: `git add -A` and `git push --force` were ASKED, never blocked.
    # Ordering IS the mechanism — being last is what makes them bind.
    "git add .*": deny
    "git add *-A*": deny
    "git add *--all*": deny
    "git push*--force*": deny
    "git push -f*": deny
---

# Sovereign Native Agent

## Domain
`android/app/src/main/kotlin/com/sovereigntagger/` — `MainActivity.kt`, `Id3Tagger.kt`, `PcmRecorderBridge.kt`, `AcrCloudBridge.kt`, `StorageBridge.kt` + Python `android/app/src/main/python/sovereign_yt/`

## Core Rules (from RULES.md)
- **Chaquopy**: `gradle:17.0.0` supports AGP 7.3–9.2 / Python 3.10–3.14 / minSdk 24
- **Python 3.14** top but few wheels — fallback to `"3.11"` in `app/build.gradle:54`
- **64-bit only**: `abiFilters arm64-v8a,x86_64` (no `armeabi-v7a`)
- **JDK 25 bundled** with `compileOptions 1.8` shim (bump to 17 only in dedicated session)

## MethodChannels (MainActivity.kt)
| Channel | Methods |
|---------|---------|
| `com.sovereign.tagger/ytdlp` | `searchMedia`, `getFormats`, `downloadMedia`, `cancelDownload`, `updateCore`, `updateFullStack`, `runDoctor`, `getDoctorRegistry` |
| `com.sovereign.tagger/ytdlp_events` | EventChannel (progress JSON) |
| `com.sovereign.tagger/id3` | `writeTags`, `readTags` |
| `com.sovereign.tagger/storage` | `addToMediaStore`, `exportConfig`, `autoImportConfig`, `getTempDirectory` |
| `com.sovereign.tagger/acrcloud` | `initialize`, `identify` |
| `com.sovereign.tagger/spider` | `scrape` |
| `com.sovereign.tagger/pcm_recorder` | `hasPermission`, `startRecording`, `stopRecording` |

## Python Modules (`sovereign_yt/`)
- **bridge.py**: `"vid+aud"` split → two `YoutubeDL` runs, `extractor_args player_client=android,web`, jobId templated `"{job_id}_v/a.%(ext)s"`, split orphan cleanup
- **spider.py**: Genius→LRCLIB→SoundCloud→iTunes→MusicBrainz cascade, `extractor_args` on SoundCloud path
- **updater.py**: `execute_scorched_earth` (tarball) + `update_python_stack` (pip) + `execute_full_scorched_earth`
- **doctor.py**: `PATCH_REGISTRY` (5 signatures), `diagnose()`, `get_registry()`

## Id3Tagger.kt (jaudiotagger)
- `writeTags(filePath, metadata)` — `deleteField` on empty value, `deleteArtworkField` on empty art
- **ReplayGain TXXX frames**: `REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_TRACK_PEAK`, `REPLAYGAIN_ALBUM_GAIN`, `REPLAYGAIN_ALBUM_PEAK` via `FrameBodyTXXX`/`ID3v24Frames`
- `readTags(filePath)` — returns Map with standard fields + `ARTWORK_BASE64` + ReplayGain fields

## PcmRecorderBridge.kt
- `AudioRecord` 48kHz/16-bit mono WAV
- Header placeholder → LE finalize on stop
- Single `ByteBuffer` reuse (no per-loop alloc)
- `startRecording(path, sampleRate, channels)` / `stopRecording()` → returns file path

## ACRCloud Fix (Phase 21)
- Bridge stores credentials, auto-reinitializes per call
- **Fully stops + releases client after every recognition** — mic indicator extinguishes immediately

## FFmpeg Introspection (boot)
- `FFmpegKitExtended.getRegisteredFilters()` count logged at splash
- `WHISPER SURFACE: DETECTED/NOT EXPOSED` verdict
- Device probe: 548 filters, rubberband/soxr/x264/vpx/opus/vidstab confirmed

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: yt-dlp search/download; ID3 write/read; PCM record 48k WAV; ACR identify (mic releases); Whisper transcribe