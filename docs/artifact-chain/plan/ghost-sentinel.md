# Plan: GhostBot talks directly to Sentinel

Status: DRAFT — awaiting spec approval (Build gate). This plan is
written SECOND, at the same time as the GhostBrain plan, in the
order Glenn set 11 November 2026: pCloud first, then these two
at the same time.
Spec: `spec/sentinel-ghost-cloud-addendum.md`, Part A, plus
`spec/sentinel.md` §7–§8 (hit-list store) and §5 (Forge /
Pipeline handoff). Intent: `intent/sentinel.md` (policy locked
11 Nov 2026; hub / mission-contract outcome removed).
No implementation is authorized by this plan alone; approval of
the spec authorizes implementation, task by task, with review
per `review/REVIEW.md`. Repo law: stage by explicit path,
approval before commit/push, `main` only.
Base repo: GhostMan612/sovereign_tagger, main `b8fdbe6`.
Verified against that HEAD 11 Nov 2026: `GhostBrain.respond`
(`lib/services/ghost_brain.dart`, 1,728 lines) routes
`_crossTabAutomation` → `_command` → `_knowledge`; `_command`
handles playback, queue, favorites, sleep, repeat/shuffle, open
screens, Forge, mediainfo, EQ, settings — but has NO Sentinel
vocabulary at all; `GhostWorld` is the abstract interface in
`ghost_brain.dart:44` and `AppGhostWorld`
(`lib/services/ghost_world.dart`, 548 lines) implements it;
`GhostReply(text, tone, chips, laugh, hide)` is the only reply
shape; `_knowledge` has 30 `_KbEntry` records.

## Dependency (read first)

This plan depends on Sentinel slice 1 landing first, or at
least on the `SentinelStore` API being frozen: the world methods
in T2 read `sentinel_hits.json` (spec `sentinel.md` §7) and the
statuses `open` / `in_forge` / `in_pipeline` / `resolved` /
`ignored` / `uncompletable` / `stale`. The Sentinel plan itself
is not yet written — that is a separate, still-open item, not a
blocker for writing this plan. If Sentinel slice 1 changes the
store's shape, T2 re-verifies against the new shape before any
other task in this plan proceeds. Do not build Ghost ↔ Sentinel
against a store that does not exist yet.

## Acceptance criteria

- A1 — "What needs fixing?" returns real counts from the
  store (by severity, top 3 issues), with chips. No scan ever
  run → "No scan yet — want me to run one?", never a guess.
- A2 — "Show me files missing art" lists the first 5 real
  hits, with counts, and a chip per hit opens it in Forge
  with the Sentinel expected name prefilled.
- A3 — A scan started by Ghost runs with the same rules as a
  manual scan (batched, cancellable, never while Forge /
  Pipeline / FFmpeg is running) and reports progress, then a
  summary. Ghost never auto-starts a scan.
- A4 — No Ghost-initiated rename, tag write, batch queue, or
  status change happens without the operator saying so in
  that turn (or tapping the chip Ghost offered). "Fix my
  library" is answered with a question, never executed.
- A5 — Every Ghost-initiated status change is recorded in the
  hit record (ghost, voice/text, date, reason).
- A6 — `flutter analyze --no-pub` clean on the host gate;
  device smoke on the Moto G passes per T9.

## Task order

### T1 — Freeze the Sentinel query API (spec Part A §A.3)
Files: none in the app yet — a contract note in this plan's
review record, reconciled against `spec/sentinel.md` §7 when
Sentinel slice 1 lands.
- Write down, as the contract T2 will build against:
  `sentinelSummary()` (counts by status and issue, total hits,
  last scan id / time), `sentinelHits({issue, severity, status,
  limit})`, `sentinelHit(id)`, `sentinelScan()`,
  `sentinelOpenInForge(hitId)`, `sentinelSendToPipeline(hitIds)`,
  `sentinelMarkUncompletable(hitId, reason)`,
  `sentinelIgnore(hitId, reason)`.
- Record the two rules the contract must carry: a summary
  never triggers a scan, and a hit's tag snapshot is the
  evidence — Ghost shows the snapshot's facts, never a
  paraphrase of them.
- Done when: the contract is written and matches the Sentinel
  spec's record shape field-for-field.
- Proof: A1 (partial).

### T2 — GhostWorld additions (spec Part A §A.3)
Files: `lib/services/ghost_brain.dart` (`GhostWorld` interface),
`lib/services/ghost_world.dart` (`AppGhostWorld`),
`lib/services/sentinel_store.dart` (consumer side only — the
store itself belongs to Sentinel slice 1, not this plan).
- Implement the T1 contract in `AppGhostWorld`, backed by
  `SentinelStore`. Read-only methods first (`sentinelSummary`,
  `sentinelHits`, `sentinelHit`); handoff methods second
  (`sentinelOpenInForge` via the existing `ForgeRequest` /
  `SovereignState.sendToForge`, `sentinelSendToPipeline` via
  the existing Pipeline queue with the 80% confidence gate
  intact). `sentinelScan` starts a scan under the same rules
  as a manual scan and reports progress the way the scan UI
  does.
- No new brain architecture. No new store. No change to the
  Forge save / verify path or the Pipeline gate.
- Done when: each world method works from a real hit-list on
  device (or a fixture hit-list on the host, if the device is
  not available for a given check — record which).
- Proof: A1, A2, A3.

### T3 — _command branches: Sentinel intents (spec Part A §A.3)
Files: `lib/services/ghost_brain.dart` (`_command` only, in
`_command` order — lexical first, so they are testable by
string).
- Deterministic branches, in this order:
  "What needs fixing?" / "How's my library?" / "library health"
  → summary reply + chips [Show missing art] [Show bad names]
  [Run a scan]; "Show me files missing art / lyrics / bad
  names / missing track numbers" → first 5 hits + counts +
  chips per hit [Open in Forge] [Next 5]; "Fix this song's
  tags … and rename it to policy" → Forge handoff with the
  Sentinel expected name prefilled in `FILE NAME ON SAVE`;
  "Send the missing-art files to batch" / "Send these to
  Pipeline" → queue the current filtered hits, reply with
  how many queued and that <80% go to REVIEW; "This one can't
  be fixed" / "Mark this uncompletable" → status transition
  with reason; "Run a Sentinel scan" / "Check the library" →
  start scan, report progress, then summary.
- "Fix my library" / "fix everything" is NOT a branch — it
  falls through to the safety reply in T5 ("Want me to show
  you the worst 5 first?").
- Done when: every branch above answers correctly from a
  fixture hit-list, by typed text, and the same phrases by
  voice transcription produce the same branches.
- Proof: A1, A2, A3, A4.

### T4 — Knowledge entries: Sentinel explainer (spec Part A §A.5)
Files: `lib/services/ghost_brain.dart` (`_kb` only).
- New `_KbEntry` records, following the existing shape (keys,
  2–3 detail lines in Ghost's voice, chips that lead to the
  T3 branches): `sentinel`, `library health`, `missing art`,
  `missing lyrics`, `bad names`, `uncompletable`, `scan`.
  The existing `duplicate` entry is the model: short,
  practical, ends in an action, not a lecture.
- Done when: "What is Sentinel?" / "How does Sentinel work?"
  / "What does uncompletable mean?" are answered from these
  entries, not from a generic fallback.
- Proof: A1 (partial).

### T5 — Safety gate: confirmation, no invented counts, evidence trail (spec Part A §A.4)
Files: `lib/services/ghost_brain.dart` (`_command` / `_respondSingle`
only), `lib/services/sentinel_store.dart` (status-transition
recording — consumer side only).
- Rules, enforced in code, not in prose: Ghost answers
  questions and opens things; it never renames, writes tags,
  queues a batch, or changes a status without the operator
  saying so in that turn or tapping the chip Ghost offered.
  A chip tap is the confirmation. A voice transcript that
  sounds like "fix everything" is not a command to fix
  everything. Batch / destructive verbs require an explicit,
  single-turn confirmation.
- No invented counts: no scan ever run → "No scan yet";
  stale store (last scan older than the library's last change)
  → Ghost says so before giving counts.
- Every Ghost-initiated status change records ghost /
  voice-or-text / date / reason in the hit record, so the
  evidence trail in `spec/sentinel.md` §7 survives the voice
  path.
- This task is deliberately separate from T3 so the safety
  rule is reviewable on its own. It is also the task the
  Plan/Build/Review separation applies to most strictly:
  independent review pass required.
- Done when: a destructive paraphrase cannot execute without
  confirmation (tested by string), and a status change made
  via Ghost is visible in the hit record with its reason.
- Proof: A4, A5. This task's proof is a negative test — record
  the refused commands, not just the accepted ones.

### T6 — Follow-ups: walk the list (spec Part A, via Part C §C.2.5)
Files: `lib/services/ghost_brain.dart` (`_lastEntry` /
`_lastDetail` follow-up path only).
- "Tell me more" already works via `_lastEntry`; extend it to
  the hit-list: "…and now the next one" walks the filtered
  hits in order, "show next 5" pages. No new state machine —
  reuse the existing follow-up path.
- Done when: a three-turn walk (summary → first 5 → next 5)
  works by text without repeating or skipping a hit.
- Proof: A2 (partial).

### T7 — README and blueprint accuracy
Files: `README.md`, `.blueprints/CURRENT_STATE.md`,
`SESSION_HANDOFF.md`, `ROADMAP.md` (only the sections this
change touches).
- Document the Sentinel questions Ghost can answer and the
  handoffs it can do, and the safety rule (Ghost never
  auto-fixes). Do not document a proactive mode — there is
  none in this plan (see Risks).
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
- Chain-consistency check: every spec requirement (Part A)
  traces to a task and a test/device check; no orphan tasks.

### T9 — Moto G device smoke test (closes the device-proof rule)
- Fresh install/upgrade on the Moto G (ARM64), real hit-list
  from a real Sentinel scan: A1–A5 by typed text and by voice
  (Whistle preferred, per the hands-free chain — do NOT let
  this smoke test decide D2/D3; auto-send is a separate chain
  with its own gates), "run a scan" by voice with progress
  shown, a refused "fix everything" paraphrase, and a
  Ghost-made uncompletable mark visible in the hit record.
- Record results (pass/fail per criterion, device, build) in
  the PR or in `.blueprints/` verification notes. A code
  review alone does not close this task.

## Order-of-work notes

- T1 before T2: the contract is the build's foundation, and it
  is cheap to write and expensive to change later.
- T2 before T3: commands call world methods, not the store.
- T5 is reviewable on its own and must not be folded into T3.
- T4 and T6 may run in parallel with T3 (different code paths),
  but they join the same device smoke test (T9).
- This plan and the GhostBrain plan are built at the same time
  by Glenn's order. They touch the same file
  (`ghost_brain.dart`) in different places: this plan owns the
  Sentinel `_command` branches and Sentinel KB entries; the
  GhostBrain plan owns the general KB batch, the general
  commands, memory, and proactive behaviour. If both plans are
  built in one branch, keep their diffs separable by task, and
  do not let a GhostBrain memory change silently alter a
  Sentinel safety reply.
- If any task's diff grows past one reviewable change, split
  it.

## Risks carried into the build

- The Sentinel store dependency (see top): if Sentinel slice 1
  slips or changes shape, T2–T9 wait or re-verify. This plan
  does not build a second store to work around that.
- Proactive Ghost is NOT in this plan. Ghost answers when
  asked and offers a chip when the operator is already in the
  Library / Sentinel screen. A proactive mode belongs to the
  GhostBrain plan (default-off) and must not be smuggled in
  here as a "helpful" summary on open.
- Hands-free D2 (auto-send allowlist) and D3 (silence
  defaults) are untouched by this plan. A voice command that
  reaches Ghost still goes through the hands-free chain's
  gates; this plan adds no auto-send and changes no silence
  default.
- The zero-test-suite rule (Phase 13, parked 1 Oct 2026)
  applies: do not create `test/` unilaterally — ask Glenn
  first, as the Sentinel spec already records.
