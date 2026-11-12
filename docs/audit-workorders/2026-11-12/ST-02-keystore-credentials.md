# ST-02 — Android Keystore vault and crash-safe credentials migration

> **Priority:** P1  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
pCloud bearer token, ACRCloud secret/key and Hugging Face token remain in ordinary SharedPreferences; SOV2:K encrypted configuration backups do not automatically secure these entries.

- [lib/core/cloud_settings.dart:70-130](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_settings.dart#L70-L130)
- [lib/screens/settings_screen.dart:115-129](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/settings_screen.dart#L115-L129)
- [android/app/src/main/AndroidManifest.xml](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/AndroidManifest.xml)
- [docs/audit-workorders/pcloud-keystore-credential-migration.md](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/docs/audit-workorders/pcloud-keystore-credential-migration.md)

## Intended implementation touch surfaces
- `android/app/src/main/kotlin/com/sovereigntagger/CredentialVault.kt (new)`
- `MainActivity or narrow native channel dispatcher`
- `lib/core/credential_store.dart (new)`
- `cloud_settings.dart`
- `settings_screen.dart`
- `android/app/src/main/res/xml/*backup* (new)`

## Detailed work order
1. Inventory all persistence, export, debug, screenshot, backup, issue-report and log surfaces for pCloud, ACRCloud, Genius and HF credentials; explicitly classify identifiers vs secrets.
2. Use a dedicated Keystore AES-GCM key per vault or key namespace with unpredictable IV, authenticated ciphertext, versioned format and strict length/encoding checks; never embed plaintext or a static master key.
3. Expose save/read/delete/status via narrow MethodChannel, not generic config-backup APIs; restrict raw-secret lifetime to request boundary.
4. Plan one-way migration with verify-write-readback, removal of plaintext only after durable encrypted storage, idempotent crash recovery marker and explicit failure state; do not silently log out or erase only copy.
5. Add Android Auto Backup and Android 12+ dataExtractionRules exclusions for encrypted data and legacy preferences; test restore without a matching Keystore alias as signed-out, never plaintext fallback.
6. Refactor current CloudSettings and Settings UI to expose no token text, reject forged OAuth redirects, clear manual token controller and preserve region metadata; use same abstractions for ACRCloud, HF, Genius.
7. Document local revocation/logout vs provider-side revocation failure, loss of hardware key and OEM key invalidation behavior.

## Negative and regression test matrix
- [ ] Instrumented tests API 26/29/33/36: encrypt, restart, reload, tamper, invalid alias, backup/restore and logout.
- [ ] Fault injection before encrypted write, after encrypted write, before legacy removal and after legacy removal; migration remains recoverable without plaintext residue.
- [ ] Ensure no secrets in logs, app export, cloud backup, URL, screenshots after submission or generated issue reports.

## Acceptance criteria and evidence required
- [ ] Verified storage and backup exclusions, no credential plaintext left after successful migration.
- [ ] Existing pCloud US/EU, ACRCloud and HF flows reauthenticate without regressions.
- [ ] Native compile and two-device smoke gates; explicit limitations of Keystore on compromised devices.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
After merged OAuth PRs #39–#41; may land independently of voice/Workbench.

## Rollback / failure policy
Retain previously encrypted record until a forward migration succeeds; do not downgrade to plaintext; require reconnect if unrecognized vault version.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
