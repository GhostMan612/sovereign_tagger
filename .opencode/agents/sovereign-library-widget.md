---
name: sovereign-library-widget
description: Library tab (MediaStore browse) + Home screen widget (RemoteViews) + Backup/Restore (XOR encrypted JSON).
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

# Sovereign Library + Widget + Backup Agent

## Domain
- `lib/tabs/tab_library.dart` — Library tab (MediaStore browse by Album/Artist/Folder)
- `android/app/src/main/kotlin/com/sovereigntagger/SovereignWidgetProvider.kt` — Home screen widget (RemoteViews)
- `lib/screens/settings_screen.dart` — Backup/Restore (XOR `0x53` encrypted JSON)

## Library Tab (`TabLibrary`)
- **Browse modes**: ALBUM / ARTIST / FOLDER (dropdown)
- **Search**: real-time filter by title/artist/album
- **MediaStore scan**: `FilePicker` multi-pick → reads tags via `id3` channel `readTags`
- **Play integration**: taps item → `AudioService.replacePlaylist()` → switches to Player tab (index 4)
- **UI**: `ListTile` with artwork (base64 decode), title, artist, album/year
- **BottomNav**: added as 5th tab (`Icons.library_music`, label 'LIBRARY')

## Home Screen Widget (`SovereignWidgetProvider`)
- **RemoteViews** layout: `res/layout/sovereign_widget_initial.xml`
- **Provider**: `SovereignWidgetProvider.kt` extends `AppWidgetProvider`
- **Manifest**: receiver with `android.appwidget.action.APPWIDGET_UPDATE`
- **XML config**: `res/xml/sovereign_widget_info.xml` (minWidth 250dp, minHeight 180dp)
- **Buttons**: PREV / PLAY / NEXT / QUEUE → PendingIntents to `MainActivity` with custom actions
- **Styling**: Cyberpunk — black bg, accent border, `ShareTechMono`/`VT323` fonts
- **No Glance dependency** — uses standard `AppWidgetProvider` (simpler, no extra dep)

## Backup/Restore (Settings)
- **XOR `0x53` encryption** (same as config export)
- **Backup payload** (JSON):
  - Settings: Genius/ACR keys, crossfade, gapless, accent color
  - EQ presets: 15-band values (`eq15_band_0`–`eq15_band_14`)
  - Persisted queue: `persist_queue` (paths, index, positionMs)
- **Restore**: FilePicker → decrypt → write to `SharedPreferences` → reload UI
- **Buttons**: BACKUP ALL (green) / RESTORE ALL (amber)

## Native Bridge
- `storage` channel: `exportConfig` (backup), `autoImportConfig` (restore), `getTempDirectory`
- `id3` channel: `readTags` (for library scan)

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: Library scan → play track; Widget add → buttons work; Backup → Restore round-trip