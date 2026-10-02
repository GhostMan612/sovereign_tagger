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
- `.blueprints\` **IS tracked in git** (7 files: RULES, SESSION_HANDOFF, CURRENT_STATE,
  ROADMAP, ARCHITECTURE, BLUEPRINTS). This line previously said "intentionally
  untracked — do not fix this unless asked", which was **false**: the files were
  committed, and the false note told every future session (and every auditor) to
  leave the contradiction standing. It is now documented accurately. Treat these as
  committed working docs and stage them by explicit path like any other file.

### 1.4 Nothing outside the project without approval
Do not install software, modify system settings, or write outside `C:\sovereign_tagger` / approved tool homes without asking first.

### 1.5 Builds (CHANGED 2026-10-01 — operator override)
`flutter build apk` is **allowed** on this host. The old blanket ban existed because a build was treated as device-dependent and slow; the operator has overridden that. Builds are still governed by §1A.0: they are an **end-of-plan** activity, never a mid-plan "let me check" probe — a single release build is minutes, not seconds.

- Use the full SDK path: `C:\android\flutter\bin\flutter.bat build apk --release`.
- **Release signing falls back to the debug keystore** unless `SOVEREIGN_KEYSTORE` is set (env or `local.properties`, `android/app/build.gradle:62`). A release APK is therefore **not Play-ready** until a real keystore exists — say so when reporting a release build.
- `flutter build appbundle` and direct `:app:assembleRelease` / `:app:bundleRelease` stay `ask` — store packaging and signing are deliberate operator calls.
- Installing and running on the Moto G is still the operator's step via Android Studio. A host build proves it *compiles*; only a device run proves it *works*.
- Artifacts land in `build/` and are git-ignored (`*.apk`, `*.aab`). Never stage a build output.

---

## 1A. CONTEXT & OUTPUT DISCIPLINE

### 1A.0 — ⛔ THE SHELL GATE. Read before you touch anything.

Added 2026-09-30 after a full audit found this repo had **no shell-discipline rule
at all**, and — worse — that §1A.4 below was *instructing* the agent to run
`flutter analyze` **during development**. The problem was never discipline. It was
that the documentation said the wrong thing, so an agent following it faithfully
shelled out mid-plan every few minutes.

**The rule, and it is a hard gate:**

> **During a plan, the shell must not be called at all.** Not once. Not "just to
> check one thing". The plan is not finished, so there is nothing to verify *for*.
> Verification is an **end-of-plan** activity. Calling it early does not make the
> work safer — it makes it slower, and it produces **stale signal** that you then
> have to re-derive when the plan actually ends.

**Route every intent to a tool. There is no judgment call here:**

| You want to… | Use | NEVER |
|---|---|---|
| See a file, a block, line numbers, a value | `read` | `type`, `cat`, `Get-Content`, `head` |
| Find where a symbol is defined or used | `grep` | `Select-String`, `rg`, `grep` |
| Find a file by name | `glob` | `Get-ChildItem`, `ls`, `dir` |
| Change text in a file | `edit` | `Set-Content`, `sed -i`, `Out-File`, `>>` |
| Create a file | `write` | `New-Item`, heredoc |
| Audit the repo for a pattern | `grep` + subagents | shell loops |
| Check whether a path exists | `glob` / just `read` it | `Test-Path` |
| **Does it compile?** | **NOTHING — queue it** | the shell |
| **Do tests pass?** | **NOTHING — queue it** | the shell |
| **`git status` / `diff` / `commit`** | **NOTHING — queue it** | the shell |
| **Device / smoke / screenshot** | **NOTHING — queue it** | the shell |

**The three traps, named — because all three happened here:**

1. **"Let me just check it compiles."** `flutter analyze` costs 20–90s every time
   and is blind to every bug class this repo actually has. Every law in §3 below
   (FFmpeg map arguments, audio-queue locking, tab-wrapper identity) is invisible
   to the analyzer, and each has already shipped a bug. It has caught none of them.
2. **"One quick `git status`."** Does not change the next edit. Batch it.
3. **"One probe to see what's going on."** Every probe is verification. Queue it.

**Batching is the entire point.** A correct plan here is:
`read → edit → read → edit … for the whole phase`, then **one** shell block:
`analyze --no-pub`, the mojibake signature grep, the shader compile if shaders
changed, then the commit. That is the entire allowed shell surface.

**The escape hatch, so the rule can never deadlock you:**
> If this feels like it is costing correctness — a plan that genuinely cannot be
> completed without mid-flight verification — **that is the signal to report a
> blocked item and wait, not to run the command.**

**Machine-enforced, not just prose:** the `.opencode/agents/*.md` frontmatter
`permission.bash` rules `deny` the read/search/write commands above and `ask`
on anything unclassified. A denial is a *refused call*, not a warning that
scrolls past. Prose without a deny is a suggestion.

> **Schema trap (G34).** Pattern rules live under **`permission:`**, never under
> `tools:`. `tools` is booleans-only (`additionalProperties: {type: boolean}`)
> and marked `@deprecated Use 'permission' field instead`. Putting
> `{pattern: deny}` under `tools.bash` is malformed — it does not deny anything,
> it silently fails to configure. **Within a `permission` object, insertion
> order decides: the LAST matching rule wins**, so broad rules go first
> (`"*": ask`) and narrow ones last.

### 1A.4 — Output discipline (CHANGED 2026-09-30)

- Filter all terminal output; ingest failures only, never passing noise.
- No massive file reads — probe large files with a short **read-only** script.
- Spawn subagents for deep exploration; return summaries, not raw dumps.
- Proactively compact context after each verified phase.
- ~~Targeted verification during development~~ — **REMOVED, it was the cause of
  the mid-plan shell traffic.** Verification now happens **once, at the end of a
  phase**, per §1A.0. There is no "quick check while developing" and there never
  should have been.

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
