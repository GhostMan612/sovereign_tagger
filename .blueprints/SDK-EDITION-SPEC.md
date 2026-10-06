# SDK-EDITION-SPEC.md — Sovereign Tagger dual-flavour proposal (PARKED)

> **Status: PARKED 2026-10-01 by operator.** Spec only — nothing here is
> authorised to be implemented. The operator is researching the pros/cons and
> tradeoffs before deciding. Implementation slices live in `ROADMAP.md`
> "Phase S0–S4" (all `[-]`).
>
> This document exists so the decision can be made on evidence rather than from
> memory. Every claim below is tagged with how it is known. Nothing here has
> been prototyped — treat all estimates as estimates.

## The claim being evaluated

> *"yt-dlp + chaquopy is what blocks store distribution **and** pins the
> toolchain ceiling. Strip Python out into a second `sdk` flavour and you get a
> publishable build, an unlocked ceiling, and feature headroom — while the
> existing `full` flavour keeps living for personal use."*

That claim has three parts. They have very different values and very different
risks, and they are worth scoring separately rather than as one bundle.

---

## Part 1 — Distribution

### The actual blocker

Store policy for *download managers* is about **circumventing a service's
authentication or copy protection**, not about downloading media. A user
recording their own audio, or a maintainer shipping a tool that shells to
`yt-dlp`, sits in a gray band that differs per store:

| Store | Likely posture for `full` | Likely posture for `sdk` |
|---|---|---|
| Google Play | High risk — media downloader + no Play-distributed `yt-dlp` | Plausible; no ripper present |
| F-Droid | Favorable — they accept terminal-adjacent tools | Favorable |
| GitHub Releases | No policy; whatever you ship, you ship | Same |
| Direct APK | No policy | Same |

**Do not read "Play becomes possible" as "Play accepts it."** Google Play's
policy has been read both ways on this exact category, and a rejection costs
weeks. Even for `sdk`, treat store distribution as *unvalidated* until you have
either a published listing or a written pre-review response.

### Cost of being wrong

- Low for F-Droid / GitHub / direct — those are not stores, there is no review.
- High for Play — an account-level enforcement action is possible, not just an
  app rejection.

---

## Part 2 — Toolchain ceiling

### What chaquopy is actually costing

Known constraints today, from `CURRENT_STATE.md` toolchain notes:

- `chaquopy 17.0.0` supports `AGP 7.3–9.2`. We are on `AGP 9.0.1`. Headroom is
  thin, and the ceiling is *chacuopys*, not Android's.
- Python `3.12+` is 64-bit only, so `arm64-v8a,x86_64` only — no
  `armeabi-v7a`. This is arguably a *win* (smaller APK) that was arrived at by
  accident.
- Python 3.14 has few wheels; `app/build.gradle:54` carries a documented
  fallback to `3.11`. This has not been stress-tested.
- `compileOptions 1.8` is a shim that warns on every build; `17` is "a dedicated
  Java session".
- Built-in Kotlin migration is blocked while Python lives in the build.

### Honest counter-argument — this is the part people underestimate

**Removing Python unblocks the ceiling for the `sdk` flavour only.** The `full`
flavour still carries chaquopy, so:

- The `full` flavour stays on `AGP ≤ 9.2`, `compileOptions 1.8`, Python `3.14`.
- Every future Android/Flutter bump has to be applied **twice**, once per
  flavour, or the flavours drift apart and `sdk` quietly becomes unmaintainable.
- You do not get "unlocked ceiling". You get **two ceilings**, one of which is
  still locked, plus a permanent obligation to maintain both.

If the ceiling is the actual motivation, the honest question is *"do we still
want the ripper?"* — not *"can we ship two flavours?"*. Those are different
projects with different answers.

---

## Part 3 — Maintenance and APK size

### Cost of two flavours

- Two build variants to test on the Moto G. Smoke matrix roughly doubles.
- Gradle flavour conditionals leak into Dart via a channel — every Python-aware
  feature (Grabber, updater, doctor) needs a guarded code path, and a missing
  guard is a runtime crash on one flavour only.
- Documentation splits: README, SESSION_HANDOFF and the known-issue registry all
  need per-flavour variants, or they become wrong (this repo has *already* had
  three doc/code-drift incidents in two days).
- The `win32 ↔ file_picker ↔ wakelock` cap is **unrelated to Python** (S3 says so
  explicitly). A second flavour does not lift it.

### Cost of one flavour

`full` today is a **~120–150 MB on-device Python tax** plus FFmpeg full+gpl
(~40 MB/ABI) plus a bundled 141 MB Whisper model, across 2 ABIs. That is a large
APK and it is the single strongest argument for a second flavour — but it is an
*argument about size*, not about the ceiling. Size and ceiling are separable
goals; bundling them into one project multiplies the cost of each.

---

## Reversibility

| Slice | Reversible? |
|---|---|
| S0 audit | Yes — read-only inventory |
| S1 Dart spider port | Yes — new Dart code alongside Python; Python still default |
| S2 Gradle flavours | **Partly** — flavours are easy to add, hard to remove once conditional code spreads |
| S3 ceiling raise | Partly — `compileOptions 1.8→17` and Kotlin migration are individually revertible, but combined with a flavour split the diff is large |
| S4 packaging/distribution | Yes, but a published listing is a public commitment |

**S0 and S1 are cheap and independently valuable.** If you want evidence before
committing, S0–S1 is the low-regret path: the Dart spider port is useful even if
the flavour split is never built, because it removes the last non-Dart,
non-Kotlin subsystem and makes a future split mechanical rather than risky.

---

## Open questions to answer before deciding

1. **Is store distribution actually required?** F-Droid + GitHub Releases + a
   direct APK is zero-cost and needs no flavour split. If the goal is "people
   can install it", the current `full` build already achieves that.
2. **Is the ceiling the real pain, or just visible?** What specifically is
   blocked today that you have actually hit? If the answer is "nothing yet",
   this track is solving a hypothetical.
3. **Will the `full` flavour be maintained indefinitely?** If yes, Part 2's
   "unlocked ceiling" is not real and the main benefit evaporates.
4. **Is a second APK worth doubling the smoke matrix?** Phase 28 alone produced
   8 pending device-smoke items for one flavour.
5. **What is the decision deadline?** Nothing here is urgent; the current `full`
   build is feature-complete through Phase 28.

---

## Recommendation

**Do not start S0–S4 as a single project.** If the SDK idea is worth pursuing,
the sequencing with the best ratio of evidence to risk is:

1. **S0 audit only** — read-only, produces the real touchpoint inventory,
   invalidates nothing, and directly informs questions 2 and 3.
2. Decide with that inventory in hand.
3. If still yes, **S1 alone** — the Dart spider port, kept as additive code.
   Useful standalone, and it de-risks S2 by removing the only real Python
   surface outside the Grabber.

Hold S2/S3/S4 until the operator explicitly unparks them.

## Traceability

- Slice detail: `ROADMAP.md` → "Phase S0–S4" (all `[-]`)
- Rationale origin: `ROADMAP.md:251` (verbatim rationale retained there)
- Current toolchain truth: `CURRENT_STATE.md` → "Toolchain notes"
- Dependency ceiling: `CURRENT_STATE.md` → "Toolchain notes" (win32 pair +
  compileSdk 37) — orthogonal to Python, see S3
