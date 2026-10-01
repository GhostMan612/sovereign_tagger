---
name: sovereign-visual
description: "Cyberpunk visuals: MatrixRain splash, CyberBackdrop GPU shader backdrop (AmbientBackdrop painter fallback), electric arcs, traveling comets, AnimatedTabStack, CyberNavBar, page transitions, lifecycle pause, TextPainter reuse, accent-color reactivity."
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

# Sovereign Visual Agent

## Domain
`lib/widgets/machine_rain.dart` — `MatrixRain` (splash) + `AmbientBackdrop` (painter fallback) · `lib/widgets/cyber_backdrop.dart` — `CyberBackdrop` (the primary per-tab GPU backdrop) · `animated_tab_stack.dart`, `cyber_nav_bar.dart`, `cyber_ink.dart`, `cyber_page_transitions.dart`, `tap_fx_layer.dart`

## Core Rules (from RULES.md)
- **Cyberpunk aesthetic**: black, monospace (`ShareTechMono`, `VT323`), accent-color reactive (`SovereignState.accentColor`)
- **Code-drawn only**: No raster assets — `CustomPainter`, `Shader`, `Lottie`/`Rive` JSON only if added to `pubspec.yaml`
- **Asset limits**: `pubspec.yaml:34` declares `assets/`; new assets need rebuild. Current: `assets/splash-screen-bg.png` + fonts only
- **Performance**: Single `TextPainter` reuse (was 400 allocs/frame), cols capped 36, GC pressure ↓60%
- **Lifecycle**: `CyberBackdrop` AND its `AmbientBackdrop` fallback both pause on app pause/hidden (lifecycle observer) — kills background GPU spam and battery drain

## MatrixRain (Splash)
- `MatrixRainPainter` — single `TextPainter` reused, 36 columns, char len 7–14
- Overlay on `SplashScreen` with `assets/splash-screen-bg.png` at 22% opacity
- Accent-color reactive via `ValueListenableBuilder<SovereignState.accentColor>`

## CyberBackdrop (MainShell — primary, GPU)
- `shaders/backdrop.frag` via `FragmentProgram.fromAsset`, 30 fps, own `RepaintBoundary`
- Accent nebula + synthwave grid floor + per-tab layer: **Grabber** data streams, **Forge** embers, **Batch** scan bands, **Workbench** waveform
- Uniforms fed with `setFloat` in **declaration order** (a `vec2` takes 2 slots, `vec4` takes 4)
- Compile-check before shipping: `impellerc --runtime-stage-gles` / `--runtime-stage-vulkan` / `--sksl`
- **Fallback**: if the shader fails to load, it returns `AmbientBackdrop` instead — never a blank screen

## AmbientBackdrop (painter fallback, also still the no-shader path)
- `BackdropVariant` per tab:
  - **Grabber**: vertical drops (2 arcs, 2 travelers)
  - **Forge**: slow pulse (1 arc, 1 traveler)
  - **Pipeline**: horizontal flows (2 arcs, 3 travelers)
  - **Workbench**: mixed (2 arcs, 2 travelers)
- Electric arcs: jagged polylines on grid lines, white-hot head + glow, 45%-cycle flashes
- Traveling comets: multi-dot tails gliding grid rows/cols
- `alpha 0.035` grid + `0.18` sparks, 4s `AnimationController`
- Zero new deps, zero assets, no rebuild needed

## MainShell Integration
- `Stack` → `CyberBackdrop` (variant via `ValueListenableBuilder<SovereignState.currentTab>`) + `AnimatedTabStack` + mini-player + `CyberNavBar`; `GhostChatOverlay` is the LAST `Stack` child (GH9 — earlier and the opaque tab `Scaffold`s bury it)
- Tab switching goes through `AnimatedTabStack`, never by swapping its wrapper types (G32); page transitions come from `CyberPageTransitionsBuilder` in the theme, so plain `MaterialPageRoute`s animate automatically
- Every tappable gets FX for free from `TapFxLayer` (a `MaterialApp.builder`); do NOT hand-roll per-button bursts

## Rive/Lottie Path (if needed later)
- Add `assets/animations/<tab>.json` + `pubspec.yaml: assets: - assets/animations/` → rebuild
- Still <100KB, stays under `hooks`/`code_assets` without NDK

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: splash rain 60fps; per-tab pulses 60fps; lifecycle pause on background; accent color change propagates instantly