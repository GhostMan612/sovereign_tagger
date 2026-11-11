# Intent: Sovereign Tagger Sentinel (DRAFT — not started)

Status: ACCEPTED FOR SPEC — policy locked 11 November 2026, no code
started, not part of the hands-free voice goal.
Origin: discussion checkpointed 29 October 2026 (per a summary shared in
chat); naming policy settled with Glenn 11 November 2026 (see "Policy —
locked 11 November 2026" below). Do not treat this intent as scoped work
beyond what that section records.

## Title

Sentinel: offline-first autonomous library maintenance for Sovereign Tagger.

## Problems (as checkpointed, unverified)

- Library maintenance today is manual and reactive: nothing watches the
  library, finds drift or damage, or repairs it on its own.
- Retrieval for maintenance decisions has no stated mechanism; the
  checkpoint names EmbeddingGemma-assisted retrieval.
- Repairs, if automated, need policy control: not every repair is safe to
  apply without a human.
- There is no stated evidence record for autonomous actions.
- No file is named from its tags by a single stated rule: the code's
  current canonical form (`NN - Artist - Title.ext`, via
  `TitleCleaner.buildFileName`) is not the form Glenn wants, and nothing
  prowls the library to find files that drift from the wanted form or
  that are missing tags, art, or lyrics.

## Proposed outcomes (checkpointed concepts)

- Offline-first autonomous library maintenance.
- EmbeddingGemma-assisted retrieval informing maintenance decisions.
- Policy-controlled repairs.
- Persistent evidence for autonomous actions.
- A persistent, on-device hit-list: every incomplete file, with its
  issues and the tag snapshot it was judged from, so it can be worked
  through in Forge / Pipeline on the same phone.

## Affected users

Glenn, on-device. Any multi-device or Mantle scope is explicitly future
("eventual") and out of this intent's scope until scoped separately.

## Constraints

- Offline-first, like the rest of Tagger. Nothing in this intent may assume
  a network service.
- Policy control is a requirement, not a nice-to-have: autonomous repair
  without policy is out of scope.
- This intent must not absorb the hands-free voice goal. Separate chain,
  separate gates.
- No code, no file map, and no verification plan exist yet — those belong
  to the spec/plan stages, which must not start until this intent is
  accepted and the open questions are answered.

## Policy — locked 11 November 2026 (Glenn)

Filename, from tags: `TT - Album Artist · Song Title.ext`
(`TT` = two-digit track; `·` = middle dot U+00B7; extension = original,
lowercased). Example: track 2, album artist "x man", title "soon
enough" → `02 - X Man · Soon Enough.mp3`.

- Title Case: every word capitalised except small words (`a, an, the,
  and, of, to, in, on, for`, etc.), which stay lowercase unless first
  word. Formal/proper names (McDonald, DMX, AC/DC, …) are always fixed
  to their proper form, via a maintained exception list.
- Featured artists: at the end of the title as `ft. X & Y` (no
  brackets), and the same way in ARTIST. ALBUM_ARTIST is main artist
  only; ARTIST is main + `ft. …`; TITLE is title + `ft. …`. "Match"
  means the main-artist part of ARTIST matches ALBUM_ARTIST.
  Example: ALBUM_ARTIST `X Man`, ARTIST `X Man ft. Yara & Zed`,
  TITLE `Soon Enough ft. Yara & Zed`, file
  `02 - X Man · Soon Enough ft. Yara & Zed.mp3`.
- Album Artist missing: fall back to ARTIST's main part (feat stripped);
  flag only if both are missing.
- Complete = ALL of TITLE, ARTIST, ALBUM_ARTIST, ALBUM, TRACK, YEAR,
  GENRE, ARTWORK, LYRICS. Lyrics count if embedded OR a sidecar
  `.lrc` / `.txt` sits next to the file.
- Missing track: use `00` as the placeholder, and flag missing-track
  underneath. Collisions are hits, never overwrites.
- Version/noise in titles (`(Remastered)`, `(Deluxe)`, `[Explicit]`,
  `(Official Video)`, …): stripped from the filename, kept in the tag
  if real.
- Scope: filename only, all audio types (mp3, flac, m4a, ogg, wav).
- Uncompletable: a file that cannot be completed because there is not
  enough online data to fill its tags/art/lyrics correctly is marked
  specifically as cannot-be-completed, and is not re-flagged forever.
  It is re-checked only if its tags change or new data appears.

## Correction — 11 November 2026 (supersedes the 29 October checkpoint)

Glenn withdrew the laptop-hub idea in the same conversation that locked
the policy: "forget I even said anything about a hub." Tagger works
offline on Android, online only for grabs and Forge / metadata
enrichment. There is NO laptop hub, NO mission contract to another
device, and NO Tagger-to-Tagger / Mantle handoff in Sentinel's scope.
The "portable mission contract" outcome from the 29 October checkpoint
is therefore REMOVED, not deferred. If a cross-device handoff is ever
wanted again, it is a new intent, not a revival of this one.

## Open questions — answered 11 November 2026

1. What counts as "library maintenance"? The settled set, for v1:
   name-not-to-policy, missing required tags, missing artwork, missing
   lyrics, name collisions, unreadable tags. Duplicates, corrupt files,
   and fake-lossless detection are brainstorm items for later, not v1.
2. What does "policy-controlled" mean concretely? v1 is find-only:
   Sentinel never renames or rewrites on its own. Repairs go through
   the existing Forge / Pipeline paths with their read-back verify and
   write-access prompt. Any later auto-apply needs its own allowlist
   decision.
3. What is "persistent evidence"? A per-hit record in a local JSON
   hit-list (see `spec/sentinel.md`): identity fingerprint, current
   name, expected name, issues, tag snapshot, scan id, status.
4. Mission contract: removed — see Correction above.
5. How does Sentinel relate to GhostBrain/embedding work? It reuses
   the existing EmbeddingGemma service and GhostVectorIndex only where
   they already help (fuzzy matching for untagged files); it does not
   create a second embedding service. The first slice needs no
   embeddings at all.
6. What is the first verifiable slice? Scan-only, end to end, on
   device: run a scan, produce a hit-list, open a hit in Forge. No
   renames, no tag writes in slice 1.

## Recommended next step

Spec is written (`spec/sentinel.md`, 11 November 2026). Next: plan
(file map, task order, verification per task), then build slice 1
only on Glenn's approval. Do not jump from spec to implementation.
