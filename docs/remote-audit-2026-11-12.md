# Sovereign Tagger — Remote Audit Register (2026-11-12)

**Base:** `main` `ba708fe347aa83cba199375e1441ad4aeb1c7408`
**Method:** Read-only remote source review, GitHub tree enumeration (273 entries), indexed symbol searches, targeted full-source reads across Flutter/Dart, Kotlin/Android, Python/Chaquopy, test and documentation surfaces, plus isolated draft changes created on branches. **Not a line-by-line verification of every source file.** No local Android build, Flutter execution, ADB operation, or destructive media test performed by this auditor.
**Disposition:** 14 remediation drafts created separately as PR #24–#37, all targeting `main`, none merged as part of this audit. The PRs below are the individual review units.

## Executable fixes and narrow documentation corrections

| PR | Priority | Finding | Change type |
|---|---|---|---|
| [#24](https://github.com/GhostMan612/sovereign_tagger/pull/24) | P1 | Offline cache entry deleted before replacement copy succeeds; potential loss of last valid offline copy | Code + regression tests |
| [#25](https://github.com/GhostMan612/sovereign_tagger/pull/25) | P1 | Same cloud file's parallel downloads share staging filenames | Code |
| [#26](https://github.com/GhostMan612/sovereign_tagger/pull/26) | P3 | AGENTS/ARCHITECTURE describe old XOR-only boot and obsolete state | Documentation |
| [#27](https://github.com/GhostMan612/sovereign_tagger/pull/27) | P1 | Recovery-vault platform failure reported as empty list; false-safe UI | Code + regression tests |
| [#28](https://github.com/GhostMan612/sovereign_tagger/pull/28) | P3 | Unreferenced Sentinel naming wrappers duplicate canonical policy | Code prune |
| [#29](https://github.com/GhostMan612/sovereign_tagger/pull/29) | P1 | Millisecond timestamp can collide across recovery backup operations | Kotlin code |
| [#30](https://github.com/GhostMan612/sovereign_tagger/pull/30) | P0 | Untrusted OAuth callback hostname reaches bearer-token API endpoint | Code + regression tests |
| [#32](https://github.com/GhostMan612/sovereign_tagger/pull/32) | P1 | pCloud downloader accepts truncated nonempty file despite known Content-Length | Code |
| [#37](https://github.com/GhostMan612/sovereign_tagger/pull/37) | P3 | F-Droid readiness, original-untouched guarantee, missing contributor verification script | Documentation |

## Larger work orders — not functional fixes

| PR | Priority | Finding / required implementation |
|---|---|---|
| [#31](https://github.com/GhostMan612/sovereign_tagger/pull/31) | P1/P2 | Whistle fails without automatic Whisper fallback; `VoiceInput.useEngine` no discovered UI call; Ghost play-history persisted but unconnected |
| [#33](https://github.com/GhostMan612/sovereign_tagger/pull/33) | P1/P2 | Whistle/Whisper size-only model checks; MediaStore backup may not equal original; folder enumeration depth/cap/progress; missing native failure injection |
| [#34](https://github.com/GhostMan612/sovereign_tagger/pull/34) | P0/P1 | Python updater deletes live yt-dlp before replacement and has no rollback; no explicit digest/provenance check; misleading per-dependency success |
| [#35](https://github.com/GhostMan612/sovereign_tagger/pull/35) | P2/P3 | Dormant `SentinelStore.sentinelScan` duplicates stronger live scanner; uncalled Kotlin channel cases; large cross-cutting modules |
| [#36](https://github.com/GhostMan612/sovereign_tagger/pull/36) | P1/P2 | pCloud OAuth callback lacks `state` binding; bearer token held in ordinary preferences; need regional callback consistency |

## Architecture and maintenance critique

- Large source units complicate regression isolation: `tab_workbench.dart` ~193 KB, `settings_screen.dart` ~109 KB, `ghost_brain.dart` ~98 KB, `tab_grabber.dart` ~85 KB, `main_shell.dart` ~65 KB and `StorageBridge.kt` ~61 KB. Safe incremental extraction needs parity tests before reorganizing.
- `flutter analyze` and Flutter/Python CI do not validate Kotlin compilation or native fault injection. Treat CI green as a narrow gate, not device/data-integrity sign-off.
- Symbol search located no production `UnimplementedError` declarations or literal TODO/FIXME stubs, but functional dead ends exist. **No blanket zero-stub guarantee** is justified without full static/dynamic reachability analysis.
- Online-capable pCloud/yt-dlp/pip paths must be clearly scoped to operator intent; claims of completely offline operation are true only for local processing, not those integrations.
- License/distribution status should not be advertised as official F-Droid-ready without a reproducible build and third-party binary review, especially the proprietary ACRCloud SDK.

## Merge order and gates

**First:** #26, #28, #24, #25, #32 (small source/docs, after test review).
**Next:** #27 and #29 (recovery fail-closed + backup uniqueness; Android fault injection required).
**Security priority:** #30 (pCloud host allowlist); treat it as high urgency, independently verify real pCloud sign-in before shipping.
**Critical architecture:** #31, #33, #34, #35 and #36 are planning drafts and must not be labeled as fixed code. Follow their work orders in separate child PRs.
**Documentation:** #37 should be reconciled with downstream distribution and security review.

All drafts remain open for operator review. None of this register implies a finished full-repository proof, hardware verification, or approval to modify irreplaceable media.
