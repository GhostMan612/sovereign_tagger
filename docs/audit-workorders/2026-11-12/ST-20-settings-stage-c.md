# ST-20 — Stage C Settings cards and secure credential coordinator

> **Priority:** P3 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
Settings screen is roughly 109 KB and combines OAuth initiation, raw-token entry, Python updater triggers, recovery vault, diagnostics and UI, making security review and functional testing difficult.

- [`lib/screens/settings_screen.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/settings_screen.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)
- [`lib/core/cloud_settings.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/cloud_settings.dart)
- [`lib/core/model_lifecycle.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/model_lifecycle.dart)

## Proposed file/interface changes
- `lib/screens/settings/cloud_account_card.dart (new)`
- `lib/screens/settings/recovery_vault_card.dart (new)`
- `lib/screens/settings/engine_diagnostics_card.dart (new)`
- `lib/screens/settings/audio_preferences_card.dart (new)`
- `lib/screens/settings_screen.dart`

## Surgical extraction phases
1. Inventory every Settings shared ValueNotifier, controller, persistence key, MethodChannel and side effect before cutting a widget.
2. Extract recover-vault card as a presentation adapter over existing tested StorageClient contracts; do not change recover/discard semantics.
3. Extract cloud account card with typed AuthAttemptState, active state nonce ownership and region constraints; protect manual-token path; defer secret-at-rest changes to ST-02.
4. Extract engine diagnostics card with updater clearly disabled pending P0 ST-01, Python doctor results and FFmpeg model readiness report.
5. Extract audio, visual and background-effect preferences with typed settings model and idempotent initialization; no writes from build() methods.
6. Retain SettingsScreen coordinator for dialogs, platform permission prompts, snapshot update order and disposal of all controllers.
7. Use bounded widgets and isolate async callbacks from disposed context; avoid rebuilding entire screen for one progress tick.

## Tests and negative conditions
- [ ] Golden and interaction tests for all cards, status transitions, OAuth state callback, reconnect and recovery-vault failure.
- [ ] Widget disposal during pending await does not call setState; controllers/subscriptions disposed exactly once.
- [ ] Accessibility labels, theme, backup/export flows and scroll positions preserved.

## Acceptance evidence
- [ ] No token logging or callback bypass introduced by UI move; no destructive updater reactivation.
- [ ] Same stored preference keys with migration plan if changed.
- [ ] Android device settings navigation and keyboard/permission smoke.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
Security ST-01/02 must not be bundled into this UI-only extraction; integrate after their interfaces stabilize.

## Rollback plan
Recombine affected UI card without changing underlying native data or persisted preference schema.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
