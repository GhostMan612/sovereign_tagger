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
