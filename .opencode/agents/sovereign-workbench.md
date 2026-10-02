---
name: sovereign-workbench
description: "FFmpeg DSP operations: audio/video processing, filters, encoding, Whisper transcription, ReplayGain, 15-band EQ, crossfade. All operations via FFmpegExecutor queue."
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
    # Build boundary — `flutter build apk` is ALLOWED per RULES.md §1.5 (operator
    # override 2026-10-01). appbundle/gradle release stay `ask`: signing and
    # store packaging are deliberate operator calls.
    "adb*install*": deny
    "adb*uninstall*": deny
    "adb*root*": deny
    "adb*push*": deny
    # End-of-plan ONLY. TIMING is governed by §1A.0 — once per phase, never
    # after an individual edit, and never "just to check".
    "*flutter.bat analyze*": allow
    "*flutter.bat pub get*": allow
    # RULES.md 1.5 - builds allowed (operator override 2026-10-01). Still
    # END-OF-PLAN: a release build is minutes, never a mid-plan probe.
    "*flutter.bat build apk*": allow
    "*build apk*": allow
    "*build appbundle*": ask
    "*assembleRelease*": ask
    "*bundleRelease*": ask
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

# Sovereign Workbench Agent

## Domain
`lib/tabs/tab_workbench.dart` (~1.4k L) — DSP, format conversion, clipping, normalization, AI ops, recording.

## Core Rules (from RULES.md)
- **FFmpeg calls**: ALWAYS `await FFmpegExecutor.execute(...)` — serialized queue
- **Tag writes**: Native `id3` channel (jaudiotagger) only — never FFmpeg remux for tags
- **Lossless guarantee**: Preserve container unless explicit conversion; `flac→flac`, `wav→wav`, `m4a→m4a`, etc.
- **Container-preserving**: `preserveOp` list gates `_audioCodecArgs(ext)` with source extension
- **Async UI**: `if (!mounted) return;` after every `await`

## Operations (preserveOp = true)
- Normalize Audio (LUFS -14): `loudnorm=I=-14:LRA=11:TP=-1.5` + two-pass option
- Granular Audio DSP: `asetrate`/`rubberband`/`atempo` + `aecho` reverb
- Apply Fades: `afade=t=in/out`
- Fold To Mono: `pan=mono|c0=0.5*c0+0.5*c1`
- Trim Silence: `silenceremove`
- AI Denoise: `afftdn=nf=-25`
- Parametric EQ: 5-band (bass/low-mid/mid/high-mid/treble)
- Compress Dynamics: `acompressor=threshold=0.1:ratio=1-12:attack=50:release=500`
- **15-Band Equalizer (AutoEq)**: 15 bands 25Hz–16kHz, Q=1.2, `equalizer=f=FREQ:t=q:w=1.2:g=GAIN`
- **Scan ReplayGain (EBU R128)**: `ebur128` → TXXX frames via `id3` channel
- **Whisper AI**: bundled `ggml-base.en.bin` (141MB), `-af "whisper=model=<path>:language=<en|auto>:destination=<path>:format=srt" -f null -`

## Key State
- `_selectedOperation` — dropdown of 13 operations
- `_sampleRate` / `_bitDepth` — mastering quality (lossless-gated)
- `_pcmLossless` — 48k/16-bit WAV via `PcmRecorderBridge` (default ON)
- `_eq15Bands[15]` + `_eq15Freqs[15]` — AutoEq-compatible, synced with Settings

## Native Bridge
- `id3` channel: `writeTags` (TXXX for ReplayGain), `readTags`
- `pcm_recorder` channel: `hasPermission`, `startRecording` (48k/16-bit WAV), `stopRecording`
- `storage` channel: `getTempDirectory`, `addToMediaStore` (MIME map)

## Verification
- `flutter analyze --no-pub` → "No issues found!" — **END OF PLAN ONLY** (§1A.0). Once per phase, never after an individual edit, never "just to check". Fix everything you can see with `read`/`grep`/`edit` first, then gate once.
- Device smoke: PCM record → Apply Fades/Loudnorm → export; Whisper transcribe → .srt sidecar; 15-band EQ apply
