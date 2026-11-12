# ST-17 — Reconcile CURRENT_STATE, ROADMAP, security and model documentation with main

> **Priority:** P2; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
Current-state preamble stops at PR #38 though #39–#42 merged; old zero-test policy and bundled 141MB Whisper claim conflict with current tree; queue is described as pause/resume though only cancellation exists, and vault backup encryption can be mistaken for OAuth token protection.

- [`.blueprints/CURRENT_STATE.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/CURRENT_STATE.md)
- [`.blueprints/ROADMAP.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ROADMAP.md)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)
- [`.blueprints/SESSION_HANDOFF.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/SESSION_HANDOFF.md)
- [`AGENTS.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/AGENTS.md)
- [`SECURITY.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/SECURITY.md)
- [`README.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/README.md)
- [`assets/models/README_MODEL_HERE.txt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/assets/models/README_MODEL_HERE.txt)

## Files proposed for the implementation PR(s)
- `.blueprints/CURRENT_STATE.md`
- `.blueprints/ROADMAP.md`
- `.blueprints/SESSION_HANDOFF.md`
- `.blueprints/ARCHITECTURE_DECOMPOSITION.md`
- `AGENTS.md`
- `SECURITY.md`
- `README.md`
- `LICENSES.md`

## Ordered implementation workchain
1. Create concise first-screen snapshot listing exact HEAD, merged PR #39–#42 OAuth outcomes, pCloud Keystore SPEC-ONLY disposition, Stage A/B status and remaining B.8–B.10 issues.
2. Preserve historical roadmap decisions as dated history, explicitly supersede zero-test-suite historical policy with current Flutter/Python test workflow.
3. Correct current Whisper distribution: tracked whistle.cact bundle, on-demand ggml-base.en.bin, no bundled Whisper weight on main; reconcile stale APK-size comments based on new measured artifact only.
4. Correct decomposition blueprint Workbench line count/bytes, Stage C not landed, queue cancel but not pause/resume, and distinguish modeled target files from actual code.
5. Update SECURITY to separate SOV2:K config vault vs plaintext pCloud/ACRCloud/HF secret persistence; do not claim Keystore migration completed.
6. Reconcile AGENTS/RULES process constraints, deprecated packages/compatibility versions, hardware smoke evidence and CI coverage.
7. Move huge chronological changelog behind a bounded current-state summary and auto-generate checkable status index as evidence requires.

## Negative and regression test plan
- [ ] Doc lint verifies actual referenced files exist, version constants match manifests, and PR links resolve.
- [ ] Automated assertions that 'bundled' models exist and explicit test suite existence matches tree.
- [ ] Review current/historical/desired-status labels and reject completion without implementation evidence.

## Acceptance / evidence gates
- [ ] No contradictory current-state claims across entry-point docs.
- [ ] No spec-only work marked fixed or device-verified solely by CI.
- [ ] Artifact chain records code and evidence independently.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
Can land early; needs follow-up after every implementation PR.

## Rollback / operator preservation
Preserve historical text under clearly marked archival changelog instead of deleting important decisions.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
