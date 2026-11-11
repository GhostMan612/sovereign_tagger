# Plan: pCloud in the player (cloud folder, jetAudio-style)

Status: DRAFT — awaiting spec approval (Build gate). This plan is
written FIRST in the order Glenn set 11 November 2026: pCloud first,
then Ghost ↔ Sentinel and more GhostBrain at the same time.
Spec: `spec/sentinel-ghost-cloud-addendum.md`, Part B. Intent: none
separate — the ask is recorded in the addendum (Glenn, 11 Nov 2026).
No implementation is authorized by this plan alone; approval of the
spec authorizes implementation, task by task, with review per
`review/REVIEW.md`. Repo law: stage by explicit path, approval
before commit/push, `main` only.
Base repo: GhostMan612/sovereign_tagger, main `b8fdbe6` (10 Nov 2026).
Verified against that HEAD 11 Nov 2026: no cloud code exists in the
repo (grep for pcloud / dropbox / drive / onedrive / webdav across
`lib/`, `android/`, `pubspec.yaml` returns nothing); the player only
knows local `File` paths (`AudioService._taggedSource` in
`lib/screens/main_shell.dart` builds
`AudioSource.uri(Uri.file(f.path))`); just_audio `^0.10.6`,
audio_service `^0.18.19`, shared_preferences `^2.5.6` in
`pubspec.yaml`; `StorageClient.copyToStaging` /
`overwriteOriginal` exist in `lib/core/storage_client.dart`.

## Gate T0 — The OAuth-app blocker (decision, not code — must pass before any build task)

Spec Part B, §B.3 blocker. pCloud has paused self-service
registration of new OAuth apps; registered apps keep working.
Before T1, Glenn confirms in chat (this is the only task in this
plan that is a question, not code):

1. Do you already have a pCloud OAuth app (client id / secret),
   or can you get one provisioned by pCloud support? If neither,
   this whole plan STOPS here — do not build a workaround that
   pretends OAuth works (no password flow, no scraped login).
2. US or EU account? (Determines `api.pcloud.com` vs
   `eapi.pcloud.com`. The app must store the host from OAuth,
   not guess — but the answer is needed for T1 verification.)
3. Which folder is the music root in pCloud? One folder, or the
   whole drive?
4. Scope: app-folder-only or whole-drive? (Recommendation in the
   spec: app-folder if the music is in one place.)
5. Stream by default, download on demand — or download by
   default? (Recommendation in the spec: stream by default.)

Done when: all five answers are recorded in the spec's §B.6, and
the client id exists. Proof: Glenn's answers, not a code check.
If T0 fails, close this plan as blocked, do not start T1.

Status update, 11 Nov 2026 (Glenn, in chat): he HAS a pCloud
account, but does NOT yet have the OAuth-app / folder-sharing
setup that would let a music player connect to it directly.
He is working on getting the pCloud side going. T0 is therefore
PARTIALLY answered (account: yes; OAuth app: no, in progress).
Remaining T0 answers still open: US vs EU, music root folder,
scope, stream vs download.

## Acceptance criteria (what "done" means, per task)

- A1 — Connect with the real pCloud account, browse the music
  folder, play a track by streaming, with no local copy made.
- A2 — A cloud folder plays, shuffles, and queues like a local
  folder; a mixed local + cloud queue plays through, and a
  cloud track is skipped (with a clear status) rather than
  stalling when offline.
- A3 — "Download to Music" produces a real local file that
  enters MediaStore and is then auditable by Sentinel and
  taggable in Forge.
- A4 — No pCloud token, client secret, or file link ever appears
  in a log, a git diff, or a crash report. Disconnect revokes /
  deletes the token on device.
- A5 — No remote file is tagged, probed, or rewritten in place.
  Every fix path goes through download → local Forge.
- A6 — Cache is bounded (default 1 GB, user-set), LRU-evicted,
  and never evicts a queued file.
- A7 — `flutter analyze --no-pub` clean on the host gate; device
  smoke on the Moto G passes per T11.

## Task order

### T1 — Verify the pCloud API against docs.pcloud.com (spec Part B §B.3)
Files: none in the app yet. A verification note in this plan's
review record (or `review/`), plus a scratch check outside the
repo if needed — do not add a scratch client to `lib/`.
- Confirm, from docs.pcloud.com (not from search summaries):
  OAuth 2.0 token flow for mobile, the US/EU host rule
  (`locationid` / `hostname` from the redirect), `listfolder`,
  `getfilelink` (temporary streaming URL, its expiry), error
  codes and rate limits, and whether tokens really do not
  expire. Record the doc URLs / dates checked.
- Confirm the just_audio side on the host: `UriAudioSource`
  with an `https` URL is a supported source in just_audio
  0.10.6, and mixed `Uri.file` + `Uri.https` sources work in
  one `ConcatenatingAudioSource`. If the docs are ambiguous,
  a minimal host test (not in the app) settles it.
- Done when: the verification note lists every endpoint the
  build will call, with its doc source, and the T0 answers
  match the API (e.g. the host Glenn's account actually uses).
- Proof: A1 (partial — API facts), review note.

### T2 — CloudSource abstraction + pCloud provider (spec Part B §B.3)
Files: `lib/core/cloud_source.dart` (new), `lib/core/cloud_pcloud.dart`
(new). No UI, no player wiring yet.
- `CloudSource` interface: provider id, `listFolder(remoteId)`,
  `fileLink(remoteId)` → temporary streaming URL,
  `downloadFile(remoteId, toPath)` with progress, and a
  `CloudTrack` / `CloudFolder` model (provider id, remote id,
  remote path, display name, size, mime, duration if known).
  Listing is lazy — list on open, never pre-walk the drive.
- pCloud provider: pure Dart `HttpClient` (the same pattern as
  `EmbeddingModel`'s Hugging Face download — no new dependency
  for v1). Host stored per account from the OAuth redirect.
  Token sent as the API requires, never logged, never in a URL
  that gets logged. Errors surfaced as plain-word failures
  ("pCloud said no — check the connection", not an HTTP code
  dump).
- Done when: a host-level check (or a small Dart test, if the
  zero-test-suite rule allows — see Risks) lists a real folder
  and returns a playable link for a real file, using only the
  abstraction. No player code may import the pCloud provider
  directly — only `CloudSource`.
- Proof: A1 (partial), A4.

### T3 — Auth + Settings (spec Part B §B.3)
Files: `lib/screens/cloud_settings_screen.dart` (new, or a
Settings section — plan decision at build time, Settings Kernel
is the current home for keys), `lib/core/ghost_settings.dart`
(if a setting lives there), `AndroidManifest.xml` (only if a
redirect scheme is needed — see below).
- Connect: OAuth authorise flow. Open question the build must
  resolve BEFORE writing the flow, and record the answer in
  the review: (a) custom-scheme / app-link redirect back into
  Tagger so the token flow completes in-app, or (b) browser
  authorise + manual paste of the token (the pattern Genius /
  ACRCloud keys already use: open the page, paste the key in
  Settings). (a) is the better UX; (b) is the fallback if the
  redirect plumbing is not worth it in v1. Either way, the
  token lives in device-private `SharedPreferences` (the
  `hf_token` pattern), never in code, never in git, and the
  `.bin` vault backup path must be checked — a bearer token
  for the whole drive must not be backed up to a place Glenn
  did not expect. Record the backup decision.
- Disconnect: deletes the token on device, clears cached
  cloud listings, and tells Glenn the pCloud-side authorisation
  (in his pCloud account) is a separate step he can take.
- Settings: music root folder picker (from T0's answer, changeable),
  cache size (default 1 GB), stream-only vs download toggle,
  data warning on mobile data (streaming on mobile data warns
  once, then remembers).
- Done when: connect → browse works, disconnect → token gone
  and cloud folder disappears from the Library, and a fresh
  install with no token shows "not connected" rather than an
  error.
- Proof: A4, A1 (partial).

### T4 — Library cloud folder (spec Part B §B.4)
Files: `lib/tabs/tab_library.dart`, `lib/core/cloud_source.dart`
(consumer side only), new `lib/widgets/cloud_folder_view.dart`
(or a Library view — plan decision at build time).
- A CLOUD view alongside SONGS / ALBUMS / ARTISTS / FOLDERS /
  PLAYLISTS / NEW, or a cloud folder entry at the top of
  FOLDERS (decide at build time; the behaviour is the same):
  tap to browse remote folders, tap a track to play, long-press
  for Download to Music / queue next / add to playlist.
- Remote listing gives name / size / dates, not ID3 tags — so
  the cloud view is folder-first in v1, with no album/artist
  grouping. Search in v1 is per-source (search local in
  Library, search cloud in the cloud folder); unified search
  is v2 and is NOT built here.
- Play a folder / shuffle a folder from the cloud view.
- Done when: browsing a real pCloud music folder, playing a
  track from it, and playing / shuffling the folder all work
  from the Library, with a visible "cloud" marker so a remote
  track is never mistaken for a local one.
- Proof: A1, A2 (partial).

### T5 — Playback: stream, mixed queue, offline behaviour (spec Part B §B.3–B.4)
Files: `lib/screens/main_shell.dart` (`AudioService`), `lib/tabs/tab_player.dart`
(only if the now-playing UI needs a cloud marker — keep the diff
minimal).
- Tap a remote track → `getfilelink` → `AudioSource.uri(httpsUrl)`
  → plays without downloading the whole file. The queue holds
  `AudioSource`s, so a mixed local + cloud queue is one
  `ConcatenatingAudioSource`; do not build a second player.
- Offline / link-expired behaviour, device-verified in T11:
  a cloud track that cannot be reached is skipped with a clear
  status ("Couldn't reach pCloud — skipped"), never a stall,
  never a silent stop of the whole queue. A `getfilelink` URL
  that expires mid-queue is re-fetched once; if that fails,
  skip the same way.
- Seek / gapless / ReplayGain on a remote stream: verify on
  device in T11 and record what actually works. Do not claim
  ReplayGain on a stream until the device says so — the
  ReplayGain path assumes a local file today.
- Done when: A2 passes on device, and the T11 notes record
  seek / gapless / ReplayGain results as observed, not assumed.
- Proof: A2, A7.

### T6 — Download to Music + offline cache (spec Part B §B.3, §B.4)
Files: `lib/core/cloud_cache.dart` (new), `lib/core/cloud_pcloud.dart`
(download path), `lib/core/storage_client.dart` (consumer side only
— reuse `copyToStaging` / the Music save path, do not fork it).
- Per-track and per-folder "Download to Music": download →
  local file in Music → it enters MediaStore → Sentinel can
  audit it, Forge can tag it, Pipeline can enrich it. That is
  the intended on-ramp, not a side effect. Progress shown;
  cancel works; a cancelled download leaves no partial file
  in Music.
- Cache (streamed files kept for replay): bounded, default
  1 GB, user-set in Settings, LRU eviction, never evict a
  queued file. Cached files are staging, not library files —
  they do not enter MediaStore and Sentinel does not audit
  them.
- Done when: A3 and A6 pass on device, and a downloaded file
  is indistinguishable in the Library from a file that was
  always local.
- Proof: A3, A6.

### T7 — Upload fixed copy back (optional, explicit only — may be deferred)
Files: `lib/core/cloud_pcloud.dart` (upload path),
`lib/tabs/tab_forge.dart` (one explicit action only).
- After a downloaded file is fixed in Forge, an explicit
  "Upload fixed copy to pCloud" action uploads it back to the
  same remote folder. Never automatic. Confirmation names the
  remote file it will replace. This is the ONLY place a cloud
  file can be overwritten, and it needs its own confirmation.
- If Glenn answers T0 with "download-only is enough to start",
  T7 is dropped from v1, not built — record the decision in
  the review, do not build it speculatively.
- Done when: the action works once, end to end, with the
  confirmation, and the remote file is the fixed copy.
- Proof: A5.

### T8 — Ghost knowledge + commands for cloud (small; after GhostBrain T1)
Files: `lib/services/ghost_brain.dart` (KB entries + one
`_command` branch), `lib/services/ghost_world.dart` (only if a
new world method is needed — prefer reusing `playTracks` /
`library` paths).
- KB entries: "pCloud", "cloud folder", "download to Music",
  following the existing `_KbEntry` shape (2–3 detail lines,
  chips). Commands: "play from pCloud", "download this to
  Music". No new brain architecture.
- This task is deliberately small and deliberately last among
  the feature tasks, because it depends on the GhostBrain plan's
  T1 (KB-entry conventions). It may be folded into the
  GhostBrain plan's knowledge batch if both plans are being
  built at once — record the fold in the review, do not build
  it twice.
- Done when: Ghost answers "how do I play from pCloud?" and
  "download this to Music" works by voice/text from the
  player.
- Proof: A1 (partial).

### T9 — README and blueprint accuracy
Files: `README.md`, `.blueprints/CURRENT_STATE.md`,
`SESSION_HANDOFF.md`, `ROADMAP.md` (only the sections this
change touches).
- Document the cloud folder, the OAuth setup, the stream /
  download behaviour, and the "remote files are not taggable
  in place" rule. Do not document upload-back if T7 was
  dropped.
- Done when: README matches what T11 actually proved.

### T10 — Host verification gate
- Run on Glenn's host: `flutter analyze --no-pub`, `flutter test`
  (where tests exist). Fix failures in the same change; do not
  merge with a red gate.
- CI note: the Dart workflow is red at dependency install since
  25 October 2026 (pre-existing), and Dart CI failed on main at
  `b8fdbe6` on 11 Nov 2026 (build job died in 11 seconds) — the
  same pre-existing failure, not new breakage. The host gate
  above is authoritative; do not treat a red CI run as this
  change's failure, and do not merge on CI status alone.
- Chain-consistency check: every spec requirement (Part B)
  traces to a task and a test/device check; no orphan tasks.

### T11 — Moto G device smoke test (closes the device-proof rule)
- Fresh install/upgrade on the Moto G (ARM64), real pCloud
  account: connect (T3), browse (T4), stream a track on Wi-Fi
  (A1), stream on mobile data (warning shown once), play /
  shuffle a cloud folder, mixed local + cloud queue (A2),
  go offline mid-queue (skip, not stall), download a track to
  Music (A3), cache limit respected (A6), disconnect (A4).
  Record seek / gapless / ReplayGain on a stream as observed.
- Record results (pass/fail per criterion, device, build) in
  the PR or in `.blueprints/` verification notes. A code
  review alone does not close this task.

## Order-of-work notes

- T0 before everything. No code task starts until T0 passes.
- T1 before T2: the provider must be built against verified
  API facts, not search summaries.
- T2 before T4/T5: the Library and the player consume the
  abstraction, not pCloud directly.
- T3 may run in parallel with T2 (different files), but T4
  needs both: no cloud folder without auth and without the
  provider.
- T6 after T5: download reuses the playback / staging paths
  T5 proves.
- T7 is optional and independent; it may be dropped entirely.
- T8 last among feature tasks (depends on GhostBrain plan T1).
- If any task's diff grows past one reviewable change, split
  it; do not bundle the provider, the UI, and the player
  change into one diff.

## Risks carried into the build

- T0 is the whole plan's single point of failure. The plan
  says so plainly and stops if it fails.
- Token scope: a whole-drive bearer token is a bigger blast
  radius than an app-folder token. T3 must record the scope
  actually granted and the backup decision.
- `getfilelink` URLs expire; the re-fetch-once rule in T5 is
  the mitigation, and T11 must actually observe it.
- The zero-test-suite rule (Phase 13, parked 1 Oct 2026 — "zero
  test suite until every feature is built out") means T2's
  host check may need to be a scratch check outside the repo
  rather than a `test/` file. Do not create `test/`
  unilaterally — ask Glenn first, as the Sentinel spec
  already records.
- ReplayGain / gapless / seek on a remote stream are
  unverified until T11. The plan does not promise them.
