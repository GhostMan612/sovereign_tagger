# ST-05 — Fail-closed release signing and artifact identity

> **Priority:** P1  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
Release build falls back silently to signingConfigs.debug whenever no release keystore is configured; release-looking APK might use development identity.

- [android/app/build.gradle:76-95](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/build.gradle#L76-L95)
- [android/app/src/main/AndroidManifest.xml](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/AndroidManifest.xml)
- [.github/workflows/dart.yml](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.github/workflows/dart.yml)

## Intended implementation touch surfaces
- `android/app/build.gradle`
- `android/gradle.properties (if needed)`
- `build/release verification scripts (new)`
- `docs/release-signing.md (new)`

## Detailed work order
1. Remove implicit signingConfig=debug fallback from release build type and make release package fail with targeted actionable error for absent key materials.
2. Define separate signed release and explicitly labeled unsigned release artifact options; never rename a debug-signed APK as release.
3. Verify final APK/AAB package id, versionCode, certificate SHA-256 fingerprint and signing scheme before publishing; sign only in protected host workflow.
4. Use credentials from environment/secure CI, never in tracked local.properties or logs; validate storeFile, alias, passwords, and cert expiry.
5. Supply documented one-shot local build and verify commands (apksigner / bundletool) with expected artifact manifest and reproducible checks.

## Negative and regression test matrix
- [ ] Without keystore, release signing/build gate fails; debug build still succeeds.
- [ ] With disposable CI fixture signing identity, verify fingerprint and all APK signature schemes appropriate to target.
- [ ] Reject debug certificate in release publish job, missing alias, wrong password and expired cert.

## Acceptance criteria and evidence required
- [ ] No distributable release artifact can be debug-signed silently.
- [ ] Secret-free release CI verified; artifact identity recorded in release manifest.
- [ ] Physical install/update preserving signing identity gate.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
Native Android CI (#06) should run against unsigned/debug artifact without production key.

## Rollback / failure policy
Safe revert is to explicit debug flavor, not debug signing fallback in release.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
