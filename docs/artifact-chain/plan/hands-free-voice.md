# Plan: Hands-free Ghost voice

Status: DRAFT — awaiting spec approval (Build gate)
Spec: `spec/hands-free-voice.md`. Intent: `intent/hands-free-voice.md`.
No implementation is authorized by this plan alone; approval of the spec
authorizes implementation, task by task, with review per `review/REVIEW.md`.
Repo law: stage by explicit path, approval before commit/push, `main` only.

## Task order

### T1 — Verify and integrate the shipped Phase 33 embedding mechanism (spec R4, decision D1 closed by event)
Files: `lib/core/embedding_service.dart`, `lib/services/ghost_brain.dart`,
`lib/services/ghost_vector_index.dart`, `lib/core/embedding_model.dart`,
`lib/core/model_lifecycle.dart`,
`android/app/src/main/kotlin/com/sovereigntagger/EmbeddingGemmaBridge.kt`,
`MainActivity.kt` (channel handler).
- Phase 33 already built the native bridge; this task verifies it instead
  of rebuilding it: channel name, method names, and argument keys match
  on both sides (verified in code 3 November 2026 — re-verify if the code
  moves); epoch/space-locking holds on every path, including a simulated
  mid-request engine flip; a `ghost_vectors.bin` index written under the
  other engine rebuilds or refuses, never compares across spaces; with no
  model weights on device, the hash fallback governs end to end.
- Add the regression check (test or static trace) that pins the above; no
  mixed-space path may remain, and no new embedding path may be
  introduced.
- Done when: the check passes and the mechanism is confirmed as the basis
  for T3's intent gate.
- Proof: A4.

### T2 — Automatic Whisper fallback + engine visibility (spec R3)
Files: `lib/core/voice_input.dart`, `lib/core/speech_to_text.dart`,
`lib/core/whistle_model.dart`, `lib/widgets/ghost_chat_overlay.dart`,
`lib/core/ghost_settings.dart`.
- Engine selection at voice-start: Whistle attempt → automatic Whisper
  fallback on load/ABI/model failure; active engine shown in the overlay;
  `useEngine` wired to a settings preference that fallback still
  overrides on failure.
- Done when: forcing the Whistle failure path still yields a working
  voice command via Whisper, with the engine label correct.
- Proof: A2, plus a host test for the selection logic where the native
  layer can be faked.

### T3 — Silence detection + automatic send (spec R1, R2, decision D2)
Files: `lib/core/voice_input.dart`, `lib/core/pcm_recorder.dart`,
`lib/widgets/ghost_chat_overlay.dart`, `lib/services/ghost_brain.dart`
(intent gating only), `lib/core/ghost_commands.dart` (intent gating only).
- End-of-speech detection with the spec's proposed defaults; 12-second
  cap kept; transcript submitted automatically; transcript visible as
  processed; D2 allowlist enforced at the intent gate — destructive
  intents always confirm, even when auto-sent.
- Done when: a read-only voice command completes with zero taps, and a
  destructive voice command cannot execute without confirmation.
- Proof: A1, A3. This is the task the Plan/Build/Review separation
  applies to most strictly: independent review pass required.

### T4 — WAV and lifecycle hardening (spec R5)
Files: `android/app/src/main/kotlin/com/sovereigntagger/WhistleBridge.kt`
(WAV parsing), `lib/core/voice_input.dart` (stop handling),
`lib/core/whistle_model.dart` (threshold constant), native dispose path
(`nativeReset`), ducking owner (`lib/services/ghost_world.dart` /
audio handler wiring).
- Sample-rate check/resample-or-reject, chunk padding, explicit stereo
  policy; honor `PcmRecorder.stop()` result; call `nativeReset` on
  dispose; single model-size constant; single ducking owner with exact
  volume restore.
- Done when: each item has a regression test or a documented device
  check.
- Proof: A5 (native items), device smoke notes.

### T5 — Settings/UI polish for the voice path
Files: `lib/widgets/ghost_chat_overlay.dart`, `lib/core/ghost_settings.dart`.
- Engine label, engine preference control, failure messaging from R3.
  Small task; may fold into T2 if the diff stays reviewable.
- Done when: Glenn can see and change the engine preference and read a
  failure in plain words.

### T6 — README and blueprint accuracy (spec R6)
Files: `README.md`, `.blueprints/` engine-status notes only.
- Remove stale Whisper-live/Whistle-unwired wording; describe shipped
  behavior and the fallback.
- Done when: README matches A6.

### T7 — Host verification gate
- Run on Glenn's host: `flutter analyze`, `flutter test`. Fix failures in
  the same change; do not merge with a red gate.
- Chain-consistency check: every spec requirement traces to a task and a
  test/device check; no orphan tasks.
- CI note: the Dart workflow is red at dependency install since
  25 October 2026 (pre-existing). The host gate above is authoritative;
  do not treat a red CI run as this change's failure, and do not merge
  on CI status alone.

### T8 — Moto G device smoke test (closes the device-proof rule)
- Fresh install/upgrade on the Moto G (ARM64): A1 read-only voice
  command, A2 fallback path, A3 destructive-confirmation, silence
  behavior in a normal room and a noisy room, 12-second backstop — plus
  the Phase 33 paths: native embeddings active (model weights present,
  GEMMA badge shown), fallback with weights absent, RAM lifecycle (idle
  unload, unload before a heavy job), and vector-index search returning
  same-space results.
- Record results (pass/fail per criterion, device, build) in the PR or
  in `.blueprints/` verification notes. A code review alone does not
  close this task.

## Order-of-work notes

- T1 before T3: the intent gate in T3 depends on routing behaving
  consistently. T1 is verification-heavy by design: the mechanism shipped
  in Phase 33; T1's job is to prove it, not to rebuild it.
- T2 before T3: auto-send must never be tested against an engine that
  silently fails.
- T4 may run in parallel with T2/T3 (different files), but its native
  changes join the same device smoke test (T8).
- If any task's diff grows past one reviewable change, split it; do not
  bundle unrelated hardening into the auto-send task.

## Risks carried into the build

- Silence tuning is device work (see spec Risks). T8 owns it.
- D2 undecided blocks T3 only; T1/T2/T4 may proceed once the spec is
  approved with D2 deferred to its default (confirm destructive).
