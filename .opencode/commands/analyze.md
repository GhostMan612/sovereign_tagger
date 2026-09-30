---
description: Flutter analyze (filtered) — errors/warnings only. END-OF-PLAN ONLY.
agent: build
---

⛔ **END-OF-PLAN TOOL (RULES.md §1A.0).** Do not invoke this while implementing.
Run it once when the phase is finished, in the same batched shell block as the
commit. It is a gate, not a lookup — invoking it "to check one thing" is the exact
habit §1A.0 exists to stop.

Run the Sovereign Tagger analyzer gate exactly as defined in AGENTS.md. Do not dump raw output.

1. Execute `flutter analyze --no-pub` in `C:\sovereign_tagger`
   (⚠️ this previously said `C:\sovereign_tagger_2`, which is **deprecated** — the command was pointed at a dead path.)
2. Pipe through `Select-String -Pattern "error •|warning •"` and show the first 20 hits only
3. Then show the last 3 lines (expect "No issues found!" on clean)
4. If any `error •` exists, group by file and suggest the fix. If only `warning •`/`info`, note them but do not block.
5. Never ingest full unfiltered logs.
