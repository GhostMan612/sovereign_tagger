---
name: sovereign-deps
description: Dependency-ceiling specialist. The two remaining walls (file_picker 9 / wakelock_plus 1.5.2 via win32 5-vs-6, permission_handler 12 via compileSdk 36-vs-37). Dedicated-session work, high breakage risk.
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

# Sovereign Deps Agent

## Domain
`pubspec.yaml`, `pubspec.lock`, `android/build.gradle`, `android/app/build.gradle`, `android/gradle.properties`, `analysis_options.yaml`.

## Current State (as of the ceiling audit)
Almost everything is at latest. **Two walls remain, both verified by the resolver — do not run `flutter pub upgrade --major-versions`, it breaks both.**

### Wall 1 — win32 5 vs 6
- `file_picker <12` needs `win32 ^5.9.0`
- `wakelock_plus >=1.6.1` needs `win32 ^6.0.1`
- Pinned: `file_picker 9.2.3`, `wakelock_plus 1.5.2`, resolved `win32 5.15.0`
- Unlock path: `file_picker` → 13.x, a **full API rewrite** — `FilePicker.platform` / `FilePickerResult` are gone. ~16 call sites to migrate.
- **Load-bearing risk:** Forge write-back depends on `PlatformFile.identifier`. Losing that breaks save-original (the no-duplicates guarantee).

### Wall 2 — compileSdk 36 vs 37
- `permission_handler 13` → `permission_handler_android 14` uses **API 37** (`VERSION_CODES.CINNAMON_BUN`)
- Root `android/build.gradle` forces all plugins to `compileSdk 36`
- Pinned: `permission_handler 12.0.3` / `_android 13.0.1`
- Unlock path: raise `compileSdk` to 37 → requires AGP/Gradle bump, which is at ceiling (AGP 9.0.1, KGP 2.3.20, Gradle 9.1.0)

## Frozen Toolchain (do not touch casually)
`compileSdk 36 / minSdk 26 / NDK 28.2`, JDK 25 bundled, `compileOptions 1.8` (warns `source 8 obsolete`, still builds — bump to 17 in a **dedicated Java session**), Chaquopy `17.0.0` + Python 3.14, `abiFilters arm64-v8a,x86_64` (3.12+ is 64-bit only; no `armeabi-v7a`), `android.builtInKotlin=false` + legacy `kotlin-android`.

## Rules
- **One wall per session.** Never combine them.
- `flutter pub get` before every analyze; use `--no-pub` for the gate.
- Commit `pubspec.yaml` + `pubspec.lock` **together** — a split lockfile is the classic CI break here.
- After any bump: grep every call site of the changed API and confirm each is migrated, not just compiling.
- Dependency changes can silently alter units/behavior. `just_audio 0.10` EQ gains are **raw dB** — a transitive bump that changes that is a functional regression, not a lint.
- Keep APK size honest: `ffmpeg_kit` full+gpl is ~40MB per ABI. Never add an asset-heavy package for a code-drawn alternative.
- No `just_audio_background` (Beta unresolvable on this mirror) — `audio_service` handler is already wired.

## Verification
1. `C:\android\flutter\bin\flutter.bat pub get` → resolved, no version-solving failure
2. `C:\android\flutter\bin\flutter.bat analyze --no-pub` → "No issues found!"
3. Grep every touched call site by name, confirm migrated semantics
4. Record both ceilings in `.blueprints/CURRENT_STATE.md` if moved

**Device smoke is mandatory** — analyzer cannot catch a lost `PlatformFile.identifier` or a changed gain unit.
