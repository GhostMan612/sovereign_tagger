# Intent: Hands-free Ghost voice for Sovereign Tagger

Status: DRAFT — awaiting Glenn's acceptance (Plan gate)
Origin: Glenn's stated goal, 26 October 2026: speak and have GhostBrain
respond without tapping stop or send after transcription.
Source evidence: full-code audit, 26 October 2026, clone HEAD `1c52bdd`
(51 Dart files, 19,044 lines). Revised 3 November 2026: Phase 33 (commit
`01eb25f`, 2 November 2026) shipped the native EmbeddingGemma bridge;
problem 4 and open question 3 updated accordingly — see Revisions. No
code changed by this intent.

## Title

Hands-free Ghost voice: speak, and Ghost responds — no stop tap, no send tap.

## Problems

1. Today a voice transcript only fills the query field. `GhostBrain.respond`
   runs only after a manual send. Glenn must tap send for every voice
   command.
2. Stopping requires waiting out a fixed 12-second auto-stop. There is no
   silence detection, so short commands waste the wait and long commands
   risk being cut.
3. Whistle is the preferred offline engine in code, with Whisper kept as
   fallback — but the fallback is never automatic. `useEngine` exists in
   `lib/core/voice_input.dart` and is never called anywhere in `lib/`, so
   if Whistle cannot load, voice fails instead of falling back.
4. GhostBrain's intent routing ran on two different vector spaces: the
   cross-tab path awaited the native embedding when available, while intent
   exemplars and the knowledge base always used the hash fallback. Phase 33
   (2 November 2026, commit `01eb25f`) shipped the native bridge and
   rewrote routing with engine-ID/epoch space-locking (gotcha G48), so the
   mismatch is addressed in code — but the hands-free change must build on
   that shipped mechanism and verify it on device, not re-decide it. The
   remaining risk is a mid-request engine flip (e.g. an OOM unload) or a
   stale persisted index comparing across spaces.
5. The README still describes Whisper as live and Whistle as "registered
   but not wired," which is outdated relative to the code and the Phase 31
   docs. Anyone reading the README gets the wrong engine story. Still true
   after both 2 November 2026 commits (Phases 32/33): neither touched the
   README.

## Proposed outcomes

- Glenn speaks a command; recording ends on silence (12-second cap kept as
  a backstop); the transcript is sent to GhostBrain automatically; Ghost
  replies or acts without any tap.
- If Whistle cannot load or the device does not support it, Whisper takes
  over automatically, and the active engine is visible in the UI.
- Intent routing uses one embedding source of truth everywhere, so
  exemplars, knowledge base, and live queries are always compared in the
  same space.
- The README describes the engine that actually ships.

## Affected users

Glenn, on his Moto G (ARM64), using Tagger offline. No other user is in
scope for this change.

## Constraints

- **Safety first, and non-negotiable:** Ghost can play and delete real
  media. A misheard command must never execute unreviewed. Auto-send must
  therefore distinguish intent classes (see Open questions). The current
  manual-send behavior exists for exactly this reason (README rationale).
- Offline-first: Whistle stays the preferred engine; no network dependency
  may be introduced for the voice path.
- No new Android permissions unless a requirement demands one (none
  identified).
- Verification limits: this environment has no Flutter/Android toolchain,
  so `flutter analyze`, unit tests, and any device run happen on Glenn's
  host and Moto G. A code-only review never proves device behavior; the
  Phase 31 docs record the ARM64 build as verified but the device smoke
  test as still pending (15 October 2026), and the 6 October partial
  voice proof predates the Whistle switch. Phase 33 (2 November 2026)
  likewise records its device smoke test as pending, and the Dart CI
  workflow has been red at dependency install since 25 October 2026
  (pre-existing; the host gate is authoritative).
- Repo law: `main` is the single canonical branch; stage by explicit path;
  no commit/push without explicit approval; no secrets in commits.

## Open questions (must be answered before the spec is approved)

1. **Auto-send allowlist:** which intent classes may execute on voice
   without confirmation (e.g. playback control, navigation, read-only
   queries), and which always require confirmation (delete, overwrite,
   share, anything destructive or irreversible)? Default if unanswered:
   confirm everything destructive; auto-send read-only only.
2. **Silence detection:** end-of-speech threshold and hang time — pick
   values, or accept the spec's proposed defaults and tune on device?
3. **Embedding source of truth:** ANSWERED BY EVENT — Phase 33 shipped the
   native bridge (spec §D1, decided). The remaining question is
   verification: does the shipped engine-ID/epoch locking hold on device,
   including a mid-request engine flip and a persisted index written under
   the other engine?
4. **Failure surfacing:** when both engines fail, what does Glenn see, and
   does the overlay stay usable for typed queries?

## Non-goals

- Text-to-speech. The chain is voice-in, text reply/actions out; TTS is a
  separate intent if Glenn wants it.
- Changing the GhostBrain knowledge base or intent taxonomy beyond what
  the embedding fix requires.
- Any change to Grabber, Forge, Workbench, or the player beyond the voice
  path and the shared embedding service.

## Revisions

- **3 November 2026** (Phoenix, from Glenn's approval to update the chain
  for Phase 33): the native EmbeddingGemma bridge shipped, so problem 4
  and open question 3 were revised — the mechanism decision (spec D1) is
  closed by event, and the remaining work is verification/integration.
  Nothing else in this intent changed; the outcomes, constraints, and
  remaining open questions stand.

## Acceptance (intent gate)

Glenn accepts this intent as the correct statement of the problem and the
outcomes, and answers (or explicitly defers) the open questions. Acceptance
triggers the spec stage; it does not authorize implementation.
