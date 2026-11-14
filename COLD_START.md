# COLD_START.md — Sovereign Tagger

Point a fresh agent here. It contains everything needed to finish the current work
without re-deriving the environment. Read this first, then follow the document map
in `.blueprints/SESSION_HANDOFF.md`.

## 1. What this is

Sovereign Tagger — a Flutter Android media engine (yt-dlp via Chaquopy Python, FFmpeg
DSP, ACRCloud + Genius, offline STT). Repo root: `C:\sovereign_tagger`.

Entry chain: `AGENTS.md` (root, auto-injected) → `.blueprints/RULES.md` (canonical law)
→ `.blueprints/SESSION_HANDOFF.md` (deltas + document map) → `.blueprints/CURRENT_STATE.md`
+ `.blueprints/ROADMAP.md` → `BLUEPRINTS.md` / `ARCHITECTURE.md`.

Executable truth outranks prose: `pubspec.yaml`, `analysis_options.yaml`, and the scripts
under `android/app/src/main/python/`.

## 2. Environment (verified 2026-11-13)

| Thing | Value |
|---|---|
| Repo | `C:\sovereign_tagger` |
| Flutter SDK | `C:\android\flutter\bin\flutter.bat` — full path required, bare `flutter` may not resolve. NOT `C:\src`. |
| adb | `C:\Users\612co\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| Shell | git-bash / MSYS. POSIX syntax (`ls`, `$HOME`, `&&`). Native Windows tools need `C:/...` forward-slash paths; MSYS path conversion is disabled. |
| Scratch | `C:\Users\612co\AppData\Local\hermes\cache\scratch` (`$TMPDIR`) |
| Target device | Moto G `ZT4222BMWN` — 720x1604 @ 280dpi, DPR 1.75 |
| Second device | Blu View 5 `7040016025040287` — Android 14 |
| App id | `com.sovereigntagger/.MainActivity` |

Writable: `C:\sovereign_tagger` only, plus `%USERPROFILE%\.gradle`, pub-cache, `C:\android`.
READ-ONLY — never write: `C:\pathfinder_god`, `C:\Recovery for All`, `C:\Sovereign Nodes`,
`C:\sovereign_mantle`. `C:\sovereign_tagger_2` is a deprecated playground copy — do not use.

Build/analyze (END OF PLAN ONLY — see the shell gate):
```
C:\android\flutter\bin\flutter.bat pub get
C:\android\flutter\bin\flutter.bat analyze --no-pub     # expect "No issues found!"
C:\android\flutter\bin\flutter.bat build apk --release  # minutes, not seconds
```

## 3. Laws that will bite a new agent

- **Shell gate (RULES.md §1A.0):** during a plan, the shell must not be called at all. No
  "let me just check it compiles", no "one quick git status". Correct shape is
  `read → edit → read → edit …` for the whole phase, then ONE shell block.
- **Git:** stage by explicit path (`git add lib/tabs/tab_foo.dart`). `git add .` / `git add -A`
  are forbidden. No force-push without asking. Do not commit/push unless asked.
- **Mojibake ban (RULES.md §3.1):** never edit source via PowerShell text pipelines
  (`Get-Content -replace`, `Set-Content`, `Out-File`). PS 5.1 mis-reads UTF-8 as ANSI and
  silently swaps letters (`setState` → `setYtate`). Editor tools only.
- **FFmpeg:** always `await FFmpegExecutor.execute(...)`. Sync `execute()` freezes the UI.
- **Media:** `Duration` has no `isAfter`/`isBefore` — use `<=` / `>=`.
- **UI:** `setState` after any `await` needs `if (!mounted) return;`.
- **Tagging:** native `id3` channel (jaudiotagger) in place, never FFmpeg remux.
- **Comments:** none in code beyond the Genesis header on core files.
- **Secrets:** never read, print, or commit `.env` / credential files.

## 4. Standing operator directives (from the user — still in force)

1. **Complete Implementation PRs only.** Every implementation PR must contain:
   (1) actual source-code changes resolving the issue, (2) regression tests covering normal
   behavior, failures and edge cases, (3) integration into the existing architecture,
   (4) CI verification including Android builds when native code is affected,
   (5) acceptance evidence stating what passed, what remains unverified, and known limitations.
   Disabling a broken feature is containment, not a complete fix. A CI workflow is
   infrastructure, not a runtime bug fix. Order: source first, tests second, verification
   third, merge last.
2. **Keep the 15 draft PRs open. Make no merges.**
3. **Disposable test media and credentials only.** Never overwrite the user's real
   Genius/ACRCloud credentials during device testing.
4. **Do not record private audio contents in logs.**

## 5. Where things stand (2026-11-13)

- **Branch:** `fix/p1-ffmpegkit-ffi-bridge` @ `10f8e52`
  `fix(grabber): reach FFmpegKit through its C API instead of missing Java classes`
- **Open draft PRs:** 15 — `#71`–`#85`. Merge order: #71–#82 in dependency order, then #83,
  #84, #85 last. **None merged. Keep them drafts.**
- **Build under test:** APK sha256
  `cd1f273615d34197ba299323f0d06b2b8e22eb70db347534de04d48d83d28791`,
  manifest sourceSha `a4119ba5be33a19d0b2b9a9e1314dde79fd477fa` (dirty tree at build time).
- **Device state:** clean. Both speech models restored and sha256-verified; app restarted.
  No test media or pending imports left on the device.

| Subsystem | Status |
|---|---|
| Provenance & physical-device identity | Passed |
| Grabber FFmpeg capability bridge | Passed — device reports FFmpegKit available |
| MediaStore publication | Passed |
| Workbench pending-import recovery | Passed |
| Keystore migration | Passed (save, restart, retrieve, migration; no plaintext residue) |
| **Voice fallback** | **5 of 7 criteria passed — see §6** |
| Transactional updater rollback | Pending (next P1 gate after voice) |
| Sustained playback / audio focus | Pending |
| Metadata duplication (TDRC) investigation | Pending — defect NOT yet proven |

## 6. ACTIVE TASK — P1 voice fallback acceptance (Moto G)

Work order: "Moto G — Whistle → Whisper", acceptance checklist 0/7 at the time it was
issued. **5 of 7 are now done; #5 and #7 remain.**

Voice pipeline files:
`lib/core/whistle_model.dart`, `lib/core/speech_to_text.dart`, `lib/core/voice_input.dart`,
`lib/core/speech_fallback.dart`, `lib/core/model_digest.dart`,
`android/app/src/main/kotlin/com/sovereigntagger/WhistleBridge.kt`,
`lib/widgets/ghost_chat_overlay.dart`.

Model assets and pinned digests (both verified on device 2026-11-13):
```
assets/models/whistle.cact      16,919,407 B  b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb
assets/models/ggml-base.en.bin 147,964,211 B  a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002
```
On-device location: `/data/data/com.sovereigntagger/files/whistle_model/` and
`.../files/whisper_model/` (both models are ALSO bundled in the APK, so a corrupt file is
silently reinstalled from the bundle — see the technique below).

### Completed criteria

**#1 Record with the real microphone; Whistle returns a usable transcript — PASS.**
Played a generated clip ("Forge. Workbench. Playlist. Equalizer. Ghost.") through the
speaker while recording; the panel returned `HEARD: Forge workbench playlist Equalizer Ghost`.
`WhistleJNI` load logs present, zero FFmpegKit activity.

**#2 Controlled Whistle failure → Whisper fallback executes — PASS.**
Method (see §6.1): removed `whistle.cact` and made its directory read-only, then restarted
the app so `isLoaded=false`. Evidence:
- Status line `TRANSCRIBING WITH WHISPER...` — that exact string exists only at
  `lib/core/speech_fallback.dart:54`, emitted by `invoke()` for whichever engine is active.
  Whisper is never the primary, so reaching that line proves the secondary path ran.
- Final transcript `HEARD: forge workbench. playlist equalizer ghost.` — the spoken words,
  so Whisper actually executed and returned text.
- `SpeechFallback.transcribe` calls `invoke(secondary)` once with no retry loop, so
  "exactly once" holds by construction.
- No `voice_input.wav` / `.srt` remained, so the flow ran to completion.

**#3 Original WAV survives the failure and reaches the fallback intact — PASS (indirect but solid).**
Whisper was handed the same path and produced a correct transcript of the same audio, so the
file was present and complete at fallback time.

**#4 Cancel during transcription → no delayed fallback or stale transcript — PASS.**
With Whistle disabled, recorded and cancelled mid-Whisper. Status went to `CANCELED`; the
Ghost panel contained no transcript from the attempt; no leftover `voice_input` files.

**#6 Restart then transcribe works without stale engine state — PASS.**
App restarted (force-stop + relaunch), then a recording returned
`Forge Workbench playlist Equalizer Ghost` via Whistle (`needle_load returned 0`, no Whisper
activity), confirming the engine reloaded cleanly.

### Remaining criteria

**#5 Missing / corrupt / mismatched model assets fail safely with actionable errors — NOT DONE.**
Setup is prepared and reversible (§6.1): break BOTH models, then record. Expected result:
```
TRANSCRIBE ERROR: Primary speech engine failed; offline fallback is not installed.
Download the Whisper model from Settings to enable fallback. Primary error: ...
```
Verify that string appears (it is the actionable guidance, not a bare failure). The
Whistle half of this is already proven — the remaining step is to make Whisper unavailable
too and confirm the refusal message. **The device is currently restored; re-apply §6.1
before attempting.**

**#7 Capture engine selection, result, cancellation and error evidence without recording
private audio contents — NOT DONE.** Compile the evidence file from §6.2 and state plainly
that no audio payloads were logged (only engine selection, status strings and transcripts).

### 6.1 Controlled-failure technique (critical — do not skip)

Both models are bundled in the APK, so **deleting the model file alone does nothing**:
`WhistleModel.ensure()` / `WhisperModel.ensure()` detect the digest mismatch and reinstall
from `assets/models/`. To make a model genuinely unavailable you must BOTH remove the file
AND make its directory non-writable, then restart the app (to clear the native `isLoaded`
flag). Exactly what worked:

```bash
ADB=/c/Users/612co/AppData/Local/Android/Sdk/platform-tools/adb.exe
D=ZT4222BMWN

# Break Whistle
"$ADB" -s $D shell run-as com.sovereigntagger cp files/whistle_model/whistle.cact files/whistle_model/whistle.cact.bak
"$ADB" -s $D shell run-as com.sovereigntagger rm  files/whistle_model/whistle.cact
"$ADB" -s $D shell run-as com.sovereigntagger chmod 500 files/whistle_model
"$ADB" -s $D shell am force-stop com.sovereigntagger
"$ADB" -s $D shell am start -n com.sovereigntagger/.MainActivity

# Break Whisper as well (for criterion #5)
"$ADB" -s $D shell run-as com.sovereigntagger cp files/whisper_model/ggml-base.en.bin files/whisper_model/ggml-base.en.bin.bak
"$ADB" -s $D shell run-as com.sovereigntagger rm  files/whisper_model/ggml-base.en.bin
"$ADB" -s $D shell run-as com.sovereigntagger chmod 500 files/whisper_model
"$ADB" -s $D shell am force-stop com.sovereigntagger
"$ADB" -s $D shell am start -n com.sovereigntagger/.MainActivity

# RESTORE afterwards (always — the device must be left clean)
"$ADB" -s $D shell run-as com.sovereigntagger chmod 700 files/whistle_model
"$ADB" -s $D shell run-as com.sovereigntagger cp files/whistle_model/whistle.cact.bak files/whistle_model/whistle.cact
"$ADB" -s $D shell run-as com.sovereigntagger rm  files/whistle_model/whistle.cact.bak
"$ADB" -s $D shell run-as com.sovereigntagger chmod 700 files/whisper_model
"$ADB" -s $D shell run-as com.sovereigntagger cp files/whisper_model/ggml-base.en.bin.bak files/whisper_model/ggml-base.en.bin
"$ADB" -s $D shell run-as com.sovereigntagger rm  files/whisper_model/ggml-base.en.bin.bak
"$ADB" -s $D shell run-as com.sovereigntagger toybox sha256sum files/whistle_model/whistle.cact files/whisper_model/ggml-base.en.bin
# expect b6e02f04...  and  a03779c8...
```

The Ghost panel is toggled by the sparkle icon at approximately `(590, 111)`; panel state is
observable without vision via the pref:
`run-as com.sovereigntagger cat shared_prefs/FlutterSharedPreferences.xml | grep ghost_visible`.

### 6.2 Evidence already captured (reuse, do not re-run)

- Whistle transcript, `HEARD: Forge workbench playlist Equalizer Ghost`
- Fallback trigger, status `TRANSCRIBING WITH WHISPER...` (unique to `speech_fallback.dart:54`)
- Fallback transcript, `HEARD: forge workbench. playlist equalizer ghost.`
- Cancel result, status `CANCELED`, no transcript published, no leftover files
- Post-restart Whistle transcript, `Forge Workbench playlist Equalizer Ghost`
- Recording events via `adb shell dumpsys audio | grep -E "rec (update|stop)"`
- `WhistleJNI: needle_load returned 0 for .../whistle.cact (size 16919407)`

## 7. After voice is green — next P1 gates

1. **Transactional updater rollback** (PR #82). Constraint from the operator: keep the 15
   drafts open, no merges, and **avoid destructive updater tests against the installed runtime.**
2. **Sustained playback / audio focus.**
3. **Metadata duplication (TDRC) investigation.** The operator's correction, verbatim in
   substance: a `TDRC` frame appearing first in an ID3v2.4 tag is NOT evidence of duplication
   — `TDRC` is a legitimate recording-time frame. A defect requires comparing source vs
   Workbench output and demonstrating multiple `TDRC` frames, corrupted values, or an
   unintended change in recording date. Treat it as an unproven hypothesis until then.

## 8. Working notes / pitfalls hit this session

- **Vision service throttles hard** (`Error code: 429`) and one call took 420s to fail.
  Budget for it; prefer source grep, `dumpsys`, pref files and logcat. `uiautomator dump`
  is unreliable on this app ("could not get idle state" — Flutter semantics off).
- **FFmpegKit does not log to logcat in this build.** `ffmpeg_kit_extended_flutter` is an FFI
  package; no `FFmpegKit` tag appears even during real sessions. Do not treat the absence of
  FFmpegKit logs as absence of FFmpeg work — use the UI status strings and output artifacts.
- **The Ghost panel's mic button** is at approximately `(520, 1050)` in the panel, but the
  panel shifts with content. Blind coordinate tapping is unreliable; hand the device to the
  user with explicit steps rather than probing.
- **The app process can be killed (signal 9) mid-test** if the user presses Home/Back. Keep
  the app foregrounded and say so in the instructions.
- **`python -c "import PIL"` is blocked by user consent — do not retry.**
- `gh` needs `export PATH="/c/Program Files/Git/cmd:$PATH"` before it resolves on this host.
- MediaStore baseline on the Moto G: **2548** audio rows after cleanup.
- Keystore vault: `shared_prefs/sovereign_credentials_v1.xml` holds `acr_key`, `acr_secret`,
  `genius_key`, `hf_token`. The `hf_token` currently holds the disposable test value
  `SOVTESTHF0001` (authorized for clearing; the real ACR/Genius credentials must be untouched).
