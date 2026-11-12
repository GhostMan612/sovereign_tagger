# ST-24 — Extract Kotlin StorageBridge media, vault, journal and photo services

> **Priority:** P2 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
Native StorageBridge (~62 KB) handles recovery transactions, crypto, MediaStore, photo EXIF and file export under one class; accidental API/permission drift is dangerous for existing users.

- [`android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt)
- [`android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/kotlin/com/sovereigntagger/MainActivity.kt)
- [`lib/core/storage_client.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/storage_client.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)

## Proposed file/interface changes
- `android/app/src/main/kotlin/com/sovereigntagger/storage/MediaStoreOps.kt (new)`
- `android/app/src/main/kotlin/com/sovereigntagger/storage/RecoveryJournal.kt (new)`
- `android/app/src/main/kotlin/com/sovereigntagger/storage/CryptoVaultOps.kt (new)`
- `android/app/src/main/kotlin/com/sovereigntagger/storage/PhotoGeometryOps.kt (new)`
- `android/app/src/main/kotlin/com/sovereigntagger/StorageBridge.kt`

## Surgical extraction phases
1. Inventory every public storage MethodChannel method name, payload key, exception envelope and return value from Dart and MainActivity before moving code.
2. Extract pure photo EXIF/orientation transforms with pinned fixtures and no change to original media overwrite behavior.
3. Move cryptographic envelope SOV2 variants and Keystore execution into CryptoVaultOps with legacy migration vectors and no static shared secrets.
4. Extract recovery journal lifecycle and atomic copy/restore/discard with UUID/sha256 and validated path confinement; preserve crash recovery states.
5. Extract MediaStore operations behind interface suitable for fake ContentResolver fault injection; include import, overwrite, rename, thumbnails and scoped storage.
6. Keep StorageBridge as thin contract dispatcher, not owner of duplicate caches or stale mutable state; preserve constructor/visibility until ABI compatibility proven.
7. Do not mix behavioral fixes such as ST-02 credentials or ST-10 SHA verification into mechanical extraction unless independently proven by tests.

## Tests and negative conditions
- [ ] Exact MethodChannel string/method/return parity test across all handlers.
- [ ] Pass SOV2:K, SOV2:P, legacy recovery vectors and photo orientation 5/7 before and after extraction.
- [ ] Crash at every journal state: no false committed, no path traversal and original source remains recoverable.
- [ ] API 26,29,33+, current Android 16 native integration with scoped MediaStore edge cases.

## Acceptance evidence
- [ ] Native Kotlin/Android build and instrumentation green, plus two-device upgrade and recovery smoke.
- [ ] No data-format changes and no new auth/backup export of secrets.
- [ ] Measured class responsibility/size reduction and one owner per side-effect.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
ST-06 native CI, ST-02 vault contract, ST-10 MediaStore verified commits. Start pure extraction first.

## Rollback plan
Preserve old dispatcher API and serialized data; each service extraction revert independently.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
