# Sovereign Tagger — 2026-11-12 Deep Audit Master Workchain

> **Status:** PLANNING INDEX ONLY · **Audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81` · **Repository:** `GhostMan612/sovereign_tagger`  
> **27 independently authored remediation specs**, PRs #43–#69. All PRs begin from this same verified `main` SHA, and each changes only its own Markdown document. **None is an executable fix.**

## Ground truth and terminology

Git tree review covered 292 entries, 226 tracked blobs without truncation, followed by deep source inspection of specific high-risk components. Dart CI green on [run #43247794791](https://github.com/GhostMan612/sovereign_tagger/actions/runs/43247794791) does **not** prove Kotlin/JNI/Chaquopy APK build success, live pCloud authorization, or on-device media integrity. Do not imply every tracked line was independently audited. The original evidence record is the Sovereign Tagger Deep Repo Audit dated 2026-11-12 and the code-linked draft specs below.

### Work-order states (do not conflate)

- `DISCOVERED`: source/audit evidence only, no accepted spec.
- `SPEC_ONLY`: requirements and acceptance gates are written and reviewed, but production code is unchanged.
- `CODE_DRAFT`: source changes exist in a separate PR; neither merged nor verified by default.
- `CODE_MERGED`: implementation merged; unknown runtime evidence must remain explicit.
- `DART_CI_PASS`: analyzer and unit tests passed on the exact SHA.
- `ANDROID_BUILD_PASS`: Kotlin/JNI/Chaquopy APK compile passed on exact SHA.
- `DEVICE_VERIFIED`: actual device/ABI/real-provider smoke recorded; no claim based on emulators alone.
- `RELEASE_VERIFIED`: cryptographic signing, provenance, packaging and distribution gates established.

Do not mark an issue resolved when its documentation PR merges; create and link **implementation PRs** with test evidence and update the index only after their merge.

## Full coverage and dependency register

| Work order | Priority | Draft PR | Description | Cluster | Implementation dependencies | Current status |
|---|---|---|---|---|---|---|
| ST-01 | P0 | [#43](https://github.com/GhostMan612/sovereign_tagger/pull/43) | Update transaction safety | Risk containment | None | **SPEC ONLY** |
| ST-02 | P1 | [#44](https://github.com/GhostMan612/sovereign_tagger/pull/44) | Keystore secret vault | Security & build | OAuth #39–#41 merged | **SPEC ONLY** |
| ST-03 | P1 | [#45](https://github.com/GhostMan612/sovereign_tagger/pull/45) | Voice engine fallback | Runtime reliability | ST-04 | **SPEC ONLY** |
| ST-04 | P1 | [#46](https://github.com/GhostMan612/sovereign_tagger/pull/46) | Model SHA-256 integrity | Runtime reliability | None | **SPEC ONLY** |
| ST-05 | P1 | [#47](https://github.com/GhostMan612/sovereign_tagger/pull/47) | Release signing | Security & build | ST-06 optional | **SPEC ONLY** |
| ST-06 | P1 | [#48](https://github.com/GhostMan612/sovereign_tagger/pull/48) | Native Android CI | Security & build | None | **SPEC ONLY** |
| ST-07 | P2 | [#49](https://github.com/GhostMan612/sovereign_tagger/pull/49) | Cloud folder completeness | Runtime reliability | None | **SPEC ONLY** |
| ST-08 | P2 | [#50](https://github.com/GhostMan612/sovereign_tagger/pull/50) | Deferred Workbench imports | Runtime reliability | ST-09, ST-10 | **SPEC ONLY** |
| ST-09 | P2 | [#51](https://github.com/GhostMan612/sovereign_tagger/pull/51) | FFmpeg cancellation ownership | Runtime reliability | ST-06 | **SPEC ONLY** |
| ST-10 | P2 | [#52](https://github.com/GhostMan612/sovereign_tagger/pull/52) | MediaStore SHA-256 commit | Runtime reliability | ST-06, ST-08 | **SPEC ONLY** |
| ST-11 | P2 | [#53](https://github.com/GhostMan612/sovereign_tagger/pull/53) | Ghost history privacy/retirement | Dead ends | Operator opt-in decision | **SPEC ONLY** |
| ST-12 | P2 | [#54](https://github.com/GhostMan612/sovereign_tagger/pull/54) | Single Sentinel scanner | Dead ends | ST-26 cross-reference scan | **SPEC ONLY** |
| ST-13 | P2 | [#55](https://github.com/GhostMan612/sovereign_tagger/pull/55) | Cloud HTTPS redirects | Security & build | OAuth #40 merged | **SPEC ONLY** |
| ST-14 | P2 | [#56](https://github.com/GhostMan612/sovereign_tagger/pull/56) | Dependency compatibility matrix | Size & compatibility | ST-06 | **SPEC ONLY** |
| ST-15 | P2 | [#57](https://github.com/GhostMan612/sovereign_tagger/pull/57) | Full vs Lean APK profiles | Size & compatibility | ST-14, ST-16 | **SPEC ONLY** |
| ST-16 | P1 | [#58](https://github.com/GhostMan612/sovereign_tagger/pull/58) | SBOM & binary license evidence | Security & build | None | **SPEC ONLY** |
| ST-17 | P2 | [#59](https://github.com/GhostMan612/sovereign_tagger/pull/59) | Blueprint and README drift | Documentation & gates | Current main baseline | **SPEC ONLY** |
| ST-18 | P2 | [#60](https://github.com/GhostMan612/sovereign_tagger/pull/60) | Fault-injection/device test gates | Documentation & gates | ST-06 | **SPEC ONLY** |
| ST-19 | P3 | [#61](https://github.com/GhostMan612/sovereign_tagger/pull/61) | Workbench Stage C | Stage C | ST-08, ST-09 | **SPEC ONLY** |
| ST-20 | P3 | [#62](https://github.com/GhostMan612/sovereign_tagger/pull/62) | Settings Stage C | Stage C | ST-01, ST-02 | **SPEC ONLY** |
| ST-21 | P3 | [#63](https://github.com/GhostMan612/sovereign_tagger/pull/63) | GhostBrain Stage C | Stage C | ST-11, ST-12 | **SPEC ONLY** |
| ST-22 | P3 | [#64](https://github.com/GhostMan612/sovereign_tagger/pull/64) | Grabber Stage C | Stage C | ST-01, ST-09 | **SPEC ONLY** |
| ST-23 | P3 | [#65](https://github.com/GhostMan612/sovereign_tagger/pull/65) | MainShell Stage C | Stage C | ST-03, ST-09 | **SPEC ONLY** |
| ST-24 | P2 | [#66](https://github.com/GhostMan612/sovereign_tagger/pull/66) | StorageBridge Kotlin Stage C | Stage C | ST-02, ST-06, ST-10 | **SPEC ONLY** |
| ST-25 | P1 | [#67](https://github.com/GhostMan612/sovereign_tagger/pull/67) | OAuth deep-link device proof | Security & build | OAuth #39–#41 merged | **SPEC ONLY** |
| ST-26 | P2 | [#68](https://github.com/GhostMan612/sovereign_tagger/pull/68) | Orphan and stub adjudication | Dead ends | ST-12, ST-18 | **SPEC ONLY** |
| ST-27 | P2 | [#69](https://github.com/GhostMan612/sovereign_tagger/pull/69) | Measured performance budgets | Size & compatibility | ST-15, ST-19–24 | **SPEC ONLY** |

## Execution waves (ordered for risk containment)

### Wave 0 — Stop possible data loss and prevent risky deployment

1. ST-01: disable/guard destructive update path; specify and ship non-destructive transaction/rollback separately. Do not run old destructive updater against live installation as a test.
2. ST-05: replace implicit debug-signed release artifact fallback with a fail-closed release target.
3. ST-06: introduce native Android build and ABI test workflow; keep Dart CI separate and functional.
4. ST-16: verify proprietary binary redistribution permissions and GPL obligations before any public binary-distribution claim.

### Wave 1 — Core safety contracts

1. ST-02: dedicated Keystore token vault with rollback-safe migration and backup/restore exclusions; validate pCloud/ACR/HF paths.
2. ST-04: Whistle/Whisper/EmbeddingGemma model identity and digest checks, staged replacement.
3. ST-25: Android deep-link, live pCloud US/EU, callback replay and manual token test matrix.
4. ST-03: voice policy selects one-shot Whisper fallback, preserves WAV until terminal outcome.
5. ST-13: pCloud media URL per-hop HTTPS, no bearer leaks and bounded downloads.

### Wave 2 — Media transactions and concurrent execution

1. ST-09: FFmpeg unique session ownership and prelaunch cancellation; widget teardown.
2. ST-10: ContentResolver byte-for-byte SHA verification before URI publication.
3. ST-08: Workbench output states distinguish committed vs durable pending import with recovery manifest.
4. ST-07: cloud folder traversal explicitly reports limits, partial failures and resumable work.
5. ST-18: native FFmpeg + MediaStore synthetic fault injection, two-session cancellation and device evidence.

### Wave 3 — Dormant surfaces, packaging, source quality

1. ST-26: cross-language native/Flutter/Python/JNI orphan-contract map; do not remove dynamic callers by keyword search alone.
2. ST-12: use one Sentinel scan authority, with parity and Ghost façade decision.
3. ST-11: decide Ghost playback-history privacy opt-in versus removing dormant functionality.
4. ST-14: compatibility matrix before FFmpegKit/Chaquopy/AGP/Kotlin major version changes.
5. ST-15 + ST-27: measure per-ABI APK, performance and thermal cost, then evaluate explicit Full/Lean choice.
6. ST-17: correct current/historical documentation, model distribution, status tracking and release claims.

### Wave 4 — Stage C mechanical decomposition after contracts stabilize

- ST-19 Workbench UI presentation widgets.
- ST-20 Settings recovery/cloud/diagnostics/audio cards.
- ST-21 GhostBrain router and response façade.
- ST-22 Grabber format resolver/job queue and UI.
- ST-23 MainShell mini-player/backdrop/overlay.
- ST-24 Kotlin StorageBridge MediaStore, recovery journal, crypto and photo geometry services.

For each subsystem, use small independent implementation PRs: pure logic → async services → UI components, with no opportunistic unrelated behavior changes. Preserve MethodChannel schemas, state lifecycles and existing valid data.

## Cross-cutting closeout evidence packet

- One exact base SHA, source diff, test matrix, fail-case results, latest green CI link, and model/container/build versions.
- If native/Gradle changed: independent ARM64/x86_64 compile and Android instrumented output. If media/auth changed: device-and-provider smoke, with disposable data and no secrets in logs.
- If credential/migration/data deletion changed: crash-at-every-stage, backups, rollback and explicit ownership of staged outputs.
- If scope touches Flutter UI: key/semantics parity, real low-end device layout/performance and zero disposed-widget callbacks.
- If spec says 'all tests pass,' report actual test names and count; do not repeat a stale 143/143 total without logs from the new SHA.
- At end of phase, reconcile `.blueprints/CURRENT_STATE.md`, `ROADMAP.md`, `SESSION_HANDOFF.md`, `SECURITY.md`, `README.md`, and license docs to actual code.

## Active repository clean-up, not part of this spec campaign

The four merged OAuth branches `security/pcloud-oauth-state-binding`, `security/pcloud-bearer-header`, `security/pcloud-region-consistency`, `docs/pcloud-keystore-migration-plan` still existed after PRs #39–#42 merged; the connector has no delete-ref operation. The user has a SHA-guarded PowerShell pruning script and can delete only these four after verifying heads. **Do not delete the 28 new draft branches; they back currently open work orders.**

## Recommended PR review discipline

These 27 specs share independent branches and non-overlapping paths. They may be reviewed independently, but the eventual **runtime implementation PRs** have cross-repo dependencies listed above. An implementation PR should link the corresponding ST-number and reference a tested exact code state, not merely the spec branch. Keep the default branch stable while implementing high-risk fixes.
