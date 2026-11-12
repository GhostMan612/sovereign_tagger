# ST-03 — One-shot Whistle to Whisper voice failover

> **Priority:** P1  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
VoiceInput aborts and deletes captured WAV on Whistle prepare/transcribe failure; Whisper is implemented but never selected automatically. x86_64 Whistle JNI intentionally reports unsupported.

- [lib/core/voice_input.dart:206-270](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/voice_input.dart#L206-L270)
- [lib/core/speech_to_text.dart:246-260](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/speech_to_text.dart#L246-L260)
- [android/app/src/main/cpp/CMakeLists.txt](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/cpp/CMakeLists.txt)
- [docs/audit-workorders/voice-ghost-runtime-deadends.md](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/voice-ghost-runtime-deadends.md)

## Intended implementation touch surfaces
- `lib/core/voice_input.dart`
- `lib/core/speech_to_text.dart`
- `lib/core/whisper_model.dart`
- `lib/core/whistle_model.dart`
- `test/voice_fallback_test.dart (new)`

## Detailed work order
1. Introduce injectable SpeechSelectionPolicy with preferred engine, supported engines, allowed fallback sequence and explicit consent for downloading missing weights.
2. Separate engine unavailable, preparation error, transcription error, permission denial, operator cancellation and empty-speech terminal states; fallback only for eligible engine faults.
3. Keep the WAV in private staging until primary and at most one eligible secondary engine have completed; prevent deletion on primary failure and ensure final cleanup after terminal outcome.
4. On unsupported Whistle ABI, select supported Whisper before attempting Whistle and provide a clear user-facing status.
5. Maintain one request identifier, one transcript stream emission and one Ghost handoff, including auto-stop and disposal races. Never auto-send destructive Ghost commands.
6. Preserve existing preferred/forced-engine choices and make fallback status visible to UI; do not download model on splash or silently incur mobile data transfer.
7. Prevent FFmpeg Whisper secondary cancellation from stopping unrelated Workbench/Grabber sessions.

## Negative and regression test matrix
- [ ] Whistle success yields one transcript with no fallback.
- [ ] Whistle load and transcript failure each retry Whisper once with same WAV; both-fail produces error and cleans stage; cancel/permission denied never fallback.
- [ ] x86_64 unsupported Whistle selects Whisper without crash; rapid tap, timeout and widget dispose do not duplicate or leak WAV.

## Acceptance criteria and evidence required
- [ ] One transcript only, deterministic no-surprise-download behavior and retained audio across fallback.
- [ ] Instrumented Moto G voice-to-Ghost and emulator unsupported-ABI smoke tests.
- [ ] No new background audio capture on cancellation.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
Coordinate model digest/availability work order #04, but keep policy testable independently.

## Rollback / failure policy
Feature-flag policy returns to explicitly selected engine; no data migration.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
