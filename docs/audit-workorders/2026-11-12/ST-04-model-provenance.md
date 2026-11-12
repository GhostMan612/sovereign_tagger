# ST-04 — Digest-verified model lifecycle for Whistle, Whisper and EmbeddingGemma

> **Priority:** P1  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
Model readiness trusts size thresholds; corrupt equal-sized weights can be marked ready and downloaded/replaced without identity proof.

- [lib/core/whistle_model.dart:23-70](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/whistle_model.dart#L23-L70)
- [lib/core/whisper_model.dart:24-67](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/whisper_model.dart#L24-L67)
- [lib/core/embedding_model.dart](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/embedding_model.dart)
- [docs/audit-workorders/model-and-media-integrity.md](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/model-and-media-integrity.md)

## Intended implementation touch surfaces
- `lib/core/whistle_model.dart`
- `lib/core/whisper_model.dart`
- `lib/core/embedding_model.dart`
- `lib/core/model_lifecycle.dart`
- `test/model_integrity_test.dart (new)`

## Detailed work order
1. Inventory exact model/tokenizer name, authorized upstream revision, approved SHA-256 and license; verify historical Whistle digest against tracked blob before pinning.
2. Define ModelArtifactManifest(id, revision, bytes, sha256, sourceUrls, bundled, ABI constraints) and one streaming digest verifier for on-disk, asset and downloaded payloads.
3. Require signed/known digest or other verifiable immutable upstream artifact identity; reject unverified mutable 'main' assets and user-provided manifests as trusted identity.
4. Download to unique .part within target volume with byte cap, HTTP timeout, cancellation and optional resume metadata; never replace the working version on failed verification.
5. Verify staged digest and runtime parse/load before durable atomic replace; retain previous good model during upgrade with bounded rollback.
6. Use singleflight ensure() per model, cancellation tokens and telemetry that never discloses user text; distinguish missing/corrupt/wrong-version/unsupported.
7. Model readyness must use manifest id+digest (possibly memoized by protected metadata with invalidation), not size alone.

## Negative and regression test matrix
- [ ] Correct-size wrong-byte payload is rejected; interruption preserves last good weights.
- [ ] Two concurrent ensure requests share download; cancellation one caller doesn't corrupt another.
- [ ] Signature/digest mismatch, wrong tokenizer, 404/HTML body, corrupt bundled asset and no-storage error are explicit failures.

## Acceptance criteria and evidence required
- [ ] Verified digest at load for each model; no premature 'ready'.
- [ ] No startup downloads; offline fallback available with clear explanatory status.
- [ ] Real ARM64 load + x86 behavior, no regression in memory budget.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
Foundational for #03 and native-model release claims.

## Rollback / failure policy
Restore last digest-verified bundle; never re-enable size-only trusted state.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
