---
name: sovereign-player
description: audio_service lockscreen notification, just_audio queue management, playback controls, speed/sleep/shuffle/repeat, queue persistence, crossfade, gapless.
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

# Sovereign Player Agent

## Domain
`lib/screens/main_shell.dart` (AudioService class, ~950 L) + `lib/tabs/tab_player.dart` (TheaterScreen) + `lib/core/audio_handler.dart`

## Core Rules (from RULES.md)
- **Queue mutations**: NEVER mutate `AudioService.playlist` directly — use mutators so `_audioSource` stays in sync
- **Queue mutators**: All `Future<void>` + `await _audioSource` inside `_withQueueLock`
- **Global state**: `SovereignState` static `ValueNotifier`s + `AudioService` static singleton
- **Lockscreen**: `audio_service 0.18.19` + `SovereignAudioHandler` + manifest `AudioService`/`MediaButtonReceiver`
- **Async UI**: `if (!mounted) return;` after every `await`

## AudioService Static API
- `player` — `just_audio` `AudioPlayer`
- `_audioSource` — `ConcatenatingAudioSource` (gapless default-on)
- `playlist` / `currentIndex` — `ValueNotifier<List<File>>` / `int`
- `repeatMode` — `PlaybackRepeat.off|all|one` → `player.setLoopMode`
- `isShuffle` — `player.setShuffleModeEnabled`
- `speedFactor` — `player.setSpeed` (0.5x–2x, persisted)
- `sleepTimerMinutes` — `Timer` → `stopPlayer()`
- `videoController` — `VideoPlayerController` for video tracks

## Queue Mutators (all serialized via `_withQueueLock`)
- `replacePlaylist(files, startIndex, startPosition)` — clears `_audioSource`, adds all, seeks
- `playNext(file)` — inserts after current
- `addToQueue(file)` — appends to end
- `moveAfterCurrent(index)` — moves track to after current
- `reorderPlaylist(oldIndex, newIndex)` — `_audioSource.move()`
- `removeFromPlaylist(index)` — `_audioSource.removeAt()`
- `clearPlaylist()` — `_audioSource.clear()`

## Queue Persistence
- Debounced JSON to `SharedPreferences` (`persist_queue`: paths, index, positionMs)
- Restored on boot behind splash (`restorePersistedQueue()` → `autoMountMusicFolder()` fallback)

## TheaterScreen (`tab_player.dart`)
- Mini-player + fullscreen video + artwork pinch-zoom (1→3x, `BoxFit.contain`)
- `_SeekSlider` — drag updates local only, single `seek` on `onChangeEnd`
- Track menu: Send to Forge / Play Next / Remove From Matrix
- Queue sheet: `Material(type: transparency)` wrapper fixes ListTile assertion

## Crossfade / Gapless (Phase 22)
- Settings: `_crossfadeDuration` (0–12s) + `_gaplessEnabled` (default true)
- Persisted to `SharedPreferences`, applied via `player.setAudioSource` config

## Native Bridge
- `MainActivity.kt` → `AudioServiceActivity` (fixes `IllegalStateException`)
- Manifest: `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `AudioService`, `MediaButtonReceiver`

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: lockscreen notification art/controls; sleep/speed/LRC; queue persist; gapless audit (zero silence); crossfade 0–12s