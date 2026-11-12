# ST-16 — Produce SBOM and independently verify third-party redistribution rights

> **Priority:** P1; **Status:** SPEC-ONLY / NOT IMPLEMENTED; **Base:** `0253a994`; **Audit:** 2026-11-12

## Grounded finding
GPL-enabled FFmpeg, proprietary ACRCloud binaries, embedded Cactus native archive, Python components and neural model terms need separate confirmed redistribution rights; current license descriptions alone are insufficient evidence of public release eligibility.

- [`LICENSES.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/LICENSES.md)
- [`android/app/libs/acrcloud-universal-sdk-1.3.33.jar`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/libs/acrcloud-universal-sdk-1.3.33.jar)
- [`android/app/src/main/jniLibs/arm64-v8a/libACRCloudUniversalEngine.so`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/jniLibs/arm64-v8a/libACRCloudUniversalEngine.so)
- [`android/app/src/main/jniLibs/arm64-v8a/libneedle.a`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/jniLibs/arm64-v8a/libneedle.a)
- [`pubspec.yaml`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/pubspec.yaml)

## Files proposed for the implementation PR(s)
- `LICENSES.md`
- `docs/legal/binary-provenance.md (new)`
- `docs/legal/distribution-matrix.md (new)`
- `scripts/verify_sbom.py (new in implementation)`

## Ordered implementation workchain
1. Inventory each shipped source/binary, origin, exact SHA-256, version, embedded license/notice, build configuration and required upstream source offer.
2. Distinguish licenses of Dart/Java dependencies, GPL FFmpeg/native codec linkage, ACRCloud SDK distribution agreement, Chaquopy commercial/use terms and model weight licensing.
3. Obtain authoritative vendor-granted redistribution rights for proprietary ACRCloud; absence of evidence is an explicit HOLD, not proof of violation or automatic approval.
4. Generate machine-readable SBOM (CycloneDX/SPDX) from Gradle, pubspec.lock, Chaquopy pip pins and native binaries; detect new artifacts and license drift in CI.
5. Record source/notice obligations and track bundled GPL or LGPL codec compliance; do not claim official F-Droid eligibility without packaging-specific review.
6. Define distribution policy for sideload-only private builds, self-hosted repository and public store releases; explain separate source builds and proprietary binary constraints.
7. Treat this as an engineering/compliance checklist, with legal review before public distribution decisions.

## Negative and regression test plan
- [ ] SBOM enumerates compiled binaries, Python packages and all runtime dependencies; no missing hashes.
- [ ] CI warns on unknown license/new native blob and fails public-release gate without provenance.
- [ ] Verify license notices actually packaged and accessible to user where required.

## Acceptance / evidence gates
- [ ] Every shipped binary has tracked identity/provenance and redistribution disposition.
- [ ] No unverified F-Droid or GPL compatibility assertions in README/release notes.
- [ ] Explicit release hold until proprietary permissions are substantiated.
- [ ] Reference exact implementation SHA, diff, CI run, native/Android build, and device evidence where relevant.
- [ ] Reconcile app state, failure messaging, backward compatibility and data integrity before describing the issue as resolved.

## Dependency and phase order
ST-14 candidate dependencies and ST-15 flavors must each refresh SBOM.

## Rollback / operator preservation
Do not distribute an unverified flavor; keep original sideload-only operating policy.

## Status contract
A green documentation PR means the specification merged, **not** that executable code is fixed or native tests have passed. Implementation must ship under a separate branch with verification artifacts, then update `.blueprints/CURRENT_STATE.md` and roadmap only after merge.
