# Artifact chains for Sovereign Tagger

Adapted from Anthropic's AI-native SDLC playbook (published 21 August 2026):
every stage produces a version-controlled, human-readable, machine-actionable
Markdown artifact, acceptance of one artifact triggers the next stage, and
human judgment concentrates at the gates. This package applies that loop to
Sovereign Tagger, respecting the repo's own law (`CLAUDE.md`, `RULES.md`):
`main` is the single canonical branch, stage by explicit path only, and no
commit/push without explicit approval.

## The chain (primary)

| Stage | Input | Output artifact | Gate |
|---|---|---|---|
| Plan | Idea, ticket, or alert | `intent/<name>.md` | Glenn accepts the intent |
| Design | `intent/<name>.md` | `spec/<name>.md` | Glenn approves the spec |
| Build | `spec/<name>.md` | `plan/<name>.md` + diff/PR | Approval authorizes implementation |
| Test | Code changes | Verified diff | `flutter analyze` + `flutter test` on host; device smoke test where native code changed |
| Deploy | PR | Merged commit + record | Review passes; merge to `main` (Tagger ships outside app stores) |
| Maintain | Field report / anomaly | New `intent/<name>.md` | Anomaly exceeds the control band |

Six artifacts in all, per the playbook: intent, spec, plan, the diff with its
tests, the PR with its review findings, and the incident record that opens the
next intent. Git history is the audit trail.

## Chains that fit Tagger, and when to use each

1. **Anthropic SDLC loop (this package, primary).** Feature work with real
   users and real devices. Use for hands-free voice. One intent per change;
   intents live in `intent/`, one folder, and may also be mirrored into the
   repo's `.blueprints/` docs if Glenn wants them versioned with the code.
2. **dig → clarify → decomposition plugin pipeline.** When the requirement
   itself is ambiguous. Artifacts: `decisions.md` → `specification.md` →
   todos. Use for Sentinel scoping: the concepts are checkpointed but the
   requirement is not yet nailed down. Do not jump Sentinel straight to a
   spec; run the pipeline first.
3. **Plan / Build / Review separation.** Verification-heavy work, or any
   change that mutates real media (play/delete) or touches native bridges.
   Builder and reviewer are different passes; the reviewer checks the diff
   against the spec, not against the builder's intentions. This is the loop
   already used for the Atlas KML PR (external review → verify → fix in the
   same PR). Use it for the voice auto-send change, because a misheard
   command must never execute unreviewed.

## Skills and hooks

- **Grilling skill** — interviews Glenn (or the originator) decision-tree by
  decision-tree until intent and agent share an understanding, then writes
  the intent file. Trigger at the end of the interview, not during.
- **Spec-generation skill** — reads the intent, applies repo constraints
  (offline-first, ARM64 Moto G, no new permissions unless a requirement
  demands it, `CLAUDE.md`/`RULES.md` law), and writes the spec. Trigger:
  intent accepted.
- **Plan skill** — reads intent + spec, interviews about the repo, writes
  the plan with file changes, order of work, and proof per task. Trigger:
  spec approved.
- **Review skill** — applies `review/REVIEW.md`: severities, passes,
  thresholds. Trigger: diff ready.
- **Hook (proposed, not installed):** on intent acceptance, draft the spec;
  on spec approval, draft the plan. Hooks propose; Glenn disposes. Nothing
  here auto-commits or auto-pushes.

## Evals: does the chain still work?

- **Chain-consistency check (run before any merge):** every spec
  requirement traces to at least one plan task and one test or device check;
  every plan task traces to a spec requirement. Orphan requirements and
  orphan tasks are both findings.
- **Reversal rule:** an intent edit made after the first spec commit is a
  reversal. Record it as a dated entry appended to the intent (date, author,
  reason, what it supersedes). Do not silently rewrite the old line — the
  reason for the change of mind is the part that gets lost.
- **Device-proof rule:** a native/voice change is not "working" until the
  Moto G smoke test passes. Code review alone never closes a device claim.
  This VM has no Flutter/Android toolchain, so host and device verification
  always happen on Glenn's side.

## Status board (30 October 2026)

- **Hands-free voice** — intent, spec, and plan drafted in this package
  from the 26 October 2026 code audit (clone HEAD `1c52bdd`), revised
  3 November 2026 for Phase 33 (HEAD `01eb25f`): the embedding decision
  (D1) is closed by event — the native bridge shipped — while the
  auto-send allowlist (D2) and silence defaults (D3) still await Glenn.
  No code changed by this package.
- **Revision, 3 November 2026** — Phase 33 landed 2 November (native
  EmbeddingGemma bridge, semantic index, RAM lifecycle). Intent, spec,
  and plan revised to build on the shipped mechanism; D1 closed by event.
  Whisper fallback and README accuracy remain open; Dart CI red at
  dependency install since 25 October (pre-existing).
- **Sentinel** — intent accepted for spec 11 November 2026; naming
  policy locked the same day (Q1–Q7, see `intent/sentinel.md`); spec
  written (`spec/sentinel.md`, 11 November 2026, base main `b8fdbe6`).
  Hub / mission-contract outcome removed 11 November 2026 at Glenn's
  direction — Sentinel is on-device only. No code started; not part
  of the hands-free goal. Next: plan, on Glenn's approval of the spec.
- **Sentinel slice 5 spec, 11 November 2026** — `spec/sentinel-slice5.md`:
  auto-apply spec-only (no code), with a DRAFT allowlist (classes
  A1–A7, all proposed OFF, catalog threshold 0.95, 25-file run cap),
  safety gates (preview-first, re-verify at apply time, Forge's
  verified write path, per-file undo, mutual exclusion, audit log),
  and six decisions for Glenn (D-S5-1–D-S5-6). Slice 1 merged, slice 2
  in draft PR #13. Note: the Sentinel plan (`plan/sentinel.md`) is not
  in this repo — it lives only in the local chain — and its S11 is the
  Moto G smoke test, not slice 5; the plan change is a new task S12,
  drafted in the spec's §7 for the local chain.
- **Addendum, 11 November 2026** — `spec/sentinel-ghost-cloud-addendum.md`:
  Ghost ↔ Sentinel, pCloud in the player, more GhostBrain. Plans
  written the same day, in Glenn's order — pCloud first
  (`plan/pcloud.md`), then Ghost ↔ Sentinel (`plan/ghost-sentinel.md`)
  and more GhostBrain (`plan/ghostbrain.md`) at the same time. The
  earlier "Plan more GhostBrain first" turn was interrupted and is
  superseded by that order. pCloud plan is gated on T0 (OAuth app
  must exist or be provisionable — pCloud paused new self-service
  OAuth apps). No code started on any of the three tracks.

## Placement decision (Glenn's call)

This package lives outside the repo at
`~/workspace/sovereign-tagger/artifact-chain/`. To version it with the code,
copy it into the repo (suggested: `docs/artifact-chain/`, keeping
`.blueprints/` canonical for SESSION_HANDOFF/RULES/CURRENT_STATE/ROADMAP).
Do not commit secrets; fixtures use synthetic data only, per repo law.
