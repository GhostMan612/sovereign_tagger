# CLAUDE.md — Sovereign Tagger

Flutter Android app: yt-dlp via chaquopy Python, FFmpeg DSP, jaudiotagger tagging, `just_audio` player. The main touch surface is `lib/**/*.dart`. Native bridges are `android/app/src/main/kotlin/**/MainActivity.kt` and `android/app/src/main/python/sovereign_yt/`.

## Read first (every session, in order)

1. `.blueprints/SESSION_HANDOFF.md`: where we are, what shipped and the next actions. Its DOCUMENT MAP links every other doc.
2. `.blueprints/RULES.md`: the **canonical** operating law. When docs conflict, RULES wins.
3. `.blueprints/CURRENT_STATE.md` has the per-file map and the known-issue registry; check it before touching a tab. `.blueprints/ROADMAP.md` has the phases and their verification gates.
4. `AGENTS.md`: the compact guide, with architecture, the laws table and toolchain quirks (the dependency ceiling is frozen).

Executable files (`pubspec.yaml`, `android/app/build.gradle`) beat prose. Never rely on memory across sessions.

## Branches & git

- `main` is the single canonical branch. Do new work on `main` or on a short-lived branch off it. `master` is legacy (fully merged into `main`), so don't build on it.
- Stage by explicit path only (`git add lib/tabs/tab_forge.dart`). Never use `git add .` or `git add -A`.
- Wait for explicit approval before `git commit` / `git push`, unless you are executing an already-approved plan. Never force-push or delete branches unless asked.
- Never commit secrets such as Genius/ACRCloud keys, keystores or `local.properties` (RULES §1.2). Fixtures use synthetic data only.

## Verification

- The gate: `flutter analyze --no-pub` must print `No issues found!`.
  ```bash
  flutter analyze --no-pub 2>&1 | tail -3
  flutter analyze --no-pub 2>&1 | grep -E "error •|warning •" | head -20
  ```
- There is no `test/` suite and no test runner script. Don't invent one.
- Never run `flutter build apk` here. The operator builds and installs on their device through Android Studio. Anything that needs a device goes on the smoke list under "Next actions" in SESSION_HANDOFF.

## Editing

- **PowerShell mojibake ban (RULES §3.1):** never edit source through PowerShell text pipelines (`Get-Content`/`-replace`/`Set-Content`, `Out-File`, `Add-Content`). PS 5.1 double-encodes UTF-8 (`—` → `â€"`) and silently swaps letters (`setState` → `setYtate`). Use the Read/Edit/Write tools. If a bulk transform is unavoidable, script it in Python with `encoding='utf-8'` on both read and write. Then run analyze and grep the changed files for `â€|Ã|Â`.
- **No code comments** except the Genesis header that core files already carry (RULES §2).
- Obey the technical laws in RULES §3 and the `AGENTS.md` laws table: async FFmpeg only, tag writes through jaudiotagger, a `mounted` check after every `await`, and queue changes only through the `AudioService` mutators.

## Context discipline

- Filter CLI output down to failures. Never read passing noise, full logs or raw JSON into context.
- Run targeted checks on what you changed, and save the full gate for when a change is ready to commit.
- Probe large files with short scripts or filtered searches. Don't read them whole.

## Session end

Update SESSION_HANDOFF ("Where we are" and "Next actions"), tick ROADMAP and refresh CURRENT_STATE. Log new gotchas in `.blueprints/BLUEPRINTS.md` (RULES §4.2).
