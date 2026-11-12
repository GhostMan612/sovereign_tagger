# CONTRIBUTING TO SOVEREIGN TAGGER

> **The Sovereign Directives & Code Conventions**  
> All contributors, agents, and maintainers must strictly adhere to the following laws before submitting code.

---

## 1. Absolute Operating Laws

### 1.1 The Genesis Header
Every source code file (`.dart`, `.kt`, `.py`) must open with the exact 4-line Genesis header on lines 1–4:
```
// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================
```
*(In Python source files, use `#` prefixes instead of `//`).*

### 1.2 Zero Comments in Code
In accordance with Sovereign Tagger project standards:
- **No inline or block comments are permitted anywhere in code files after line 4.**
- Code must be fully self-describing through expressive naming, robust type signatures, and clear architecture.
- Do not add `// TODO`, `// FIXME`, `/* block comments */`, or explanatory docstrings in application logic.
- Documentation lives exclusively in Markdown (`README.md`, `ARCHITECTURE.md`, `.blueprints/`).

### 1.3 Full Implementations Only
- No stubbed functions or placeholder implementations (`throw UnimplementedError()`).
- No empty catch blocks that swallow critical diagnostics.
- No incomplete snippets. Every edit must deliver fully working code.

---

## 2. Engineering & Toolchain Discipline

### 2.1 The Shell Gate (§1A.0)
During active editing and plan execution, terminal commands must **never** be executed mid-flight.
- Code changes, inspections, and file creation must proceed through editor tools (`read_file`, `edit_file`, `write_file`).
- Verification is an **end-of-plan** activity:
  ```powershell
  # The End-of-Plan Batch
  C:\android\flutter\bin\flutter.bat analyze --no-pub
  python -m unittest discover -s test/python -p "test_*.py"
  C:\android\flutter\bin\flutter.bat build apk --debug --target-platform android-arm64
  ```

### 2.2 PowerShell Mojibake Law (§3.1)
**NEVER modify source files (`.dart`, `.kt`, `.py`, `.yaml`, `.gradle`) using PowerShell text pipelines** (`Get-Content`, `Set-Content`, `Out-File`, `Add-Content`). PowerShell 5.1 misinterprets UTF-8 files as ANSI, injecting fatal character corruption (em-dashes corrupted to multi-byte noise) and silent character swaps (`setState` → `setYtate`).
- Always use proper UTF-8 editor APIs or Python scripts explicitly initialized with `encoding='utf-8'`.

### 2.3 Explicit Git Staging
- **Never use `git add .` or `git add -A`.**
- Stage modified files explicitly by relative path:
  ```bash
  git add lib/tabs/tab_grabber.dart lib/core/playback_fx.dart
  ```

---

## 3. Architecture & Media Safety Invariants

1. **FFmpeg Serialization:** Never call `FFmpegKit.execute()` directly on the UI thread. All FFmpeg executions must be queued through `await FFmpegExecutor.execute(...)`.
2. **Audio Queue Locking:** Never mutate `AudioService.playlist.value` directly. Queue operations must route through `AudioService` serialized mutators (`replacePlaylist`, `playNext`, `addToQueue`, `reorderPlaylist`, etc.) to keep JustAudio and the system notification in sync.
3. **Lossless Guarantee:** The Forge must never transcode or alter container formats during tag operations. Workbench DSP operations must preserve the source container (`FLAC` → `FLAC`, `WAV` → `WAV`) unless the operator explicitly selects a conversion format.
4. **UI Lifecycle Safety:** Every `setState` invocation following an `await` must be preceded by an `if (!mounted) return;` guard.
