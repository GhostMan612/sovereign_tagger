# ST-19 — Stage C Workbench UI panels and waveform controller extraction

> **Priority:** P3 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
Workbench is still about 180 KB in one stateful tab despite Stage A pure builders and Stage B batch queue extraction; UI pieces are entwined with session lifecycle and MediaStore error paths.

- [`lib/tabs/tab_workbench.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/tabs/tab_workbench.dart)
- [`lib/widgets/waveform_studio.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/widgets/waveform_studio.dart)
- [`lib/workbench/workbench_models.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/workbench/workbench_models.dart)
- [`lib/workbench/workbench_queue.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/workbench/workbench_queue.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)

## Proposed file/interface changes
- `lib/workbench/components/waveform_editor.dart (new)`
- `lib/workbench/components/dsp_controls.dart (new)`
- `lib/workbench/components/batch_controls.dart (new)`
- `lib/tabs/tab_workbench.dart`
- `test/workbench_widget_contract_test.dart (new)`

## Surgical extraction phases
1. Take widget tree inventory and identify state owners for waveform, region selection, DSP mode controls, batch list, status and output save UI; preserve existing lib/widgets/waveform_studio.dart rather than duplicate it.
2. Extract waveform view/controller only after mapping paint inputs, transform, selection drag semantics and audio progress subscriptions; keep source-of-truth in coordinator until tests pass.
3. Move DSP panels into independent stateless/presentation components, with typed immutable parameter objects and callbacks, no direct FFmpeg or file I/O in widgets.
4. Extract batch job controls and status into a widget reading WorkbenchQueue snapshots, including cancel, pending-import recovery, error and monotonic progress.
5. Keep TabWorkbench as coordinator holding active queue, mount/unmount lifecycle, navigation and permission prompts; avoid changing operation registry or FFmpeg commands.
6. Preserve keys, accessibility/semantics, keyboard shortcuts, theme/color animations and Android saved state. If 35 KB target isn't realistic, measure and explain.
7. No move of native platform handlers or MediaStore saving in a pure widget extraction PR; route missing feature requests to separate work orders.

## Tests and negative conditions
- [ ] Golden/widget tests for selected waveform region, seeks, touch gestures, tabs and orientation changes.
- [ ] Repeated navigation/disposal during batch yields zero setState-after-dispose, leaked subscriptions or duplicate renders.
- [ ] Compare full set of DSP operation labels, ranges, output files and callbacks against baseline.

## Acceptance evidence
- [ ] Behavior parity and no new FFmpeg/MediaStore I/O ownership in presentation components.
- [ ] Workbench root size reduced measurably, with source-state contract documentation.
- [ ] Dart CI plus Moto G UI/gesture smoke.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
Work only after/alongside ST-08/09 queue lifecycle repairs; one panel per implementation PR.

## Rollback plan
Revert individual presentation extracts while retaining Stage A/B pure/service files.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
