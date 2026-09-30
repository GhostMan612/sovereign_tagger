# RULES.md — Sovereign Tagger v2 Operating Law
> **CANONICAL RULESET.** Every session MUST read this file before doing any work.
> If any other document contradicts this file, THIS FILE WINS.

---

## 1. ABSOLUTE RULES (never violated, no exceptions)

### 1.1 External directories are READ-ONLY
Never create, modify, move, or delete ANYTHING under these paths:
```
C:\pathfinder_god
C:\Recovery for All
C:\Sovereign Nodes
C:\sovereign_mantle
```
- **Writable work area:** `C:\sovereign_tagger` (plus user-approved tool homes: `%USERPROFILE%\.gradle`, `%USERPROFILE%\pub-cache`, usage of `C:\android` SDK).
- `C:\sovereign_tagger_2` was the disposable playground copy but is now deprecated — all work happens in `C:\sovereign_tagger`.

### 1.2 Secrets and commercial data never enter source control
- Never commit: API keys (Genius/ACRCloud), keystores (`*.keystore`, `debug.keystore`), `local.properties`.
- Keys live only in device SharedPreferences or user-exported `.bin` backups — never hardcoded, never fixture data.
- Synthetic data only: test fixtures use placeholders (`SAMPLE ANCESTOR A`, `Test Track 01`). No real operator family names or personal media metadata in committed code/tests.

### 1.3 Git discipline
- **Stage by explicit path only.** `git add -A` / `git add .` are FORBIDDEN — they pull in unrelated tagger work.
- Commits happen as part of an approved session workflow; never force-push or delete branches unless explicitly asked.
- `.blueprints\` is intentionally untracked/local-only — do not "fix" this unless asked.

### 1.4 Nothing outside the project without approval
Do not install software, modify system settings, or write outside `C:\sovereign_tagger` / approved tool homes without asking first.

---

## 1A. CONTEXT & OUTPUT DISCIPLINE

- Filter all terminal output; pipe for failures only (`| Select-String "error|fail"`), never ingest passing noise.
- No massive file reads — probe large files/logs/data with short scripts or filtered searches instead.
- Targeted verification during development (`flutter analyze --no-pub` filtered); full builds reserved for staged-phase verification.
- Spawn subagents for deep exploration when available; return summaries, not raw dumps.
- Proactively compact context after each verified phase.

---

## 2. PROJECT CONVENTIONS (The Sovereign Directives)

1. **Full code only** — no partial snippets, no TODO stubs.
2. **No comments in code** — except the Genesis header already carried by core files:
   ```
   // ============================================================
   // As Above, So Below. As Within, So Without.
   // The Future Dictates the Past and the Past is Always Present.
   // ============================================================
   ```
3. **Cyberpunk aesthetic is canon**: monospace fonts (`ShareTechMono`, `VT323`), black backgrounds, accent-color (`SovereignState.accentColor`) reactive UI. All new UI obeys the theme.
4. **Lossless guarantee**: Forge never transcodes; Workbench DSP preserves lossless containers (FLAC→FLAC, WAV→WAV) unless the operator explicitly chooses lossy output.
5. **Global state flows through `SovereignState` / `AudioService` statics** (main_shell.dart). New cross-tab features extend those, not ad-hoc singletons.

---

## 3. TECHNICAL LAWS (learned the hard way — see BLUEPRINTS.md gotcha registry)

| Law | Rule |
|-----|------|
| FFmpeg calls | ALWAYS `FFmpegKit.executeAsync()`. Sync `execute()` freezes the Android UI thread. |
| Merge muxing | Explicit `-map 0:v:0 -map 1:a:0` on every merge. Verify output stream count via `getMediaInformation`; never trust blind `-c copy` fallbacks. |
| Tag writes | Native `id3` channel (jaudiotagger) only — it edits in place, lossless. NEVER route tag changes through FFmpeg remux. Preserve original container extension on export renames. |
| yt-dlp split jobs | Composite format ids arrive as `"vid+aud"`. Python bridge downloads halves separately; Flutter owns the merge. Facebook often lacks `audio only` formats — always probe before merging. |
| Batch loops | Every await inside `_runBatch` must be guarded; any throw must reset `_isBatchRunning` or the pipeline tab locks forever. |
| Async UI | Every `setState` after an `await` needs a `mounted` check first. |
| Queue mutations | Never mutate `AudioService.playlist` directly — use `AudioService` mutators so `_audioSource` stays in sync. |
| Storage | MediaStore exports via `storage` channel only. Temp artifacts belong under `getTempDirectory`; clean up on failure paths too. |

### 3.1 THE POWERSHELL MOJIBAKE LAW (hard-won, broken multiple sessions)

> **NEVER modify source files (.dart / .kt / .py / .yaml / .xml / .gradle) through PowerShell text pipelines.**
> This means: `Get-Content` → `-replace` → `Set-Content`, `Out-File`, `Add-Content`, `[IO.File]::WriteAllText` re-encoding, heredoc string splicing. **BANNED for source edits.**

Observed damage (Phase 25 device-debug rounds AND earlier original-build sessions):
- PS 5.1 reads UTF-8 files as ANSI when no BOM is present, then writes back double-encoded: `—` → `â€"`, `•` → `â€¢`, `✓` → garbage, `⚠` → garbage.
- Worse, it produced **silent single-letter substitutions inside ASCII code**: `setState`→`setYtate`, `SYSTEM STABLE`→`YYYTEM YTABLE`, `TextStyle`→`RextStyle`, `AUDIT`→`AUDIR`. Some of these compile-break (analyzer catches), but swaps inside string literals ship silently to the device.
- Cost: an entire debug round lost diagnosing ghost rendering while the real regression was tooling corruption.

Required procedure:
1. **All source edits go through editor tools (Read/Edit/Write)** — never shell text pipelines.
2. Scripted bulk transforms (if truly necessary) only via **Python with explicit `encoding='utf-8'` on both read and write**.
3. After ANY scripted or bulk touch, run BOTH:
   - `flutter analyze --no-pub` → must be clean
   - signature grep: `'â€|Ã|Â'` over changed files + eyeball known-label strings
4. If corruption is found: repair byte-exact (Python replace pairs), never by re-running PS. See SESSION_HANDOFF Phase 25 entry for the repair-pair list (`setState/setYtate`, `Text/RextStyle`, `â€"→—`, etc.).

---

## 4. WORKFLOW LAW

### 4.1 Cold start (every session, in order)
1. Read `.blueprints\SESSION_HANDOFF.md`
2. Read THIS file (`RULES.md`)
3. Read `.blueprints\CURRENT_STATE.md` → `.blueprints\ROADMAP.md`
4. Work the current phase; consult `BLUEPRINTS.md` / `ARCHITECTURE.md` as needed

### 4.2 Session end (every session)
1. Update `.blueprints\SESSION_HANDOFF.md` ("Where we are" + "Next actions")
2. Tick phase status in `.blueprints\ROADMAP.md`
3. Refresh `.blueprints\CURRENT_STATE.md`
4. Log notable discoveries in `BLUEPRINTS.md` gotcha registry

### 4.3 Verification law
No phase is done until its verification gate passes (analyze filtered + targeted smoke checks + build when structural). Evidence before status flips.

### 4.4 Scope law
Big dreams go into ROADMAP phases first. Ship vertical slices per phase; never let polish precede correctness gates.
