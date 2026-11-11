# Python pins — Sovereign Tagger

Pinned 2026-11-11. Before this, all three pip installs in
`android/app/build.gradle` were unpinned (`install "yt-dlp"` etc.), so the
build-time version floated with every upstream release — a broken upstream
release could break a fresh build. There is still no `requirements.txt` or
`pyproject.toml`; the `pip {}` block in `build.gradle` is the only declaration,
and these pins live there.

## Pinned versions

| Package | Pinned | Why this version |
|---|---|---|
| yt-dlp | 2026.10.26 | Verified working against the real yt-dlp by the grabber-choices build (PR #7): full option wiring exercised with a stubbed `YoutubeDL`, ffmpeg-present and ffmpeg-absent paths. |
| mutagen | 1.48.1 | Latest stable on PyPI (25 Jun 2026). Ships a universal `py3-none-any` wheel, so Python 3.14 is not a wheel problem. |
| lyricsgenius | 3.15.0 | Latest stable on PyPI (9 Oct 2026, full provenance). Ships a universal `py3-none-any` wheel, requires Python 3.11+, so Python 3.14 is not a wheel problem. |

`doctor.py` reports both sides at runtime: `ytdlp_version` (live) and
`pinned_versions` (this table, from `PINNED_VERSIONS`).

## The rule: build-time pins vs the runtime updater

Pins make **fresh builds reproducible** — a build today installs exactly
these versions. The **runtime updater may still move versions forward on
device, and that is intentional**:

- `updater.py: execute_scorched_earth()` pulls the latest yt-dlp tarball from
  GitHub releases. That is deliberate: yt-dlp breaks when sites change, and
  the updater + doctor exist precisely to heal that. Pinning the updater to
  the build version would reintroduce the outdated-extractor failure mode
  the doctor's `ytdlp_outdated_extractor` rule is built to fix.
- `updater.py: update_python_stack()` upgrades mutagen + lyricsgenius with
  unpinned `pip install --upgrade`. That is pre-existing behaviour, unchanged
  by this PR.

In short: the pin is the known-good **floor** a fresh build starts from, not
a ceiling the device must stay under. If a runtime update ever breaks
something, `doctor.py: diagnose()` shows live vs pinned versions, and
Scorched Earth can be re-run or the pin bumped in a follow-up PR.

## Notes / open items

- **mutagen is installed but never imported.** No `import mutagen` exists
  anywhere in `android/app/src/main/python/` or `lib/`; it is only named in
  `updater.py`'s upgrade list and a settings-screen status string. It is
  pinned anyway (harmless, keeps the diff minimal). Removing it — or wiring
  it in — is a separate decision for Glenn.
- **lyricsgenius 3.15.0 is a big jump from the 3.7.x line** the repo was built
  against. `spider.py` uses only the stable `Genius()` constructor kwargs
  (`token`, `skip_non_songs`, `remove_section_headers`, `timeout`, `retries`,
  `verbose`), unchanged since 3.0, so no code change was needed — but a real
  Genius lookup on the Moto G is the proof that matters, not this reasoning.
- Chaquopy's `pip { install "..." }` accepts standard pip requirement
  specifiers, including `==` pins. No Gradle build could be run on the VM
  that made this change (no Android toolchain), so the Gradle sync itself
  still needs a host build to confirm.
