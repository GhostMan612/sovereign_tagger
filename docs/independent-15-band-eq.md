# Sovereign Tagger — Independent 15-band playback EQ

## Audio path

The 15-slider screen already existed, but prior to this change, PlaybackFx
resampled its curve onto the handset's fixed-band Android Equalizer. The Moto G
exposed five hardware bands; changing 15 sliders did not create 15 DSP bands.

The replacement keeps just_audio/Media3 and audio_service as transport owners.
The Kotlin audio-session MethodChannel now owns the EQ effect. On Android 9+
(API 28+), Sovereign15BandEq attaches Android DynamicsProcessing with a
15-band **PreEq** stage and sends all 15 gains without downsampling. The
stage is separate from the fixed-band Android Equalizer. Its cutoffs are
geometric midpoints between the 15 UI center frequencies, with 20 kHz as the
last upper cutoff. The same 15 centers drive the UI and platform contract.

Android API 26–27, and devices unable to create the requested DynamicsProcessing
engine, use the existing fixed-band Equalizer with explicit backend=`legacy`.
The UI identifies this as compatibility mapping, **not** independent 15-band
DSP. When neither engine attaches, backend=`unavailable` and playback proceeds
without EQ; the application must never mute playback just because DSP failed.

## Safety and lifecycle

- All 15 finite gains are required; values clamp to ±12 dB.
- The effect is attached to the current Media3 audio-session ID, not globally.
- Session reassignment releases the previous EQ before creating the next.
- DSP enable/disable bypasses the entire EQ, leaving transport independent.
- The independent engine is not layered with the legacy hardware EQ; at most
  one is active at a time.
- ReplayGain/LoudnessEnhancer and the volume/fade logic remain separate.
- Settings continue using existing `eq15_band_0..14` and `eq_enabled` keys.
- Mixer implementations and OEM effect availability vary. A successful
  configuration is not proof of audible frequency response.

## Required device acceptance (not established by CI)

1. Install the exact CI APK; record commit, manifest and APK SHA-256.
2. Start playback on Moto G (Android 16); expect
   `SOVEREIGN EQ BACKEND: dynamics15 bands=15`.
3. Confirm changing an individual 25 Hz, 1 kHz and 16 kHz gain produces a
   corresponding response via spectrum/loopback measurement, without mute,
   clipping, or audible discontinuity.
4. Confirm enable/bypass, presets, persistence, app restart and session changes.
5. Verify headphone/Bluetooth route changes, rapid seeks, and background play.
6. On API 26/27, expect `legacy` and an explicit UI fallback explanation.
7. Verify when both effects are unavailable, playback remains audible.
8. Confirm no double EQ and no lingering effect resource after Activity teardown.

CI compiles both supported ABIs and exercises JVM cutoff/interpolation tests,
but does not substitute for these device-level measurements.

## Recorded device verification (Moto G — Android 16 / API 36)

### Build provenance & unit gate

- **Commit (`feat/p1-independent-15-band-dsp`):** `765c64d85702de85c5a48bf8c1647fda381b99cb` (`sourceDirty: false`, `versionName: 1.0.0`, `versionCode: 1`, `abis: ["arm64-v8a", "x86_64"]`, `gradle: 9.3.1`, `builtAtUtc: 2026-11-14T07:28:12Z`)
- **APK tested (`build/app/outputs/flutter-apk/app-debug.apk`):** SHA-256 `746d3c09d749c7478abfecb4dad37eb4c2e7935786ddfe4bd9e72831608bcbdc`
- **Target handset:** Moto G (`ZT4222BMWN`, `model: moto g - 2025`, Android `16` / API `36`, `arm64-v8a`)
- **Kotlin JVM tests (`:app:testDebugUnitTest`):** `SovereignEqBandsTest` 5/5 passed (0 skipped, 0 failures), including `stereoReadbackRequiresBothChannelsEnabledAndMatching`.

### Startup & backend attachment (`logcat`)

Every launch logged matching build provenance and attached `dynamics15` with zero duplicate `Equalizer` effect:

- `BOOT: BUILD PROVENANCE: sha=765c64d85702de85c5a48bf8c1647fda381b99cb version=1.0.0(1) abis=arm64-v8a,x86_64 built=2026-11-14T07:28:12Z`
- `SovereignEq15: Attached independent 15-band DSP to session 4281`
- `MainActivity: SOVEREIGN EQ BACKEND: dynamics15 bands=15`
- `flutter: SOVEREIGN FX: session=4281 backend=dynamics15 bands=15`

### Stereo readback & AudioFlinger HAL signal sweep

Tested with synthetic 30-second 48 kHz 16-bit stereo PCM WAV tones (`eq_test_25hz.wav`, `eq_test_1khz.wav`, `eq_test_16khz.wav`) at `-18 dBFS` with `rg_mode=off`, `rg_preamp=0.0`, and `crossfade=0.0`, polling `SovereignEq15` two-channel readback (`channelsMatch=true` across every case) and `dumpsys media.audio_flinger` (`AudioOut_15`):

| Case | Target Band | ch0 / ch1 Readback (`channelsMatch`) | AudioFlinger `Dynamics Processing` State (`Session State Reg Int Ena Susp`) | `Frames written` Delta (~2 s) | Track `PortVol` | HAL 50 ms Power Mean |
|---|---|---|---|---|---|---|
| `flat_25hz` | 25 Hz (`0`: `0.0 dB`) | `[0.0 x 15]` (`true`) | `04281 003 y n y n` (`EffectHal::threadLoop n=131`) | `+102,400` (`66922496 -> 67024896`) | `-40 dB` | `-67.55 dB` |
| `25hz_plus12` | 25 Hz (`0`: `+12.0 dB`) | `[12.0, 0.0 x 14]` (`true`) | `04289 003 y n y n` (`EffectHal::threadLoop n=125`) | `+100,352` (`67254272 -> 67354624`) | `-40 dB` | `-61.49 dB` (`+6.06 dB` vs flat) |
| `25hz_minus12` | 25 Hz (`0`: `-12.0 dB`) | `[-12.0, 0.0 x 14]` (`true`) | `04297 003 y n y n` (`EffectHal::threadLoop n=135`) | `+100,352` (`67608576 -> 67708928`) | `-40 dB` | `-71.16 dB` (`-3.61 dB` vs flat) |
| `flat_1khz` | 1 kHz (`8`: `0.0 dB`) | `[0.0 x 15]` (`true`) | `04305 003 y n y n` (`EffectHal::threadLoop n=122`) | `+102,400` (`67940352 -> 68042752`) | `-40 dB` | `-55.10 dB` |
| `1khz_plus12` | 1 kHz (`8`: `+12.0 dB`) | `[..., 12.0@8, ...]` (`true`) | `04313 003 y n y n` (`EffectHal::threadLoop n=132`) | `+100,352` (`68288512 -> 68388864`) | `-40 dB` | `-48.56 dB` (`+6.54 dB` vs flat) |
| `1khz_minus12` | 1 kHz (`8`: `-12.0 dB`) | `[..., -12.0@8, ...]` (`true`) | `04321 003 y n y n` (`EffectHal::threadLoop n=130`) | `+102,400` (`68636672 -> 68739072`) | `-47 dB` | `-67.20 dB` (`-6.59 dB` vs bypassed at `-47 dB`) |
| `flat_16khz` | 16 kHz (`14`: `0.0 dB`) | `[0.0 x 15]` (`true`) | `04329 003 y n y n` (`EffectHal::threadLoop n=123`) | `+102,400` (`68964352 -> 69066752`) | `-47 dB` | `-53.60 dB` |
| `16khz_plus12` | 16 kHz (`14`: `+12.0 dB`) | `[0.0 x 14, 12.0]` (`true`) | `04337 003 y n y n` (`EffectHal::threadLoop n=119`) | `+102,400` (`69283840 -> 69386240`) | `-47 dB` | `-43.90 dB` (`+9.70 dB` vs flat) |
| `16khz_minus12` | 16 kHz (`14`: `-12.0 dB`) | `[0.0 x 14, -12.0]` (`true`) | `04345 003 y n y n` (`EffectHal::threadLoop n=137`) | `+108,544` (`69634048 -> 69742592`) | `-47 dB` | `-62.30 dB` (`-8.70 dB` vs flat) |
| `bypassed_1khz` | `eq_enabled=false` (`8`: `+12.0 dB`) | `[..., 12.0@8, ...]` `enabled=false` (`true`) | `04353 000 y n n n` (`Enabled=n`) | `+102,400` (`69998592 -> 70100992`) | `-47 dB` | `-60.61 dB` (no `+12 dB` boost, unmuted) |

No `Equalizer` effect was ever registered alongside `Dynamics Processing` (`Loudness Enhancer` stayed disabled in state `000`, `Music Listener` was session-attached, and Moto G global `DAP` ran on session `0`). The OS stepped track `PortVol` from `-40 dB` to `-47 dB` before `1khz_minus12`; comparisons above group cases by matching `PortVol`.

### Persistence, transport, background & teardown checks (`ZT4222BMWN`)

- **Restart persistence:** Seeded custom stereo curve `[6.0, 0.0, ..., -9.0@8, ..., 12.0@14]`, force-stopped, and relaunched without rewriting preferences (`PID 9120`, session `4369`); `SovereignEq15` read back identical gains on both channels (`channelsMatch=true`, `enabled=true`) and resumed playback at `5000 ms`.
- **Seek / track changes & background playback:** Dispatched `fast-forward`/`rewind`/`next` across `eq_test_25hz` → `eq_test_1khz` → `eq_test_16khz`; `Dynamics Processing` stayed active (`04369 003 y n y n`) with no duplicate `Equalizer`. Backgrounded via `KEYCODE_HOME`; session remained `PlaybackState.PLAYING(3)` and `Frames written` advanced `71145472 -> 71247872` (`+102,400`).
- **Teardown & device cleanup:** After `am force-stop com.sovereigntagger`, `dumpsys media.audio_flinger` contained zero lingering `Dynamics Processing` or `com.sovereigntagger` references. Original `FlutterSharedPreferences.xml` (`3054` bytes) was restored byte-for-byte and temporary cache WAVs were deleted.

### Live slider drag, Save & Discard re-smoke (Moto G — `ZT4222BMWN`)

- **Commit (`feat/p1-independent-15-band-dsp`):** `152a5e5280cfd9ea046e38151adb6ee258a3f64a` (`sourceDirty: false`, `versionName: 1.0.0`, `versionCode: 1`, `abis: ["arm64-v8a", "x86_64"]`, `gradle: 9.3.1`, `builtAtUtc: 2026-11-14T08:27:29Z`)
- **APK tested (`build/app/outputs/flutter-apk/app-debug.apk`):** SHA-256 `6bb2b4f53640be3eaafd18d71bdc331642e4250e02bacd5a8688440902987934`
- **Startup & attachment:** Launched `com.sovereigntagger/.MainActivity` (`PID 17745`) playing `eq_resmoke_1khz.wav` (`48 kHz` stereo PCM); logged matching `BOOT: BUILD PROVENANCE` and attached `dynamics15` to session `4433` (`SovereignEq15: Attached independent 15-band DSP to session 4433`, `MainActivity: SOVEREIGN EQ BACKEND: dynamics15 bands=15`).
- **Live upward slider drag:** Navigated `TheaterScreen` → `EqPresetsScreen` and swiped the `25 Hz` slider (`band 0`) upward over `1.2 s`; observed 10 incremental live `SovereignEq15` stereo readbacks (`1.0`, `2.0`, `3.0`, `5.0`, `6.0`, `7.0`, `8.0`, `9.0`, `10.0`, `11.0 dB`, `channelsMatch=true`) before saving while `flutter.eq15_band_0` on disk stayed `0.0`.
- **`SAVE PRESET`:** Tapped `SAVE PRESET` and confirmed `FlutterSharedPreferences.xml` persisted `flutter.eq15_band_0 = 11.0`.
- **Unsaved downward drag + `DISCARD`:** Swiped band `0` downward over `1.0 s` and observed incremental live stereo readbacks (`10.0` down to `-11.0 dB`, `channelsMatch=true`) while `flutter.eq15_band_0` on disk remained `11.0`; tapped AppBar Back (`UNSAVED PRESET`) → `DISCARD`, confirming clean pop back to `TheaterScreen`, native `SovereignEq15` revert to `[11.0, 0.0 x 14]` (`channelsMatch=true`), and `flutter.eq15_band_0 = 11.0` preserved on disk.
- **Teardown & cleanup:** Force-stopped `com.sovereigntagger` (confirming session `4433` teardown in `dumpsys media.audio_flinger` with zero active `Dynamics Processing` effects remaining), deleted temporary cache/staging WAV/XML files, and restored original `FlutterSharedPreferences.xml` (`3054` bytes, SHA-256 `2bbdf28b5e889da0aa198293ba68fced16d2b524119c8171ac399c21f7dbbe02`) byte-for-byte.

### Atomic Save ordering amendment

Each Save captures an immutable fifteen-band curve at the tap and places it in
the same FIFO as live updates. Pending live updates may coalesce; a Save is a
barrier that cannot be replaced. Native application and every preference write
use that captured curve. Only confirmed persistence advances the committed
baseline, and dirty state compares the current sliders with that baseline.
Later edits remain live and unsaved. Multiple Saves commit in tap order.

Navigation remains guarded while any Save is pending. Confirmed Discard freezes
further edits, waits for pending Saves, then restores the last successfully
committed curve. Completion after disposal does not update UI or show feedback.

Preference writes check both false results and exceptions. A failure attempts
to restore all fifteen previous preference values (including absent keys),
keeps the preset dirty, and reports the failure so Save can be retried. A rollback
failure is reported explicitly. This is application-level ordering and recovery,
not a crash-atomic storage transaction across fifteen preference keys.
Native-apply failure is separate: a successfully persisted preset is reported as
saved with a live-EQ failure/unavailable message, not as fully applied.

The deterministic regression matrix covers edits before and during Save, a
Save queued behind a native drag, repeated Save snapshots, guarded Back and
Discard with pending Saves, failed preference writes and retry, exact native and
persisted curves, dirty state, and completion after disposal. Route tests wait
for transition completion rather than assuming the spring settles within its
nominal duration; native and persistence checkpoints use independent Completers.

**Executed local validation (2026-11-14):** Genesis-header/comment/mojibake checks
passed; `flutter analyze --no-pub` passed with no issues;
`flutter test --no-pub` passed **206/206** with zero skips, including **12 added
atomic Save regressions** across `eq15_contract_test.dart` and
`eq_save_recovery_test.dart`; `android/gradlew.bat :app:testDebugUnitTest` executed
and passed **5/5** JVM tests with zero skips. Diff and added-line encoding checks
passed. CI build, ABI and source-to-APK provenance evidence for the pushed head
is linked from PR #86. No new physical-device run is claimed for this amendment.

### Remaining gaps not verified in this sweep

- **Build variant:** Tested local clean-provenance debug APKs (`app-debug.apk` at `765c64d` and `152a5e5`), not the release CI artifact.
- **Acoustic / external loopback & routing:** Gain deltas were observed via Android's internal AudioFlinger `Hal stream dump: Signal power history (resolution: 50.0 ms)` (post-mixer, with system `DAP` active on session `0`) rather than an external speaker/microphone or wired/Bluetooth loopback analyzer; wired/Bluetooth route switching was not exercised in these automated ADB sweeps.
- **API 26–27 `legacy` & `unavailable`/`error` paths:** No physical Android 8.x (API 26–27) handset was tested (`ZT4222BMWN` runs Android 16 / API 36); those fallback and `PlaybackFx` `'error'` recovery paths are covered by unit/contract tests only.
