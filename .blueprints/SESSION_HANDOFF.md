# SESSION_HANDOFF.md — Sovereign Tagger v2
> Read this FIRST every session. Updated Phase 28 complete + tooling hardening 2026-10-01.

## DOCUMENT MAP — cold-start hooks (read top-to-bottom)

| # | File | Holds | When to read |
|---|------|-------|--------------|
| 0 | `AGENTS.md` (root) | Auto-injected into every session by opencode — the true guaranteed entry point; compact ramping guide + laws table | automatic |
| 1 | `.blueprints/RULES.md` | **CANONICAL** operating law: read-only paths, git discipline, §3 technical laws incl. **§3.1 POWERSHELL MOJIBAKE BAN** | EVERY session, before any edit |
| 2 | THIS FILE | Latest session deltas ("What shipped"), Next actions queue, Open decisions, toolchain notes | EVERY session |
| 3 | `.blueprints/CURRENT_STATE.md` | Verified per-file architecture map (44 Dart files), known-issue registry (`K/A/V/GH/CS/EQ/PW/AR/FX/UI` rows — check before touching grabber/pipeline/workbench/player/ghost/settings), frozen-ceiling toolchain notes | before writing code |
| 4 | `.blueprints/ROADMAP.md` | Phase tracker (Phases 0–28, `[x]/[~]/[ ]/[-]`) with per-phase verification gates | when planning/phases |
| 5 | `.blueprints/BLUEPRINTS.md` | Design specs + **append-only GOTCHA REGISTRY** (SPEC-S* ids) | before novel features |
| 6 | `.blueprints/ARCHITECTURE.md` | Boot flow + data-flow reference diagrams | structural changes |
| — | `README.md` (root) | Operator-facing capabilities/API-keys/maintenance docs (kept synced with reality) | release/closeout/doc work |
| — | `pubspec.yaml`, `android/app/build.gradle`, `gradle.properties` | **Executable truth**: frozen dep ceiling pins, `SOVEREIGN_TAGGER.apk` name, debug-signing fallback, chaquopy/python version, builtInKotlin opt-out | any dependency/signing/build question |

Conflict law: RULES.md > other docs; executable files > prose.
Session-end law: update rows 2–4 every session (+ row 5 when a new gotcha is learned).

## Where we are

**Date:** 2026-10-02
**Phase:** 0–28 COMPLETE. `flutter analyze --no-pub` → `No issues found!` (Flutter 3.47.5). **No planned implementation work remains** — every ROADMAP phase 0–28 is `[x]`, and as of the 2026-10-02 audit pass every registry row is FIXED/IMPLEMENTED. The open items are device-gated: smoke 1, 1b–1h. See Next actions.
**Last operator device pass (2026-10-02):** both previously-open verification items **PASS** — crossfade exercised at > 0 (fade audible and continuous, so the `0.0 → 0.05` mute-floor fix is hardware-verified, closing the last "safe by construction" caveat), and the Ghost UI behaving as expected. The operator then ran the **scripted per-defect checklist** and confirmed **GH23–GH27 individually**: GH23 no longer says "No match" for `"the beatles"` (it searches the library), GH24 no longer just reports the loaded track (it acts on the request), GH25 pauses, GH26 "play all my library tracks" loads and plays the full library shuffled, GH27 a fresh download is found and played immediately. That is five per-defect confirmations, not a surface-wide impression.
**Branch:** `main` is the single canonical branch and the only local or remote branch. 2026-10-01: `master`, `backup-before-main-sync` (local) and `claude/strange-lewin-97ba5a` / `claude/elegant-franklin-j99jl0` (remote) were **deleted** after verifying every one of them was fully merged into `main`. They no longer exist — do not reference them. Work on `main` (or a short-lived branch off it).

## GH29 closed by measurement — tag commits are provably lossless for all 11 extensions (2026-10-02)

Answering "can you actually close the last one?" — **yes**, without UI taps and without a test suite. The trick: run **the app's exact shipping jar** off-device. `android/app/build.gradle:116` pins `net.jthink:jaudiotagger:3.0.1` and it is the only version in the Gradle cache, so a JVM probe exercises literally the same code that ships.

Method: build 44.1 kHz / 16-bit / stereo WAV + AIFF carrying a deterministic multi-harmonic signal, record the audio-payload SHA-256, then run `AudioFileIO.read → getTagOrCreateAndSetDefault → setField → commit()` with `TagOptionSingleton.setAndroid(true)` — the identical sequence to `Id3Tagger.writeTags` — and re-hash.

| Format | Commit | Bytes | Payload SHA-256 before → after | Verdict |
|--------|--------|-------|------------------------------|---------|
| wav | OK | 352844 → 352970 | `ab1952f6…` → `ab1952f6…` **identical** | **LOSSLESS, proven** |
| aiff | OK | 352854 → 352968 | `ab1952f6…` → `ab1952f6…` **identical** | **LOSSLESS, proven** |
| dsf | OK | 705692 → 705898 | `6b187373…` → `6b187373…` **identical** | **LOSSLESS, proven** |

On commit, jaudiotagger **appends** metadata and rewrites no audio. In WAV, `fmt` stays at offset 12 and `data` at offset 36 with an identical size, with a `LIST` chunk added at the end; in AIFF an `ID3 ` chunk is appended. DSF needed a spec-valid synthesised fixture (a PCM generator cannot emit 1-bit DSD): a 28-byte `DSD ` header, a 52-byte `fmt ` chunk declaring DSD-raw / 2ch / 2822400 Hz / 1 bit, and a `data` chunk of 705600 deterministic DSD bytes. jaudiotagger read it first try and every stream number was identical afterwards. DSF stores metadata differently but equivalently harmlessly — no nested `ID3 ` chunk, instead the header's metadata pointer at `20:28` is repointed at a bare 206-byte ID3v2 tag appended *after* the DSD data, leaving `data` at offset 80 byte-identical. Channels/rate/bits/frames unchanged in all three. Same class of change as an mp3 ID3 commit: a metadata edit, never a re-encode. The lossless law holds for every format in `writableExtensions`.

**Three method traps, all of which bit me and are recorded so they are not repeated.** (1) The first AIFF run failed with `CannotReadException…Size:0` and it was **my generator's bug** (SSND size omitted its 8-byte `soundOffset`+`blockSize`), not a jaudiotagger limitation — had I stopped there I would have reported "AIFF tagging is broken" and been wrong. (2) My chunk-walking hasher then returned a false `payload=None` on the DSF, because **DSF declares chunk sizes inclusive of the 12-byte chunk header while RIFF/IFF do not**; a parser that mis-walks is indistinguishable from one that found nothing, so the payload hash is always cross-checked against the generator's own baseline. (3) The probe wouldn't compile against the very jar the app uses, which briefly looked like version skew — actually Kotlin's synthetic property access (`.tagOrCreateAndSetDefault` → `getTagOrCreateAndSetDefault()`). **A single failing probe is not evidence.**

No code change was needed, and none was made. The probe stayed in `%TEMP%\opencode` — no framework, no committed fixtures, per the zero-test-suite directive; the recipe is recorded in `CURRENT_STATE.md` so it can be re-run.

**The known-issue registry now has zero open defects.

## GH29 coverage extended to ALL ELEVEN writable extensions (2026-10-02)

The previous GH29 entry generalised from **three** containers to the whole app. That was a real flaw: `TagIO.writableExtensions` (`lib/core/tag_io.dart:13`) lists **eleven** extensions across **eight** jaudiotagger writer classes, and eight of them — MP3, MP4, Ogg, FLAC, ASF — had never been measured. A conclusion drawn from three samples was presented as if it covered eleven.

Two facts were established before writing a single fixture:

1. **The contract is sound.** Reflecting over `AudioFileIO.getDefaultAudioFileIO()` dumped the live `readers` (17) and `writers` (14) maps. Every one of the eleven declared extensions has a writer, so `canWrite()` never promises a container `write()` would refuse: `aif/aifc/aiff→AiffFileWriter`, `dsf→DsfFileWriter`, `flac→FlacFileWriter`, `m4a/m4b/m4p/mp4→Mp4FileWriter`, `mp3→MP3FileWriter`, `oga/ogg→OggFileWriter`, `wav→WavFileWriter`, `wma→AsfFileWriter`.
2. **Two of them are the dangerous ones.** `AsfFileWriter.writeTag` takes two `RandomAccessFile`s and rebuilds the file instead of patching in place, and `Mp4FileWriter` must relocate `mdat` when `moov` grows around it. Those are exactly where a payload could shift, so they got the closest attention.

No ffmpeg on this machine, so every fixture was synthesised byte-by-byte from its spec, and **each generator also emitted the exact audio bytes it embedded as a sidecar**. Verification used a *separate* re-implementation that re-walks the committed file structurally — if the writer moves boxes, that walk still finds the audio by shape. A parser that mis-walks is indistinguishable from one that finds nothing, so cross-checking two independent implementations is the only way the result means anything.

Final sweep, all eleven, `COMMIT_OK`, payload byte-identical and stream fields identical in every case:

```
ext    commit      pre_len   post_len  payload  stream
mp3    COMMIT_OK   16680     16680     SAME     SAME
m4a    COMMIT_OK   10240     10240     SAME     SAME
m4b    COMMIT_OK   10240     10240     SAME     SAME
mp4    COMMIT_OK   10240     10240     SAME     SAME
flac   COMMIT_OK   16394     16394     SAME     SAME
ogg    COMMIT_OK   1024      1024      SAME     SAME
wav    COMMIT_OK   352800    352800    SAME     SAME
aif    COMMIT_OK   352800    352800    SAME     SAME
aiff   COMMIT_OK   352800    352800    SAME     SAME
wma    COMMIT_OK   4096      4096      SAME     SAME
dsf    COMMIT_OK   705600    705600    SAME     SAME
```

A useful cross-check fell out of this: `wav`, `aif` and `aiff` independently reproduced `ab1952f6…b1b4bc` and `dsf` reproduced `6b187373…65f1104c` — the same payload hashes established in an earlier session by a *different* implementation. Two unrelated implementations, written days apart, agreeing byte-for-byte.

### Fixtures cost real debugging — every failure below was mine, not jaudiotagger's

- **FLAC STREAMINFO** packed 20/3/5/36 bits by hand and came out as `channels=3 rate=2756 bits=2`. Those fields are exactly one 64-bit word (`rate<<44 | (ch-1)<<41 | (bps-1)<<36 | total`); arithmetic shifts on bytes are not bitfields.
- **MP4 `mp4a`** was emitted 30 bytes long. `AudioSampleEntry` is exactly 28 (6 reserved + 2 dri + 8 reserved + 2×4 + 4 samplerate). Two stray bytes desynchronised the atom walk and surfaced as the useless `Unable to find next atom because identifier is invalid  #es`.
- **MP4 `stco`** was patched by rebuilding the box, which changed `moov`'s size and invalidated the offset it was meant to store. It now writes a placeholder and patches the value in place, with an assert on the 28-byte sample entry.
- **Ogg pages** were missing the `OggS` magic and version byte entirely, with the CRC at offset 18 instead of 22.
- **Ogg identification header**: "fixing" the framing bit by merging it into the blocksizes byte dropped the packet to 29 bytes, which jaudiotagger reported as `ArrayIndexOutOfBoundsException: Index 29 out of bounds for length 29`. The blocksizes byte and the framing bit are **separate** bytes; the packet is 30.
- **ASF header** originally used a 2-byte object count. `AsfHeaderReader.createContainer` (confirmed by reading its bytecode) reads a **UINT32** count and then demands the two reserved bytes be exactly `0x01` and `0x02` — hence the otherwise baffling `IOException: No ASF`.
- **ASF** then needed a **Header Extension Object**; `AsfFileReader` dereferences `header.getExtendedHeader()` unconditionally and NPEs without one. Every real WMA file has one.
- **DSF extraction** assumed `fmt ` sat at offset 12. It sits at **28**, after the 28-byte DSD header, and its size field (52) is inclusive of the 12-byte chunk header — so `data` begins at 80 and its payload at 92.

Two of the verifiers were also wrong before the fixtures were, which is worth recording: the drift check compared strings that still carried their `BEFORE `/`AFTER ` labels (so it reported drift on files whose fields were identical), and its regex `channels=(\S+) rate=` could not match MP3's two-word channel mode `Joint Stereo`. Both were fixed and re-run rather than explained away — a checker that cries wolf is worse than no checker.

The lesson generalises past GH29: **a sample is not a surface.** Three containers agreed, which made the claim feel safe, but the untested five included the two writers most likely to move bytes. Anything phrased as "X is fine" needs the denominator attached — how many of the declared cases were actually exercised.

## Voice input for the Ghost + Whistle reconnaissance (2026-10-02)

Operator asked to look at `C:\Call-Dad` for its "uses whisper" feature and replicate it as an optional button beside a send button. Two of the three premises did not survive inspection, and finding that out early is the whole value of having read the repo:

- **Call-Dad does not use Whisper.** It uses Android's built-in `createOnDeviceSpeechRecognizer` (API 31+). No whisper.cpp, no `jniLibs`, no `externalNativeBuild`, no `ndkVersion`, no `.bin`/`.tflite`/`.onnx` anywhere under `app/`. Verified in both gradle files, `gradle/libs.versions.toml`, and a file-glob.
- **It has no mic beside Send.** The composer is `Row { OutlinedTextField(weight 1f), IconButton(Send) }` and is *deliberately* mic-free (`docs/kid-safe-ux.md`: "a 6-year-old cannot dictate at this age"). Its mic is a full-screen "Tap to Speak" circle.
- **Its transcript goes nowhere useful.** `onResults` feeds `KeywordBot` then TTS; `lastHeard`/`lastSpoken` are write-only state (5 hits, all inside the ViewModel); `onPartialResults` is an empty no-op. There is no path from a recognized string into a text field.
- Worth stealing: it requests `RECORD_AUDIO` **on the press**, and the grant callback starts listening, so there is no second tap. Its network-recognizer refusal is pinned by a regression test after it once uploaded a child's speech off-device.

**"Whistle" is real** — Cactus Compute, released 2026-10-02. A 16.9 MB single `whistle.cact`, CPU-only, no GPU, prebuilt binaries for 17 targets including Android, word timestamps + keyword biasing, 7 languages. Roughly 9× smaller than Whisper base (145.3 MB) and ahead of it on several benchmarks. (There is an unrelated 2024 academic paper of the same name — ignore it.) Latency figures are M4 Pro vendor claims, not a mobile SLA.

**Why it is registered but NOT wired:** consuming Whistle means NDK + CMake + JNI to `needle_load`/`needle_transcribe` plus a new model. This project has **zero native integration today** — a new toolchain surface on a repo with hard APK-size and dependency ceilings, for a model one day old. The operator chose *"both behind one interface"*, so `SpeechEngine` exists with two implementations and the Whisper one is live.

**What actually shipped** is the feature, on the engine the app already had — `PcmRecorderBridge` + the FFmpeg `whisper` filter + `WhisperModel.ensure()`. Zero new dependencies, zero APK growth. Transcript fills the field and waits for confirmation; it does **not** auto-send, because the Ghost can play and delete real media. Capture is 16 kHz mono so a later Whistle swap needs no capture change. Full detail in `CURRENT_STATE.md` → "Voice input (Ghost)".

## GH30 — the app was hijacking the device's rotation setting (2026-10-02)

Operator: *"the auto-rotate quick tile always gets activated although I don't want the feature activated at all on my device."*

Cause was `tab_player.dart` `_FullScreenVideoScreenState`, and it had **two** halves:

1. `initState` force-locked orientation based on aspect ratio.
2. `dispose` then called `setPreferredOrientations([all four])` — writing a *fresh* orientation preference back to the system on every exit, even when nothing had been locked. That lands as `SCREEN_ORIENTATION_FULL_USER` on Android and is what flips the auto-rotate tile on.

Nothing in Kotlin or the manifest touches orientation; this was the only source.

### My first fix was wrong, and the operator caught it

I made it **opt-in, default off** (`RotationSettings.lockFullscreenVideo` + a settings switch), and I wrote "no code path exists that can touch the rotation preference". That claim was true of the *default* state and useless in practice: the moment the toggle is touched, the original bug is back, and the operator is explicitly someone who does not want the feature at all. The operator tested it and replied **"it still activates the 'auto-rotate' quick tile."**

The mistake was treating "off by default" as equivalent to "gone". For a capability the operator has refused outright, the only honest fix is to **delete the capability**, not ship it behind a switch that must never be flipped. A disabled landmine is still a landmine.

The orientation code is now **removed outright**. `rotation_settings.dart` deleted, the settings switch deleted, the `main.dart` load deleted. Verified mechanically rather than by assertion — `setPreferredOrientations`, `requestedOrientation`, `setRequestedOrientation`, `screenOrientation` and `RotationSettings` all return **zero hits** across `lib/`, and `screenOrientation` returns zero hits across `android/` including the manifest and Kotlin.

Fullscreen video still goes immersive (`setEnabledSystemUIMode`), which is a system-bar change and cannot touch rotation. Orientation is now governed solely by the device's own setting.

### Round 3 — the actual root cause (and two wrong answers first)

Opt-in was wrong, and so was deletion. Both were reported back as still-broken, correctly. Only the third attempt found it, and it was not in our Dart at all.

**What I measured, in order:**

1. `grep` for every orientation API across `lib/` and `android/` → after round 2, **zero** hits. `setPreferredOrientations` confirmed **absent from the compiled `libapp.so`**, so it was genuinely not shipping.
2. Merged manifest (not the source manifest — dependencies contribute there) → **no `screenOrientation`** on the activity. It was `unspecified`, i.e. **rotatable**.
3. Read `MainActivity.kt` end to end → no orientation, no `Settings.System` writes.
4. Controlled experiment on the Moto G (`moto g - 2025`, Android 16 / SDK 36):
   - app **force-stopped**, rotation forced to `0`, 20s idle → stays `0`
   - **launch** app, 25s → **`1`**
   - uninstall → `0`; install **without launching** → stays **`0`**; launch → **`1`**

So: **install does not cause it, launching does**, and nothing in our code requests orientation. The remaining variable is that the activity was declared **rotatable**. On Android 16 that is enough to engage the auto-rotate quick tile.

**Fix: `android:screenOrientation="locked"`** (`SCREEN_ORIENTATION_LOCKED`) on `MainActivity`, confirmed present in the merged manifest. The activity pins itself to whatever orientation the device is in at launch, never asks the system to rotate, and never writes `ACCELEROMETER_ROTATION`. Combined with round 2 (all orientation code deleted), the app now has **no** mechanism to touch rotation by any route.

**Device confirmation is still outstanding** — adbd stopped listening partway through (`192.168.5.21` answers ICMP but refuses 5555/39313/5037), so the last install-and-measure did not run. Do not record GH30 as verified until `accelerometer_rotation` is still `0` after a launch on the `locked` build.

### The lesson, twice over

Round 1 I asserted "FIXED" from a code-reading argument with zero device evidence, on a device that was **reachable at that moment**. Round 2 I asserted "FIXED" again from a mechanical grep. Both were wrong, and both would have shipped as confident lies. Measuring took four experiments and found in ninety seconds what two rounds of reasoning missed — and the answer was in a file I had never opened (`AndroidManifest.xml`, then `MainActivity.kt`), not in the Dart I had been staring at. **When a symptom survives a fix, the fix is wrong; stop defending it and go measure.**

## Audit of the voice feature I had written but never reviewed (2026-10-02, same session)

I wrote ~450 lines of new code and then ran only the analyzer. The analyzer is blind to almost every bug class that matters here, so the "Next Move" review I had listed was still outstanding and I did it before anything else. **It was not a formality — it found real defects, including two that would have shipped as user-visible failures.**

Ordered by severity:

1. **The mic leaked if the Ghost was closed mid-recording.** `VoiceInput.dispose()` cancelled the timer but never stopped `PcmRecorder`. Since `PcmRecorder` is a **global singleton channel**, that left the microphone hot *and* made the Workbench's recorder fail forever after with "the other recorder is busy". Both `dispose()` and the overlay's `dispose()` now stop the recorder and delete the WAV.
2. **`cancel()` was dead code.** The mic button was `onPressed: null` while busy, so a user watching a 141 MB first-run download had **no way out** — minutes of an uninterruptible spinner. The button is now always live: listening → stop and transcribe, preparing/transcribing → cancel. Cancel sets a flag that is re-checked after every `await`, so a late-arriving transcript is discarded instead of filling the field after the user gave up.
3. **Silence could produce a confident hallucination.** Whisper reliably emits "Thank you." / "Thanks for watching!" / "Subtitles by the Amara.org community" on near-silence. On a surface whose commands **play and delete real media**, that is the worst possible failure mode, and a length check would not catch it. Added an exact-match blocklist (`isLikelyHallucination`), normalised for case and punctuation, applied in both the engine and the input layer → surfaced as "DID NOT CATCH ANY WORDS."
4. **Notify-after-dispose.** In-flight async work called `notifyListeners()` with no disposed guard — a live crash class, since `dispose()` does not cancel futures. Added `_disposed` and routed every notification through `_safeNotify()`.
5. **Temp-file leak on a failed arm.** `PcmRecorder.start()` returning false left a zero-length WAV in the cache dir forever. Now deleted.
6. **Permanently-denied mic was a dead end.** `request()` returns `permanentlyDenied` and the old code just said "MIC ACCESS DENIED", leaving the user no route to fix it. Now detected, and tapping the mic again opens app settings.
7. **`useEngine` could swap engines mid-transcription**, feeding a WAV captured for one engine into another. Now a no-op while busy.
8. **My own rewrite introduced a cleanup ordering bug** — `finally` nulled `_pendingPath` *before* the `?? _pendingPath` read it, so the WAV would never be deleted. Caught on re-read. Worth recording because it is exactly the class of bug I was auditing for, introduced while fixing it.
9. `destination=` was unquoted in the filter graph; a colon in the path is FFmpeg's option separator, so it is now single-quoted. `-i` was already quoted, which is why this hid.
10. `srtToPlainText` dropped **every** all-digits line as a cue index — so a spoken "1984" or "2026" vanished. Now a numeric line is only skipped when the next non-empty line is a timing line.
11. `minBytes = 16000` was 0.5s of audio (16 kHz × 16-bit mono = 32000 B/s), an unexplained magic number. Now `minBytesForOneSecond` derived from `bytesPerSecond`.
12. `SpeechEngineNotWired` threw **synchronously** across an interface declared `Future`-returning. Harmless where it was called, a latent trap for the next caller. Both methods now `async`.

Lesson: **"it analyzes clean" is not a review.** Twelve defects, none of which the analyzer, the build, or a green `diff --check` could see. Every one needed someone to read the code and ask "what happens if the user changes their mind halfway through?"

- **GH29 (11/11 containers), GH23–GH27 (per-defect), crossfade: device-verified.** Analyzed, built, installed, boot-smoked, plus operator checks.
- **Voice input + GH30 rotation: `analyze` clean, release build green (488.6MB), but NOT device-verified.** The Moto G's wireless adb pairing collapsed mid-session — the daemon restarts between commands and `adb mdns services` comes back empty, so the device never reappeared. Neither change has been on hardware.
- Confirmed clean and worth stating: the release APK was **not** installed on `B160V` (`pm list packages` has no `com.sovereigntagger`, `pm path` empty). One install attempt failed with "device offline" while the daemon was flapping; checked explicitly afterwards because that device is off-limits.

Next session, in order: (1) get the Moto G back on adb, (2) install, (3) confirm the auto-rotate tile **stays off** after using fullscreen video, (4) smoke the mic button end-to-end including the 141MB first-run model download, (5) then commit.**

## Ghost GH23–GH27 re-verified statically (2026-10-02)

The one previously "blocked" item was exact Ghost-phrase smoke, which is unreachable because `uiautomator` cannot see Flutter semantics. Rather than leave it blocked, all five fixes were re-read in source and confirmed present and correct:

- **GH23** `lead` (ghost_brain.dart:614) now contains `'the'` and `'my'`, and the strip loop at :617 consumes them, so `play the beatles` reduces to `[beatles]`.
- **GH24** `playVerb` is hoisted to :458, above the now-playing phrase test at :460, and gates it — a play/queue/shuffle verb always wins.
- **GH25** `gateFiller` (:524) / `cmdWords` (:525) widen the gate without touching inner matching semantics.
- **GH26** the `all`/`them`/`both` hijack at :371 requires `words.length <= 3`, so `play all my library tracks` (5 words) falls through to normal dispatch while a bare `all` still resolves the prompt.
- **GH27** `StorageClient.libraryRevision` (storage_client.dart:36) + `bumpLibrary()` (:38) is fired from pipeline:297, forge:714 and storage_client:93/107/113, and ghost_world.dart:109 bumps the generation on change.

Code + clean boot build is the honest ceiling here; no further static evidence exists without a device operator.

## Full-gamut verification at HEAD (2026-10-02)

Whole sweep re-run end to end, not just the changed code:

1. **Mojibake signature grep** over the repo: **10 hits, all in documentation that deliberately quotes the signature** (`AGENTS.md`, `RULES.md`, `CLAUDE.md`, `BLUEPRINTS.md`, `CURRENT_STATE.md`, `SESSION_HANDOFF.md`, `.opencode/agents/sovereign-docs.md`). **Zero hits in `lib/**`, `android/**`, `shaders/**`.** Worth noting the trap this session: `rg` is **not installed** on this box, so a shell mojibake check silently produces a *false clean* — it never ran. That check must go through the encoding-correct grep tool (G42 / VS7). A "clean" result from a command that did not execute is worse than no result.
2. **`flutter analyze --no-pub`** → `No issues found!`
3. **`flutter build apk --release`** → success, `488.6MB`, 126.5s. Only the two known-benign warnings (three plugins applying KGP ahead of Flutter's built-in Kotlin migration; SDK XML v4 vs the older reader).
4. **Installed to the Moto G only** (`ZT4222BMWN`). `B160V` untouched, as always.
5. **Boot smoke, clean logcat, 32M buffer:**

```
I/flutter: BOOT: FFmpeg armed: 534 filters registered (full+gpl)
I/flutter: BOOT: WHISPER SURFACE: DETECTED in registered filters — wire transcribe op
I/flutter: SOVEREIGN FX: prefs eqEnabled=true crossfade=0.0 rgMode=track
I/flutter: SOVEREIGN PLAYBACK: processingState -> ProcessingState.idle (idx=null playing=false volume=1.0)
I/flutter: SOVEREIGN PLAYBACK: audio handler ready
I/flutter: Using the Impeller rendering backend (Vulkan).
```

`audio_service` lockscreen session registers as `com.sovereigntagger/media-session/85` with `error=null`. **Zero** `E/flutter`, `F/flutter`, `FATAL EXCEPTION`, `Unhandled Exception` or `ANR`.

Two things that look like findings but are not:

- The `E/sovereigntagger` lines in the raw log (`Invalid base format! req_base_format = 0x0`, `Failed to query component interface`, `perfctl`) are **Android graphics/perfctl noise tagged with the app's PID**, not Dart errors. No Dart-side error line exists anywhere in the buffer.
- The `AndroidRuntime` lines are **monkey's own** launcher process (`VM exiting with result code 0`), not the app.

The GPU shader is confirmed live by *absence* of a failure: `cyber_backdrop.dart` only ever logs on the error paths (`:38` load failure, `:66` `fragmentShader()` failure). Neither `BACKDROP:` marker appears, so `FragmentProgram.fromAsset('shaders/backdrop.frag')` succeeded and the GPU backdrop is painting rather than falling back.

**Crossfade caveat — CLOSED 2026-10-02 by operator.** This previously read: *"`crossfade=0.0` on device, so the 0.05 crossfade floor is still not runtime-exercised. It is a safe-by-construction change (it can only make fades shorter than total silence) but it is unproven on hardware."* The operator set crossfade > 0 and exercised it on the Moto G: **PASS** — fade audible and continuous, no silence gap. That was the last thing keeping the audio fix at "safe by construction"; it is now hardware-verified.

**Ghost UI — operator PASS, with an honest note on its strength.** The operator exercised the Ghost on device and reported everything working "as expected". This closes the operator-only blocker on GH23–GH27, but it is worth being precise about what kind of evidence it is: the operator had **not** been given the per-defect checklist, so this is a *"nothing is visibly broken"* pass across the Ghost surface — **not** five individual confirmations against their exact repros.

Both are legitimate closes, and neither involved a code change. The distinction is recorded so a future session does not read "Ghost verified" as "each of GH23–GH27 was confirmed against its repro". If anyone wants the stronger claim, the script is in `CURRENT_STATE.md` and takes about a minute:

```
GH23  play the beatles                    -> must not say "No match" for "the beatles"
GH24  play what is this                   -> must not just report the loaded track
GH25  please pause the song now           -> must pause, not fall through to a knowledge entry
      go to the next song                 -> must advance
GH26  (with a disambiguation prompt open) play all my library tracks
                                           -> must play the library, not the pending candidates
GH27  download a track, ask about it immediately
                                           -> must find it at once, no 2-minute "No match"
```

## Operator feedback round 3 — the six deferred Ghost items, now closed (2026-10-02)

Operator confirmed the Ghost settings toggles **flip when tapped** (GH22 verified), completing the round-2 fix. Forge round-trip verification also confirmed on device.

With the device live I went back and fixed the six defects that had been deliberately left recorded rather than changed, since "can't test it" was no longer true:

- **GH23** — `lead` had `some`/`a`/`an` but not `the`/`my`, so `play the beatles` searched the literal `"the beatles"`. Added both.
- **GH24** — `play what is this` matched the now-playing phrase list *before* `_playSomething`, so the Ghost reported the loaded track instead of playing the request. Hoisted `playVerb` above the phrase test and gated the branch on `!playVerb`.
- **GH25** — `words.length <= 3` dropped `please pause the song now` and `go to the next song` into a random knowledge entry. The gate now counts politeness filler stripped. **Matching semantics deliberately unchanged** — only the gate widened, so `repeat one` still resolves as before.
- **GH26** — a pending disambiguation prompt hijacked `play all my library tracks`. The `all`/`them`/`both` hijack now requires a short query, so a bare `all` still resolves the prompt but a real command does not.
- **GH27** — a just-downloaded song read as "No match" for up to 2 minutes. The cache now tracks a generation counter bumped by `StorageClient.libraryRevision`, so `bumpLibrary()` invalidates it on every download/export/overwrite. Generation counter rather than a per-instance listener, so recreating the overlay cannot leak listeners.
- **GH28** — **audit false positive, corrected not "fixed".** The claim that `more` never returns chips was wrong: `_continueEntry` does return them on the terminal path. The audit quoted that line with the chips omitted. No code changed.

**GH29 — was left open here, now CLOSED BY MEASUREMENT.** This entry previously read "`wav`/`aif`/`aiff`/`dsf` … very likely compliant, but it is **unverified**". That is superseded. It was also **wrong about scope**: it named four extensions when the app declares eleven, and the untested remainder included the two writers most likely to move bytes (`AsfFileWriter` rewrites the whole file; `Mp4FileWriter` relocates `mdat`). All eleven are now measured — see "GH29 coverage extended to ALL ELEVEN writable extensions" above. Tag commits are byte-for-byte lossless across the entire declared surface, so the lossless law holds without qualification and no extension needed removing.

## Operator feedback round 2 — Ghost settings toggles were dead controls (2026-10-02)

Operator confirmed **Forge round-trip verified** ("Round-Trip Verified On Final File"), so FG2/FG3/FG4's stage→verify→release reorder works end-to-end on real hardware.

Then reported: **tapping the Ghost chatbot settings toggles does not flip them.** Cause: all three `SwitchListTile`s read `GhostSettings.<x>.value` **directly** in `build` with no `ValueListenableBuilder` — the tap fired, the notifier updated, the handler ran, and nothing rebuilt the tile, so the switch snapped back. Invisible to every automated check because nothing throws and nothing logs. Fixed by wrapping all three, matching the FeedbackSettings toggles in the same file. A repo-wide sweep confirmed these were the only three (Workbench switches and review-sheet checkboxes use local `setState` and are fine). Also gave `GhostSettings` one `_persist` helper that logs a failed write instead of silently reverting next launch.

**Toolchain correction worth keeping (G42):** while checking this, a PowerShell text read of `tab_workbench.dart:928` displayed a clean em-dash as `�?"` — indistinguishable from real corruption. Verified with a UTF-8-safe read: the file is fine. A repo-wide scan using the **encoding-correct grep tool** over `lib/**` returns **zero** hits. **Never run the mojibake check through PowerShell** — it fabricates the very corruption signature RULES §3.1 warns about, and chasing it would mean "fixing" clean files.

## Device verification of the audited build — Moto G, 2026-10-02

`5594935` installed on the Moto G (Android 16). Boot is clean: **0 `E/flutter`, 0 `FATAL`, 0 `Unhandled Exception`.**

The two things that were previously "should work, unproven" are now **proven**:
- **DG1** — `BOOT: FFmpeg armed: 534 filters registered (full+gpl)` and `BOOT: WHISPER SURFACE: DETECTED in registered filters` both print. Those lines were previously unreachable behind a dead `catch (_) {}`.
- **AN2** — `dumpsys audio` shows a live **`AudioTrack usage=USAGE_MEDIA content=CONTENT_TYPE_MUSIC`** for uid 10735 with audio focus **held, `loss: none`**. That is objective proof audio is routed, not just that state changed. `volume=1.0` on every logged state and `volume driven to ZERO` never appeared.

Also confirmed on-device: the shader loads (no `BACKDROP:` failure), the EQ pipeline constructs (`device EQ has 5 bands`, no fallback), and the new `_firePlay()` instrumentation reports **0** `REJECTED` / `0** `PLAYER ERROR`.

**Three device gotchas, recorded so nobody repeats them:**
1. **The keyguard silently eats media commands.** `cmd media_session dispatch play` and `KEYCODE_MEDIA_PLAY` both succeed and do nothing while the lock screen is up. Wake + swipe + `wm dismiss-keyguard` first, then confirm `topResumedActivity`.
2. **logcat rotation ate the boot lines.** A 35 s capture made 1.2 MB and the splash diagnostics were already gone; `adb logcat -G 32M` fixed it. Raise the buffer before launching and dump within ~15 s.
3. **`uiautomator dump` cannot see Flutter semantics** (362-char dump), so the UI-only paths are not host-automatable.

**Still needs operator fingers** (no host path exists): Forge `SAVE & FIX ORIGINAL` end-to-end (FG2/FG3/FG4 — the reorder). The Ghost command smoke (GH15–GH21) got a general "everything works as expected" pass from the operator, and the crossfade mute-floor fix is now **hardware-verified** (crossfade > 0 exercised, audible and continuous — that caveat is closed). What remains is the *scripted* per-defect confirmation: a broad pass cannot distinguish "GH23 is fixed" from "GH23 was never exercised". The repro list lives in `CURRENT_STATE.md`.

## What shipped — source audit of every remaining unverified area, 25 defects (2026-10-02)

The operator rejected "needs a device" as a stopping point, so the four still-unverified smoke areas were audited by reading source instead of waiting: **Forge save-back, boot diagnostics, Ghost commands, and visuals/shader/lifecycle.** **25 defects found; all critical/high ones fixed.** Full table in `CURRENT_STATE.md` under "Audit pass 2026-10-02". The four that mattered most, all of the same species — **the UI told the user a lie**:

- **FG1 (CRIT)** Forge ran a full FFmpeg `-c copy -movflags +faststart` remux of the user's m4a on *any* failed tag write, then reported "Nothing Was Saved" — after having already rewritten the container. A direct violation of the lossless law. Remux deleted; a container jaudiotagger refuses now fails honestly and the original is untouched.
- **FG2/FG3/FG4 (CRIT)** The write-back path truncated the original before confirming a single new byte, swallowed a failed rename (`ORIGINAL FIXED ✓` on a file still called `old_name.mp3`), and deleted the working copy *before* verifying anything. Reordered to stage → size-check → verify → then release, with loud `WARN:` on every silent-degradation path (G38).
- **GH15 (CRIT)** The **"RESET FIRST LAUNCH" button set the flag to `true`** — the exact opposite of a reset, with no code path able to clear it, while the snackbar announced it had reset.
- **GH17 (HIGH)** The Ghost's entire command-dispatch path had **zero exception handling**; four reachable commands hit unguarded `just_audio` calls, so a stale MediaStore path produced no reply, no error, nothing. Now speaks failures aloud and guards against double-tap.

Also fixed: `setState` called *inside* an `!mounted` branch (a guaranteed post-dispose crash on rotate), a swallowed jaudiotagger field failure that let Forge clobber originals missing COMPOSER/ENCODER/LANGUAGE, an unstaged partial-file leak on the highest-frequency temp path, a missing write-back timeout that could brick Forge unrecoverably, a failed shader load memoized forever with no log and no retry, a fallback backdrop that rebuilt a full-screen gradient 60×/s *and* re-rasters the entire tab tree, `whenCompleteOrCancel` hard-cutting rapid tab switches, and `precision mediump` making the backdrop degrade the longer the app runs (a 30-second smoke test could never have caught that one).

**Recorded but deliberately not changed** (behaviour changes in code that cannot be executed without a device): Ghost artist-search breaking on leading articles, the now-playing phrase list pre-empting song searches, a >3-word gate silently dropping padded transport commands, a disambiguation prompt hijacking later queries, and the 2-minute MediaStore cache reading a fresh download as "no match". Each is listed with its repro in `CURRENT_STATE.md`. The seventh item on that list — the unproven lossless guarantee for `wav`/`aif`/`aiff`/`dsf` — is **now measured and disproved as a risk**: all eleven writable extensions commit with byte-identical audio payloads, so it no longer belongs on a "cannot verify" list.

## What shipped — first device run of the release APK, and 3 bugs it caught (2026-10-01)

Release APK installed on the Moto G (`ZT4222BMWN`, Android 16 / SDK 36, arm64-v8a, via wireless adb — note a second USB device `B160V` is also attached; always target the Moto G serial explicitly with `adb -s`). Two devices being visible at once is a real footgun: an unscoped `adb install` could have gone to the wrong phone.

Boot was clean enough to reach the foreground, but the log revealed three genuine defects. **All three are release-only or first-run-only, so no amount of static analysis or debug-build testing would have found them.**

1. **`flutter build apk --release` was broken** — see `BLD1` / earlier entry. Fixed with `proguard-rules.pro`.
2. **GH14 — first-launch sequence crashed.** `Unhandled Exception: Null check operator used on a null value` from `State.setState` via `_typewriterSay:149` ← `_runFirstLaunchSequence:122` ← `_checkFirstLaunch:115`. Root cause was NOT the missing guard: `GhostSettings.load()` is async and was never awaited, so the overlay ran the welcome sequence off default values; when prefs finished loading and `ghost_visible` was false, MainShell removed the overlay and disposed its State mid-typewriter. Fixed with mounted guards **plus** a `GhostSettings.isReady`/`ready()` gate so the overlay waits for real prefs. Note release builds strip asserts, so `setState`-after-dispose surfaces as a bare null-check error instead of the helpful Flutter assert.
3. **AN1 — lockscreen buttons broken in release** (G35). Every MediaSession update threw `IllegalArgumentException: You must specify an icon resource id to build a CustomAction`. Wiring `proguard-android-optimize.txt` in (fix #1) enabled resource processing, which deleted the 7 `audio_service_*` icons because the plugin resolves them **by name** via `getIdentifier` — invisible to the shrinker. This one was **self-inflicted by fix #1** and only caught because the APK was actually installed. Fixed with `shrinkResources false` + `res/raw/keep.xml`.

**VERIFIED-STATIC on device (release APK, Moto G):** install succeeded; `analyze` clean; app process alive and holding window focus; **zero** `E/flutter` / unhandled exceptions; **zero** `CustomAction` errors; `MediaSessionStack` registered and `Media button session is changed to com.sovereigntagger`; no FATAL.

**Fourth defect found — and one deliberate loose end:** the user then reported the media player **accepted a track and showed state changes but produced no sound**. Both plausible causes were fixed: `PlaybackFx._fadeFactor` began a crossfade at exactly `0.0` (a full mute, contradicting its own `0.05` clamp later in the file), and release was running R8 over `com.ryanheise.**` / `androidx.media3.**` with no keep rules at all. An instrumented build was produced and installed, but **the Moto G then went over wireless-adb idle timeout before the logs could be read**, so the build could not be driven headlessly. The user retested and **audio now works**. Recorded honestly as AN2: the mute floor and the R8 keeps are sound-by-construction, but *which one* actually restored audio was never isolated. The new `SOVEREIGN PLAYBACK:` / `SOVEREIGN FX:` logcat markers are still in the build and will localise any recurrence immediately.

**Operational gotcha (cost real time this session):** the Moto G is on **wireless adb** and drops off the `adb devices` list when the screen sleeps — an `adb -s <serial> install` against a vanished serial does **not** fail fast, it blocks forever on "waiting for device" and burns the whole command timeout. Use `adb devices` first, or `adb connect`, and never issue an install against a remembered serial. The second USB device (`B160V`) is a different phone; keep targeting `ZT4222BMWN` explicitly.

**NOT verified — still needs a human on the device:** the functional smoke list. Nothing interactive was tested: Grabber download + SAVE TO MUSIC, Forge save-back over an original, EQ audibility, crossfade, art fallbacks, Ghost chat commands, tab transitions, shader rendering on the GPU path. `SovereignTagger.apk` is installed and ready for that pass. Boot diagnostics (`WHISPER SURFACE`, filter count) printed nothing to logcat in release — worth confirming they still log if you rely on them for field diagnosis.

## What shipped — release build unblocked + a real build fix (2026-10-01)

- **Operator override: `flutter build apk` is now allowed on this host** (`RULES.md` §1.5). `*build apk*` moved from `deny` to `allow` in all 11 agent permission maps; `build appbundle` / `:app:assembleRelease` / `:app:bundleRelease` stay `ask` (signing + store packaging are operator calls). All 11 agents re-verified: 46 rules, 29 denies, 28/28 command resolutions correct. Builds remain END-OF-PLAN per §1A.0.
- **Every agent cited a rule that does not exist.** All 11 permission maps said "Build boundary … (RULES.md §1.6)" — RULES.md only ever had §1.1–§1.4, §1A.0–§1A.4, §2–§4. The build boundary lived solely in AGENTS.md/CLAUDE.md/README prose. Added a real `RULES.md §1.5 Builds`, so the citation now resolves.
- **`flutter build apk --release` was completely broken and nobody knew.** Only the debug build had ever been built here, and debug skips R8. Release failed `:app:minifyReleaseWithR8`:
  - Layer 1 — `Missing class java.awt.image.BufferedImage`, `javax.imageio.ImageIO`, `javax.imageio.stream.ImageInputStream`. jaudiotagger (the `id3` backend) references desktop-Java artwork helpers. There was **no `proguard-rules.pro` in the repo at all** and the `release` buildType had no `proguardFiles` wiring.
  - Layer 2 — after fixing layer 1, R8 then failed on Flutter's Play Core deferred-component references (`SplitInstallManager` etc.). Play Core is not a dependency; Flutter's embedding still references it.
  - Fix: new `android/app/proguard-rules.pro` (verbatim R8-generated `-dontwarn`s, broad AWT/ImageIO guard, `-keep class org.jaudiotagger.**` because jaudiotagger resolves tag readers reflectively and would otherwise fail at *runtime* not build time, `-keep class com.sovereigntagger.**`, `-dontwarn com.google.android.play.core.**`) wired in via `proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'`.
  - **VERIFIED-STATIC: `√ Built build\app\outputs\flutter-apk\app-release.apk` — 487.1MB, zero R8 errors.** NOT device-tested. Registry row `BLD1`.
- **Gotcha for next time:** R8 reports missing classes ONE LAYER AT A TIME, so a release build can need several fix-build cycles. `build/app/outputs/mapping/release/missing_rules.txt` contains the exact rules R8 wants — read it instead of guessing.
- **S0–S4 SDK edition PARKED** (operator decision): spec written to `.blueprints/SDK-EDITION-SPEC.md`, `ROADMAP.md` slices all `[-]`, `BLUEPRINTS.md` SPEC-S5 added. Headline counter-argument recorded: removing Python unlocks the ceiling for the `sdk` flavour only — `full` keeps chaquopy, so you get two ceilings and a dual-maintenance obligation, not one unlocked ceiling.
- **ZERO test suite CONFIRMED** (operator decision): `ROADMAP.md` Phase 13 `[-]` PARKED. Was previously marked `[~]` in-progress, which contradicted the zero-bloat doctrine.

## What shipped — tooling + doc alignment (2026-10-01)

No app code changed. Two classes of real defect fixed, both in the rulebook rather than the app:

- **`.opencode/` was entirely untracked** — the 11-agent workflow, 3 slash commands and the `package.json` plugin pin had no version control, so no clone ever received them, and a clean-slate reset **deleted the whole rulebook** (proved by `f062e01`). All are tracked now, and `package-lock.json` is tracked too so the toolchain is reproducible.
- **Every agent's deny map was under `tools:`, not `permission:`** — `AgentConfig.tools` is `additionalProperties: {type: boolean}` and `@deprecated`, so a `{pattern: deny}` map there is malformed and enforces nothing. The fleet *looked* hardened and denied nothing. All 11 moved to `permission.bash` (45 rules, 33 denies).
- **Last-match-wins ordering bug** — the narrow denies sat *above* the broad `"git add *": ask` / `"git push*": ask` rules, which re-matched and downgraded them. `git add -A` and `git push --force` were **asked, not refused**, in all 11 agents. Narrow denies moved last. Verified by resolving 23 real commands through each parsed map (fnmatch, keep-last) — not by reading YAML. Recorded as **G34**.
- **5 of 11 agents had invalid YAML** — unquoted `description:` containing a colon, which can stop an agent loading entirely. Quoted; all 11 now parse.
- **Per-edit verification taught in 4 places** — AGENTS.md "then analyze + signature-grep", BLUEPRINTS G23 "re-run analyze after every scripted patch", SESSION_HANDOFF tooling law, and CLAUDE.md "run targeted checks on what you changed". All reworded to end-of-phase. `ROADMAP` "gate per slice" deliberately KEPT — a slice is a staged phase, not a per-edit check.
- **CLAUDE.md had no shell gate at all**; now carries the §1A.0 block.
- **Doc/code drift corrected** (docs described Phase ≤27 while the code was Phase 28): `matrix_rain.dart` → `machine_rain.dart` rename; `ghost_classifier.dart` deleted in favour of `ghost_brain.dart` + `ghost_world.dart`; `IndexedStack`/`BottomNavigationBar`/`AmbientBackdrop` → `AnimatedTabStack`/`CyberNavBar`/`CyberBackdrop`; `tap_feedback.dart` no longer plays `just_audio` data-URI wavs (it delegates to the native `SoundPool` `Sfx` bank); EQ presets entry is the **Player** AppBar tune icon, not Workbench (CS4); 44 Dart files, not 23. Historical ROADMAP/SESSION_HANDOFF phase entries were left as a changelog but now carry a note.
- Repairs: `20260803_110842.mp4` (9.5MB) was untracked **and** unignored; now ignored with `*.mov/*.apk/*.aab/keystores/screenshots` + `/.claude/worktrees/`.

Gate: `flutter analyze --no-pub` → `No issues found!`. Device smoke unchanged and still pending.

## What shipped — Phase 27 (2026-09-25)

- **Grabber is no longer a pipeline**: finished downloads become cards (editable title/artist/album/track/file name + thumbnail-as-cover) with PLAY / SAVE TO MUSIC / SEND TO FORGE / DISCARD. No auto tab switch, no `player.stop()` on download. Default audio = original M4A/AAC (no re-encode); MP3 320K / AS-IS optional. Parallel jobs + working CANCEL (`bridge.cancel` never existed before). Share-to-app (ACTION_SEND) fills the link box.
- **Forge fixes the original**: mounts make a private working copy; SAVE writes tags there, then `StorageClient.overwriteOriginal` (MediaStore `createWriteRequest` on R+, RecoverableSecurityException on Q, legacy write ≤P). Before this, Forge/Pipeline edited a file_picker cache copy and `addToMediaStore`d a NEW file → originals never fixed + duplicates. Spider/ACR results go through `metadata_review_sheet.dart` (current vs proposed, candidate picker) instead of fill-empty-only. RESET/STRIP/CLEAR are form-only (they used to rewrite the file). PLAY IN PLAYER. Karaoke LRC embeds into LYRICS.
- **Spider rewrite**: timeouts everywhere, scored candidates (iTunes/Deezer/MusicBrainz), LRCLIB `/api/get` with duration, Genius optional. Fixed: MB URL never worked (raw spaces), SoundCloud uploader written as ALBUM, "7 Rings" → track 7.
- **Player**: EQ presets now drive `AndroidEqualizer` (was placebo), ReplayGain track/album + pre-amp, fade transitions (crossfade/gapless toggles were placebo; FFmpeg-only gapless audit removed). Handler actions route through the video-aware facade (fixes double audio on videos). End of queue keeps loaded state. Lock-screen art. Queue sheet with titles/drag/swipe/save-as-playlist. Favorites/playlists/recently played (`lib/core/playlists.dart`). Lyrics sheet reads embedded tags.
- **Library tab** was a stub (file picker + nonexistent `storage.readTags`); now MediaStore-backed Songs/Albums/Artists/Folders/Playlists/New with Edit in Forge + system delete.
- **Batch** (nav label, was PIPELINE): load from Library, one permission prompt, fix in place, ≥80% confidence auto-apply else REVIEW → Forge. Keys optional.
- **Widget** buttons now send media-button broadcasts and show now-playing (they launched unhandled intents; `android:configure` removed).
- **Game-feel 28.4 (shaders + transitions)**: `CyberBackdrop` (`shaders/backdrop.frag`, GPU, 30 fps, fallback to the painter) replaces the CPU backdrop; `AnimatedTabStack` replaces `IndexedStack` (fade/slide, state kept, hidden tabs' tickers paused); `CyberNavBar` replaces `BottomNavigationBar` (spring pill, icon pop, whoosh); `CyberPageTransitionsBuilder` for every route; Hero cover art mini-player → player. Verified: shader compiles for GLES/Vulkan/SkSL and renders in flutter_tester (5 variants reviewed), tab state/typed text survives switching, hidden tabs' TickerMode off, push/pop clean; 12/12 scratch tests pass. Phase 28 complete.
- **Game-feel 28.3 (ghost brain)**: `lib/services/ghost_brain.dart` replaces the TF-IDF classifier + canned paragraphs. Offline and free: typo-tolerant, synonym-aware; commands drive the app through `AppGhostWorld` (`ghost_world.dart`): play/shuffle/queue artist, album or song ("play X by Y", "which one?" follow-ups), transport, shuffle/repeat, sleep timer/end of track, what's playing, favorite, fix in Forge, open tabs/EQ/engine/settings, library counts, paste-a-link grab. ~28 BM25 knowledge entries written from the real UI labels, "more" follow-ups. Verified with a fake-world transcript test (40 commands, 11 questions, all 29 suggestion chips resolve, gibberish → fallback).
- **Game-feel 28.2 (ghost look)**: `GhostAvatar` rebuilt — one ticker drives the painter (`repaint:` listenable), idle life (float, breathe, blink, eye wander + glance at taps, rippling tail, scanlines, wisps), moods via `GhostAvatarController.setMood(idle/listening/thinking/talking)` + `talk()`, emotions and glitch-laugh; pauses when dematerialized/backgrounded. Overlay: black box removed, frosted-glass panel (`BackdropFilter` blur 16 + accent outline/glow), outlined query field, glass chips, slide-in bubbles, listen/think/talk wiring and open/close/type/message SFX. Verified in flutter_tester: avatar paints 2.8k px, 1.4k px differ between idle frames, ticker stops after dematerialize; overlay first-launch script + query run clean; snapshots reviewed.
- **Game-feel 28.1 (feel)**: every tappable now animates — `TapFxLayer` draws a pulse outline on press and a shockwave ring + spark burst on release, with a tap sound; `CyberInk` replaces the theme ink splash. UI sounds are a 13-sound bank synthesized in Dart (48 kHz) and played by native `SoundPool` (`SfxEngine.kt`, `USAGE_GAME`) — the old `just_audio` data-URI beeps could duck the music. `CyberTapFeedback` used to delete its child mid-burst (G28); it is now a press-scale wrapper. Verified in flutter_tester: FX layer paints (1.4k px held / 2.9k px burst) and clears to 0, disabled buttons and scroll drags get none, handlers fire once.
- **Album art (27.9)**: player now falls back from embedded tag art to Android's own extractor (`StorageClient.loadArtwork` → MediaMetadataRetriever, covers opus/ogg/webm) and then to cover/folder/front/album .jpg/.png beside the file. Root causes fixed: default Grabber M4A (YouTube DASH) failed every tag write so SAVE TO MUSIC aborted; jaudiotagger ran in desktop mode (FLAC/OGG art writes would throw an Error and hang the Dart call); APIC art was written with invalid picture type 255. See G24/G25.
- **Dependency max (27.8)**: resolver-verified that the only ceiling is `file_picker 9` ↔ `wakelock_plus 1.5.2` (win32 ^5 vs ^6) plus `permission_handler 13` needing compileSdk 37. Everything else bumped to latest: `ffmpeg_kit 0.6.2` (FFmpeg 9.0.1, quote/space-safe argv), `just_audio 0.10.6` + `audio_session 0.2.4` (queue on the new playlist API; EQ/loudness gains are now real dB, G18), `audio_waveforms 2.0.2` (`RecorderSettings`), `permission_handler 12.0.3`, `flutter_lints 6`, `flutter_launcher_icons 0.14.4`, plus a lockfile refresh.
- **Hygiene**: mojibake repaired (`main.dart` splash, `ghost_avatar` glyphs), BOMs stripped, UTF-16 `.gitignore` line fixed, `local.properties` + build report untracked, Whisper model downloads on first use.

## Next actions

1. Device smoke (Moto G): Grabber card → SAVE TO MUSIC; share a YouTube link into the app; Forge on a Library song → SAVE & FIX ORIGINAL (permission prompt, no duplicate); SEARCH METADATA review sheet on a messy title; EQ preset audibly changes playback; lock-screen art/buttons; headset button during a video; widget buttons; Batch with one permission prompt.
1g. Motion smoke (28.4): backgrounds animate subtly per tab (grid floor, streams/embers/bands/wave) and stay readable; switching tabs slides/fades with a whoosh and the glowing pill springs across; typed text in a tab survives switching away and back; Settings/EQ/Theater open with the rise + scanline sweep; tapping the mini-player flies the cover art into the player; background shader pauses when the app is in the background (no battery drain).
1h. Phase-28 verification 2026-09-29 (Muse Spark, fetch+diff+gate): `6471a6c` confirmed — 34 files +3637/−1709 across 4 commits (28.1 feel, 28.2 ghost, 28.3 brain, 28.4 motion); pubspec delta is ONLY the `shaders:` block (zero new deps, ceiling untouched); SFX channel `com.sovereign.tagger/sfx` wired end-to-end (sfx.dart load/play → MainActivity → SfxEngine SoundPool USAGE_GAME); Settings keeps 10 FeedbackSettings refs; old button-vanish flaw independently confirmed in prior code (burst CustomPaint dropped the child — rewrite keeps it). NOT verifiable statically: shader compile on all 3 GPU paths, the 12 scratch tests (not committed — consistent with zero-bloat), all runtime behavior. `flutter analyze --no-pub` clean on real SDK (C:\android\flutter).
1f. Ghost brain smoke (28.3): 'shuffle everything', 'play <an artist you have>', 'play <partial title>' → pick from 'which one?', 'sleep in 1 min', 'stop after this song', 'what's playing', 'favorite this', 'fix this song' (opens Forge), 'open eq', paste a YouTube link, 'how many songs', 'why is there no album art' then 'more'. First run of a library command needs the Library's audio permission.
1e. Ghost smoke (28.2): ghost floats/blinks/looks around with no box behind it and glances toward where you tap; tap it → glass panel opens (background blurred through it, accent outline); focus + type → ghost leans in (listening); send → thinking dots, then it talks (mouth + type ticks) and chirps when done; long-press → glitch laugh; Settings reduce-motion calms it; minimize/close sounds play.
1d. Feel smoke (28.1): tap buttons/list rows/chips/switches → outline pulse on press, ring + sparks + tap sound on release; scrolling a list makes no burst; disabled buttons do nothing; play music and tap around → music never ducks or pauses; Settings FX toggles (burst/ring/pulse/sound/haptics) each switch their part off; REC button bursts red.
1c. Album-art smoke (27.9): play a Library song with embedded art → art in player, mini-player and lock screen; Grabber default M4A → SAVE TO MUSIC succeeds with thumbnail art and correct duration; Forge art on an MP3 and a FLAC saves without hanging; an opus/webm file shows art; a folder with cover.jpg shows art (Android ≤12, or 13+ only if Photos access was granted — the app doesn't request it).
1d. Art-fix verification 2026-09-25 (Muse Spark, fetch+diff+gate): `5a50412` confirmed — Android mode set (`isAndroid=true`), `catch Throwable`, raw-byte FLAC/OGG picture blocks, APIC type-front-cover path, `moof`/`mvex` fragmentation pre-scan + `_flattenMp4` + write retry in `TagIO.write`, Grabber always-remuxes-m4a, player falls back to `StorageClient.loadArtwork` (MediaMetadataRetriever). **SUPERSEDED 2026-10-02: the `_flattenMp4` FFmpeg-remux retry has been DELETED as a lossless violation (FG1) — a fragmented m4a/m4b/mp4 that jaudiotagger refuses now fails honestly instead of silently rewriting the user's container.** CORRECTION (cloud session): the third tier IS in code — `AudioService._folderArt` (`lib/screens/main_shell.dart`, names built from `_folderArtNames` × `_folderArtExts`, so a literal `cover.jpg` grep misses it), called last in `_resolveArtwork`; chain is 3-tier (tags → retriever → folder image). Caveat: on Android 13+ the app only requests `Permission.audio`, so folder images are invisible unless Photos access is granted — tier 3 is effectively ≤ Android 12 today. `flutter analyze --no-pub` clean on real SDK; device run still the gate.
1b. Dependency-upgrade smoke (27.8): EQ preset and ReplayGain boost sound right (not 10× hot/weak — just_audio 0.10 gains are real dB); Workbench ops + Grabber MP3/remux on FFmpeg 9.0.1; Workbench REC (AAC via `RecorderSettings`); queue restores on relaunch and resumes at the saved position.
2. Build check: first `flutter build apk --release` compiles the new Kotlin (StorageBridge/MainActivity/Widget) — now POSSIBLE on this host (`RULES.md` §1.5 override 2026-10-01); was not compiled in the cloud session. Output is debug-keystore-signed unless `SOVEREIGN_KEYSTORE` is set, so it is not Play-ready.
3. Optional: true overlapping crossfade (dual player) and a custom 15-band DSP (device EQ is typically 5 bands) — Phase 28 candidates.

## Where we were (Phase 25 snapshot)

**Date:** 2026-08-25
**Phase:** 0–25 COMPLETE. All gated `flutter analyze --no-pub` → `No issues found!`
**Project:** `C:\sovereign_tagger` (promoted from playground copy). No APK built on this host; Android Studio on Moto G is sole compiler.

## What shipped (delta since last handoff 2026-08-24)

- **Phase 25 — Contextual Settings Split (jetAudio pattern)** [x]:
  - Research verdict: jetAudio uses one settings tree + contextual entry points, NOT per-tab screens. Mapped accordingly.
  - `lib/screens/playback_engine_screen.dart` — Crossfade 0–12s + Gapless toggle + Gapless Audit moved out of Settings; persists instantly (`onChangeEnd` slider / switch change) to `crossfade_duration`/`gapless_enabled`. Entry: Player AppBar merge-icon action.
  - `lib/screens/eq_presets_screen.dart` — 15-band preset matrix moved out of Settings; SAVE PRESET/FLAT, `_dirty` PopScope discard-confirm. Syncs with Workbench via `eq15_band_$i`. Entry: Workbench header tune icon.
  - Root Settings now KERNEL/SYSTEM only (~772 L): keys, accent color, maintenance, ghost, backup/restore. Backup/Restore untouched (reads prefs directly).
- **Phase 25 hotfix round (same session, operator feedback)** [x]:
  - **GH7 — ghost never rendered**: `GhostChatOverlay.build` returned a nested `Positioned` while MainShell already wrapped the overlay in one → ParentDataWidget assertion silently killed the whole ghost subtree (no orb, no chat, no first-launch sequence). Overlay now returns a plain `Column`; full file rewritten clean. Tutorial copy de-staled ("train TFLite" refs removed; PLAYER tip now mentions merge/tune icons).
  - **CS4 — EQ moved to PLAYER** (this was the point of the jetAudio research): tune icon on Player AppBar opens `EqPresetsScreen`; Workbench header icon removed. Sliders rebuilt as big VERTICAL rails (260px tall via RotatedBox quarterTurns:3, 52px band width, horizontal-scroll rack, thumb r11). Workbench keeps its 15-band DSP op + SAVE PRESET sync (`eq15_band_$i`).
  - **PW1 — PCM live wave finished**: bridge computes peak in existing read loop (merged single pass, zero extra alloc), throttled 50ms → `pcm_events` EventChannel → `PcmRecorder.amplitudes()` → `_PcmWavePainter` 48-bar redAccent level meter + midline in Workbench lossless capture box; sub cancelled at HALT/dispose. Native side (PcmRecorderBridge.kt listener + MainActivity pcm_events channel) landed earlier in session.
    - Build fix: first device run failed `compileDebugKotlin` — `Short > Int` peak comparison resolved to star-projected `Number & Comparable<*>` under KGP 2.3.20 (prohibits `compareTo`). Fix: explicit `val v: Int = if (s < 0) -s.toInt() else s.toInt()` (`PcmRecorderBridge.kt:75`). Verified `:app:compileDebugKotlin` BUILD SUCCESSFUL on host; full assembleDebug via Android Studio pending re-run.
- **Phase 25 device-smoke round 2 (GH7 still-no-ghost root cause chain)** [x]:
  - **GH7b — avatar build crash**: device log threw `opacity >= 0.0 && opacity <= 1.0` at `ghost_avatar.dart:613` every frame → `AnimatedOpacity` error widget = orb invisible even after Positioned fix. Root cause: `_materialize` uses `Curves.easeOutBack` (overshoots >1.0) and `_dematerialize` `easeInBack` (`1-t`) — both leave [0,1]. Fix: `_opacity.clamp(0.0, 1.0)` + `_scale.clamp(0.0, ∞)` at the widget.
  - **GH7c — consumed first-launch flag**: earlier broken builds ran overlay initState + animations invisibly (rendering crashed AFTER initState), so `setFirstLaunchComplete()` persisted without the sequence ever being seen. Key bumped to `ghost_first_launch_complete_v2`; MainShell now reads via `GhostSettings.firstLaunchComplete` instead of raw old key. Sequence will replay once on next cold start.
  - **Launch boops explained** (operator query): NOT mic-access tones — they are our own TapFeedback wavs fired by the invisible ghost: `materialize()`→`matrixTap()`, `glitchLaugh()`→`matrixConfirm()`, dematerialize→`matrixBoop()` (ghost_avatar.dart:486/507/531, 8kHz mono base64 wavs via just_audio). They'll accompany visible animations now. Remove/re-pitch if unwanted.
  - **Workbench SwitchListTile assertion**: "LOSSLESS PCM" switch inside decorated Container → ListTile ink assertion; wrapped in `Material(color: transparent)` (same pattern as Phase 21 queue-sheet fix).
  - **GH9 — THE ACTUAL RENDER KILLER (z-order)**: round-2 log had zero Flutter exceptions, sounds played, IME fired — ghost was building fine but **painted UNDER the tabs**: it sat at Stack child #2 while the tab `Column` (opaque black `Scaffold` per tab + mini-player) came after it in the same `Stack`, covering the full body. Fix: ghost `ValueListenableBuilder` moved to **last Stack child** (paints on top of everything). Ghost was rendering correctly the whole time — buried.
  - **Auto-keyboard killed**: chat's `_controller.addStatusListener` requested input focus on programmatic expand → IME popped at every launch. Listener removed; focus now only via user-initiated orb tap (`_toggleCollapse`).
  - **GH10 — orb painted off-canvas (the "just a box" bug)**: `_drawGhost` used `ghostPath.shift(center)` — path is authored in a 100×100 design space, shift only TRANSLATED it by the canvas midpoint so the silhouette drew at 32→132px on a 64px canvas (~75% off-screen; only chat panel visible → "box with text and buttons"). Fix: proper canvas mapping — translate to center, `scale(shortestSide/100)`, recenter on path bounds (51,57). Orb silhouette + accent glow now fills the 64px box.
  - **Drag-to-move**: orb is the drag handle (`GestureDetector.onPanUpdate` on avatar), whole overlay (panel included) follows via `Transform.translate(_dragOffset)`; clamped to screen bounds in overlay state.
  - **Auto-collapse**: after contextual tutorial finishes, panel collapses back to orb-only after 8s unless user already interacted (`_userInteracted` flag set by manual toggle/input).
  - **GH11 — orb scale/opacity zero-init + racy materialize (agent-audited root cause)**: `GhostAvatarState._scale/_opacity` init 0.0 and the ONLY materialize caller is MainShell's one-shot postFrameCallback, which fires while overlay is collapsed-shrink → `GlobalKey.currentState == null` → `_state?._materialize() ?? Future.value()` silent no-op → fresh state mounts at scale-0/opacity-0 forever. Fixes: (1) avatar SELF-materializes post-frame on mount (silent=true — no launch beep); (2) overlay NEVER returns shrink — collapsed = orb-only, always mounted/tappable (also kills state-destruction-on-collapse F8); (3) overlay `_checkFirstLaunch` now reads GhostSettings v2 flag (was raw old key — F10 desync); (4) orb opacity constant 1.0; auto-collapse 8s→12s. Agent audit: ses_fc4c0342affe9rzuG4NtYBtQnr findings F1-F10.
  - **GH12 — shape + panel restyle (operator feedback post-verification)**: old silhouette path was a lumpy multi-loop blob → replaced with clean classic ghost (dome cubic head, straight sides, 4-scallop quadratic hem; bounds x20-80 y8-~89, center 50/49) + oval eyes/mouth drawn on main pass only (`customPaint == null` guard keeps RGB-shift layers body-only). Chat panel DE-BOXED: outer Container decoration (bg/border/radius/glow) removed — header row, bubbles, input float free with minimal padding; power/X buttons unchanged.
  - **Release closeout** (operator demand): still gated per repo law — no host `flutter build apk --release`; Android Studio does device builds. Signing currently falls back to debug keystore unless `SOVEREIGN_KEYSTORE` env/local.properties provided (`app/build.gradle:62`).
  - Remaining launch-log noise confirmed benign: mali_gralloc format errors, BLASTBufferQueue max-frames spam, HWUI undefined symbols, Choreographer skips during startup, SELinux vendor prop denials.

- **Phases 16–21 completed** (were missing from handoff docs): safe patches (`0.5.13/2.14.0/1.5.2` inside `win32 5.9.0` cap), 6 mounted guards, true-lossless PCM bridge, tap feedback, per-tab pulsing grid (Phase 16), heavier electric arcs + traveling comets (Phase 19), Whisper transcription wired via bundled `ggml-base.en.bin` 141MB (Phase 18), Whisper command corrected from DOCS output + `AudioServiceActivity` migration + status boxes top + staging hygiene + HALT auto-export + Material bottom sheets + AmbientBackdrop lifecycle pause (Phase 20), video merge probe retry + queue-end pause/rewind + ACR mic release + queue-sheet Material wrapper (Phase 21).
- **Phase 22 completed**: All 8 F-Droid-grade items shipped:
  - ReplayGain scanner (`ebur128` → TXXX tags via id3)
  - 15-band `anequalizer` (AutoEq, 25Hz–16kHz, Q=1.2, Settings↔Workbench sync)
  - Crossfade 0–12s + Gapless toggle (Settings → Playback Engine)
  - Gapless Audit test (2-tone pattern → RMS gap measurement)
  - LRCLIB lyrics fallback in `spider.py` (free, no key, after Genius)
  - Home screen widget (`SovereignWidgetProvider` — RemoteViews, 4-button control)
  - Library tab (`TabLibrary` — MediaStore browse by Album/Artist/Folder, search, play)
  - Backup/Restore (XOR `0x53` encrypted JSON: settings + EQ presets + persisted queue)
- **Phase 23 — Cyberpunk Tap Feedback** [x]:
  - `lib/core/cyber_tap_feedback.dart` — `CyberTapFeedback` widget with particle burst (12 exploding dots), expanding shockwave ring, button scale pulse
  - Pre-computed trajectories, single `AnimationController`, `CustomPainter` reuse — zero alloc during animation
  - `CyberButton` / `CyberIconButton` convenience widgets (primary/secondary styling, accent glow shadow)
  - Integrates with existing `TapFeedback` (haptic + 880/1400Hz base64 tick/boop)
  - Zero battery drain: particles only live during 300ms burst, no background timers
- **Phase 24 — Ghost Avatar Tutorial Chatbot** [x] (Slices 24.1–24.5, TFLite lane ripped in C — ceiling conflict):
  - `lib/widgets/ghost_avatar.dart` — `GhostAvatar` widget: code-drawn Android ghost emoji silhouette, glitch effects (scanlines, RGB shift, jitter), glitch laugh (wobble + particle burst + "hahaha" typewriter)
  - Three-emotion particle system: sarcastic (glitch squares 72%), happy (circles 72%), serious (matrix chars 72%) with weighted randomization
  - Animations: materialize (easeOutBack), dematerialize (easeInBack), glitchLaugh (wobble + particle burst + "hahaha" typewriter)
  - OverlayEntry integration: floats in MainShell bottom-right, persists across tabs, 72px collapsed orb
  - `GhostSettings` — ValueNotifiers for reduceMotion, visible, autoExpand, firstLaunchComplete (SharedPreferences persisted; useTflite removed)
  - Reduce motion global: disables ghost glitch/wobble/scanlines + AmbientBackdrop/MatrixRain
  - Integrated in MainShell: Positioned bottom-right (above bottom nav), ValueListenableBuilder for visibility
  - `lib/widgets/ghost_chat_overlay.dart` — `GhostChatOverlay`: Chat UI with typewriter text, message bubbles, suggestion chips, text input + send
  - First-launch sequence: "Welcome to... The Machine... SkyNet? Just Kidding... hahaha!" with glitchLaugh
  - Contextual tutorials: `lib/services/ghost_classifier.dart` pure-Dart TF-IDF + cosine similarity (15 intents, threshold 0.14, no native dep) → `GhostChatOverlay` now tries classifier first, falls back to keyword routing
  - Suggestion chips: Context-aware action chips for quick queries
  - GlobalKey integration: MainShell controller drives GhostAvatar in overlay
  - Settings: Ghost Tutorial section now visibility / auto-expand / reduce-motion (global) / reset first-launch (TFLite toggle + train button removed — replaced by pure-Dart classifier)
  - Build: `tflite_flutter` removed from pubspec (sole JVM-target mismatch source), `SovereignTagger.apk` flat name
- **Repo cleanup** [x]: Removed dead scaffolding (`lib/core/jobs`, `lib/core/models`, `tools/`), stale blueprint files, old versioned blueprints.
- **Safe patches inside frozen `^` ceiling** (no `--major-versions`): `ffmpeg_kit 0.5.12→0.5.13`, `video_player 2.13.0→2.14.0`, `wakelock 1.5.2` maxed (`1.7.0` blocked by `file_picker ^9 win32 ^5.9.0` vs `win32 ^6.0.1` — intentional). `pubspec.yaml:16,23,26` now `^0.5.13/^2.14.0/^1.5.2` lock `0.5.13/2.14.0/1.5.2` synced, Studio no longer throws `win32` mismatch. `^0.6.0/^12/^0.10/^13` still blocked for dedicated major session.
- **6 mounted guards** `tab_forge:85,180,276` `tab_grabber:201,226` `tab_pipeline:52,66` `tab_workbench:154` `main_shell:72` + `FilePicker PlatformException` wrappers + pipeline `if(!mounted) break`.
- **True-lossless PCM** `android/app/src/main/kotlin/com/sovereigntagger/PcmRecorderBridge.kt:18` `AudioRecord` 48k/16-bit WAV (header placeholder → LE finalize, single `ByteBuffer` reuse) + `lib/core/pcm_recorder.dart` + `lib/tabs/tab_workbench.dart:110` `LOSSLESS PCM (48K WAV)` toggle default ON (fallback `aac 48k/256k 50ms`).
- **Tap feedback** `lib/core/tap_feedback.dart:10` haptics + embedded `880/1400Hz` 0.7–1.3KB base64 wav via `just_audio` data URI + `dispose()`.
- **Per-tab electricity** `lib/widgets/matrix_rain.dart:98` `AmbientBackdrop` now `Stateful` `4s` pulse, `BackdropVariant` per tab (grabber vertical, forge slow, pipeline horizontal, workbench mixed) `alpha 0.035` grid + `0.18` sparks, `MainShell` `ValueListenableBuilder currentTab` switch.
- **Whisper AI** bundled `assets/models/ggml-base.en.bin` (141MB) + `pubspec.yaml:37` + `tab_workbench.dart:_executeWhisper` extracts to cache, runs `-af "whisper=model=<path>:language=<en|auto>" -f srt`, writes `.srt` sidecar + text preview. Self-diagnosing: failure pulls `-h filter=whisper` into `_whisperReport` panel. Settings probe card has **DOCS** button for ground-truth syntax.
- **Critical 5 HOLD** still gated: `ffmpeg queue Future<void> _drain` `22`, `jobId UUID` `48`, `Id3 deleteField` `Id3Tagger.kt:23`, `bridge split orphan` `114`, `Storage MIME` `StorageBridge.kt:39`.
- **HIGH 6 HOLD** still gated: extractor `android,web` rotation `bridge.py:19` + `spider.py:79`, `_queueLock` serialized `main_shell:72`, `PcmRecorderBridge:60` reuse, runtime `READ_MEDIA_*` via `permission_handler`, scoped-storage cache copy.

## Toolchain notes (dependency ceiling: win32 pair + compileSdk 37)

- `pubspec.yaml:6` `sdk >=3.0.0 <4.0.0` / `Flutter 3.47 / Dart 3.13` / `compileSdk 36 / NDK 28.2 / JDK 25 bundled jbr/bin/java 25.0.2` / `compileOptions 1.8` shim (bump to `17` only in dedicated Java session). `AGP 9.0.1 / KGP 2.3.20 / Gradle 9.1.0` at ceiling (Chaquo max `9.2`). `python 3.14` top but few wheels — `app/build.gradle:54` fallback to `"3.11"` comment. `3.12+` is 64-bit only (`arm64-v8a,x86_64` only). `minSdk 26 / abiFilters arm64-v8a,x86_64` 64-bit-only documented.
- **Repo cleaned**: Removed dead scaffolding (`lib/core/jobs`, `lib/core/models`, `tools/`), stale blueprints (old versions, PDFs, large text dumps).
- Verification: `flutter analyze --no-pub` only; no `test/` suite; device smoke required for `audio_service` notification, FB mux, PCM WAV, rain perf, Whisper transcribe, Ghost chat.

## Next actions (archived — Phase 25–26 era, superseded by the §Next actions at top)

1. **Device smoke on Moto G** (Android Studio `Install`): **Ghost: orb materializes bottom-right, first-launch SkyNet sequence plays, chat expands, classifier replies, hide/laugh chips** (GH7 fix — verify no console ParentDataWidget error); **Player AppBar tune icon → vertical EQ rack renders + saves; merge icon → Playback Engine**; **Workbench REC → live red wave bars move with mic level** (PW1); Whisper transcribe → `.srt` sidecar; ReplayGain scan → verify tags written; 15-band EQ op → apply/verify; Crossfade 0–12s → verify; Gapless Audit → run test pattern; LRCLIB fallback → verify lyrics fill; Home widget → add to launcher; Library tab → scan MediaStore; Backup/Restore → round-trip; `grabber` quick-video `1080/720` + FB silent-heal; `pipeline` batch cancel/retry; `workbench` PCM record → HALT auto-export → DSP; `player` edge-to-edge pinch + `sleep/speed/LRC` + queue persist; `splash` rain + per-tab pulses 60fps.
2. **Git decision — RESOLVED 2026-09-25**: repo is versioned; `main` is the single canonical branch tracking `origin/main` (merged master history + Phase-27 rework + review fixes; old `master`/`claude/elegant-franklin-j99jl0` remotes retained but frozen). Local `master` + `backup-before-main-sync` refs kept as fallback. Work on `main` only.
3. **Phase 26+** (future, optional): Cloud sync, Last.fm scrobbling, Chromecast, Opus encoding, multi-user profiles.
4. **Optional major session (explicit ask only):** `file_picker 13` migration (16 call sites + verify `PlatformFile.identifier` still feeds Forge write-back) which unlocks `wakelock_plus 1.8`; `permission_handler 13` needs root `compileSdk 37`. Plus `java 1.8→17`. Never `--major-versions` blindly — needs Moto G regression.
5. **PCM wave amplitude (nice-to-have):** wire `AudioRecord` max amplitude to `onCurrentDuration` stream for live wave in lossless mode (currently static `PCM CAPTURING` indicator).
6. **UI/UX polish session (operator-flagged):** buttons/taps still lack sound FX + visual feedback across tabs — `CyberTapFeedback`/`CyberButton`/`CyberIconButton` (`lib/core/cyber_tap_feedback.dart`) exist from Phase 23 but are NOT wired into most surfaces. Sweep grabber/forge/pipeline/workbench/library/player/settings: wrap primary actions with `CyberTapFeedback`, wire `TapFeedback.machineTap/Boop/Confirm` (post-matrix-rename names) to presses, verify haptics on device.
7. **Phase 26 staged** (ROADMAP has full slices): 26.0 ghost scrim [x] + 26.0b key onboarding [x] (storage/openUrl intent channel, settings title hyperlinks, ghost rituals/chips) shipped; next up **26.1 Waveform Studio** — use `audio_waveforms` `PlayerController.extractWaveformData` (dep already owned) + custom painter peak/RMS dual-shade, pinch-x viewport zoom, drag selection → CLIP op; then 26.2 ops pack (`adeclick`/`deesser`/`alimiter`/`mcompand`/`amix`/`acrossfade`/`apad`/`dcshift`), 26.3 yt-dlp help sheet, 26.4 spectrogram stretch (`showspectrogrampic`). Research base: Lexis/WaveEditor/WavePad/Audacity feature digests in ROADMAP Phase 26 notes.
7. **Phase 26 SHIPPED (all slices)** [x]: ghost scrim; key onboarding (`storage/openUrl`, settings hyperlinks, ghost rituals/chips); **Waveform Studio** (`lib/widgets/waveform_studio.dart` — FFmpeg s16le→peak buckets, mirrored painter w/ selection shading, adaptive ruler, drag-select w/ edge zones, zoom ±/FIT + RangeSlider pan, auto-syncs CLIP fields); **9 new Workbench ops** (Insert Silence/Delete Region/Mix With File/Crossfade Join/adeclick/deesser/alimiter/mcompand/highpass — all container-preserving, second-media picker for mix/xfade); **yt-dlp FIELD MANUAL** sheet in Grabber header help icon; Tone Generator + Spectrogram Snapshot ops; MediaStore tail falls back to cache-path note; tap-feedback sweep wired `machineTap()` into 25 handlers (internal chains excluded); **visual CyberTapFeedback installed** around 8 primary buttons in pure-visual mode (burst+ring+pulse; haptic/audio flags off so inner button's machineTap stays single-source).
7b. **FEEDBACK MATRIX card** (Settings > UI PREFERENCES, right under accent color): `lib/core/feedback_settings.dart` (persisted ValueNotifiers: burst/ring/pulse/sound/haptics; haptics default OFF per operator) loaded at boot in main.dart. Gates live inside `tap_feedback.dart` primitives (sound+haptic) and `cyber_tap_feedback.dart` `_triggerBurst` (per-layer visual gating; all-off skips animation entirely). Completion haptics added via `machineConfirm()` at workbench/forge/grabber/pipeline success tails — so HAPTICS toggle = buzz on actions AND completions, SOUND toggle = clicks/boops, VISUAL layers = any combo of the three.
8. **TOOLING LAW (new, RULES.md §3.1 + AGENTS.md table):** PowerShell text pipelines are BANNED for source edits — PS 5.1 mis-reads UTF-8 as ANSI (mojibake `—`→`â€"`) and caused silent letter swaps (`setState`→`setYtate`, `Text`→`RextStyle`) during Phase 25 matrix-rename pass AND earlier sessions. Editor tools only; Python `encoding='utf-8'` if scripted; at the END of the phase (RULES §1A.0) follow with ONE `analyze --no-pub` + `'â€|Ã|Â'` signature grep — never per edit.
9. **Device smoke additions for P26:** wave studio loads peaks + drag-select syncs CLIP fields; Insert Silence/Delete Region round-trip; Mix + Crossfade need SECOND MEDIA mounted first; adclick on a noisy clip; deesser/limiter audible; tone gen lands in Music vault + auto-mounts; spectrogram PNG path shown in status (cache fallback expected until png MIME added); grabber FIELD MANUAL opens; taps beep across tabs without double-fires during downloads.
10. **Branch merge verified 2026-09-25 (Muse Spark, fetch+diff review):** `origin/main` tip verified as true merge of empty-old-main + `2706b7d` (both parents present, both histories ancestors, no force-push — `master@2e3ad7d` + feature branch untouched); junk scan clean (no ggml binary / local.properties / build reports on `main`); all Phase 24–26 work confirmed present; EQ-via-just_audio-AndroidEqualizer + ReplayGain + queue-persist-split + Library-PopScope fixes confirmed in-diff. Analyzer/device run still unverified from here — merge-to-main already done upstream; device smoke remains THE gate before trusting the build. Local machine now on `main` tracking `origin/main`; Whisper model intact on disk (correctly git-ignored on `main`).

## Open decisions (deferred-zero-bloat)

- **`test/` suite — DECIDED 2026-10-01: ZERO, until every feature is built out.** Not the old "deferred unless you opt in"; a standing operator decision. `ROADMAP.md` Phase 13 is `[-]` PARKED. Do not create `test/`.
- **Phase S0–S4 SDK edition — PARKED 2026-10-01, spec only.** Operator is researching pros/cons and tradeoffs. See `.blueprints/SDK-EDITION-SPEC.md`. Do not begin it as a side effect of another task.
- **`flutter build apk` — ALLOWED 2026-10-01** (`RULES.md` §1.5). Supersedes the old host-build ban. Still end-of-plan; still not a substitute for a device run; release builds are debug-keystore-signed unless `SOVEREIGN_KEYSTORE` is set.
- `file_picker` / `wakelock_plus` / `permission_handler 13` — stay pinned until dedicated session (everything else already at latest).
- Java `1.8→17` — stay shimmed until dedicated Java session.
- **SDK EDITION track approved (spec only)**: ROADMAP "Phase S0–S4" — dual-flavor future (full = personal w/ yt-dlp; sdk = publishable, Python ripped). Prerequisite order matters: S1 Dart spider port BEFORE S2 flavor split BEFORE S3 ceiling raise. win32/file_picker cap documented as orthogonal to Python removal.

(End of file - total 44 lines)