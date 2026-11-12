# ST-23 — Stage C MainShell transport, backdrop and Ghost overlay boundaries

> **Priority:** P3 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
MainShell (~65 KB) coordinates audio service transport, shader/ticker lifecycle, navigation and Ghost overlay with shared static buses; this entanglement makes playback focus and UI disposal regressions likely.

- [`lib/screens/main_shell.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/screens/main_shell.dart)
- [`lib/widgets/animated_tab_stack.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/widgets/animated_tab_stack.dart)
- [`lib/widgets/ghost_chat_overlay.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/widgets/ghost_chat_overlay.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)

## Proposed file/interface changes
- `lib/shell/mini_player_bar.dart (new)`
- `lib/shell/shell_backdrop.dart (new)`
- `lib/shell/ghost_overlay_manager.dart (new)`
- `lib/screens/main_shell.dart`
- `test/main_shell_lifecycle_test.dart (new)`

## Surgical extraction phases
1. Map root Stack, AnimatedTabStack preservation rules, navigation bus, current media and color notifiers and AudioService ownership.
2. Extract mini-player as a view over stable transport state; do not create duplicate audio players or music notification sessions.
3. Extract shader/background painter/ticker ownership into a disposed controller, with RepaintBoundary and occlusion behaviors unchanged.
4. Extract Ghost overlay visibility, keyboard, focus and voice sheet coordination without losing tab state or duplicating VoiceInput.
5. Keep MainShell as navigator, lifecycle observer and state-binding root; no business logic in painter/widget methods.
6. Use measurable frame-time benchmarks and prevent ticker subscriptions when screen is inactive.

## Tests and negative conditions
- [ ] Tab switching, rotation, background/foreground and app resume maintain queue and player focus.
- [ ] Ghost overlay mic/keyboard interactions do not leak focus or duplicate speech transcripts.
- [ ] Shader frame budget and MiniPlayer position consistency on weak device.

## Acceptance evidence
- [ ] No background playback/notification regressions and no extra global player instances.
- [ ] No ghost modal focus trap, ticker leak or screen rebuild overwork.
- [ ] Moto G and BLU two-device lifecycle smoke.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
ST-03 voice fallback, ST-09 lifecycle cancellation; can extract visuals independently.

## Rollback plan
Revert one presentation component at a time while preserving root app shell and global bus.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
