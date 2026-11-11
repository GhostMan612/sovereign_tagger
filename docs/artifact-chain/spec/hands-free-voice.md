# Spec: Hands-free Ghost voice

Status: DRAFT — awaiting Glenn's approval (Design gate)
Intent: `intent/hands-free-voice.md` (accepted version governs; if intent
and spec disagree, intent wins and the spec is revised)
Source evidence: full-code audit, 26 October 2026, clone HEAD `1c52bdd`;
Phase 33 verified 3 November 2026 at HEAD `01eb25f` (commit 2 November
2026). All file paths verified against those revisions. No code changed
by this spec.

## What this spec defines

The technical requirements and expected behavior for hands-free Ghost
voice: speak → silence-detected stop → automatic send → GhostBrain
response, with automatic Whisper fallback and one embedding source of
truth. It does not define TTS, knowledge-base changes, or any Grabber /
Forge / Workbench behavior.

## Current behavior (verified in code, not on device)

The voice chain is wired end to end in source: mic in
`lib/widgets/ghost_chat_overlay.dart` → `lib/core/voice_input.dart` →
`PcmRecorderBridge.kt` → `WhistleBridge.kt` / `sovereign_whistle.cpp`
(`needle_load`, `needle_transcribe`) → `VoiceInput.onTranscript` → query
field → `GhostBrain.respond` only after manual send. Whistle is the
preferred engine in `lib/core/speech_to_text.dart`; Whisper is retained
as a fallback engine. The ARM64 native build was verified (Phase 31
docs); the device smoke test was still pending at 15 October 2026.

Phase 33 (2 November 2026, verified in code 3 November 2026) added the
native embedding path the audit found missing: `EmbeddingGemmaBridge.kt`
(LiteRT 1.4.0, XNNPACK 4-thread CPU, memory-mapped model) plus a
pure-Kotlin SentencePiece tokenizer, registered on
`com.sovereign.tagger/embeddings` (`isAvailable`, `status`, `loadModel`,
`unloadModel`, `embedText`, `embedBatch`) in `MainActivity.kt`, with
`onTrimMemory`/`onDestroy` lifecycle wiring. `embedding_service.dart` and
`ghost_brain.dart` were rewritten around engine IDs (native = 2, fallback
= 1) with epoch-tagged caches and space-locked comparisons (gotcha G48),
plus a persistent `GhostVectorIndex` (`ghost_vectors.bin`, `GVEC`,
engine-ID-locked) and a RAM lifecycle (external model files, idle unload,
unload before FFmpeg/Whisper jobs). The model weights themselves are
external (Hugging Face download or local import); with no weights on
device, the native path is inactive and the hash fallback governs. Device
proof for Phase 33 is still pending.

## Requirements

### R1 — Automatic send after transcription
- When transcription completes, the transcript is submitted to
  `GhostBrain.respond` without a send tap.
- The submitted text is shown in the overlay exactly as it will be
  processed, before or as it is submitted, so Glenn can see what Ghost
  heard.
- Manual send still works; typed queries are unaffected.

### R2 — Silence-detected stop, 12-second cap kept
- Recording ends on detected end-of-speech, not only on the 12-second
  auto-stop. The 12-second cap remains as a backstop for continuous
  speech.
- Proposed defaults (tune on device): energy-based voice activity
  detection over the PCM stream, ~800 ms of trailing silence ends the
  utterance. Final values are set from the Moto G smoke test, not from
  this spec.
- If silence is never detected, behavior degrades exactly to today's
  12-second behavior.

### R3 — Automatic Whisper fallback
- Engine selection is automatic at voice-start: attempt Whistle load; on
  load failure, unsupported ABI, or missing/corrupt model, fall back to
  Whisper with no user action.
- The active engine is visible in the overlay (e.g. a small engine label)
  so Glenn always knows which engine heard him.
- The existing manual `useEngine` path is wired to a settings/UI control
  instead of remaining dead code: the UI control sets a *preference*;
  automatic fallback still overrides the preference on failure.
- Both engines failing produces a clear, non-crashing state: overlay
  stays usable for typed queries, and the failure is surfaced in words
  (which engine failed, and why, at the level the platform reports).

### R4 — One embedding source of truth (shipped in Phase 33; verify, don't rebuild)
- The shipped Phase 33 mechanism is the source of truth: native engine
  (ID 2) when the bridge is loaded, deterministic hash fallback (ID 1)
  otherwise, with epoch-tagged caches and same-space comparison enforced
  (G48).
- No call site may mix a native embedding with a hash-fallback embedding
  in one comparison — including across a mid-request engine flip (e.g. an
  OOM unload switching engines mid-request) and including vectors read
  back from the persisted `ghost_vectors.bin` index, whose header engine
  ID must match the active engine or trigger a rebuild.
- The hands-free change adds no new embedding path; it verifies the
  shipped one (see plan T1) and must not reintroduce a mixed-space path.
- Decision D1 is closed by event (see below); the invariant above is not
  negotiable.

### R5 — WAV and lifecycle hardening (audit medium items)
- `WhistleBridge.readWavToFloatArray`: check the parsed sample rate
  against the rate the engine expects (resample or reject loudly, never
  silently misinterpret); handle odd-sized chunk padding; define the
  stereo policy explicitly (documented: downmix or left-channel, chosen
  deliberately, not by accident).
- `VoiceInput` honors the return value of `PcmRecorder.stop()` so a
  recording is never transcribed from an unfinalized WAV header; on a
  failed stop, the attempt is discarded and reported, not transcribed.
- `nativeReset` is called on the appropriate dispose path so the Whistle
  model does not stay memory-mapped after the voice session ends.
- The Dart/Kotlin model-size thresholds are unified into a single
  constant, owned in one place, with the same value on both sides
  (today: Dart ≥ 16,000,000 bytes vs. Kotlin rejecting only < 10,000,000).
- Volume ducking has a single owner during recording: resolve the
  `AppGhostWorld` absolute-0.18 duck vs. the `audio_handler` 25%-of-pre-duck
  duck so an interruption mid-recording cannot produce two competing
  duck states. Whichever owns it, the pre-duck volume is restored exactly.

### R6 — README accuracy
- The README describes the engine that ships: Whistle preferred/offline,
  Whisper automatic fallback, hands-free behavior as implemented. The
  "Whisper live / Whistle unwired" wording is removed.
- Phase/verification notes in `.blueprints/` are updated only where they
  state engine status; no blueprint rewrite is in scope.
- The README also describes the EmbeddingGemma native engine: what it is,
  that the model files are downloaded/imported separately (not bundled),
  and that the hash fallback governs when they are absent.

## Decisions required (Design gate)

- **D1 — Embedding mechanism: DECIDED BY EVENT, 2 November 2026.** Option
  A shipped in Phase 33 (commit `01eb25f`): native
  `EmbeddingGemmaBridge.kt` + `SentencePieceTokenizer.kt`, channel handler
  in `MainActivity.kt`, Dart rewrite with engine-ID/epoch locking
  (verified in code 3 November 2026). Option B (unify on the hash
  fallback) is superseded. What remains for the Design gate is Glenn's
  acknowledgment that the shipped mechanism is the basis for this change
  — not a re-decision of the mechanism. If Glenn rejects the shipped
  mechanism, that is a reversal: record it and re-run the gates.
- **D2 — Auto-send allowlist.** Which intent classes execute without
  confirmation vs. always confirm (see intent open question 1). Default:
  confirm everything destructive or irreversible; auto-send read-only
  (playback control, navigation, queries). Glenn decides; the default
  applies if he defers.
- **D3 — Silence defaults.** Accept the R2 proposed defaults for the
  first device run, or set different values before implementation.

## Acceptance criteria

- A1: On the Moto G, speaking a read-only command produces a Ghost
  response with zero taps, and the transcript shown matches what was
  processed.
- A2: With Whistle disabled/unavailable (test by a build or device state
  that forces the failure path), the same command still works via
  Whisper, and the overlay shows the Whisper engine active.
- A3: A destructive voice command (delete) is never executed without the
  confirmation required by D2, including on a deliberately misheard
  transcript in testing.
- A4: A unit/integration check demonstrates that exemplars, knowledge
  base, live queries, and persisted index vectors share one embedding
  space on every path — including a simulated mid-request engine flip
  and an index file written under the other engine (rebuild or refusal,
  never a mixed comparison).
- A5: `flutter analyze` clean; `flutter test` green on host; the R5
  hardening items each have a regression test or a documented device
  check where a unit test cannot reach (native WAV handling).
- A6: README engine description matches the shipped behavior; no stale
  Whisper-live/Whistle-unwired wording remains.

## Risks

- Silence detection tuned on one device/room may misfire in noise; the
  12-second backstop and visible transcript mitigate, but tuning is a
  device task, not a code-review task.
- Automatic fallback adds a second engine's failure modes to the voice
  path; R3's failure-surfacing requirement exists to keep failures
  visible instead of silent.
- Auto-send changes a deliberate safety property (manual send). D2 is
  the control; if D2 is not decided, implementation does not start.
- The Dart CI workflow has been red at the dependency-install step since
  25 October 2026 (before Phases 32/33); it never reaches analyze or
  tests. The host gate (plan T7) is authoritative until CI is fixed; a
  red CI run alone neither proves nor blocks this change.
- The native embedding path is inactive until model weights are present
  on device (download or import). Every native-active behavior must
  degrade to the hash fallback with the fallback governing comparisons —
  never to a silent mixed-space result.

## Explicitly not changed

- `LngLat`/geometry code, Grabber, Forge, Workbench DSP, player
  internals, backup/restore, theming. Kotlin handlers with no Dart caller
  (`describeMedia`, `scanFile`, `getDoctorRegistry`) are noted, not
  removed, in this change.
- No new permissions. No new network calls and no new native libraries
  *from this change* — Phase 33 already added the LiteRT native library
  and the optional Hugging Face model download; this change adds nothing
  further on either count.
