# Review guide for Sovereign Tagger artifact-chain work

Adapted from the playbook's REVIEW.md idea: review passes, severity
definitions, and merge thresholds, written down before the diff exists.

## Severity definitions

- **P0 — merge blocker.** Wrong behavior that ships to the user: a
  destructive command executing without required confirmation, a voice
  path that silently fails, a mixed embedding space, a build/test gate
  red. Fix in the same PR; no merge with an open P0.
- **P1 — fix before merge unless Glenn explicitly defers with a reason
  recorded in the PR.** Behavior that is wrong but contained, missing
  tests for a new behavior, stale docs describing behavior that changed.
- **P2 — fix or file.** Edge cases, hardening follow-ups, naming drift.
  If deferred, file it as a dated note in the PR or a new intent — never
  silently dropped.

## Review passes (in order)

1. **Spec trace.** Every spec requirement maps to code or a test; every
   code change maps to a requirement. Orphans are findings.
2. **Safety (media-mutating paths).** Any path that plays, deletes,
   overwrites, or shares real media is traced from trigger to effect.
   Voice-triggered paths get the strictest reading: assume the transcript
   is misheard.
3. **Native boundary.** Dart ↔ Kotlin channel names, method names, and
   argument keys match; JNI names match the C++ side; model/threshold
   constants agree on both sides. (The 26 October audit's scripted checks
   are the model for this pass.) Embedding paths additionally verify
   engine-ID/epoch agreement: native vs. fallback spaces are never
   compared, including across a mid-request flip and a persisted index
   written under the other engine (G48).
4. **Failure behavior.** Every new failure mode is surfaced in words and
   leaves the app usable. Silent fallbacks and swallowed return values
   are findings.
5. **Docs.** README and affected `.blueprints/` notes match the shipped
   behavior. Stale engine/status wording is a P1.

## Merge thresholds

- No open P0. No red host gate (`flutter analyze`, `flutter test`).
  (The Dart CI workflow is red at dependency install since 25 October
  2026 — pre-existing, and not the host gate; do not merge on CI status
  alone.)
- Native/voice changes: device smoke test recorded (criterion, device,
  build, result). Code review alone never satisfies this threshold.
- Auto-send changes: independent review pass (reviewer pass ≠ builder
  pass), D2 allowlist verified by test or device check.
- Chain-consistency check passed: no orphan requirements, no orphan tasks.
- Repo law honored: staged by explicit path, approval before commit/push,
  no secrets, `main` only.

## What review does not do

Review does not re-decide the intent. If review finds the intent itself
wrong, that is a reversal: record it dated in the intent (reason, what it
supersedes) and re-run the gates; do not quietly rewrite the intent
mid-review.
