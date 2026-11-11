# Plan: More brains for GhostBrain

Status: DRAFT — awaiting spec approval (Build gate). This plan is
written SECOND, at the same time as the Ghost ↔ Sentinel plan, in
the order Glenn set 11 November 2026: pCloud first, then these
two at the same time.
Spec: `spec/sentinel-ghost-cloud-addendum.md`, Part C. Intent:
none separate — the ask is recorded in the addendum (Glenn,
11 Nov 2026: "more brains to the GhostBrain, more responses
and ways to help").
No implementation is authorized by this plan alone; approval of
the spec authorizes implementation, task by task, with review
per `review/REVIEW.md`. Repo law: stage by explicit path,
approval before commit/push, `main` only.
Base repo: GhostMan612/sovereign_tagger, main `b8fdbe6`.
Verified against that HEAD 11 Nov 2026: `GhostBrain`
(`lib/services/ghost_brain.dart`, 1,728 lines) has 30 `_KbEntry`
records, deterministic `_command` intents, `_crossTabAutomation`
(lexical first, semantic fallback second), `_knowledge` (BM25 /
semantic), `suggestionsFor(tab)` (line 587), `_IntentExemplar`
with `_exemplars` / `_nativeExemplars` and 220 ms background
warm-up slices (lines 161–346); semantic fallback uses
`EmbeddingGemmaService` (native LiteRT 256-D, hash fallback,
engine IDs 1/2) plus `GhostVectorIndex` (`ghost_vectors.bin`);
no memory — every turn starts fresh except in-conversation
`_lastEntry` / `_lastDetail`; no proactive behaviour.

## Order within this plan (spec Part C recommendation)

Knowledge + commands first (cheapest / most useful), memory
second (most alive), proactive last and default-off (riskiest).
Personality is not expanded — one line of tone per reply, then
the answer, per the existing `GhostReply.tone` discipline.

## Acceptance criteria

- A1 — Every new KB entry is reachable by its own keywords
  and by semantic fallback, and its chips lead somewhere real.
- A2 — Every new command works by typed text and by voice
  transcription, and a paraphrase of a destructive command
  cannot execute it without an explicit, single-turn
  confirmation.
- A3 — "Play more like this" / "What did I play yesterday?"
  work from on-device memory only, and "Forget what you've
  learned" in Settings erases that memory.
- A4 — Proactive Ghost, if enabled, appears only on the
  Library / Sentinel screen, only with a chip, only when
  there is something new — and is OFF by default until
  Glenn turns it on.
- A5 — No new command phones home, changes D2/D3, or bypasses
  Forge / Pipeline safety (working copy, read-back verify,
  write-access prompt).
- A6 — `flutter analyze --no-pub` clean on the host gate;
  device smoke on the Moto G passes per T9.

## Task order

### T1 — Knowledge batch 1: 12 new entries (spec Part C §C.2.1)
Files: `lib/services/ghost_brain.dart` (`_kb` only).
- New `_KbEntry` records, following the existing shape (keys,
  2–3 detail lines in Ghost's voice, chips): `sentinel`
  (if the Ghost ↔ Sentinel plan has not already added it —
  do not build it twice; record the fold in the review),
  `pcloud` / `cloud folder` (if the pCloud plan has not
  already added them — same rule), `duplicates`,
  `forensics` / `fake-lossless`, `scheduled scans`,
  `album view`, `genre`, `formal names`,
  "why is this file named like that?", "what does
  uncompletable mean?", "how do I mark a file?".
  The final list of 12 is fixed at build time from this
  list; if one is dropped, record why.
- Done when: each entry answers its own question by keyword
  and by semantic fallback, and no entry's chips are dead ends.
- Proof: A1.

### T2 — New commands batch 1 (spec Part C §C.2.2)
Files: `lib/services/ghost_brain.dart` (`_command` only, in
`_command` order — lexical first, testable by string),
`lib/services/ghost_world.dart` (only where a new world method
is genuinely needed — prefer reusing `playTracks` /
`queueTracks` / `library` / `forgeExtract`).
- Deterministic branches:
  play by mood / lyric / description via the existing semantic
  index ("play something dark and synthwave", "find the song
  that says 'tears in the neon rain'" — the README already
  promises these; wire them as commands, not just KB text);
  "play my favorites" / "play recently added" / "play this
  album" / "play more like this" (seeded from the current
  track's artist / genre / vector neighbours — the last two
  need T4's memory; if T4 is not built yet, they answer
  honestly that they need play history, they do not guess);
  queue management ("queue the next three by X", "clear the
  queue except this song", "move X to next"); library counts
  ("how many songs do I have?", "how many by X?" — from
  `library()`, real answers, not KB text); fix flows as
  commands ("fix the tags on this song … and rename it to
  policy", "…and find lyrics", "…and fetch art" — distinct
  `ForgeAutoTask`s: `searchMetadata`, `acrIdentify`,
  `fullAutoTagAndLyrics`, `findLyrics` already exist, the
  brain just needs the words); workbench by voice ("scan
  ReplayGain on this", "transcribe this with Whisper" —
  cross-tab commands already wired in Phase 36).
- Done when: every branch above works by typed text and by
  voice transcription, and the two memory-dependent branches
  either work (if T4 is built) or decline honestly (if not).
- Proof: A2, A5.

### T3 — Semantic routing: exemplars + suggestions + follow-ups (spec Part C §C.2.5)
Files: `lib/services/ghost_brain.dart` (`_IntentExemplar`
lists, `_exemplars` / `_nativeExemplars` build, `suggestionsFor`,
`_lastEntry` follow-up path).
- Every new command in T2 and every new KB entry in T1 gets
  intent exemplars, or the semantic fallback will never find
  them. Exemplars are built in the same 220 ms background
  slices as today; do not change the warm-up budget without
  recording why. Engine-space rule from the hands-free plan
  (T1) still holds: exemplars are per-engine, never compared
  across spaces.
- `suggestionsFor(tab)` extended per tab with the new
  commands, so the chips teach the vocabulary instead of the
  operator having to guess it.
- Follow-ups: "tell me more" already works; extend it to
  multi-turn fix flows ("…and now the next one" walks the
  hit-list in order — only if the Ghost ↔ Sentinel plan's
  T6 has not already built it; do not build it twice).
- Done when: a new command phrased three different ways
  (keyword, synonym, semantic paraphrase) reaches the same
  branch, and the per-tab chips include the new vocabulary.
- Proof: A1, A2.

### T4 — Memory / context, on-device only (spec Part C §C.2.3)
Files: new `lib/core/ghost_memory.dart` (or a section in
`lib/core/ghost_settings.dart` — decide at build time; a
separate file is the default, so memory is deletable without
touching settings), `lib/services/ghost_brain.dart` (read
side only), `lib/screens/settings_screen.dart` (the forget
switch).
- A small, local, private context record — SharedPreferences
  or a JSON file next to the hit-list (decide at build time;
  never a network service, never leaves the device):
  last played / recently played (needed for "what did I play
  yesterday?" and "play more like this"), favorites and
  per-artist play counts (for "play my most-played" and for
  ranking semantic results), last Sentinel scan summary (for
  Part A answers without re-reading the store every turn),
  formal-name corrections Glenn made in Forge ("it's DMX") —
  offered to the exception list (spec §10 brainstorm), so
  Ghost learns the name once and stops asking.
- What Ghost must NOT remember: anything from a file Glenn
  did not play / fix / ask about, and nothing about other
  people. Memory is per-device, per-operator, deletable in
  Settings with one tap ("Forget what you've learned"), and
  the plan must say so in the UI copy.
- This task answers the open question in the addendum (Part C
  §C.4 Q2): play history is on-device only, deletable. If
  Glenn answers "no" to play history, T4 is reduced to
  Sentinel-summary + formal-name memory only — record the
  reduction, do not build play history speculatively.
- Done when: A3 passes, and the forget switch erases the
  record (verified by reading the store before and after).
- Proof: A3, A5.

### T5 — Proactive Ghost, default off (spec Part C §C.2.4)
Files: `lib/widgets/ghost_chat_overlay.dart` (offer surface
only), `lib/services/ghost_brain.dart` (one-line offer text),
`lib/core/ghost_settings.dart` (the setting, default OFF).
- Ghost volunteers only in two places, only with a chip,
  never with an auto-action: on opening the Library /
  Sentinel screen, one line if there is something new since
  last visit ("12 new hits since your last scan — want the
  worst first?"), dismissible, and silent if there is nothing
  new; after a completed action, one follow-up ("That fixed
  the tags — want me to rename it to policy too?"), not a
  chain.
- Never on boot, never as a notification, never while music
  is playing unless the operator is already talking to Ghost.
  Proactive behaviour is a setting, default OFF until Glenn
  turns it on — that default is part of the spec, not a detail
  to leave to the build.
- Done when: A4 passes with the setting off (silence) and on
  (one line, one chip, dismissible), and no notification is
  ever posted by this task.
- Proof: A4.

### T6 — Personality discipline (spec Part C §C.2.6)
Files: none — a review rule, not a code task. Record it in
the review for T1–T5.
- Ghost's voice (sarcastic / happy / serious tones, glitch
  laugh, "Boo. Kidding.") is already a strength and already
  wired to the 3D avatar. More brains must not mean more
  jokes per answer. One line of personality per reply, then
  the answer. Any T1–T5 reply that is longer on personality
  than on answer is sent back.
- Done when: the review for T1–T5 records this check as done.

### T7 — README and blueprint accuracy
Files: `README.md`, `.blueprints/CURRENT_STATE.md`,
`SESSION_HANDOFF.md`, `ROADMAP.md` (only the sections this
change touches).
- Document the new commands and KB topics, the memory record
  and its forget switch, and the proactive setting with its
  default-off state. Do not document a command T2 declined
  to build.
- Done when: README matches what T9 actually proved.

### T8 — Host verification gate
- Run on Glenn's host: `flutter analyze --no-pub`, `flutter test`
  (where tests exist). Fix failures in the same change; do not
  merge with a red gate.
- CI note: the Dart workflow is red at dependency install since
  25 October 2026 (pre-existing), and Dart CI failed on main at
  `b8fdbe6` on 11 Nov 2026 (build job died in 11 seconds) — the
  same pre-existing failure, not new breakage. The host gate
  above is authoritative; do not treat a red CI run as this
  change's failure, and do not merge on CI status alone.
- Chain-consistency check: every spec requirement (Part C)
  traces to a task and a test/device check; no orphan tasks.

### T9 — Moto G device smoke test (closes the device-proof rule)
- Fresh install/upgrade on the Moto G (ARM64): every T2
  command by typed text and by voice (Whistle preferred —
  do NOT let this smoke test decide D2/D3; auto-send is a
  separate chain with its own gates), T4 memory answers and
  the forget switch, T5 proactive off (silence) and on (one
  line, one chip), and a refused destructive paraphrase.
  Record semantic-fallback behaviour with model weights
  present and absent (hash fallback) — the brain must not
  silently change answers between engines.
- Record results (pass/fail per criterion, device, build) in
  the PR or in `.blueprints/` verification notes. A code
  review alone does not close this task.

## Order-of-work notes

- T1 before T3: exemplars are written for the KB entries
  that exist, not for ones that might exist.
- T2 before T3: commands exist before they are taught to
  the semantic router.
- T4 after T2: the memory-dependent commands in T2 are
  written to decline honestly without T4, then to work with
  it — do not write them twice.
- T5 last among feature tasks. It is the only task in this
  plan that can annoy Glenn by itself, which is why it is
  last and default-off.
- This plan and the Ghost ↔ Sentinel plan are built at the
  same time by Glenn's order. They touch the same file
  (`ghost_brain.dart`) in different places: this plan owns
  the general KB batch, general commands, memory, and
  proactive behaviour; the Ghost ↔ Sentinel plan owns the
  Sentinel `_command` branches and Sentinel KB entries.
  The Sentinel KB entry, the pCloud KB entries, and the
  "next one" follow-up each belong to exactly one plan —
  record the fold in the review wherever they land, do not
  build any of them twice.
- If any task's diff grows past one reviewable change, split
  it; do not bundle the KB batch, the commands, and memory
  into one diff.

## Risks carried into the build

- D2/D3 boundary: more brains must not silently decide the
  hands-free voice decisions. No auto-send, no silence-default
  change, in any task in this plan. A voice command that
  reaches Ghost still goes through the hands-free chain's
  gates.
- Memory is the most sensitive task in this plan. Play
  history is the only item that needs Glenn's explicit yes
  (addendum Part C §C.4 Q2); if he says no, T4 shrinks as
  written above. The forget switch is not optional.
- Semantic routing drift: new exemplars can steal queries
  from old intents. T3's three-phrasing check and T9's
  with/without-weights check are the mitigations; if an old
  command starts misrouting, the exemplar is wrong, not the
  operator.
- The zero-test-suite rule (Phase 13, parked 1 Oct 2026)
  applies: do not create `test/` unilaterally — ask Glenn
  first, as the Sentinel spec already records.
- Proactive Ghost, even default-off, is the task most likely
  to be turned off again. That is a success condition, not
  a failure — the setting exists so Glenn can say no.
