# ST-27 — Establish measured startup, DSP, vector, shader and APK performance budgets

> **Priority:** P2 · **Status:** SPEC-ONLY / NOT IMPLEMENTED · **Audit commit:** `0253a994`

## Verified risk / scope
The app runs Python/FFmpeg, 3D effects, local embeddings and audio playback on memory-constrained phones, but audit evidence does not establish reliable latency, memory, thermal or file-size budgets. Optimization without profiles risks deleting features for cosmetic gains.

- [`lib/services/ghost_brain.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_brain.dart)
- [`lib/core/embedding_service.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/embedding_service.dart)
- [`lib/services/ghost_vector_index.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_vector_index.dart)
- [`lib/core/ffmpeg_executor.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/ffmpeg_executor.dart)
- [`lib/widgets/cyber_backdrop.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/widgets/cyber_backdrop.dart)
- [`lib/screens/main_shell.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/main_shell.dart)
- [`android/app/build.gradle`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/build.gradle)

## Intended code and artifact surfaces
- `docs/performance/budgets-and-benchmarks.md (new)`
- `test/performance/** (new implementation)`
- `scripts/perf/collect_android_baseline.py (new implementation)`

## Ordered detailed work order
1. Choose representative low-memory Moto G and BLU devices plus x86 emulator; record OS/build, battery/thermal conditions, app build SHA and cold-start protocol without publishing private device identifiers.
2. Measure splash to UI, time-to-first-audio, 1s UI frame percentiles, shader GPU cost and tab navigation across repeated cold/hot starts.
3. Record FFmpeg job concurrency, memory peaks, device thermal throttling and content-probe latency for common Workbench operations using synthetic media fixtures.
4. Benchmark EmbeddingGemma native vs fallback text embeddings, index warm-up, first query, repeated query and model unload/reload on 4GB-ish RAM devices.
5. Benchmark Python grabber/Forge metadata end-to-end with offline fixtures for repeatability, then optional public network smoke with quota/consent constraints.
6. Break APK size down by ABI, FFmpeg native libraries, Python wheels, Whistle model and assets; separate source repo size from installed size.
7. Set performance guardrail thresholds from observed baseline (not fabricated numbers) and design profiler-driven changes, prioritizing duplicated caches/async stalls/overdraw over deleting functions.
8. Track regressions in CI microbenchmarks only when stable; require device-gated decisions for GPU/audio tests.

## Test matrix, failure injection and safety cases
- [ ] Repeat cold/warm runs with enough samples to report p50/p95 and confidence/variance.
- [ ] Baseline Full vs Lean and before/after each extracted Stage C component without background data changes.
- [ ] Synthetic workload ensures no user recording/text or credential enters benchmark traces.

## Required closeout evidence
- [ ] Published benchmark table with exact SHA, hardware class and methodology.
- [ ] Each proposed optimization has measurable target, baseline and proof of no feature regression.
- [ ] No APK savings or latency claims drawn solely from source line-count reduction.
- [ ] Separate code PR reviewed, exact SHA documented, CI and applicable native/device tests independently observed.
- [ ] No security or performance claims upgraded from inferred to verified without real measurement or upstream docs.

## Dependency chain
ST-15 packaging and ST-19–ST-24 decompositions; native build ST-06.

## Rollback/compatibility
Optimization is feature-flagged or revertible and always compared against baseline preserved in artifacts.

## Scope control
This PR is a reviewed specification, not an implemented repair. Follow the project artifact chain and keep any unproven deletions, network changes, or data-sensitive behavior out of the first mechanical implementation slice. Maintain history and explicit test provenance.
