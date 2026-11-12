# ST-14 — Versioned FFmpegKit, Chaquopy, Kotlin and Flutter compatibility matrix

> **Priority:** P2; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
FFmpegKit Extended, Chaquopy, Gradle, AGP, Kotlin, Flutter and Python pins evolve independently; major native upgrades may break codec/filter availability, wheel imports and ABI builds despite Dart CI green.

- [`pubspec.yaml`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/pubspec.yaml)
- [`pubspec.lock`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/pubspec.lock)
- [`android/build.gradle`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/build.gradle)
- [`android/settings.gradle.kts`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/settings.gradle.kts)
- [`android/gradle/wrapper/gradle-wrapper.properties`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/gradle/wrapper/gradle-wrapper.properties)

## Files proposed for the implementation PR(s)
- `docs/dependencies/compatibility-matrix.md (new)`
- `pubspec.yaml (only in follow-up code PR)`
- `android/build.gradle (only in follow-up)`
- `android/settings.gradle.kts (only in follow-up)`

## Ordered implementation workchain
1. Record exact existing lockfile/plugin/Gradle/AGP/Kotlin/NDK/Chaquopy/Python versions and upstream support matrices at audit date, distinguishing verified from claimed compatibility.
2. Benchmark ffmpeg_kit_extended_flutter 0.6.2 baseline vs 1.x in isolated branches; explicitly map config migration from current full+gpl block and all relevant changed APIs.
3. Record required 548-ish runtime filter inventory from a live device rather than assumed count; test whisper, rubberband, soxr, libx264, subtitle, mux and FFprobe surfaces.
4. Evaluate Chaquopy 17.2 vs 17.0.0 under Python 3.14 and pinned yt-dlp/mutagen/lyricsgenius wheels, checking native Gradle plugin compatibility.
5. Build exact matrix against ARM64 and x86_64, smoke 15-band EQ, M4A mux, video decode, Whisper STT and background playback.
6. Use separate small version-bump PRs per plugin or coherent platform lockstep, not a single wholesale upgrade.
7. Pin upstream release artifacts and collect binary hashes, package/license changes and performance regression data.

## Negative and regression test plan
- [ ] Clean offline-ish reproducible dependency resolution with lockfile; no mixed plugin versions.
- [ ] ABI compile, native model and DSP runtime smoke for each candidate matrix.
- [ ] Measure startup RAM, FFmpeg filter availability, warm import time, download/Forge parity and APK size.

## Acceptance / evidence gates
- [ ] Only upgrade to a candidate after matrix demonstrates no capability or licensing regression.
- [ ] Version pins and reasons captured; rollback commands documented.
- [ ] GitHub native CI and physical device evidence.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
Native CI work order ST-06; packaging ST-15 and licensing ST-16.

## Rollback / operator preservation
Restore pinned baseline lockfiles and Gradle coordinates; keep ABI/release artifacts reproducible.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
