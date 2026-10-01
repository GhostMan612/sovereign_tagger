---
name: sovereign-grabber
description: yt-dlp search, format selection, download, and FFmpeg merge logic. Handles Facebook silent-video self-heal, 3-rung merge ladder, and composite format splitting.
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

# Sovereign Grabber Agent

## Domain
`lib/tabs/tab_grabber.dart` (795 L) — search, format-fetch, download, merge, preview.

## Core Rules (from RULES.md)
- **FFmpeg calls**: ALWAYS `await FFmpegExecutor.execute(...)` — never sync `FFmpegKit.execute()`
- **Merge muxing**: Explicit `-map 0:v:0 -map 1:a:0`; verify output via `probeStreams`
- **yt-dlp split jobs**: Composite format `"vid+aud"` → Python bridge downloads halves separately; Flutter owns merge
- **Facebook fix**: Probe streams post-download; if zero audio streams → auto bestaudio companion + event-chained merge
- **Job IDs**: Use `_newJobId()` (UUID + millis); never pass `""`
- **Async UI**: Every `setState` after `await` needs `if (!mounted) return;`

## Key Methods
- `_searchMedia()` → `ytdlp` channel `searchMedia`
- `_fetchFormats()` → `ytdlp` channel `getFormats`
- `_downloadMedia()` → `ytdlp` channel `downloadMedia` + `ytdlp_events` EventChannel
- `_mergeStreams()` → `FFmpegExecutor` queue with 3-rung ladder
- `_selfHealSilentVideo()` — capped at 1 attempt, companion job UUID
- `_newJobId()` — `Random().nextInt(999999).toString() + DateTime.now().millisecondsSinceEpoch`

## Native Bridge
- `MainActivity.kt` → `ytdlp` MethodChannel: `searchMedia`, `getFormats`, `downloadMedia`, `cancelDownload`
- `ytdlp_events` EventChannel for progress
- Python: `android/app/src/main/python/sovereign_yt/bridge.py` — splits `"vid+aud"` into two `YoutubeDL` runs with `extractor_args player_client=android,web`

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: quick-video 1080/720 + FB silent-heal