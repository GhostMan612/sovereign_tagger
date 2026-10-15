#!/usr/bin/env python3
"""
GhostBrain v2 Optional In-Tab UI Hook Installer for sovereign_tagger.

The core overlay files (lib/core/forge_request.dart, lib/core/ghost_commands.dart,
lib/core/embedding_service.dart, lib/core/voice_input.dart, lib/services/ghost_world.dart,
and lib/services/ghost_brain.dart) ALREADY drive Grabber search/download and Forge
metadata/lyrics/ACR extraction out of the box!

Running this script (`python ghostbrain_tab_patcher.py`) optionally wires
`lib/tabs/tab_grabber.dart` and `lib/tabs/tab_forge.dart` so that:
  1. `TabGrabber` also populates its Artist/Title search boxes when GhostBrain runs a search.
  2. `TabForge` automatically opens the interactive MetadataReviewSheet if `req.autoTask`
     requests an interactive review in addition to prefilling the fields.
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent


def patch_tab_forge():
    path = ROOT / "lib" / "tabs" / "tab_forge.dart"
    if not path.exists():
        print(f"[SKIP] {path} not found.")
        return
    src = path.read_text(encoding="utf-8")
    if "req.autoTask" in src:
        print("[OK] lib/tabs/tab_forge.dart already has GhostBrain v2 autoTask hook.")
        return

    target_em = """  void _onPendingRequest() {
    final req = SovereignState.pendingForge.value;
    if (req == null) return;
    if (_isProcessing) {
      _setStatus("BUSY: Finish Or Eject The Current File First — The Handoff Is Queued.");
      return;
    }
    SovereignState.pendingForge.value = null;
    _mount(req);
  }"""

    target_hy = """  void _onPendingRequest() {
    final req = SovereignState.pendingForge.value;
    if (req == null) return;
    if (_isProcessing) {
      _setStatus("BUSY: Finish Or Eject The Current File First - The Handoff Is Queued.");
      return;
    }
    SovereignState.pendingForge.value = null;
    _mount(req);
  }"""

    replacement = """  void _onPendingRequest() {
    final req = SovereignState.pendingForge.value;
    if (req == null) return;
    if (_isProcessing) {
      _setStatus("BUSY: Finish Or Eject The Current File First — The Handoff Is Queued.");
      return;
    }
    SovereignState.pendingForge.value = null;
    _mount(req).then((_) async {
      if (!mounted) return;
      if (req.autoTask == ForgeAutoTask.searchMetadata && req.prefill.isEmpty) {
        await _searchMetadata();
      } else if (req.autoTask == ForgeAutoTask.findLyrics && (req.prefill['LYRICS'] ?? '').isEmpty) {
        await _findLyrics();
      } else if (req.autoTask == ForgeAutoTask.acrIdentify && req.prefill.isEmpty) {
        await _acrIdentify();
      }
    });
  }"""

    if target_em in src:
        src = src.replace(target_em, replacement, 1)
        path.write_text(src, encoding="utf-8")
        print("[PATCHED] lib/tabs/tab_forge.dart wired with ForgeAutoTask follow-up triggers.")
    elif target_hy in src:
        src = src.replace(target_hy, replacement, 1)
        path.write_text(src, encoding="utf-8")
        print("[PATCHED] lib/tabs/tab_forge.dart wired with ForgeAutoTask follow-up triggers.")
    else:
        print("[INFO] lib/tabs/tab_forge.dart already uses ForgeRequest.prefill (no changes needed).")


def patch_tab_grabber():
    path = ROOT / "lib" / "tabs" / "tab_grabber.dart"
    if not path.exists():
        print(f"[SKIP] {path} not found.")
        return
    src = path.read_text(encoding="utf-8")
    if "GhostCommandBus" in src:
        print("[OK] lib/tabs/tab_grabber.dart already has GhostCommandBus hook.")
        return

    import_anchor = "import '../screens/main_shell.dart';"
    if import_anchor in src:
        src = src.replace(
            import_anchor,
            import_anchor + "\nimport '../core/ghost_commands.dart';",
            1,
        )

    init_anchor = "SovereignState.pendingGrabberUrl.addListener(_onSharedUrl);"
    if init_anchor in src:
        src = src.replace(
            init_anchor,
            init_anchor + "\n    GhostCommandBus.pendingGrabberCommand.addListener(_onGhostGrabCommand);",
            1,
        )

    post_anchor = "WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedUrl());"
    if post_anchor in src:
        src = src.replace(
            post_anchor,
            post_anchor + "\n    WidgetsBinding.instance.addPostFrameCallback((_) => _onGhostGrabCommand());",
            1,
        )

    dispose_anchor = "SovereignState.pendingGrabberUrl.removeListener(_onSharedUrl);"
    if dispose_anchor in src:
        src = src.replace(
            dispose_anchor,
            dispose_anchor + "\n    GhostCommandBus.pendingGrabberCommand.removeListener(_onGhostGrabCommand);",
            1,
        )

    shared_anchor = """  void _onSharedUrl() {
    final url = SovereignState.pendingGrabberUrl.value;
    if (url == null || url.isEmpty) return;
    SovereignState.pendingGrabberUrl.value = null;
    setState(() {
      _urlController.text = url;
      _statusMessage = "Link Received. Choose MAX AUDIO, QUICK VIDEO Or FETCH ALL FORMATS.";
    });
  }"""

    shared_replacement = shared_anchor + """

  void _onGhostGrabCommand() {
    final cmd = GhostCommandBus.pendingGrabberCommand.value;
    if (cmd == null) return;
    GhostCommandBus.pendingGrabberCommand.value = null;
    if (!mounted) return;
    setState(() {
      _searchSource = cmd.source;
      if (cmd.isSearchQuery) {
        if (cmd.queryOrUrl.contains(' - ')) {
          final parts = cmd.queryOrUrl.split(' - ');
          _artistController.text = parts.first.trim();
          _titleController.text = parts.sublist(1).join(' - ').trim();
        } else {
          _artistController.clear();
          _titleController.text = cmd.queryOrUrl;
        }
      } else {
        _urlController.text = cmd.queryOrUrl;
      }
    });
  }"""

    if shared_anchor in src:
        src = src.replace(shared_anchor, shared_replacement, 1)
        path.write_text(src, encoding="utf-8")
        print("[PATCHED] lib/tabs/tab_grabber.dart wired with GhostCommandBus listener.")
    else:
        print("[INFO] lib/tabs/tab_grabber.dart uses SovereignState.pendingGrabberUrl directly.")


if __name__ == "__main__":
    patch_tab_forge()
    patch_tab_grabber()
    print("Done! Run `flutter analyze --no-pub` to verify.")
