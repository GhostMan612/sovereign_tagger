# ST-18 — Establish integration, fault-injection, and device evidence gates

> **Priority:** P2; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
Textual DSP fixtures and synthetic queue mocks do not prove native FFmpeg rendering or ContentResolver transactions. CI covers Dart/Python but important Android failures and two-session cancellation aren't exercised.

- [`.github/workflows/dart.yml`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.github/workflows/dart.yml)
- [`test/workbench_queue_test.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/test/workbench_queue_test.dart)
- [`test/workbench_dsp_test.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/test/workbench_dsp_test.dart)
- [`test/backup_crypto_test.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/test/backup_crypto_test.dart)
- [`docs/artifact-chain/CHAIN.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/artifact-chain/CHAIN.md)

## Files proposed for the implementation PR(s)
- `docs/verification/acceptance-matrix.md (new)`
- `test/workbench_ffmpeg_integration_test.dart (new implementation)`
- `android/app/src/androidTest/** (new)`
- `test/python/test_updater_transaction.py (new)`

## Ordered implementation workchain
1. Define multi-gate artifact chain: static analysis, Dart unit/widget tests, Python isolated tests, native Kotlin/NDK build, Android integration, physical devices, and release/security evidence.
2. Add disposable synthetic WAV/M4A/MP4/FLAC fixtures and actual FFmpegKit job execution/probe assertions for output container, audio/video presence and metadata.
3. Build fault-injected fake MediaStore provider and Kotlin integration tests for null/partial streams, equal-length corruption, publish failure, recovery and readback.
4. Exercise two real executor-owned FFmpeg jobs with controlled barriers so cancellation can't accidentally kill an unrelated owner.
5. Build an automated Dart/Kotlin MethodChannel contract inventory; compare handlers, callers, names, error envelopes and payload shapes.
6. Record tests of pCloud US/EU sign-in, TLS/CDN redirects, consent, OAuth intercept, backup migration on Moto G/BLU; never require production tokens in CI.
7. Ensure no destructive updater tests touch live app packages; only fake sandbox targets are used.
8. Create concise reproducible evidence packet per implementation PR, including exact commands, dates, device IDs withheld from public logs, SHA and known failures.

## Negative and regression test plan
- [ ] CI purposely broken Kotlin import, method-name mismatch, malformed FFmpeg output, provider corruption and unsupported Whistle ABI each fail appropriate gate.
- [ ] Observe complete synthetic FFmpeg render and in-app save readback, not just argument-string comparison.
- [ ] Device manual checklist separates verified, blocked, skipped and not run.

## Acceptance / evidence gates
- [ ] No 'full native verified' claim from Flutter unit tests alone.
- [ ] Each security/data-loss implementation PR has negative tests with concrete evidence.
- [ ] Release sign-off requires signed identity, app install/update and provider smoke.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
ST-06 native CI foundational; parallel with all implementations.

## Rollback / operator preservation
Mark unsupported/offline hardware test explicitly pending; never fabricate green from omitted tests.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
