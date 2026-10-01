---
description: Probe a large file without reading it whole (counts/preview)
agent: build
---

Probe the file at `$ARGUMENTS` without loading the entire file into context.

- If no argument given, ask the user for a path.
- Run a short **read-only** Python script to report: line count, file size (KB), first 5 lines truncated to 200 chars, and a keyword frequency if the file looks like JSON/data (count top-level keys or sample shape).
  - ⚠️ `python -c "..."` is fine for a **read-only** probe like this one. It is
    **banned for anything that writes a file** — PowerShell mangles the outer
    quoting and corrupts the target (RULES.md §3.1). For any write, write a
    `.py` to the temp dir and run it with explicit
    `io.open(..., encoding="utf-8", newline="\n")`.
- Do NOT call `read` on the whole file. Summarize the shape so the caller can decide what to read next.
- Current project root is `C:\sovereign_tagger`. Resolve relative paths against it.
  (⚠️ this previously said `C:\sovereign_tagger_2`, which is **deprecated**.)
