---
name: sovereign-forge
description: ID3 tag editor: metadata read/write, cover art, export with container preservation, write→read-back verification, karaoke sync (isolated player), eject safety, staging hygiene.
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

# Sovereign Forge Agent

## Domain
`lib/tabs/tab_forge.dart` (605 L) — tag editor, metadata, export, karaoke, cache management.

## Core Rules (from RULES.md)
- **Tag writes**: Native `id3` channel (jaudiotagger) only — edits in place, lossless
- **Export**: Preserve source extension (`mp3/flac/wav/m4a/ogg/opus`); verify with write→read-back round-trip
- **Eject safety**: Cache-only delete (`deleteSync`) + confirm dialog (never touches user originals)
- **Staging hygiene**: Export purges mounted copy from `Android/data/com.sovereigntagger/` or cache; status "Staging Copy Purged"
- **Karaoke**: Isolated `LyricSyncScreen` player (no global hijack) with play/pause/restart bar
- **Async UI**: `if (!mounted) return;` after every `await`

## Forge State
- `_selectedFile` — mounted media (from `pendingForgePath` cross-tab handoff)
- `_tags` — editable metadata Map (title, artist, album, year, genre, track, disc, lyrics, etc.)
- `_coverArt` — base64 artwork or null
- `_dirty` — unsaved changes flag

## Key Methods
- `_loadFile(path)` — reads via `id3` channel `readTags`, populates `_tags`, loads cover art
- `_saveTags()` — writes via `id3` channel `writeTags` (empty string → `deleteField`)
- `_export()` — copies to temp, writes tags, verifies read-back mismatch → MediaStore
- `_eject()` — confirm dialog → `deleteSync` cache copy only → `pendingForgePath=""` → tab switch

## Karaoke Sync (`LyricSyncScreen`)
- Own `AudioPlayer _player` (isolated, 48k sample rate)
- Transport bar: play/pause/restart + `H:MM:SS` position
- Tempo warp slider (0.5x–2x)
- LRC parse: sidecar `.lrc` or embedded `LYRICS` tag
- Auto-scroll + tap-to-seek
- `replaceAll('.mp3','')` → proper ext strip for sidecar lookup

## Cross-Tab Handoff
- `SovereignState.pendingForgePath` set from Grabber/Player/Pipeline
- Forge `initState` watches `pendingForgePath` → auto-loads on tab switch

## Native Bridge
- `id3` channel: `writeTags(filePath, metadata)`, `readTags(filePath)`
- `storage` channel: `addToMediaStore`, `getTempDirectory`

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: tag edit → export → verify tags; karaoke sync isolated player; eject cache-only; staging purge; write→read-back mismatch warnings