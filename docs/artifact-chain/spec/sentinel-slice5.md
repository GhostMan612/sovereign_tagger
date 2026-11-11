# Spec: Sentinel slice 5 — Auto-apply (allowlist-gated self-repair)

Status: SPEC — written 11 November 2026. No code started. Nothing
here is approved to build until Glenn approves this spec AND the
allowlist in §2, class by class. The allowlist is a DRAFT: every
entry is proposed, none is decided. If Glenn defers on a class, that
class stays OFF (see §2.1) — deferral is a decision for OFF, not a
decision for later.
Base repo: GhostMan612/sovereign_tagger, main `15e866ae`
(11 Nov 2026, PRs #1–#7 merged, Sentinel slice 1 merged, slice 2
in draft PR #13). All reuse points below were verified against that
HEAD 11 Nov 2026.

Parent spec: `spec/sentinel.md` (624 lines, 11 Nov 2026). That spec's
§11 says slice 5 is "NOT in this spec" and needs "a new spec with an
explicit allowlist of repair types, a severity threshold, and a
human-approval queue". This file is that spec. It does not replace
the parent spec: the locked policy (§2), the issue taxonomy (§3),
the scan (§4), the hit-list model (§7), and the find-only v1 rules
(§6) all still govern. Where this spec and the parent spec disagree,
the parent spec's policy wins and this spec is wrong — except for
the one rule this spec deliberately changes, stated in §1.1: v1's
"no auto-apply of any kind" is lifted ONLY inside the allowlist
in §2, ONLY when the master switch is ON, and ONLY through the
gates in §3. Everything outside the allowlist stays find-only.

Intent: `intent/sentinel.md`, open question 2 — "Any later
auto-apply needs its own allowlist decision." This is that
decision's proposal. The hands-free D2 auto-send allowlist
(`spec/hands-free-voice.md`, Decisions) is the pattern reused
here: default-deny, explicit per-class approval, Glenn decides,
the default applies if he defers. D2 itself is NOT decided here
and is untouched by this spec.

## 1. What auto-apply is

Sentinel, having found and listed hits, applies fixes itself
WITHOUT the operator opening Forge / Pipeline — but only for
hits whose fix falls inside the explicit allowlist in §2, only
when the operator has switched auto-apply on (§5), and only
through the gates in §3. The operator starts a run, reviews a
preview, confirms, and gets a run report. There is no
background, scheduled, or silent auto-apply — ever (see §6).

### 1.1 The one rule this spec changes

Parent spec §6: "No renames. No tag writes. No auto-apply of
any kind." After this spec is approved, that rule reads: "No
renames, no tag writes, no auto-apply of any kind — EXCEPT the
fix classes in §2 of `spec/sentinel-slice5.md`, each switched on
by the operator, each passing the gates in §3 of that spec."
The parent spec's §6 is not edited in place by this spec; the
plan (S12, see §7) records the change as a spec amendment when
the code lands, so the two specs never silently disagree.

### 1.2 What "fix" means here

A fix is one of exactly two operations, both of which already
exist and are already verified in the app:

- **Rename** — change the file's display name to the Sentinel
  expected name (`SentinelPolicy.expectedFileName`), via the
  same path Forge uses: `StorageClient.overwriteOriginal`
  with the write-access prompt. The file's bytes are never
  touched; only its name changes.
- **Tag write** — change tag fields in place via the native
  `id3` channel (jaudiotagger), via the same path Forge uses:
  working copy → `TagIO.write` → `TagIO.verify` read-back →
  `StorageClient.overwriteOriginal`. Never an FFmpeg remux
  (repo tagging law, `AGENTS.md`).

Auto-apply invents no third operation. If a fix cannot be
expressed as a rename, a tag write, or both, it is not an
auto-apply fix — it is a Forge / Pipeline job, done by hand.

### 1.3 Confidence, and why two kinds exist

Fix classes use one of two confidence kinds. They are not
interchangeable:

- **Deterministic** — the fix is a pure derivation from tags
  already present in the file, computed by
  `SentinelPolicy` (`expectedFileName`, `titleCase`,
  `splitFeaturedArtists` / `canonicalFeat`). There is no
  catalog, no guess, no threshold. The safety property is
  not a number — it is the re-verification in §3 G2: the
  live tags are re-read and the fix recomputed at apply
  time, and any difference from the preview means skip.
- **Catalog** — the fix fills a missing field from a catalog
  match, using the same cascade Pipeline uses
  (`MetadataSources.search` — spider.py Genius → LRCLIB →
  SoundCloud → iTunes → MusicBrainz). The safety property
  IS a number: the match confidence must be at or above the
  class threshold in §2. Auto-apply's catalog threshold is
  deliberately stricter than Pipeline's 0.80 auto-apply
  gate (`lib/tabs/tab_pipeline.dart:42`) — the
  operator-supervised path may apply at 0.80 with REVIEW
  below it; the unsupervised path may not. The proposed
  threshold is 0.95 (DRAFT — Glenn decides).

### 1.4 Severity is not a safety property

The parent spec §11 mentions "a severity threshold" for
slice 5. This spec proposes NO severity gate, and says why:
severity measures how broken a file looks, not how safe a
fix is. A `high` hit (`NAME_MISMATCH`) can be the safest
mechanical fix in the list, while a `low` hit (`MISSING_YEAR`
filled from a weak catalog match) can be the riskiest. The
class allowlist (§2) + the confidence threshold (§1.3) +
the gates (§3) replace the severity threshold. Severity
keeps its existing job — sorting and filtering the hit-list —
and nothing else. If Glenn wants a severity gate as well, it
is a one-line addition to §2, not a redesign — but the
default proposal is: no severity gate.

## 2. The allowlist (DRAFT — Glenn decides, class by class)

Default for every class: OFF. A class applies only if the
master switch (§5 C1) is ON **and** that class is ON. If
Glenn defers on a class, it stays OFF. "DRAFT" on an entry
means proposed, not decided — including the thresholds and
the cap in §3 G5. Nothing in this section is settled until
Glenn says so, in the review of this spec.

Rules that bind every class (not per-class options):

- A class applies only to hits whose status is `open`.
  `in_forge`, `in_pipeline`, `resolved`, `ignored`,
  `uncompletable`, and `stale` hits are never auto-apply
  candidates. `ignored` is the durable per-hit opt-out
  (§5 C3).
- A class applies only when the hit's issues are EXACTLY
  the issues that class fixes — no more, no fewer. A hit
  with `NAME_MISMATCH` + `MISSING_YEAR` is not a rename
  candidate under A1, even if the rename part is trivially
  safe. The operator fixes the compound hit in Forge, or
  enables the class that covers the other issue and lets
  a later run take it. This rule is what keeps auto-apply
  from silently fixing half a file and leaving the rest.
- A class never overwrites a present, non-empty tag value
  with a different value — except A2 / A3, whose rewrites
  are form-only (same letters / same feat names, verified
  identical modulo case / form — see each class). Substance
  changes go through Forge, by hand.
- A class never touches a hit with `UNREADABLE_TAGS`,
  `NAME_COLLISION`, or `UNWRITABLE_FORMAT`, whatever else
  it carries. Those three issues are hard denials (§2.8),
  not allowlist entries.

### 2.1 Class A1 — Rename to expected name (deterministic) — DRAFT

- **Fix:** rename the file to `SentinelPolicy.expectedFileName`
  computed from its current tag snapshot. The locked policy
  form: `TT - Album Artist · Title.ext`.
- **Applies when:** the hit's ONLY issue is `NAME_MISMATCH`;
  the tag snapshot is complete per parent spec §2.5 (all nine
  fields present); the expected name differs from the display
  name; the target name does not already belong to another
  file in the library (checked at preview AND at apply time).
- **Confidence:** deterministic (§1.3). No catalog involved.
- **Proposed default:** OFF. Glenn decides.
- **Dependency:** requires the slice 2b policy migration (plan
  S6) merged first. Until Grabber / Forge / Pipeline all
  produce the Sentinel name form, an auto-applied rename
  would disagree with Forge's own auto-name on the same file
  — two canonical names coexisting. A1 stays disabled until
  S6 lands; the other classes do not have this dependency
  (they write tags, not names).
- **Note:** a rename is the most visible thing auto-apply can
  do, and the only class whose undo (restore the old name)
  depends on the old name still being recorded (§3 G4). That
  is why A1 is its own class and its own toggle, not bundled
  with the tag classes.

### 2.2 Class A2 — Title Case normalisation of tag fields (deterministic) — DRAFT

- **Fix:** rewrite TITLE / ARTIST / ALBUM_ARTIST / ALBUM to
  their `SentinelPolicy.titleCase` output. Formal names come
  only from the shipped exception list (`sentinel_names.dart`)
  — never guessed, never added by auto-apply.
- **Applies when:** the hit's ONLY issue is `TITLE_CASE_DRIFT`;
  every field that would change differs from its Title Case
  form ONLY by casing — verified by case-insensitive
  comparison (same letters, same word order, same
  punctuation). A field that differs in any other way is
  not a candidate.
- **Confidence:** deterministic (§1.3).
- **Proposed default:** OFF. Glenn decides.

### 2.3 Class A3 — Feat canonicalisation (deterministic) — DRAFT

- **Fix:** rewrite ARTIST and TITLE to canonical
  `ft. X & Y` form, using `splitFeaturedArtists` +
  `canonicalFeat` (parent spec §2.3). ALBUM_ARTIST is
  rewritten to the main artist only.
- **Applies when:** the hit's ONLY issue is
  `FEAT_NOT_CANONICAL`; the feat set is identical before
  and after (same feat names, only the form changes —
  verified by comparing the parsed feat lists, not the
  strings). A feat clause that parses differently after
  canonicalisation is not a candidate.
- **Confidence:** deterministic (§1.3).
- **Proposed default:** OFF. Glenn decides.

### 2.4 Class A4 — Fill missing ALBUM_ARTIST from ARTIST main part (deterministic) — DRAFT

- **Fix:** write ALBUM_ARTIST = the main part of ARTIST
  (feat stripped via `splitFeaturedArtists`). This is the
  locked policy fallback (parent spec §2.1, decision Q3-B),
  applied as a tag write instead of only as a filename
  fallback.
- **Applies when:** the hit's ONLY issue is
  `MISSING_ALBUM_ARTIST` AND ARTIST is present and
  non-empty. If ARTIST is also missing, the hit is not a
  candidate (there is nothing to fall back from).
- **Confidence:** deterministic (§1.3).
- **Proposed default:** OFF. Glenn decides.

### 2.5 Class A5 — Fill missing tag fields from a catalog match (catalog, ≥ 0.95) — DRAFT

- **Fix:** fill missing TITLE / ARTIST / ALBUM / YEAR /
  GENRE from a catalog match returned by the Pipeline
  cascade (`MetadataSources.search`). ONLY fields that are
  currently missing or `unknown` are filled. A present,
  non-empty value is never overwritten — if the catalog
  disagrees with a present value, that is a Forge decision,
  not an auto-apply one.
- **Applies when:** the hit's issues are a subset of
  {`MISSING_TITLE`, `MISSING_ARTIST`,
  `MISSING_ALBUM_ARTIST`, `MISSING_ALBUM`,
  `MISSING_YEAR`, `MISSING_GENRE`} (missing-field issues
  only, no name / feat / collision / unreadable issues);
  AND the cascade returns a match with confidence ≥ 0.95;
  AND every field the match would fill is currently
  missing. ALBUM_ARTIST, when filled, is the match's main
  artist (feat stripped) — never a feat-carrying value.
- **Confidence:** catalog, threshold **0.95** (DRAFT —
  Glenn decides; deliberately stricter than Pipeline's
  0.80 supervised gate).
- **Proposed default:** OFF. Glenn decides.
- **Note:** a match at 0.80–0.94 is not "almost good
  enough" — it goes to Pipeline REVIEW, as today. No
  rounding up, no per-field threshold shopping.

### 2.6 Class A6 — Embed artwork from a catalog match (catalog, ≥ 0.95) — DRAFT

- **Fix:** embed artwork from the same ≥ 0.95 catalog match
  that would satisfy A5 (same match, same run — never a
  separate artwork-only search). Written via the `id3`
  channel, verified by read-back.
- **Applies when:** the hit's ONLY issue is `MISSING_ARTWORK`
  (or `MISSING_ARTWORK` plus missing-field issues covered
  by A5 in the same run, from the same match); the match
  confidence is ≥ 0.95; the artwork bytes are present and
  non-empty.
- **Confidence:** catalog, threshold **0.95** (DRAFT).
- **Proposed default:** OFF. Glenn decides.

### 2.7 Class A7 — Embed lyrics from a catalog match (catalog, ≥ 0.95) — DRAFT

- **Fix:** embed lyrics from the same ≥ 0.95 catalog match
  (LRCLib / Genius via the spider, as Pipeline already
  fetches them). Embedded LYRICS only — auto-apply never
  writes a sidecar `.lrc` / `.txt` (sidecars are a Forge
  choice; the file's own tags are the auto-apply surface).
- **Applies when:** the hit's ONLY issue is `MISSING_LYRICS`
  (or `MISSING_LYRICS` plus missing-field issues covered
  by A5 in the same run, from the same match); the match
  confidence is ≥ 0.95; the lyrics are non-empty.
- **Confidence:** catalog, threshold **0.95** (DRAFT).
- **Proposed default:** OFF. Glenn decides.

### 2.8 NEVER auto-apply (hard denials — not allowlist entries, not toggleable)

These are not classes Glenn can switch on. They are denials
in the spec, enforced in code, and changing one is a spec
change, not a setting:

- **Delete anything.** No file delete, no tag-field delete
  (`deleteField` / `deleteArtworkField` are never in the
  auto-apply path), no lyrics/artwork removal, no sidecar
  removal.
- **Overwrite a present tag value with a different value.**
  Auto-apply fills missing fields (A5–A7) or rewrites form
  (A2–A3, verified identical modulo case/form). It never
  changes substance. If the catalog disagrees with a tag
  the file already has, that is Forge's job.
- **`MISSING_TRACK` is never auto-filled.** The `00` in the
  locked policy is a filename placeholder, not a tag value
  — writing `00` into TRACK would be wrong. A file missing
  TRACK stays a hit (or is marked uncompletable) until the
  operator or Pipeline finds the real number.
- **`UNREADABLE_TAGS`, `NAME_COLLISION`, `UNWRITABLE_FORMAT`.**
  Cannot judge / needs a human to pick the keeper /
  cannot be fixed on device. Never candidates.
- **Artwork or lyrics from any source other than the ≥ 0.95
  catalog match for that same file.** No artwork/lyrics-only
  searches, no "best guess" art, no lyrics from an
  unverified source.
- **Anything below its class threshold.** A 0.94 catalog
  match is a REVIEW item, not an auto-apply item.
- **Anything on a file marked ignored or uncompletable,**
  or whose status is not `open` (§2, binding rules).
- **Duplicates, corrupt files, fake-lossless.** Not
  Sentinel issues in v1 at all (parent spec §10) — not in
  scope here either.
- **Folder-layout changes.** Policy scope is filename only
  (parent spec §2.1, Q7). Auto-apply moves no file between
  folders.

## 3. Safety gates (normative — all of them, every run)

These gates are enforced in code, not in prose. A run that
cannot satisfy a gate does not run, or stops at the gate.

### G1 — Preview first (dry run, human-approval queue)

Every auto-apply run starts by computing the FULL plan and
showing it — before anything writes. Per file: display name,
expected outcome, fix class, what changes (from → to, per
field), confidence (or "deterministic"), and the reason the
file is a candidate. The operator confirms the run as a
whole and may deselect individual files in the preview
(per-run opt-out, §5 C3). Nothing writes before that
confirmation. This is the "human-approval queue" the parent
spec §11 requires. There is no "apply without preview" mode.

### G2 — Re-verify at apply time (no stale decisions)

Immediately before writing a file, auto-apply re-reads its
live tags (`TagIO.read`) and recomputes the expected outcome
from the live state. If the live state differs from the
preview in ANY way — tags changed, file renamed, size
changed, fingerprint changed — that file is skipped and the
skip is recorded with the reason. A preview is a plan, not
a promise. The preview-to-apply window is kept short (the
run applies files in order, promptly), but G2 is the
guarantee, not the window.

### G3 — The same verified write path as Forge (no bypass)

Every rename and tag write goes through Forge's existing
path: working copy → `TagIO.write` → `TagIO.verify`
read-back → `StorageClient.overwriteOriginal` with the
write-access prompt. Auto-apply gets NO bypass around the
write-access prompt and NO bypass around the read-back
verify. If the read-back mismatches, the file is left as it
was and the failure is recorded. If the write-access prompt
is denied, the run stops (renames stop; tag writes that do
not need a rename also stop — the run does not continue
past a denied prompt, because the operator just said no).
Build-time verification item (not decided here): whether a
single write-access grant can cover a batch of URIs
(`requestWriteAccess` takes a list) or each file prompts —
the build must verify this on device and record the answer
in the PR; if each file prompts, the run must say so in the
preview, because 25 prompts is a different run than one.

### G4 — Per-file undo (the original is restorable)

Before ANY write to a file, auto-apply records the
pre-apply state in that hit's record: the original
displayName and the full tag snapshot (§7 of the parent
spec, extended — see §4). Undo restores the previous name
and the previous tag values through the same verified write
path (G3), and is itself verified by read-back. Undo is
available per file — from the hit, and from the run report —
until the file's fingerprint changes (tags / size changed
outside auto-apply) or the operator clears the run history.
Undo of a rename restores the old filename; undo of a tag
write restores the old tag values. An undone file returns to
`open` status with its issues re-audited (see G10), so the
hit-list never claims a fix that was undone.

### G5 — Hard cap: 25 files per run (DRAFT)

One run touches at most 25 files. The cap is a constant in
the allowlist data, NOT a setting — the operator cannot
raise it to 10,000 and forget it. Files beyond the cap stay
in the hit-list for a later run; the preview says how many
were left out and why. 25 is a DRAFT number (Glenn decides):
small enough to review in one sitting, big enough to be
useful. The cap counts files the run ATTEMPTED (applied +
skipped + failed), not only files it applied — so a run
cannot silently chew through the list by skipping.

### G6 — Mutual exclusion (never two writers)

Auto-apply refuses to start — and aborts mid-run, safely,
between files — if a scan, a Pipeline batch, a Forge save,
or an FFmpeg job is active. This reuses the existing
`SentinelStore.isHeavyOperationActive` gate (the same gate
the scan already honours) plus the scan's own `_scanning`
flag. An aborted run keeps everything it already applied
(each file's write is atomic through G3) and reports the
rest as not-attempted, never as failed. Auto-apply never
starts a scan and never queues a Pipeline batch.

### G7 — Audit log (every fix, skip, and undo is recorded)

Every applied fix, skip, failure, and undo writes an entry
into the hit-list store (§4). Each entry records: run id,
timestamp (UTC ISO), fix class, what changed (field, from →
to, old → new name), confidence (number, or
"deterministic"), and result (applied / skipped / failed /
undone) with a reason for any non-applied outcome. The log
is part of `sentinel_hits.json` — the same file, the same
atomic write — so the evidence trail survives an app kill.
The run report (§3 G10) is a view over this log, not a
separate record.

### G8 — On-device only

No network calls of its own. Catalog matches come only
from the existing Pipeline / spider paths already on the
device. No cloud, no hub, no cross-device handoff (the hub
idea was removed by Glenn, 11 Nov 2026 — see the parent
spec §1; this spec does not revive it).

### G9 — Failure behaviour (one bad file never kills the run)

A failed write on one file is recorded and the run
continues with the next file — except a denied write-access
prompt (G3, stops the run) and a storage error affecting
all files (stops the run, reported as such). Every failure
is surfaced in the run report in words (which file, what
was attempted, what the platform reported). No silent
failures, no silent skips: a skip always carries a reason.

### G10 — No silent success (re-audit, then report)

Auto-apply NEVER marks its own work `resolved`. After a
run, each affected file is re-audited (rescan-one, slice 2)
from its live state; a file becomes `resolved` only when a
fresh audit finds zero issues. Then the run report is shown:
applied N, skipped N with reasons, failed N with reasons,
undone N (if any), files left out by the cap, and the
audit-log location. The report is the run's receipt.

## 4. Data model (normative)

Extends parent spec §7. `sentinel_hits.json` moves from
`schemaVersion: 1` to `schemaVersion: 2`. A v1 file loads
with the new fields defaulting to empty — no migration
rewrite of existing hits, no data loss. The store refuses
no version it has ever written; it only ever writes v2
after this lands.

New per-hit fields (inside each hit record):

```json
"autoApply": {
  "optOut": false,
  "lastRunId": "2026-11-11T…",
  "preApply": {
    "displayName": "soon enough.mp3",
    "tagSnapshot": { "TITLE": "soon enough", "...": "..." }
  },
  "log": [
    {
      "runId": "2026-11-11T…",
      "at": "2026-11-11T…Z",
      "class": "A1",
      "change": { "field": "displayName", "from": "soon enough.mp3", "to": "02 - X Man · Soon Enough.mp3" },
      "confidence": "deterministic",
      "result": "applied",
      "reason": ""
    }
  ]
}
```

- `optOut` — per-hit durable opt-out (§5 C3). Set by the
  operator from a hit; sticky across rescans exactly like
  `ignored` (slice 2 stickiness: the scanner carries the
  flag forward while the fingerprint is unchanged).
  Distinct from `ignored`: an opted-out hit stays `open`
  and visible in the hit-list — it is only excluded from
  auto-apply runs. (Ignore removes it from the working
  list; opt-out keeps it in the list but out of the runs.)
- `preApply` — the state to restore on undo (G4). Written
  before the write, cleared when the undo window closes
  (fingerprint change, or the operator clears run history).
  Holds the full tag snapshot, not just the changed fields,
  so an undo is a complete restore, not a partial one.
- `log` — the per-hit audit trail (G7). Append-only while
  the hit lives; pruned only when the hit is pruned.

New store-level section (same file, top level):

```json
"autoApplyRuns": [
  {
    "runId": "2026-11-11T…",
    "startedAt": "2026-11-11T…Z",
    "finishedAt": "2026-11-11T…Z",
    "classesOn": ["A1", "A2"],
    "attempted": 25,
    "applied": 23,
    "skipped": 1,
    "failed": 1,
    "capLeftOut": 4
  }
]
```

- One entry per run, newest first, kept for the last 20
  runs (older entries are dropped on save — the per-hit
  `log` is the permanent record; the run list is the
  summary). The 20-run retention is a constant, not a
  setting.

Allowlist as data (new file, `lib/core/sentinel_auto_apply.dart`
— proposed file map, §7):

- One entry per class: id (`A1`…`A7`), fix kind (rename /
  tag write), issue set it covers, confidence kind
  (deterministic / catalog), catalog threshold (where it
  applies), default OFF. The thresholds are spec constants
  in this file — changing a threshold is a spec change, not
  a setting. The per-class ON/OFF lives in SharedPreferences
  (§5 C2), not in this file.

## 5. Operator controls (normative)

- **C1 — Master switch (Settings).** One switch:
  "AUTO-APPLY (SENTINEL)". Default OFF. With the master
  off, no auto-apply run can start, the Sentinel screen
  shows no auto-apply controls, and no class is active.
  Turning the master on enables nothing by itself — each
  class still needs its own toggle.
- **C2 — Per-class toggles (Settings).** One toggle per
  class (A1–A7), each default OFF, each labelled with what
  it does in plain words (e.g. "Rename files whose tags are
  already correct" — not the class id). A class applies only
  if master ON + class ON. Turning a class off mid-list
  affects the next run, never a run already in progress.
- **C3 — Per-hit opt-out (durable) + per-run deselect.**
  Durable: the `optOut` flag (§4) — set from a hit, sticky
  across rescans via slice 2 stickiness, reversible from
  the same hit. Per-run: deselect files in the preview (G1)
  — affects that run only. `ignored` (existing, slice 2)
  also excludes a file, durably, and removes it from the
  working list as well. Three mechanisms, three scopes —
  the UI must label them distinctly, not blur them into
  one "skip" button.
- **C4 — Thresholds are not settings.** The 0.95 catalog
  threshold and the 25-file cap are spec constants. The
  Settings screen shows them (so the operator knows the
  numbers) but does not let them be edited. Changing one
  is a spec amendment + a code change, reviewed like any
  other policy change.
- **C5 — Ghost may not start or confirm a run.** Ghost may
  answer "what would auto-apply do?" by reading the
  preview computation (a read-only answer, like the
  ghost-sentinel plan's read-only answers). It may never
  start an auto-apply run, confirm a preview, or apply a
  fix. A voice transcript that sounds like "fix everything"
  is not a confirmation — confirmation is a tap in the
  Sentinel screen, in that run, by the operator. This is
  the ghost-sentinel plan's T5 safety gate applied to
  auto-apply, and it is not negotiable in this spec. Any
  Ghost integration beyond a read-only answer is a
  ghost-sentinel plan change, not an S12 task.

## 6. What slice 5 does NOT do

- No hub, no cloud, no cross-device handoff. (Removed by
  Glenn, 11 Nov 2026.)
- No auto-delete of anything — files, tag fields, artwork,
  lyrics, sidecars. (§2.8.)
- No rewriting files the operator marked ignored or
  uncompletable, and no rewriting opted-out files (§5 C3).
- No background or scheduled runs. A run starts only when
  the operator starts it, in the app, in the foreground.
  (Scheduled scans are already a separate decision in
  parent spec §10 — this spec does not decide them, and a
  scheduled scan would not imply a scheduled auto-apply.)
- No overwriting present tag values with different values
  (§2.8) — except the form-only rewrites in A2 / A3.
- No artwork or lyrics from an unverified source (§2.8).
- No `MISSING_TRACK` auto-fill (§2.8).
- No duplicates, corrupt-file, or fake-lossless handling
  (parent spec §10 brainstorm — not Sentinel issues in v1).
- No folder-layout enforcement (policy scope is filename
  only).
- No new permissions. No new network calls of its own. No
  second embedding service. No changes to the locked naming
  policy — auto-apply APPLIES the policy; it does not
  extend it (no new version-noise entries, no formal-name
  additions via auto-apply — the formal-name list learns
  only via the Forge path, parent spec §10 brainstorm).
- No changes to Forge's or Pipeline's supervised paths.
  Auto-apply reuses them; it does not modify them. The
  Pipeline 0.80 gate and REVIEW stay exactly as they are.
- No Ghost-initiated runs (§5 C5).

## 7. Build order (proposed plan tasks — S12, for plan/sentinel.md)

Slice 5 is ONE slice, built in order, each task reviewable
on its own. These are proposed task numbers — the plan
numbers them when the plan is updated (see §8). Nothing
here authorises code; approval of this spec + the allowlist
authorises implementation, task by task.

Dependencies (all must be merged first): slice 1 (S1–S4)
and slice 2 (S5, draft PR #13 — rescan-one and the
full-rescan stickiness fix are prerequisites: G10 re-audits
through rescan-one, and C3 opt-out survives rescans through
slice 2 stickiness). Class A1 additionally requires slice 2b
(plan S6, policy migration) merged — see §2.1. Classes
A2–A7 do not require S6.

- **S12a — Allowlist as data + Settings controls.**
  Files: `lib/core/sentinel_auto_apply.dart` (new, classes +
  thresholds as data), `lib/screens/settings_screen.dart`
  (master switch + per-class toggles, all default OFF).
  No apply path yet — toggles persist, master off hides
  the controls. Done when: toggles persist across restart;
  with master off, the Sentinel screen shows no auto-apply
  UI. Proof: settings persistence + UI state.
- **S12b — Preview / dry-run computation.**
  Files: `lib/screens/sentinel_screen.dart` (preview list),
  `lib/services/sentinel_store.dart` (candidate selection).
  Compute the full plan per file from a live re-read +
  policy recompute: class, from → to per field, confidence.
  No writes. Done when: the preview matches the manual
  Forge outcome on the fixture set (§9), file for file.
  Proof: fixture comparison.
- **S12c — Apply engine, mechanical classes (A1–A4).**
  Files: `lib/services/sentinel_auto_apply.dart` (new,
  engine), `lib/services/sentinel_store.dart` (schema v2,
  audit log, pre-apply state, opt-out flag),
  `lib/screens/sentinel_screen.dart` (run + report + undo).
  Rename + tag writes through Forge's verified path (G3),
  with G2 re-verify, G4 undo records, G7 audit log.
  Done when: the fixture set applies cleanly, read-back
  verifies, undo restores name + tags exactly, and a
  preview-vs-live divergence is skipped, not applied.
  Proof: fixture set + undo round-trip + divergence test.
- **S12d — Apply engine, catalog classes (A5–A7).**
  Files: same engine + `lib/tabs/tab_pipeline.dart`
  (consumer side only — reuse the cascade and the
  confidence value; do NOT change the 0.80 gate).
  Fill-missing-only at ≥ 0.95, same match for art/lyrics.
  Done when: known matches apply, below-threshold matches
  go to REVIEW and never apply, present values are never
  overwritten. Proof: fixture set with known matches and
  known near-misses (0.80–0.94).
- **S12e — Run controls (cap, exclusion, report).**
  Files: engine + screen. 25-file cap, mutual exclusion
  via `isHeavyOperationActive`, run report (G10), post-run
  re-audit via rescan-one. Done when: the cap is enforced
  and reported; a run refuses to start during a Pipeline
  batch and aborts cleanly mid-run when one starts; the
  report's counts match the audit log exactly. Proof:
  cap test, exclusion test, report-vs-log comparison.
- **S12f — Host gate + Moto G device smoke.**
  Per §9. Fresh install/upgrade on the Moto G (ARM64).
  Proof: §9 checklist, recorded per criterion.
- **S12g — README and blueprint accuracy.**
  Files: `README.md`, `.blueprints/CURRENT_STATE.md`,
  `SESSION_HANDOFF.md`, `ROADMAP.md`,
  `.blueprints/BLUEPRINTS.md` (Sentinel auto-apply section
  + gotchas, if any). README gains the auto-apply section
  only when S12f passes — not before. The parent spec's §6
  amendment (§1.1) is recorded here, in the blueprints, so
  the two specs never silently disagree.

File map (proposed — plan to confirm at build time):

- New: `lib/core/sentinel_auto_apply.dart` (allowlist as
  data + thresholds as constants), `lib/services/sentinel_auto_apply.dart`
  (run engine: candidate selection, preview, apply, undo,
  report).
- Touched: `lib/services/sentinel_store.dart` (schema v2,
  `autoApply` per-hit fields, `autoApplyRuns` section,
  opt-out handling in the scanner's sticky path),
  `lib/core/sentinel_scanner.dart` (carry `optOut` forward
  on sticky hits — consumer side of the store change),
  `lib/screens/sentinel_screen.dart` (preview, run, report,
  undo, per-hit opt-out), `lib/screens/settings_screen.dart`
  (master + per-class toggles), `lib/tabs/tab_pipeline.dart`
  (consumer side only — read the cascade confidence; the
  0.80 gate is untouched).
- NOT touched: `lib/core/title_cleaner.dart`,
  `lib/core/tag_io.dart`, `lib/core/storage_client.dart`
  (the write paths are reused, not modified),
  `lib/services/ghost_brain.dart` (no Ghost-initiated runs
  — §5 C5), `lib/services/ghost_vector_index.dart`,
  `android/` (no new permission, no new channel),
  `spider.py` (the cascade is reused, not changed).

## 8. Traceability and plan status

- Parent spec: `spec/sentinel.md` §11 (slice 5 needs its
  own spec + allowlist + severity threshold + human-approval
  queue — this file answers all three: allowlist §2,
  severity addressed in §1.4, approval queue §3 G1).
- Intent: `intent/sentinel.md` Q2 (auto-apply needs its own
  allowlist decision — this file proposes it).
- Pattern reused: hands-free D2 (`spec/hands-free-voice.md`)
  — default-deny, per-class approval, Glenn decides, the
  default applies if he defers. D2 itself is untouched.
- Safety-gate precedent: ghost-sentinel plan T5 (Ghost never
  renames/writes/tags without operator confirmation in that
  turn; no invented counts; evidence trail) — applied here
  in §3 G7 and §5 C5.
- Reuse points verified 11 Nov 2026 at main `15e866ae`:
  `SentinelPolicy.expectedFileName` / `titleCase` /
  `splitFeaturedArtists` / `canonicalFeat`
  (`lib/core/sentinel_policy.dart`); statuses +
  `sentinelIgnore` / `sentinelMarkUncompletable` / `setStatus`
  / `sentinelSendToPipeline` / `onSendToPipeline` /
  `isHeavyOperationActive` / atomic save
  (`lib/services/sentinel_store.dart`); Pipeline 0.80 gate
  (`lib/tabs/tab_pipeline.dart:42`); Forge write → verify →
  overwriteOriginal (`lib/tabs/tab_forge.dart:611,619,657`);
  rescan-one + full-rescan stickiness (slice 2, draft PR #13
  — NOT on main at `15e866ae`; S12 depends on it merging).
- **Plan status — CORRECTION to the task brief:** the
  Sentinel plan (`plan/sentinel.md`) is NOT in the repo at
  `docs/artifact-chain/plan/` — it lives only in the local
  artifact chain at `~/workspace/sovereign-tagger/artifact-chain/plan/sentinel.md`,
  and its tasks are S1–S11, where **S11 is the Moto G device
  smoke test, not slice 5**. Slice 5 has no S-number in the
  plan. The correct plan change is a NEW task, **S12 —
  Auto-apply (slice 5)**, appended after S11, with the
  order-of-work notes updated (S12 after S5 + S6; S12f
  extends S11's smoke test rather than replacing it). The
  S12 text is §7 of this spec, written so it can be lifted
  into the plan verbatim. This spec does NOT create or edit
  `plan/sentinel.md` in the repo — that file does not exist
  here, and creating a fork of the local plan inside the PR
  would diverge it. The plan update belongs in the local
  chain first, then is pushed with the plan file itself.
- `CHAIN.md` status: the Sentinel bullet is updated with
  this spec's existence (see the accompanying CHAIN.md
  edit in this PR) — the chain tracks Sentinel status, so
  the slice-5 spec + its pending allowlist decision belong
  there.

## 9. Verification (device proof — S12f checklist)

- Host gate: `flutter analyze --no-pub` → `No issues found!`
  (repo gate). No `test/` suite exists by operator decision
  (Phase 13, parked 1 Oct 2026); `sentinel_auto_apply.dart`
  is pure data and the engine is the testable seam — the
  plan must record whether that decision is revisited for
  this one file, and ask Glenn first. Do not create `test/`
  unilaterally.
- Fixture set (synthetic data only, per repo law — same
  fixtures as parent spec §12, plus auto-apply-specific
  cases): one file per class (A1–A7 applying cleanly); one
  file per never-case (§2.8 — delete attempt has no code
  path, so verify by inspection + the class list, not by
  running it); a compound hit (two issues — must NOT apply
  under any single class); a below-threshold catalog match
  (0.80–0.94 — must go to REVIEW, never apply); a present
  value disagreeing with the catalog (must NOT be
  overwritten); a `MISSING_TRACK` file (must stay a hit);
  a `NAME_COLLISION` file (must stay a hit); an opted-out
  file (must be skipped); an ignored file (must be skipped);
  a preview-vs-live divergence (change the tags after the
  preview — the file must be skipped, not applied).
- Moto G, real library subset: enable one class at a time
  (master ON, single class ON), run, and verify the run
  report against the audit log, entry for entry. Undo
  every applied file and verify name + tags restore exactly
  (read-back). Run with the cap: 30 candidates, verify 25
  attempted and 5 left out with the reason shown. Start a
  run, then start a Pipeline batch mid-run: verify the run
  aborts cleanly between files and reports the rest as
  not-attempted. Deny the write-access prompt: verify the
  run stops (G3) and reports it. Record the batch-prompt
  answer (one grant vs per-file prompts — §3 G3) from the
  device.
- Confirm no file outside the allowlist changed (mtimes /
  hashes before and after, for the whole subset — not just
  the candidates). Confirm the store file is valid JSON at
  schemaVersion 2 and re-loads after a kill-and-reload.
- Chain-consistency check before any merge: every
  requirement in this spec traces to at least one plan
  task (S12a–S12g) and one test or device check; orphan
  requirements and orphan tasks are both findings.

## 10. Risks and open questions (still open after this spec)

- **The write-access prompt, batched.** Forge prompts once
  per save. A 25-file auto-apply run may prompt once per
  file, once per run, or once per grant — the build must
  verify this on device (§3 G3). If it is per-file, the
  preview must say so, and the cap in §3 G5 may need to
  come down. This is the biggest UX unknown in the spec.
- **Undo vs. later operator edits.** If the operator edits a
  file in Forge after auto-apply touched it, the undo
  window closes (fingerprint changed) — the pre-apply state
  is then stale and must NOT be restored over the
  operator's newer edit. The build must enforce this by
  fingerprint comparison at undo time, not by timestamp.
- **Catalog confidence is a single number.** Pipeline's
  confidence blends several signals; a 0.95 that is 0.95
  because of a strong title match but a weak artist match
  is still a 0.95. The spec does not decompose confidence
  per field — if device proof shows per-field overreach
  (right title, wrong artist), the fix is a per-field
  confidence floor in the spec, not a code tweak.
- **A1's rename + the write-access grant.** Renames go
  through `overwriteOriginal`, which needs a URI grant.
  MediaStore URI grants can expire or be revoked; a run
  that planned 25 renames may find mid-run that its grant
  is gone. G3's stop-the-run rule covers it, but the run
  report must distinguish "prompt denied" from "grant
  lost" — they are different operator actions.
- **The allowlist will be wrong for some real file.** A
  class will misfire on an edge case the fixture set did
  not cover (feat parsing is the likeliest — see parent
  spec §13). The mitigations are the gates (G2 re-verify,
  G4 undo, G7 audit log, G10 re-audit), not a promise that
  the allowlist is complete. When a misfire is found, the
  fix is a spec amendment to §2, reviewed like the original
  allowlist — never a silent code tweak to the class.
- **Scope creep pressure.** Once auto-apply exists, the
  next ask will be "just also do X". X is a new class,
  needing its own spec amendment and Glenn's approval.
  This spec's §2.8 denials are the line; moving the line
  is a decision, not a PR description.

## 11. Decisions required (Spec gate — Glenn)

Every item below is a decision Glenn makes in the review of
this spec. No item is decided by this spec, and no code
starts until they are decided (approval of the spec
authorises implementation, task by task — see §7).

- **D-S5-1 — The allowlist, class by class.** For each of
  A1–A7: ON or OFF (proposed default OFF for all seven).
  A class Glenn does not switch on stays OFF. He may also
  strike a class entirely, or add one — an added class
  needs its own §2 entry written before code starts.
- **D-S5-2 — The catalog threshold.** Proposed 0.95 for
  A5–A7. Glenn may set a different number, but it must stay
  stricter than Pipeline's 0.80 supervised gate — a
  threshold at or below 0.80 would make the unsupervised
  path as permissive as the supervised one, which defeats
  the point.
- **D-S5-3 — The run cap.** Proposed 25 files per run.
  Glenn may set a different number. The cap stays a
  constant, not a setting, whatever the number.
- **D-S5-4 — No severity gate.** Proposed: none (§1.4).
  Glenn may add one; if he does, it is recorded as an
  amendment to §2, with the threshold value stated.
- **D-S5-5 — A1's dependency.** A1 requires slice 2b (S6)
  merged first (§2.1). Glenn may instead approve A1
  without S6 — but then the spec must record that Forge's
  auto-name will disagree with auto-apply's rename on the
  same file until S6 lands, and that disagreement is
  accepted, not a bug.
- **D-S5-6 — Test-suite rule.** `sentinel_auto_apply.dart`
  is pure data and the engine is the testable seam. Does
  the zero-test-suite rule (Phase 13, parked 1 Oct 2026)
  stand for this change, or is a host check outside `test/`
  (or a `test/` file) wanted? Ask Glenn; do not create
  `test/` unilaterally.
