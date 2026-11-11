# Addendum: what else can be specced — Ghost ↔ Sentinel, pCloud in the player, more GhostBrain

Status: ADDENDUM SPEC — written 11 November 2026, following Glenn's
questions after the Sentinel spec was written. No code started. Each
part below is a separate spec track; approving one does not approve
the others. Base repo: GhostMan612/sovereign_tagger, main `b8fdbe6`
(10 Nov 2026, Phases 0–36). File paths verified against that HEAD
except where marked "to verify on device / in plan".

Companion spec: `spec/sentinel.md` (Sentinel v1, find-only, on-device,
policy locked 11 Nov 2026). Intent: `intent/sentinel.md`.
Hands-free voice intent/spec/plan in this same package are a separate
chain — this addendum does not change D2 (auto-send allowlist) or D3
(silence defaults), which still await Glenn.

## 0. What else can be specced — the inventory

The Sentinel spec deliberately left things out. Here is everything
that is still speccable, in the order Glenn asked about it, plus the
items the spec already parked:

1. **Ghost ↔ Sentinel dialogue** (Part A below) — GhostBot talks
   directly to Sentinel: ask what needs fixing, open hits, hand
   hits to Forge / Pipeline, mark uncompletable, by voice or text.
2. **Cloud services in the player** (Part B below) — pCloud first:
   a cloud folder in the Library that browses and plays remote
   files like a local folder, jetAudio-style.
3. **More GhostBrain** (Part C below) — more knowledge entries,
   more commands, memory/context, proactive (but polite) help,
   better semantic routing.
4. **Sentinel plan** (`plan/sentinel.md`, not yet written) — file
   map, task order, proof per task, for the spec already written.
5. **Sentinel v2 brainstorm items** (from `spec/sentinel.md` §10,
   each needs its own mini-spec): duplicates, corrupt files,
   fake-lossless verdicts, orphaned sidecars, scheduled scans,
   album-level view, formal-name learning, genre normalisation.
6. **Policy edge lists** — the closed small-word list, the seed
   formal-name exception list, the feat-parser fixture set, a
   genre canonical list. These are data, not code, and they are
   the most likely source of "Sentinel flagged a good file".
7. **Auto-apply allowlist** (Sentinel slice 5, explicitly not
   specced) — which repair types, if any, Sentinel may ever apply
   on its own, at what severity, with what human-approval queue.
8. **Verification / fixtures spec** — the synthetic test-file set
   with known tags, and the Moto G device-smoke checklist, per
   slice. Currently only sketched in `spec/sentinel.md` §12.

Nothing in this addendum is approved to build. Each part ends with
the decisions only Glenn can make.

---

## Part A. GhostBot talks directly to Sentinel — yes, and it is the natural next spec

### A.1 Answer in one line

Yes. Ghost already has the exact machinery for this: `GhostBrain`
(`lib/services/ghost_brain.dart`) routes a query through
`_crossTabAutomation` → `_command` → `_knowledge`, and
`AppGhostWorld` (`lib/services/ghost_world.dart`, implementing the
`GhostWorld` interface) is the adapter that lets the brain drive
playback, tabs, Library, Grabber, and Forge. Sentinel becomes one
more thing the world can do — a read-only query surface first, then
handoff actions that reuse the existing Forge / Pipeline paths.
No new brain architecture is needed. What is needed is a Sentinel
query API, new intents, new knowledge entries, and the safety rule
that Ghost never auto-fixes.

### A.2 How Ghost works today (verified in code, HEAD b8fdbe6)

- `GhostBrain.respond(input)` splits multi-clause input, then per
  clause tries, in order: `_crossTabAutomation` (lexical first,
  semantic fallback second), `_command` (deterministic intents),
  `_knowledge` (BM25 / semantic KB lookup).
- `_command` today handles: what is playing, how many / count,
  open/show/go-to a tab, fix this (Forge), favorite/unfavorite,
  repeat, shuffle, pause/resume, next/previous, sleep timer,
  mediainfo/forensics, EQ, playback engine, settings, player.
  It does NOT handle anything about library health, missing tags,
  or naming — there is no Sentinel vocabulary in the brain at all.
- `_knowledge` has 30 `_KbEntry` records (grab, modes, cards,
  playlistgrab, grabfail, forge, forgesave, autotag, lyrics, art,
  batch, library, playlists, player, eq, engine, sleep,
  workbench, replaygain, whisper, mediainfo, keys, look, backup,
  widget, share, permission, duplicate, self, plus one more —
  count verified by grep, 30 entries). Each entry has keyword
  keys, 2–3 detail lines, and suggestion chips.
- `GhostReply(text, tone, chips, laugh, hide)` is the only reply
  shape; `tone` drives the avatar emotion, `chips` drive the
  suggestion buttons, `hide` closes the panel.
- `AppGhostWorld` today exposes: `library()` (MediaStore tracks),
  `playTracks()` / `queueTracks()` (via `AudioService.playFiles`,
  which takes `List<File>`), play/pause/next/previous, shuffle,
  repeat, sleep, `openTab`, `openPlayer` / `openSettings` /
  `openEq` / `openPlaybackEngine` / `openMediaInspector`,
  `grab(url)`, `searchGrabber`, `downloadInGrabber`,
  `forgeExtract` / `forgeCurrent` (mount in Forge with an
  auto-task: search metadata, ACR identify, full auto-tag and
  lyrics, or find lyrics).
- The semantic side: `EmbeddingGemmaService` (native LiteRT
  256-D vectors, hash fallback, engine IDs 1/2, epoch checks)
  plus `GhostVectorIndex` (`ghost_vectors.bin`), which already
  indexes track metadata, lyrics, and sidecar `.lrc` files and
  can semantic-search them. Sentinel's fuzzy-match use of this
  is already sketched in `spec/sentinel.md` §9.

### A.3 The design: Sentinel as a world capability

Add to the `GhostWorld` interface (and `AppGhostWorld`), backed
by `SentinelStore` (`lib/services/sentinel_store.dart`, specced
in `spec/sentinel.md` §7–§8 — it does not exist yet, so Part A
depends on Sentinel slice 1 landing first, or at least on the
store's API being frozen):

- `sentinelSummary()` → counts by status and by issue, total
  hits, last scan id / time. One read, no scan triggered.
- `sentinelHits({issue, severity, status, limit})` → the top
  hits in that filter, with display name, expected name, issues.
- `sentinelHit(id)` → one hit with its tag snapshot.
- `sentinelScan()` → start a scan (operator-initiated, same
  rules as a manual scan: batched, cancellable, never while
  Forge/Pipeline/FFmpeg is running). Ghost reports progress
  the way the scan UI does; it does not silently run a scan
  because the operator asked a question.
- `sentinelOpenInForge(hitId)` → the existing Forge handoff
  (`ForgeRequest` via `SovereignState.sendToForge`).
- `sentinelSendToPipeline(hitIds)` → the existing Pipeline
  queue path, with the 80% confidence gate intact.
- `sentinelMarkUncompletable(hitId, reason)` and
  `sentinelIgnore(hitId, reason)` → status transitions only,
  recorded with reason and date.

GhostBrain additions, in `_command` first (deterministic, testable
by string), with `_knowledge` entries as the fallback explainer:

| Operator says (examples) | Brain does |
|---|---|
| "What needs fixing?" / "How's my library?" / "Ghost, library health" | `sentinelSummary()` reply: totals by severity, top 3 issues, chips: [Show missing art] [Show bad names] [Run a scan] |
| "Show me files missing art" / "…missing lyrics" / "…bad names" / "…missing track numbers" | `sentinelHits(issue: …)` reply: first 5, with counts, chips per hit: [Open in Forge] [Next 5] |
| "Fix this song's tags" (already exists) + "…and rename it to policy" | Forge handoff with the Sentinel expected name prefilled in `FILE NAME ON SAVE` |
| "Send the missing-art files to batch" / "Send these to Pipeline" | Queue the current filtered hits in Pipeline; reply with how many queued and that <80% go to REVIEW |
| "This one can't be fixed" / "Mark this uncompletable" | Status transition with reason; reply confirms it will not be re-flagged |
| "Run a Sentinel scan" / "Check the library" | Start scan, report progress, then summary. Never auto-start a scan on open, on boot, or on a timer in v1 |
| "What is Sentinel?" / "How does Sentinel work?" | `_knowledge` entry (new): explains find-only, policy, hit-list, uncompletable |

### A.4 Safety — the non-negotiable part

- Ghost answers questions and opens things. It never renames,
  never writes tags, never marks uncompletable, never queues a
  batch, without the operator saying so in that turn (or tapping
  the chip Ghost offered). A chip tap is the confirmation.
- No auto-send interaction: this is separate from the hands-free
  voice D2/D3 decisions. A voice transcript that *sounds* like
  "fix everything" is not a command to fix everything. The
  brain must treat batch/destructive verbs as requiring an
  explicit, single-turn confirmation, and must refuse to
  paraphrase a vague "fix my library" into a batch action.
- Ghost never invents hit counts. If no scan has ever run, the
  answer is "No scan yet — want me to run one?", not a guess.
  If the store is stale (last scan older than the library's last
  change), Ghost says so.
- Every Ghost-initiated status change is recorded in the hit
  record (who/what/when — "ghost, voice, 11 Nov, reason: …"),
  so the evidence trail in `spec/sentinel.md` §7 survives the
  voice path.

### A.5 New knowledge entries (proposed, to be written in the plan)

`s sentinel`, `library health`, `missing art`, `missing lyrics`,
`bad names`, `uncompletable`, `scan`. Each with keys, 2–3 detail
lines in Ghost's voice, and chips that lead to the `_command`
branches above. The existing `duplicate` KB entry is the model:
short, practical, and it ends in an action, not a lecture.

### A.6 What Ghost ↔ Sentinel does NOT do (v1 of this part)

- No proactive nagging ("You have 47 files missing art!" on
  open). Ghost answers when asked, and offers a chip when the
  operator is already in the Library / Sentinel screen. A
  proactive mode is a separate decision — see Part C.4.
- No semantic auto-identification of GHOST files via
  embeddings in v1 of this part (that is Sentinel slice 4).
- No scan scheduling (see spec §10 brainstorm).

### A.7 Decisions needed from Glenn (Part A)

1. Is read-only Q&A + handoff-by-chip enough for v1, or do you
   want a voice command that queues a whole filtered set in one
   go ("send all missing-art to batch")? The latter needs the
   explicit-confirmation rule written down first.
2. Should Ghost offer a Sentinel summary chip when you open the
   Library tab, or only when you ask?
3. Does "fix this song and rename it to policy" mean Forge with
   the expected name prefilled (my recommendation), or should
   Ghost ever apply the rename directly? (Recommendation: Forge
   only, in v1.)

---

## Part B. Cloud services in the player — pCloud first, jetAudio-style

### B.1 Answer in one line

Yes, and pCloud is a good first provider: it has a documented
HTTP/JSON API with OAuth 2.0, folder listing, and temporary
streaming links — exactly the three primitives a "cloud folder
in the Library" needs. But there is no cloud code in Tagger
today (grep for pcloud / dropbox / drive / onedrive / webdav
across `lib/`, `android/`, `pubspec.yaml` returns nothing), the
player only knows local `File` paths today, and there is one
real blocker to check before speccing further: pCloud has
paused self-service registration of new OAuth apps.

### B.2 How the player works today (verified in code)

- `AudioService` lives in `lib/screens/main_shell.dart`.
  `_taggedSource(File f)` builds
  `AudioSource.uri(Uri.file(f.path), tag: f.path)`, and
  `playFiles(List<File>)` → `replacePlaylist` →
  `player.setAudioSources(...)` (just_audio 0.10.6).
  Everything downstream — queue, Theater, mini-player,
  lockscreen via audio_service, EQ via the native AudioFX
  bridge, ReplayGain, crossfade — assumes a local file.
- The Library (`lib/tabs/tab_library.dart`) is MediaStore-only:
  `StorageClient.queryAudio()` → `LibTrack` rows (title,
  artist, album, albumArtist, track/disc, year, dateAdded,
  mime, size, displayName, path). There is no remote source
  in the Library at all.
- Tagging / forensics / workbench all assume a local file
  path: `TagIO.read/write` takes a file path and opens it
  with jaudiotagger (`Id3Tagger.kt`); `MediaForensics`
  reads the file with `RandomAccessFile` / FFprobe. A remote
  file cannot be tagged, probed, or DSP'd in place — it must
  first be downloaded to staging, exactly as Pipeline already
  stages working copies (`StorageClient.copyToStaging`).

### B.3 The design: a CloudSource abstraction, pCloud first

Do not build "pCloud in the player". Build a cloud source, with
pCloud as the first provider, so Dropbox / Drive / Box can
follow without a rewrite.

**New files (proposed):**

- `lib/core/cloud_source.dart` — the abstraction. A cloud
  track is: provider id, remote file id, remote path,
  display name, size, mime, duration (if known), and a
  way to get a playable URL. A cloud folder is: provider id,
  remote folder id, display name, children (lazy — list on
  open, never pre-walk the whole drive).
- `lib/core/cloud_pcloud.dart` — the pCloud provider:
  OAuth token handling, `listfolder`, `getfilelink`,
  thumbnail/artwork where the API offers it. Pure Dart
  `HttpClient`, like `EmbeddingModel`'s Hugging Face
  download — no new dependency for v1.
- `lib/core/cloud_cache.dart` — download / stream cache
  policy (see B.5).
- `lib/screens/cloud_settings_screen.dart` or a Settings
  section — connect / disconnect, pick the root music
  folder, cache size, stream-only vs download, data
  warning. (Plan to decide the exact placement; Settings
  Kernel is the current home for keys, per Phase 25.)
- Library: a "CLOUD" view alongside SONGS / ALBUMS /
  ARTISTS / FOLDERS / PLAYLISTS / NEW, or a cloud folder
  entry at the top of FOLDERS — plan to decide, with the
  jetAudio-style behaviour as the target: tap the cloud
  folder, browse remote folders, tap a track, it plays.

**pCloud API facts (from public docs / search, to verify in
the plan against docs.pcloud.com before building):**

- Two data centres: US `api.pcloud.com` (OAuth
  `my.pcloud.com`), EU `eapi.pcloud.com` (OAuth
  `e.pcloud.com`). The correct host comes from the OAuth
  redirect (`locationid` / `hostname`) and must be stored
  per account — never hardcode one region.
- OAuth 2.0: authorise at `…/oauth2/authorize`, token flow
  for mobile returns the access token in the redirect
  fragment; code flow exchanges a code for a token.
  pCloud tokens do not expire (per provider docs as
  summarised in search results), so there is no refresh
  flow to build — but the token must still be stored
  securely and revocable from Settings.
- Folder listing: `listfolder?folderid=0&auth=…`.
  Streaming link: `getfilelink?fileid=…&auth=…`, which
  returns a temporary `https://…pcloud.com/…` URL that
  just_audio can play as a `UriAudioSource`. Public links
  (`getfilepublink`) are a different thing — do not use
  them for playback; they are for sharing.
- **Blocker to check first:** pCloud has paused
  self-service registration of new OAuth apps (reported
  in the pcloud-mcp README: "pCloud has currently paused
  self-service registration of new OAuth apps… registered
  apps keep working — reuse credentials from an app you
  created earlier, or ask pCloud support to provision
  one"). Before any build, Glenn must confirm: do you
  already have a pCloud OAuth app (client id / secret),
  or can you get one provisioned? If not, pCloud-first is
  blocked at the front door and the plan must say so
  plainly — the fallback is a different provider, or a
  generic WebDAV provider, not a workaround that pretends
  OAuth works.

**Playback — stream vs download (the decision that shapes everything):**

- *Stream (recommended for v1):* tap a remote track →
  `getfilelink` → `AudioSource.uri(httpsUrl)` → plays
  without downloading the whole file. just_audio handles
  http(s) URIs; the queue can mix local `Uri.file` sources
  and remote `Uri.https` sources in one
  `ConcatenatingAudioSource`. No local storage cost, but
  needs connectivity, and seeking / gapless / ReplayGain
  on a remote stream need device verification.
- *Download-then-play:* tap → download to cache →
  play the local file. Works offline afterwards, costs
  storage, slower to start. This is the "make available
  offline" per-track / per-folder action, not the default.
- *Cache:* a bounded cache (plan: default 1 GB, user-set
  in Settings, LRU eviction, never evict a file that is
  currently queued). Cached files are staging, not library
  files — they do not enter MediaStore, and Sentinel does
  not audit them (see B.6).

**Credentials — follow the existing pattern, and flag the risk:**

- Today: Genius / ACRCloud keys and the Hugging Face token
  live in device-private `SharedPreferences` (e.g.
  `hf_token`), with a `.bin` vault backup/restore path.
  A pCloud OAuth token follows the same pattern — private
  prefs, never in code, never in git, revocable/disconnect
  in Settings. The plan must record that a pCloud token is
  a bearer token for the whole drive (or the app folder,
  depending on the OAuth app's scope) and that the scope
  choice — whole-drive vs app-folder-only — is made at app
  registration time, not in Tagger. Recommend app-folder
  scope if Glenn's music lives in one folder; whole-drive
  only if it is scattered.

### B.4 Library integration — what "just like jetAudio" means here

- A cloud folder behaves like a Library folder: browse,
  search within it, sort, play a track, play a folder,
  shuffle a folder, queue next. It does NOT behave like
  MediaStore: no album/artist grouping unless the remote
  metadata supplies it (pCloud's `listfolder` gives name /
  size / dates, not ID3 tags — tags come from downloading
  and reading, or from a cached metadata pass, both of
  which are v2).
- Unified search (local + cloud in one query) is v2. V1
  search is per-source: search local in Library, search
  cloud in the cloud folder.
- Playlists can mix local and cloud tracks in v1 (the queue
  already holds `AudioSource`s, not files), but a playlist
  with cloud tracks needs connectivity to play the cloud
  entries — the player must skip (with a clear status)
  rather than stall when offline.
- "Download to Music" (per track / per folder) is the
  bridge back to local: download → local file → it enters
  MediaStore → Sentinel can audit it, Forge can tag it,
  Pipeline can enrich it. That is the intended on-ramp,
  not a side effect.

### B.5 What cloud does NOT do (v1)

- No tagging in place on remote files. Tag / art / lyrics
  fixes happen after download, on the local copy, via
  Forge — and uploading the fixed file back is a separate,
  explicit action ("Upload fixed copy to pCloud"), never
  automatic. (Upload-back is the one place a cloud file
  can be overwritten; it needs its own confirmation.)
- No Sentinel audit of remote files in v1. Sentinel audits
  the local library. A cloud file becomes auditable the
  moment it is downloaded to Music. Auditing remote
  metadata without downloading is a later spec — the
  evidence (tag snapshot) cannot be produced without the
  file, and pCloud does not serve ID3 tags.
- No background sync, no auto-download, no whole-drive
  mirror. Those are sync products, not a player feature.
- No second provider in v1. The abstraction is built so
  a second provider is a new `CloudSource` implementation,
  not a rewrite — but only pCloud is specced here.

### B.6 Decisions needed from Glenn (Part B)

1. pCloud OAuth app: do you already have one, or can you
   get one provisioned? (If no, this track stops here.)
2. US or EU account? (Determines `api` vs `eapi` host;
   the app must store the host from OAuth, not guess.)
3. Stream by default, download on demand — or download
   by default for the music folder? (Recommendation:
   stream by default.)
4. Which folder is the music root in pCloud? One folder,
   or the whole drive?
5. Scope: app-folder-only or whole-drive? (Recommendation:
   app-folder if your music is in one place.)
6. Is "Upload fixed copy back to pCloud" wanted at all in
   v1, or is download-only enough to start?

---

## Part C. More brains for GhostBrain

### C.1 Where GhostBrain is today (verified in code)

- 30 KB entries, keyword-keyed, BM25-style matching with
  synonyms (`embedding_service.dart` has a synonym map:
  `youtube`, `hello`/`hi`, `thanks`, `minutes`/`min`,
  `dupes`/`duplicate`, …), plus semantic fallback via
  EmbeddingGemma (48 intent exemplars + 23 KB vectors,
  warmed in 2-item / 220 ms background slices, 6 s timeout
  on `embedText` — the Phase 36 non-blocking fix).
- Deterministic `_command` intents for playback, queue,
  favorites, sleep, repeat/shuffle, open screens, Forge,
  mediainfo, EQ, settings. Multi-clause input is split
  and each clause answered in turn.
- No memory: every turn starts fresh, except the
  in-conversation `_lastEntry` / `_lastDetail` for "tell me
  more". No record of what Glenn likes, what he fixed
  yesterday, which artists he plays most, or what Sentinel
  found last scan.
- No proactive behaviour: Ghost answers when asked. It
  never volunteers anything.
- Voice: transcript fills the query field for manual send
  (hands-free goal, D2/D3 open). More brains must not
  silently decide D2/D3 — see C.5.

### C.2 Expansion axes (each is separately speccable)

**C.2.1 More knowledge — the cheapest brains.**
Add KB entries for everything Ghost cannot currently explain:
Sentinel (Part A), pCloud / cloud (Part B), duplicates,
forensics / fake-lossless, scheduled scans, album view,
genre, formal names, "why is this file named like that?",
"what does uncompletable mean?", "how do I mark a file?".
Each entry is 2–3 detail lines + chips, in Ghost's voice,
following the existing `_KbEntry` shape. This is the
lowest-risk expansion: no new commands, no new permissions,
just more answers. Proposed first batch (12 entries) to be
listed in the plan.

**C.2.2 More commands — the most useful brains.**
New deterministic intents, in `_command` order (lexical
first, so they are testable by string):

- Play by mood / lyric / description, via the existing
  semantic index ("play something dark and synthwave",
  "find the song that says 'tears in the neon rain'" —
  the README already promises these; wire them as
  commands, not just KB text).
- "Play my favorites" / "Play recently added" / "Play
  this album" / "Play more like this" (seeded from the
  current track's artist / genre / vector neighbours).
- Queue management by voice: "queue the next three by
  X", "clear the queue except this song", "move X to
  next".
- Library questions with real answers from data, not KB
  text: "How many songs do I have?" (count from
  `library()`), "How many by X?", "What did I play
  yesterday?" (needs a play-history record — see C.2.3),
  "What needs fixing?" (Part A).
- Fix flows as commands, not just links: "Fix the tags
  on this song" already exists; add "…and rename it to
  policy", "…and find lyrics", "…and fetch art" as
  distinct Forge auto-tasks (the `ForgeAutoTask` enum
  already has `searchMetadata`, `acrIdentify`,
  `fullAutoTagAndLyrics`, `findLyrics` — the brain just
  needs to reach them by voice).
- Workbench by voice: "Scan ReplayGain on this",
  "Transcribe this with Whisper", "Open the EQ" (the
  last one exists; the first two are cross-tab commands
  already wired in Phase 36 — Ghost just needs the words).

**C.2.3 Memory / context — the brains that make it feel alive.**
A small, local, private context record (SharedPreferences
or a JSON file next to the hit-list — plan to decide; never
a network service, never leaves the device):

- Last played / recently played (needed for "what did I
  play yesterday?" and "play more like this").
- Favorites and per-artist play counts (for "play my
  most-played" and for ranking semantic results).
- Last Sentinel scan summary (for Part A answers without
  re-reading the store every turn).
- Formal-name corrections Glenn made in Forge ("it's DMX")
  — offered to the exception list (spec §10 brainstorm),
  so Ghost learns the name once and stops asking.
- What Ghost must NOT remember: anything from a file Glenn
  did not play / fix / ask about, and nothing about other
  people. Memory is per-device, per-operator, deletable
  in Settings with one tap ("Forget what you've learned"),
  and the plan must say so.

**C.2.4 Proactive Ghost — the riskiest brains, so the most tightly scoped.**
Ghost volunteers only in two places, only with a chip, never
with an auto-action:

- On opening the Library / Sentinel screen: one line if
  there is something new since last visit ("12 new hits
  since your last scan — want the worst first?"), with a
  chip, dismissible, and silent if there is nothing new.
- After a completed action: "That fixed the tags — want me
  to rename it to policy too?" (one follow-up, not a chain).
- Never on boot, never as a notification, never while music
  is playing unless the operator is already talking to
  Ghost. Proactive behaviour is a setting, default off
  until Glenn turns it on — that default is part of the
  spec, not a detail to leave to the plan.

**C.2.5 Better semantic routing — the brains under the hood.**
- More exemplars: the 48 intent exemplars + 23 KB vectors
  were written for the Phase 33 brain. Every new command
  in C.2.2 and every new KB entry in C.2.1 needs exemplars,
  or the semantic fallback will never find them.
- Per-tab suggestion chips: `suggestionsFor(tab)` already
  exists — extend it per tab with the new commands, so the
  chips teach the vocabulary instead of the operator having
  to guess it.
- Follow-ups: "tell me more" already works via
  `_lastEntry`; extend it to multi-turn fix flows ("…and
  now the next one" walks the hit-list in order).

**C.2.6 Personality — keep it, do not expand it first.**
Ghost's voice (sarcastic / happy / serious tones, glitch
laugh, "Boo. Kidding.") is already a strength and already
wired to the 3D avatar. More brains should not mean more
jokes per answer. One line of personality per reply, then
the answer — the existing `GhostReply.tone` discipline,
not a new persona spec.

### C.3 Safety — what more brains must not do

- Never auto-execute a destructive or batch action on a
  paraphrase. "Fix my library" is not a command; it is a
  question ("Want me to show you the worst 5 first?").
- Never auto-send (D2) and never change silence defaults
  (D3) as a side effect of adding commands. Hands-free
  voice remains its own chain with its own gates.
- Never phone home. More brains run on the same offline
  stack (BM25 + EmbeddingGemma on device). If a future
  brain ever needs a network model, that is a new spec
  with a new privacy decision — not an extension of this
  one.
- Every new command that touches a file goes through the
  existing Forge / Pipeline safety: working copy,
  read-back verify, write-access prompt. Ghost is a
  remote control for those paths, not a bypass around
  them.

### C.4 Decisions needed from Glenn (Part C)

1. Which axis first — more knowledge (cheapest), more
   commands (most useful), memory (most alive), or
   proactive (riskiest)? (Recommendation: knowledge +
   commands first, memory second, proactive last and
   default-off.)
2. Play history: are you happy for Ghost to remember
   what you played, on-device only, deletable in
   Settings? (Needed for "play more like this" and
   "what did I play yesterday?".)
3. Proactive Ghost: default off, or do you want the
   Library-screen one-liner from the start?
4. Any commands you specifically want that are not in
   C.2.2? (Name them in your own words — "I want to say
   X and have it do Y" is the best spec input there is.)

---

## 14. Traceability (addendum)

- Sentinel spec: `spec/sentinel.md` (11 Nov 2026).
- GhostBrain / GhostWorld: `lib/services/ghost_brain.dart`
  (30 KB entries, `respond` → `_crossTabAutomation` →
  `_command` → `_knowledge`), `lib/services/ghost_world.dart`
  (`AppGhostWorld`), `lib/core/ghost_commands.dart`
  (`GhostCommandBus`), `lib/core/embedding_service.dart`,
  `lib/services/ghost_vector_index.dart`.
- Player: `lib/screens/main_shell.dart` (`AudioService`,
  `_taggedSource`, `playFiles`), `lib/tabs/tab_library.dart`
  (MediaStore-only), just_audio 0.10.6.
- Cloud: no code in repo (verified 11 Nov 2026: no hits
  for pcloud / dropbox / drive / onedrive / webdav).
  pCloud API facts from public docs / search, to verify
  against docs.pcloud.com in the plan: US
  `api.pcloud.com` / EU `eapi.pcloud.com`, OAuth 2.0,
  `listfolder`, `getfilelink` (temporary streaming URL).
  Blocker: pCloud has paused self-service registration
  of new OAuth apps — Glenn must confirm he already has
  an app or can get one provisioned before this track
  builds.
- Next: pick one track (A, B, or C), write its plan, or
  pick the order for all three. Do not build all three
  at once.
