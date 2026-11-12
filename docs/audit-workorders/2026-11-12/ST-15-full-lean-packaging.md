# ST-15 — Measure APK size and design explicit Full versus Lean distributions

> **Priority:** P2; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
Source contains large speech/ACRCloud binaries, a full+gpl FFmpeg suite and Python; reported APK size is stale, and undocumented trimming might disable features or break runtime on unsupported ABIs.

- [`pubspec.yaml`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/pubspec.yaml)
- [`android/app/build.gradle:26-110`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/build.gradle)
- [`android/app/src/main/cpp/CMakeLists.txt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/cpp/CMakeLists.txt)
- [`assets/models/README_MODEL_HERE.txt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/assets/models/README_MODEL_HERE.txt)

## Files proposed for the implementation PR(s)
- `docs/build/size-budget.md (new)`
- `android/app/build.gradle (implementation follow-up)`
- `pubspec.yaml (implementation follow-up)`
- `docs/build/flavors.md (new)`

## Ordered implementation workchain
1. Measure release APK and AAB size by ABI and contribution: native .so/.a, Chaquopy wheels, FFmpeg, Cactus Whistle, ACRCloud, fonts/assets, Flutter code and models.
2. Verify that Whisper 141MB weights are not tracked/bundled in current tree before attributing artifact growth; report measured, not speculative, savings.
3. Define stable Full profile preserving all capabilities and optional Lean profile with explicit operator-consented exclusions and clear unsupported-feature UI.
4. Use ABI splits/APK analyzer and build outputs to isolate arm64-v8a and x86_64, verifying arm64 Whistle native and x86_64 stub behavior.
5. Audit bundled x86/armeabi ACRCloud files vs ndk.abiFilters actual packaging; never remove an architecture just because current phone is ARM64.
6. Compare alternative FFmpeg license/filter bundles only against a source-grounded feature dependency matrix; prevent silent loss of DSP filters.
7. Provide performance/storage tradeoff table: size, startup time, RAM, first-run asset download, offline behavior, update size, distribution compatibility.

## Negative and regression test plan
- [ ] Per-ABI clean install and full/lean smoke matrix; missing Lean feature reports disabled rather than crashing.
- [ ] Essential media workflows pass Full profile: PCM, mux, EQ, ASR, Forge, ACRCloud where configured.
- [ ] Output APK/ AAB actual bytes and compressed/uncompressed totals are recorded for each build.

## Acceptance / evidence gates
- [ ] No unmeasured size-saving claims or silent capability loss.
- [ ] Full remains parity baseline and Lean is explicitly opted into.
- [ ] Upstream licenses, artifact provenance and model distribution constraints recorded.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
ST-06 native builds, ST-14 dependency candidate matrix, ST-16 license review.

## Rollback / operator preservation
Maintain canonical Full flavor and disabled Lean variant until parity/smoke passes.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
