# Combined `main` Post-Merge Integration Audit (`894e4b368e44a1f2a59f17b69533330340a48516`)

Executed `2026-11-14` on Moto G (`ZT4222BMWN`, `720x1604`, Android 16 / API 36) after merging **PR #86** (`f48b8650a14c4c6487ce32b8f31a5e3ebe5ddad4`) and **PR #87** (`894e4b368e44a1f2a59f17b69533330340a48516`) into `main`. BLU View 5 (`7040016025040287`) was left untouched.

## 1. Repository & CI Baseline (`main` @ `894e4b3`)

- **Post-merge GitHub Actions CI:**
  - `Dart`: run `43617197244` -> `success`
  - `Android native build`: run `43617197241` -> `success` (`android-arm64` `7m50s`, `android-x64` `7m37s`)
- **Host gates on clean `894e4b3`:**
  - `python -m unittest discover -s test/python -p "test_*.py" -v`: **37/37 OK** (`2.115s`)
  - `C:\android\flutter\bin\flutter.bat analyze --no-pub`: **No issues found!**
  - `C:\android\flutter\bin\flutter.bat test --no-pub`: **213/213 passed**
  - `android\gradlew.bat :app:testDebugUnitTest --console=plain`: **BUILD SUCCESSFUL** (`3m 37s`)
- **Clean ARM64 debug build (`flutter build apk --debug --no-pub --target-platform android-arm64`):**
  - `sourceSha`: `894e4b368e44a1f2a59f17b69533330340a48516` (`sourceDirty: false`, `versionName: "1.0.0"`, `versionCode: 1`, `abis: ["arm64-v8a", "x86_64"]`, `builtAtUtc: "2026-11-14T17:14:31Z"`)
  - APK SHA-256: `d022fc432d0fa524c134febd0a4994f74bfcfe1086c37063a76560c98e5c8898`

## 2. In-Place Upgrade & Data Preservation (`com.sovereigntagger` on `ZT4222BMWN`)

Upgraded cleanly with `adb -s ZT4222BMWN install -r` (no uninstall, no `pm clear`):

| Artifact / Field | Pre-upgrade (`152a5e5` APK) | Post-upgrade (`894e4b3` APK) | Post-audit restored state |
|---|---|---|---|
| `base.apk` SHA-256 | `6bb2b4f5...02987934` | `d022fc43...e5c8898` | `d022fc43...e5c8898` |
| `appId` / KeySet | `appId=10821` / `560` | `appId=10821` / `560` | `appId=10821` / `560` |
| `firstInstallTime` | `2026-10-04 16:04:52` | `2026-10-04 16:04:52` | `2026-10-04 16:04:52` |
| `lastUpdateTime` | `2026-11-14 02:34:52` | `2026-11-14 11:25:30` | `2026-11-14 11:25:30` |
| `shared_prefs/sovereign_credentials_v1.xml` (`593` B) | `1e1b1615...b9f21c2b` | `1e1b1615...b9f21c2b` | `1e1b1615...b9f21c2b` |
| `shared_prefs/FlutterSharedPreferences.xml` (`3054` B) | `2bbdf28b...1f7dbbe02` | `2bbdf28b...1f7dbbe02` | `2bbdf28b...1f7dbbe02` |
| `app_flutter/sovereign_library.json` (`9845` B) | `1b2f6f00...3a762dae` | `1b2f6f00...3a762dae` | `1b2f6f00...3a762dae` |
| `shared_prefs/acrcloud.xml` | `2e61e18a...83d7129` | `2e61e18a...83d7129` | — |
| `whisper_model/ggml-base.en.bin` (`147,964,211` B) | Present | Intact | Intact |
| `whistle_model/whistle.cact` (`16,919,407` B) | Present | Intact | Intact |
| `embedding_gemma` (`179,131,736` B `.tflite`, `4,683,319` B tokenizer, `4,712` B vectors) | Present | Intact | Intact |

## 3. Boot Provenance, Settings Diagnostics & Chaquopy Checks

- **Boot logcat:**
  - `BOOT: FFmpeg armed: 534 filters registered (full+gpl)`
  - `BOOT: BUILD PROVENANCE: sha=894e4b368e44a1f2a59f17b69533330340a48516 version=1.0.0(1) abis=arm64-v8a,x86_64 built=2026-11-14T17:14:31Z`
  - `GRABBER CAPABILITIES: {"status": "success", "ffmpeg": true, "ffmpegkit": true, "ffmpegkit_version": "9d4ca21", "ytdlp": "2026.10.26"}`
  - Persisted 3-track queue restored paused (`setAudioSources OK: 3 source(s), start=2 pos=0ms state=ProcessingState.ready`) with existing EQ curve `[0.0, 0.0, 0.0, 0.0, 12.0, 0.0, -6.0, 0.0 x8]`.
- **`SettingsScreen` UI verification:**
  - `BUILD PROVENANCE` card displayed exact commit `894e4b368e44a1f2a59f17b69533330340a48516` and timestamp `2026-11-14T17:14:31Z`.
  - `CORE ENGINE MAINTENANCE` displayed staged replacement/recovery text; `CHECK FOR YT-DLP UPDATE` and `FULL STACK REFRESH (YT-DLP + DEPS)` rendered enabled and `> Idle.` (no `RECOVERY REQUIRED`, `sov_recovery` empty; live GitHub/`pip` mutation not triggered against `com.sovereigntagger`).
  - `ON-BOARD PYTHON DOCTOR -> DIAGNOSE`: `yt-dlp 2026.10.26`, `Registry 5 rules`, `Hits: (none — core likely current)`.
  - `CRASH RECOVERY VAULT [0 PENDING]` -> `RUN SECURITY & INTEGRITY SELF-TEST`: 9/9 assertions `PASS` (`OVERALL RESULT: ALL ASSERTIONS PASSED ✓`).

## 4. Playback, 15-Band EQ & Atomic Save/Discard (`sovereign_audit_1khz.wav`)

Tested using a disposable 60 s 48 kHz stereo 1 kHz `-18 dBFS` WAV (`11,520,044` B), pushed to `/sdcard/Music/sovereign_audit_1khz.wav`, scanned via MediaStore (`2546 -> 2547` tracks), and deleted afterward (`ls` -> `No such file or directory`, rescanned to `2546` tracks):

- **DSP attachment (`AudioFlinger` + `SovereignEq15`):** Session `5585` (`pid 11485`, `uid 10821`) attached `SOVEREIGN EQ BACKEND: dynamics15 bands=15` (`Dynamics Processing` Effect ID `9411`, `Enabled: y`, `48000 Hz`, stereo `AUDIO_FORMAT_PCM_FLOAT`) alongside `Loudness Enhancer` (`Effect ID 9403`, `Enabled: n`), with zero duplicate `Equalizer`.
- **Live slider drag without persistence:** Dragging Band 0 (`25 Hz`) from `0.0 -> +9.0 dB` streamed intermediate native readbacks (`+1.0, +4.0, +5.0, +7.0, +9.0 dB`, `channelsMatch=true`) while `flutter.eq15_band_0` on disk remained `0.0`.
- **`SAVE PRESET`:** Persisted `flutter.eq15_band_0` as `9.0` with `> 15-BAND EQ PRESET SAVED TO KERNEL.`.
- **Dirty drag + `UNSAVED PRESET` -> `DISCARD`:** Dragging Band 0 (`25 Hz`) down to `-9.0 dB` streamed live stereo readbacks (`+8.0, +7.0, +4.0, 0.0, -5.0, -8.0, -9.0 dB`, `channelsMatch=true`) without modifying disk `9.0`. Back navigation prompted `UNSAVED PRESET / DISCARD UNSAVED EQ CHANGES?`; tapping `DISCARD` reverted native DSP to `[9.0, 0.0, 0.0, 0.0, 12.0, 0.0, -6.0, 0.0 x8]` (`channelsMatch=true`), left disk `9.0` intact, and showed `+9.0` when re-opened.
- **Background playback & teardown:** Under `KEYCODE_HOME`, `media_session` reported `PlaybackState.PLAYING(3)` and `AudioFlinger` output thread `Frames written` advanced `110579712 -> 110678016` with `Dynamics Processing` active on session `5585`. After `am force-stop com.sovereigntagger`, `AudioFlinger` reported zero active `com.sovereigntagger` sessions or `Dynamics Processing` chains.

## 5. Isolated Transactional Updater Re-Run on Combined `main` (`894e4b3`)

- Built `:app:assembleUpdaterAcceptance` (`updaterAcceptance/SovereignTagger.apk`, `725,666,423` B) and `:app:assembleUpdaterAcceptanceAndroidTest` (`app-updaterAcceptance-androidTest.apk`, `433,593` B) at `894e4b3` and installed on `ZT4222BMWN`.
- Instrumentation runs (`com.sovereigntagger.UpdaterAcceptanceTest#isolatedUpdaterThroughSettings`):
  - `phase=failure`: `OK (1 test)` (`45.467s`)
  - `am force-stop com.sovereigntagger.updateracceptance`
  - `phase=restart`: `OK (1 test)` (`38.807s`)
  - `phase=all`: `OK (1 test)` (`102.185s`)
- Uninstalled both `.updateracceptance.test` and `.updateracceptance` (`Success`); verified `com.sovereigntagger` `appId=10821`, `base.apk` (`d022fc43...`), `sovereign_credentials_v1.xml` (`1e1b1615...`), `FlutterSharedPreferences.xml` (`2bbdf28b...`), and `sovereign_library.json` (`1b2f6f00...`) untouched.

## 6. Documented Non-Goals / Remaining Boundaries

- Live GitHub `yt_dlp` download and live `pip` upgrade (`updateFullStack`) against `com.sovereigntagger` (isolated acceptance uses synthetic `.tar.gz` + fixture overrides in `.updateracceptance`).
- Signed `release` APK acceptance (debug / `updaterAcceptance` variants only; no release keystore credentials).
- External acoustic / loopback microphone measurements and wired/Bluetooth audio route switching.
- Physical Android API 26–27 `legacy` 5-band fallback verification (`ZT4222BMWN` runs Android 16 / API 36).
