# Spec: Sovereign Tagger Sentinel (on-device library audit)

Status: SPEC — written 11 November 2026, from the locked policy in
`intent/sentinel.md`. No code started. No plan yet. Nothing here is
approved to build until Glenn approves this spec and then the plan.
Base repo: GhostMan612/sovereign_tagger, main `b8fdbe6` (10 Nov 2026,
Phases 0–36). All file paths below were verified against that HEAD.

## 1. What Sentinel is

Sentinel prowls the on-device music library, finds files that are not
named as their tags dictate or that are missing required tags, artwork,
or lyrics, and makes a persistent hit-list the operator works through
in Forge / Pipeline — on the same phone.

It is a finder first. In v1 it never renames a file and never writes a
tag on its own. Finding is the product; fixing stays in the existing,
already-safe Forge / Pipeline paths.

Tagger works offline on Android. Sentinel is offline too. It goes
online only the way Tagger already does: grabs, Forge, and metadata
enrichment (the spider / catalog cascade). There is no laptop hub, no
mission contract to another device, and no Tagger-to-Tagger / Mantle
handoff in scope. That idea was proposed, then explicitly withdrawn by
Glenn on 11 November 2026 — see the Correction in the intent. Do not
reintroduce it as a "later phase" without a new intent.

## 2. Policy (locked 11 November 2026 — normative)

This section is the policy. If code and this section disagree, this
section wins and the code is wrong.

### 2.1 Filename

```
TT - Album Artist · Song Title.ext
```

- `TT`: TRACK tag, first part before `/`, zero-padded to 2 digits.
  Track 2 → `02`. Missing track → `00`, and the file is flagged
  `MISSING_TRACK` underneath (the name can still be built).
  Tracks > 99: keep the full number (no truncation); padding is a
  minimum width of 2, not a maximum.
- Album Artist: ALBUM_ARTIST tag, Title-Cased (see 2.2), main artist
  only — no featured artists. If ALBUM_ARTIST is missing, fall back
  to the main part of ARTIST (feat stripped, see 2.3). Flag
  `MISSING_ALBUM_ARTIST` only if both are missing.
- Separator between Album Artist and Title is ` · ` — space, middle
  dot U+00B7, space. Not `-`, not `•` (U+2022 bullet — a different
  character; the builder must not confuse them).
- Title: TITLE tag, Title-Cased, with featured artists appended as
  in 2.3, and version/noise stripped as in 2.4.
- Extension: the file's original extension, lowercased
  (`mp3`, `flac`, `m4a`, `ogg`, `wav`, …).
- Sanitisation: the existing `TitleCleaner.sanitizeFileName()`
  rules — strip `\ / : * ? " < > |` and control characters, collapse
  double spaces, trim trailing dots, cap at 150 characters. The
  middle dot `·` must survive sanitisation; add a regression case
  proving it, because `TitleCleaner._trimEdges` treats `•` as an
  edge character and the two dots must never be conflated.
- Scope: filename only. No folder-layout rule in v1. All audio types
  in `TagIO.writableExtensions` plus any other audio extension found
  in the library (unwritable formats are audited for naming and
  completeness but flagged `UNWRITABLE_FORMAT` for fixing).

Worked examples (all Title-Cased per 2.2):

| Tags | Expected filename |
|---|---|
| TRACK 2, ALBUM_ARTIST "x man", TITLE "soon enough" | `02 - X Man · Soon Enough.mp3` |
| TRACK 2, ALBUM_ARTIST "x man", ARTIST "x man ft. yara & zed", TITLE "soon enough ft. yara & zed" | `02 - X Man · Soon Enough ft. Yara & Zed.mp3` |
| TRACK missing, ALBUM_ARTIST "x man", TITLE "soon enough" | `00 - X Man · Soon Enough.mp3` + `MISSING_TRACK` |
| TRACK 12, ALBUM_ARTIST missing, ARTIST "x man ft. yara", TITLE "soon enough" | `12 - X Man · Soon Enough.mp3` + `MISSING_ALBUM_ARTIST` is NOT raised (fallback used); the feat in ARTIST is still split into TITLE per 2.3 |

### 2.2 Title Case

- Capitalise every word except small words, which stay lowercase
  unless they are the first word of a field.
- Small-word list (v1, closed list — extend only by editing this
  spec): `a, an, the, and, but, or, nor, for, of, to, in, on, at, by,
  with, from, as, per, vs`.
- First word of a field is always capitalised, even if it is a small
  word. Last word: capitalised even if it is a small word (e.g.
  "… to" at the end is still "To" — this is the one place the
  "unless first word" rule is extended; if Glenn disagrees, this is
  a one-line spec change, not a code argument).
- Formal / proper names are always fixed to their proper form, via a
  maintained exception list, not by guessing. Seed list (extend in
  the plan, from Glenn's library): `DMX`, `AC/DC`, `McDonald`,
  `Mac…`, `O'Brien`, `DJ …`, `2Pac`, `LL Cool J`. A name not in the
  list gets plain Title Case; it is never "corrected" by heuristic.
  The exception list lives in code as data (`sentinel_names.dart`),
  editable without changing the casing algorithm, and is itself
  part of the hit-list evidence when it fires (so a wrong entry is
  visible, not silent).

### 2.3 Featured artists

Canonical form, in both TITLE and ARTIST:

```
<main title> ft. <Feat1> & <Feat2>
<main artist> ft. <Feat1> & <Feat2>
```

- Separator is ` ft. ` (lowercase "ft.", one space each side).
  Two featured artists are joined with ` & `; three or more are
  joined `, ` with ` & ` before the last (`ft. A, B & C`).
- ALBUM_ARTIST is main artist only. ARTIST is main + `ft. …`.
  TITLE is title + `ft. …`. "Match" means the main-artist part of
  ARTIST equals ALBUM_ARTIST after Title Case and feat-stripping.
- Input parsing (what Sentinel must recognise as a feat, in any
  field): `feat.`, `feat`, `ft.`, `ft`, `featuring`, in brackets or
  bare, case-insensitive — the same variants
  `TitleCleaner._feat` / `spider.py:_FEAT` already recognise. The
  parser must also recognise `&`, `,`, `and`, `x`, `with` as
  separators *inside* a feat clause, and must NOT treat an `&` in
  a main artist name (e.g. a duo whose name contains `&`) as a
  feat separator unless a `feat/ft.` marker precedes it.
- Sentinel's fix for a polluted ARTIST field (feat stuck in ARTIST,
  TITLE clean): split it — main artist to ALBUM_ARTIST, feat moved
  to the end of TITLE in canonical form, ARTIST rewritten in
  canonical form. That fix is a Forge / Pipeline action, not a
  Sentinel auto-action (see §6).

### 2.4 Version / noise stripping (filename only)

Strip from the *filename* (never from the tag, unless the operator
explicitly edits the tag in Forge): `(Remastered)`, `(Remaster)`,
`(Deluxe Edition)`, `(Deluxe)`, `(Bonus Track)`, `[Explicit]`,
`(Explicit)`, `(Official Video)`, `(Official Audio)`, `(Lyric
Video)`, `(Audio)`, and the noise words `TitleCleaner` already
strips for search (`official music video`, `hd`, `4k`, `lyrics`,
etc.). Keep in the filename: genuine version markers that
distinguish two different recordings of the same title *only if*
Glenn adds them to an allowlist in the plan — default is strip.
If stripping would make two files in the same album collide, that
is a `NAME_COLLISION` hit, not a reason to keep the noise.

### 2.5 Completeness — "all of it"

A file is complete only if ALL of these are present and non-empty
(after trimming; `Unknown …` / `<unknown>` count as missing):

TITLE, ARTIST, ALBUM_ARTIST, ALBUM, TRACK, YEAR, GENRE, ARTWORK,
LYRICS.

- ARTWORK: embedded artwork present. Presence is checked without
  pulling full base64 art for every file (see §4.3).
- LYRICS: embedded LYRICS present, OR a sidecar `.lrc` / `.txt`
  with the same stem sits next to the file (the reader
  `GhostVectorIndex._readSidecarLyrics` already implements this,
  ≤ 128 KB). Sidecar counts as complete.
- YEAR: 4-digit year; `TRACK` is the first part before `/`.
- GENRE / COMPOSER / PRODUCER / COMMENT: GENRE is must-have;
  COMPOSER etc. are not completeness criteria in v1.

### 2.6 Uncompletable — the "stop flagging it" status

A file that cannot be completed because there is not enough online
data to fill its tags / art / lyrics correctly is marked
specifically as cannot-be-completed. Rules:

- The mark is per-file, with a reason (`NO_CATALOG_MATCH`,
  `NO_LYRICS_SOURCE`, `NO_ARTWORK_SOURCE`, or free text) and the
  date / scan id that set it.
- A marked file is NOT re-flagged on later scans. It appears in a
  separate "Cannot complete" filter, not in the open hit-list.
- The mark clears automatically if the file's tags change (size /
  mtime / tag snapshot differs) or if a later enrichment attempt
  finds data — i.e. it is a statement about the data available at
  the time, not a permanent verdict.
- Who may set it: the operator (from a hit), or Pipeline after a
  catalog search returns no match at ≥ 80% confidence (see §5).
  Sentinel's scan alone never sets it — a scan can only *propose*
  it, by recording that no catalog data was found.

## 3. Issue taxonomy (normative)

Every hit carries one or more issue codes. Severity is for sorting
and filtering, not for auto-action — v1 has no auto-action.

| Code | Meaning | Severity |
|---|---|---|
| `NAME_MISMATCH` | displayName ≠ expected name computed from tags | high |
| `MISSING_TITLE` | TITLE empty / unknown | high |
| `MISSING_ALBUM_ARTIST` | ALBUM_ARTIST and ARTIST both missing | high |
| `MISSING_ARTIST` | ARTIST empty (ALBUM_ARTIST present) | medium |
| `MISSING_ALBUM` | ALBUM empty / unknown | high |
| `MISSING_TRACK` | TRACK empty / unparseable (name uses `00`) | medium |
| `MISSING_YEAR` | YEAR empty | low |
| `MISSING_GENRE` | GENRE empty | low |
| `MISSING_ARTWORK` | No embedded artwork | medium |
| `MISSING_LYRICS` | No embedded lyrics and no sidecar `.lrc`/`.txt` | medium |
| `ARTIST_ALBUM_ARTIST_MISMATCH` | Main part of ARTIST ≠ ALBUM_ARTIST | high |
| `FEAT_NOT_CANONICAL` | Feat present but not in `ft. X & Y` form, or feat in ARTIST but missing from TITLE (or vice versa) | medium |
| `NAME_COLLISION` | Expected name already belongs to another file | high |
| `UNREADABLE_TAGS` | `TagIO.read` returned empty / threw — cannot judge | high |
| `UNWRITABLE_FORMAT` | Extension not in `TagIO.writableExtensions` — on-device fixing impossible | low |
| `TITLE_CASE_DRIFT` | Tags present but not in Title Case / formal-name form | low |

A file with zero issues is not a hit. A file with only `low`
issues is still a hit — completeness is all-or-nothing (§2.5) —
but the UI sorts high first.

## 4. How the scan works

### 4.1 Two tiers (because MediaStore lies, politely)

- **Tier 0 — MediaStore triage (cheap, fast).**
  `StorageClient.queryAudio()` (`lib/core/storage_client.dart`)
  via `StorageBridge.queryAudio()` returns id, uri, path, title,
  artist, album, albumArtist, genre, track/disc, year, dateAdded,
  mime, size, displayName for every music file. This alone finds
  name mismatches and obvious unknowns, with no file reads. It is
  triage, not verdict: MediaStore metadata is Android's indexed
  copy and can be stale or wrong.
- **Tier 1 — true tags (verdict).**
  `TagIO.read(path, withArtwork: false)`
  (`lib/core/tag_io.dart` → `Id3Tagger.readTags`, jaudiotagger)
  reads TITLE, ARTIST, ALBUM, ALBUM_ARTIST, YEAR, GENRE, TRACK,
  LYRICS, and artwork *presence*. Run Tier 1 for every Tier 0
  candidate, plus a sample of Tier 0-"clean" files (see §4.4).
  `TagIO.read` returning `{}` is `UNREADABLE_TAGS`, not "missing
  everything" — the two must never be conflated.
- **Tier 2 — artwork / lyrics confirmation (only for candidates).**
  Artwork presence: check without full base64 — `TagIO.read`
  with artwork, or `StorageClient.loadArtwork(uri)` (thumbnail /
  `MediaMetadataRetriever` embedded picture). Lyrics: embedded
  LYRICS from Tier 1, else sidecar `.lrc` / `.txt` via the
  `GhostVectorIndex._readSidecarLyrics` pattern.

### 4.2 Scan engine

New code, no existing scanner to reuse — `TabLibrary._scan`
(`lib/tabs/tab_library.dart`) only loads MediaStore rows into the
Library view; it never reads tags per file. Pipeline's
`_addItems` (`lib/tabs/tab_pipeline.dart`) reads tags per file,
but only for files the operator queued by hand.

- Runs in small batches (plan to fix the number; start at 10
  files per batch) with a yield between batches, a progress
  callback (scanned / total / hits so far), and cancel.
- Resume: a scan records its progress in the store (§7); a
  cancelled scan resumes from the last completed batch, it does
  not restart.
- Incremental: on a later scan, files whose fingerprint (uri +
  size + dateAdded + displayName) is unchanged and whose hit
  status is `resolved` / `ignored` / `uncompletable` are skipped
  unless the operator forces a full rescan.
- Never blocks the UI thread; never runs while a Forge save,
  Pipeline batch, or FFmpeg job is running — queue behind
  `FFmpegExecutor` the way other heavy work does, and unload the
  EmbeddingGemma model first if RAM is low (the existing
  `ModelLifecycle` / `beforeExecuteHook` pattern).
- `path` may be empty on newer Android (MediaStore `DATA` is
  deprecated). A file with no usable path is `UNREADABLE_TAGS`
  with reason `NO_FILE_PATH` until a uri-based read path exists.
  Do not silently skip it.

### 4.3 Performance guards (Moto G is the reference device)

- No full artwork base64 in Tier 1. Ever.
- Batch, yield, progress, cancel — as above.
- Skip files already resolved / ignored / uncompletable on
  incremental scans.
- The scan must survive a library of thousands of files without
  holding all tag maps in RAM at once: stream batches through
  the auditor, persist hits per batch.

### 4.4 Sampling (honesty control)

Tier 0-"clean" files are not all re-read on every scan — that
would make the scan as expensive as a full Tier 1 pass. Instead:
every scan Tier-1-reads all Tier 0 candidates plus a random
sample (plan: 5%, minimum 20 files) of Tier 0-clean files, so
MediaStore-vs-tag drift is measured, not assumed. The scan
summary reports the sample size and how many sample files turned
out to have issues — if that number is high, the next scan widens
the sample.

## 5. Handoff to Forge / Pipeline (on-device, existing paths)

Sentinel does not fix. It hands off. The handoff uses paths that
already exist and already have their safety checks:

- **Open in Forge** (per hit): mount the file in Forge with its
  current tags prefilled (`ForgeRequest`, `SovereignState.sendToForge`).
  Forge already does working-copy → `TagIO.write` → `TagIO.verify`
  read-back → `StorageClient.overwriteOriginal(uri, displayName)`
  with the single write-access prompt. The displayName passed is
  the Sentinel expected name — Forge's `FILE NAME ON SAVE` shows
  it, the operator confirms it.
- **Send to Pipeline** (per hit, or a filtered batch): queue the
  file in Pipeline. Pipeline already classifies GHOST / PARTIAL /
  PRISTINE, searches the catalog cascade (`MetadataSources.search`
  — spider.py Genius → LRCLIB → SoundCloud → iTunes → MusicBrainz,
  plus ACRCloud fingerprinting when keys are set), applies only at
  ≥ 80% confidence (`_autoApplyThreshold = 0.8`), otherwise
  REVIEW, and renames only if the operator toggled
  `RENAME FILES TO ARTIST - TITLE`. That toggle's label and the
  underlying `TitleCleaner.buildFileName` call must be updated to
  the new policy (see §8) — Sentinel does not invent a second
  rename path.
- **Mark uncompletable** (per hit): sets the §2.6 status with a
  reason. Pipeline may also set it when a catalog search returns
  no match at ≥ 80%.
- **Ignore** (per hit): operator decision, recorded with a reason,
  reversible. Ignored files are not re-flagged until their tags
  change.
- **Rescan one file**: re-runs Tier 1 + Tier 2 for that file only
  and updates its hit.

## 6. What Sentinel does NOT do (v1)

- No renames. No tag writes. No auto-apply of any kind.
- No background / scheduled scans. No WorkManager, no new
  permission. A scan is started by the operator, in the app.
  (A scheduled scan is a brainstorm item, §10 — it needs a
  separate decision, because it needs a background mechanism the
  app does not currently have.)
- No folder-layout enforcement.
- No duplicate detection, no corrupt-file detection, no
  fake-lossless detection. Those are brainstorm items (§10) with
  their own evidence problems; they are not smuggled into v1.
- No network calls of its own. Enrichment network calls happen
  only inside the existing Pipeline / Forge / spider paths.
- No second embedding service. EmbeddingGemma is used only as
  in §9.

## 7. Hit-list — data model (normative)

One record per file. Persisted as JSON, atomically (write to
`.part`, verify, rename — the `EmbeddingModel` pattern), in
app-private storage next to `ghost_vectors.bin`. No new database
dependency; the repo has no SQLite dependency and adding one for
this would be overkill. File: `sentinel_hits.json`, versioned
(`schemaVersion: 1`).

```json
{
  "schemaVersion": 1,
  "scanId": "2026-11-11T…",
  "generatedAt": "2026-11-11T…",
  "hit": {
    "id": "stable-hash-of-uri+size+dateAdded",
    "uri": "content://media/external/audio/media/123",
    "path": "/storage/emulated/0/Music/…",
    "size": 1234567,
    "dateAdded": 1700000000,
    "displayName": "soon enough.mp3",
    "expectedName": "02 - X Man · Soon Enough ft. Yara & Zed.mp3",
    "issues": ["NAME_MISMATCH", "MISSING_YEAR"],
    "severity": "high",
    "tagSnapshot": {
      "TITLE": "soon enough",
      "ARTIST": "x man",
      "ALBUM_ARTIST": "",
      "ALBUM": "Neon Rain",
      "TRACK": "2",
      "YEAR": "",
      "GENRE": "Synthwave",
      "LYRICS": "",
      "ARTWORK": false
    },
    "evidence": {
      "mediaStoreTitle": "soon enough",
      "sidecarLyrics": false,
      "sampled": false
    },
    "status": "open",
    "statusReason": "",
    "firstSeen": "2026-11-11T…",
    "lastSeen": "2026-11-11T…",
    "scanId": "2026-11-11T…"
  }
}
```

Statuses: `open` → `in_forge` / `in_pipeline` (while handed
off) → `resolved` (re-scan finds zero issues) | `ignored` |
`uncompletable` (see §2.6). `resolved` / `ignored` /
`uncompletable` are sticky until the fingerprint changes.
A hit whose file disappears from MediaStore becomes `stale`
and is pruned on the next scan — never silently deleted
mid-scan, so the operator can see what vanished.

The tag snapshot is the evidence. The hub-era idea of a
"mission contract" is gone; this JSON is a local record, and
the optional local export (see §8, slice 3) is the same JSON,
for Glenn's own review — not a handoff to another device.

## 8. File map (proposed — plan to confirm)

New files:

- `lib/core/sentinel_policy.dart` — PURE policy. No Android
  calls, no I/O. `expectedFileName(tags)`, `audit(tags,
  displayName)` → issues, `titleCase(text)`,
  `splitFeaturedArtists(artist)`, `canonicalFeat(names)`,
  the small-word list and the formal-name exception list.
  This is the one file that can be unit-tested in isolation.
- `lib/core/sentinel_names.dart` — the formal-name exception
  list as data (seeded in the plan, from Glenn's library).
- `lib/core/sentinel_scanner.dart` — Tier 0 → Tier 1 → Tier 2
  orchestration, batching, progress, cancel, resume,
  sampling (§4.4).
- `lib/services/sentinel_store.dart` — hit-list JSON store:
  load / save (atomic), upsert per batch, status transitions,
  pruning stale hits, scan summaries.
- `lib/screens/sentinel_screen.dart` — the hit-list UI (or a
  Library-tab section; plan to decide — a dedicated screen is
  the default, because the hit-list is a work queue, not a
  browse view).
- `lib/core/sentinel_scan_summary.dart` — maybe folded into the
  store; plan to decide. Scan id, counts by issue / severity,
  sample size and sample-hit rate, duration.

Touched files (existing behaviour must not change except as noted):

- `lib/core/title_cleaner.dart` — ADD a Sentinel builder
  (`buildSentinelFileName`, or extend `buildFileName` with a
  named policy parameter — plan to decide). Do NOT change the
  existing `buildFileName` output in place: Grabber, Forge,
  and Pipeline all call it, and changing it silently changes
  every new download's name. The migration of Grabber / Forge /
  Pipeline to the new policy is a deliberate, separately
  verified step (see §11, slice 2b), with
  `GhostBrain`'s "AUTO NAME FROM TAGS builds 'NN - Artist -
  Title'" copy updated at the same time.
- `lib/tabs/tab_pipeline.dart` — rename toggle label and the
  `buildFileName` call at the rename step; Pipeline may set
  `uncompletable` on no-match (see §5).
- `lib/tabs/tab_library.dart` — entry point to Sentinel
  (button / nav); no change to `_scan` itself.
- `lib/tabs/tab_forge.dart` — accept a Sentinel hit as a
  `ForgeRequest` with expected name prefilled; no change to
  the save / verify path.
- `.blueprints/CURRENT_STATE.md`, `SESSION_HANDOFF.md`,
  `ROADMAP.md`, `README.md` — updated when a slice lands,
  per repo law. `README.md` gains the Sentinel section only
  when slice 1 is device-verified, not before.
- `AGENTS.md` / `CLAUDE.md` — only if the plan adds a new law
  (e.g. "Sentinel never writes").

NOT touched in v1: `Id3Tagger.kt`, `StorageBridge.kt`,
`MainActivity.kt`, `spider.py`, `ghost_brain.dart`,
`ghost_vector_index.dart`, `embedding_service.dart`. If the
plan finds a touch is needed, that is a plan change, not a
silent edit.

## 9. GhostBrain / EmbeddingGemma — optional, later, small

The first slice needs no embeddings. Where they help later:

- **Fuzzy matching for untagged files.** A GHOST file with no
  usable title/artist can be matched against the existing
  `GhostVectorIndex` (which already indexes track metadata,
  lyrics, and sidecar `.lrc` files into `ghost_vectors.bin`)
  to propose a likely identity — as a *proposal* in Forge,
  never as an auto-fix. This reuses the shipped
  EmbeddingGemma-300M bridge (`com.sovereign.tagger/embeddings`,
  Phase 33) and the existing service; no second service.
- **Ghost voice:** "What needs fixing?" / "How many files are
  missing art?" answered from the hit-list store, via the
  existing `GhostBrain` / `GhostWorld` command path. Read-only
  answers only in v1.
- Both are slice 4 or later. Neither blocks slice 1.

## 10. Brainstorm — NOT v1, needs separate decisions

Recorded here so the ideas are not lost, and so nobody mistakes
them for scope. Each needs its own intent / decision before it
is specced.

- **Duplicates.** Same audio, different files. Evidence is
  hard: duration + size is weak; acoustic fingerprinting
  (ACRCloud, already wired) or a hash of the decoded audio
  is strong but expensive. Policy question: is a duplicate a
  hit, or a separate "duplicates" view? What counts as the
  keeper — best bitrate, best tags, earliest added?
- **Corrupt / unreadable files.** `UNREADABLE_TAGS` already
  covers "cannot read tags"; true corruption (decode fails,
  truncated file) needs the forensics decode scan
  (`media_forensics.dart` — full decode error scan already
  exists in Phase 34). Policy question: is a corrupt file a
  Sentinel hit or a forensics report?
- **Fake-lossless.** The Phase 34 spectral shelf probes
  (16.2 / 19.5 kHz) already detect upsampled MP3s disguised
  as FLAC/WAV. Policy question: does Sentinel flag
  "claims lossless, is not" as a hit, or is that a separate
  forensics verdict? The evidence (spectrogram, shelf probe)
  is heavier than a tag snapshot.
- **Orphaned sidecars.** `.lrc` / `.txt` / cover art files
  with no matching audio file. Easy to find during a scan;
  policy question is what to do with them (delete? keep?
  offer in Forge?).
- **Scheduled scans.** A nightly / weekly scan needs a
  background mechanism the app does not have (no WorkManager,
  no new permission in v1). Decision needed: is a manual scan
  enough forever, or is background worth the new dependency
  and battery cost?
- **Album-level view.** Group hits by album: "this album is
  7/12 complete". The hit-list already carries ALBUM, so
  this is a UI grouping, not a new scan — cheap, likely
  slice 2 or 3.
- **Formal-name list learning.** When Glenn corrects a name
  in Forge ("it's DMX, not Dmx"), offer to add it to the
  exception list. That is a UX decision, not a scan decision.
- **Year / genre normalisation.** YEAR as 4 digits is in
  policy; GENRE spelling ("Synthwave" vs "synthwave" vs
  "SynthWave") is not. A genre canonical list is a policy
  decision waiting to happen.

## 11. Slices (build order — plan to confirm, Glenn approves each)

- **Slice 1 — Scan-only, end to end, on device.**
  `sentinel_policy.dart` + `sentinel_scanner.dart` +
  `sentinel_store.dart` (in-memory + JSON persist) + a minimal
  UI that runs a scan and lists hits with counts. No renames,
  no tag writes, no Forge/Pipeline wiring beyond "open in
  Forge" if it is trivial — otherwise that is slice 2.
  Gate: `flutter analyze --no-pub` clean; device smoke on
  the Moto G on a real library subset; scan completes,
  cancels cleanly, resumes; hit-list JSON is valid and
  re-loads.
- **Slice 2 — Work the list.**
  Full Sentinel screen (filters by issue / severity / status,
  per-hit actions in §5), `uncompletable` / `ignore` /
  `rescan-one` actions, album grouping if cheap.
  **Slice 2b — Policy migration (separate, deliberate).**
  Grabber / Forge / Pipeline move from `buildFileName`
  (`NN - Artist - Title`) to the Sentinel builder. Verified
  separately: new downloads, Forge auto-name, Pipeline rename
  all produce the new form; GhostBrain copy updated. Do NOT
  fold 2b silently into slice 2.
- **Slice 3 — Local export (optional).**
  Export `sentinel_hits.json` to Downloads via the existing
  `StorageClient.exportTextToDownloads`, for Glenn's own
  review. This is a local file for a human, not a handoff to
  another device. If Glenn does not want it, slice 3 is
  dropped, not built.
- **Slice 4 — Embeddings + Ghost (optional, later).**
  Fuzzy-match proposals and Ghost read-only answers (§9).
- **Slice 5 — Auto-apply (needs its own allowlist decision).**
  NOT in this spec. If Glenn ever wants Sentinel to fix
  anything on its own, that is a new spec with an explicit
  allowlist of repair types, a severity threshold, and a
  human-approval queue — the "policy-controlled repairs"
  from the original intent, still unscoped.

## 12. Verification (per slice — plan to turn into tasks)

- `flutter analyze --no-pub` → `No issues found!` (repo gate).
- No `test/` suite exists by operator decision (Phase 13,
  parked 1 Oct 2026 — "zero test suite until every feature is
  built out"). `sentinel_policy.dart` is pure and testable in
  isolation; the plan must record whether that decision is
  revisited for this one file, and ask Glenn first — do not
  create `test/` unilaterally.
- Device smoke (Moto G, Glenn's side — this VM has no
  Flutter/Android toolchain): run a scan on a real library
  subset; confirm counts, cancel, resume, and that opening a
  hit in Forge shows the expected name; confirm no file was
  renamed or retagged by the scan itself (check mtimes /
  hashes before and after).
- Synthetic fixtures: a small set of test audio files with
  known tags (complete, missing each field, feat in ARTIST,
  feat in TITLE, no track, colliding names, unwritable
  format) — built on the laptop, scanned on device, expected
  hits compared exactly. Fixtures use synthetic data only,
  per repo law; no real library files are copied anywhere.
- Chain-consistency check before any merge: every spec
  requirement traces to at least one plan task and one test
  or device check; orphan requirements and orphan tasks are
  both findings (per `CHAIN.md`).

## 13. Risks and open questions (still open after policy lock)

- **MediaStore `DATA` may be empty** on newer Android — see
  §4.2. Uri-based tag reading is the unscoped fallback.
- **TagIO cost on large libraries** — jaudiotagger per-file
  reads are the scan's bottleneck; batch size and sampling
  (§4.4) are the mitigations, and the plan must measure them
  on device rather than assume.
- **Feat parsing edge cases** — `&` in a duo's name, `x`
  as a collaborator marker vs the letter x, multiple feats
  with mixed separators. The parser needs a fixture set
  covering these before slice 1 is called done.
- **Small-word list and formal-name list are closed lists
  in this spec** — they will be wrong for some real title.
  The correction path (Forge edit → offer to add to the
  exception list) is a brainstorm item, not a v1 feature.
- **"All fields must-have" is strict** — a much-loved track
  with no YEAR and no GENRE anywhere online will sit in
  the hit-list until it is marked uncompletable. That is the
  policy Glenn chose; the UX must make marking uncompletable
  one tap, or the hit-list will feel like nagging.
- **Slice 2b migration risk** — changing the canonical
  filename form changes every new download's name. Existing
  files are NOT renamed by the migration; only Sentinel hits
  (and new saves) use the new form, until Glenn decides
  otherwise.

## 14. Traceability

- Intent: `intent/sentinel.md` (policy locked 11 Nov 2026;
  hub / mission-contract outcome removed the same day).
- Policy decisions: Q1 Title Case A, Q2 feat Reading A, Q3
  Album Artist fallback B, Q4 completeness ALL + uncompletable
  mark, Q5 missing track `00`, Q6 strip noise A, Q7 filename-
  only / all audio types A — all Glenn, 11 Nov 2026, in chat.
- Base code: main `b8fdbe6`; reuse points verified 11 Nov 2026:
  `TitleCleaner.buildFileName` / `sanitizeFileName`
  (`lib/core/title_cleaner.dart`), `TagIO.read` / `verify`
  (`lib/core/tag_io.dart`), `StorageClient.queryAudio` /
  `overwriteOriginal` / `exportTextToDownloads` / `loadArtwork`
  (`lib/core/storage_client.dart`), Pipeline 80% gate and
  REVIEW (`lib/tabs/tab_pipeline.dart:42,233`),
  `TabLibrary._scan` (`lib/tabs/tab_library.dart`),
  sidecar lyrics (`lib/services/ghost_vector_index.dart`),
  forensics probes (`lib/core/media_forensics.dart`).
- Next: plan (`plan/sentinel.md`) — file map, task order,
  proof per task — on Glenn's approval of this spec.
