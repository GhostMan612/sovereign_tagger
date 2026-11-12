# Audit work order — Voice and Ghost runtime dead ends

**Baseline:** `main` at `ba708fe` (2026-11-12)
**Status:** specification only; implementation deferred for focused review
**Scope:** `lib/core/voice_input.dart`, `lib/core/speech_to_text.dart`, `lib/core/ghost_memory.dart`, `lib/screens/main_shell.dart`, `lib/widgets/ghost_chat_overlay.dart`, and tests.
**Related chain:** `docs/artifact-chain/{intent,plan,spec}/hands-free-voice.md`.

## V1 — Preferred Whistle engine has no automatic Whisper fallback (P1)

### Source evidence
- `VoiceInput._stopAndTranscribe` returns `null` when `_engine.prepare()` fails.
- Its `_engine.transcribe(path)` catch block sets `TRANSCRIBE ERROR`, deletes the captured WAV, and returns `null` without attempting a second engine.
- `SpeechEngines` already exposes both `WhistleEngine` and `WhisperFfmpegEngine`, but availability alone is not fallback.
- `VoiceInput.useEngine(id)` is implemented; default app caller/search evidence contains no production call to it.
- The existing hands-free voice artifact chain specifies automatic fallback, but its acceptance conditions are not implemented in these paths.

### Implementation plan
1. Add a single engine-selection policy that records configured preference, chosen engine, and fallback eligibility without invoking model downloads on app startup.
2. On Whistle model-load or transcription failure (not user cancellation or permission denial), preserve the WAV and attempt Whisper **once**. Do not delete the WAV until fallback is complete or abandoned.
3. Keep request-ID/cancellation guards across both attempts. Never dispatch duplicate transcripts or mutate Ghost state after cancellation.
4. Expose active engine and reason for fallback in Ghost overlay; add persistent optional engine preference and an operator-visible fallback disable switch if needed.
5. Normalize errors once at the orchestration boundary; keep a clear failure reason if both engines fail.

### Acceptance gates
- Whistle success → one transcript, no Whisper invocation.
- Whistle prepare failure → Whisper success → one transcript.
- Whistle transcribe failure → Whisper success → one transcript.
- Cancel during fallback → zero transcript, no stale WAV.
- Both fail → actionable status; no silently empty result.
- No model download or new blocking initialization at splash startup.
- Instrumented recording-to-Ghost voice response smoke test on Android ARM64.

## G1 — GhostMemory play history is persisted but unwired (P2)

### Source evidence
`lib/core/ghost_memory.dart` contains `GhostMemory.recordPlay()`, `history`, `artistCounts`, and name-correction persistence. Current symbol search finds `GhostMemory` only in its module and `test/ghost_foundations_test.dart`. The live player calls `PlaylistStore.recordPlay(path)` in `main_shell.dart` instead; therefore the Ghost-specific play history is not populated by actual playback.

### Implementation plan
1. Decide whether Ghost recommendations are allowed to learn from play history and document an opt-in privacy default.
2. If enabled, connect `GhostMemory.recordPlay` to a single authoritative playback transition from `AudioService`; do not increment on every widget rebuild or pause/resume.
3. Include available title and artist metadata, handle cloud/local URIs, and dedupe replay events.
4. Expose a clear-history control using the existing `GhostMemory.forgetAll()`; prohibit writing playback history to logs.
5. If product decision is to avoid this data entirely, prune the unused memory module and its tests instead of retaining misleading functionality.

### Acceptance gates
- One completed track transition generates no more than one play record.
- Rebuild/reopen and pause/resume do not increment counts.
- History survives restart and can be cleared completely.
- Cloud and local paths are handled consistently; no unknown-path collisions.
- No background recording unless enabled by the operator.

## Review boundary

This PR changes only the work-order specification. It does **not** claim the fallback or Ghost play-memory integration is implemented, and it must not be merged as functional completion. Execute each runtime change in a separate child PR with tests and hardware evidence.
