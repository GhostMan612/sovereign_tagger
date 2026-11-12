# Critical work order — Chaquopy Python updater transaction safety

**Baseline:** `main` at `ba708fe`, 2026-11-12
**Source:** `android/app/src/main/python/sovereign_yt/updater.py`
**Disposition:** review-only draft. No runtime update behavior changed.

## U1 — Destructive update without recoverable rollback (P0)

### Verified execution path
1. `execute_scorched_earth()` requests the `yt-dlp` GitHub latest-release tarball dynamically.
2. It downloads an archive to a temporary directory and extracts it.
3. After confirming only that an extracted `yt_dlp` directory exists, it executes `shutil.rmtree(target_dir)`.
4. It copies the extracted package with `shutil.copytree(source_ytdlp_dir, target_dir)`.
5. If copy fails after removing `target_dir`, the outer exception handler reports an error but leaves the working package absent or partial. There is no previous-version rollback.
6. The temporary tree is removed only on the successful path; failures leak it.

### Required implementation
- Treat embedded packages inside APK/Chaquopy as immutable. Determine a writable, versioned override location; do not attempt to delete bundled site-packages.
- Download into app-private uniquely named staging, with finite connection/read timeouts, file-size cap, trusted release identity and signature/digest verification.
- Validate archive members before extraction; require an extraction policy safe for the **actual** embedded Python version. Reject absolute paths, `..` escapes, symlinks/hardlinks leaving extraction root and unexpected top-level layout.
- Verify the replacement imports and reports a valid `yt_dlp.version.__version__` before activation.
- Activate with an atomic pointer/rename or explicit journal state. Keep old package until the new one is fully validated; rollback on import or smoke-test failure.
- Guarantee temporary cleanup in `finally`, even on network, filesystem or reload errors.
- Preserve a clear operator-visible pending-restart state if hot module reload is not safe for active downloads.
- Never update while a grabber job or FFmpeg mux is active.

### Acceptance tests
- Malformed archive; archive traversal; wrong package layout; truncated download; mid-copy write failure; import failure; cancelled update; read-only bundled runtime; device reboot during activation.
- After each failed scenario, prior yt-dlp remains importable and the current active extractor version is unchanged.
- User-visible status differentiates downloaded, validated, activated and rolled-back states.

## U2 — Dependency updater can claim success after skipped upgrades (P1)

`update_python_stack()` records per-package statuses `pip rc=...`, `subprocess rc=...`, or `skip: ...` and still returns top-level `status: success`. `execute_full_scorched_earth()` reports overall success whenever `update_python_stack` returns success, regardless of the result strings.

**Required:** a structured per-package `installed / upgraded / skipped / failed` result; top-level partial/failure if mandatory components did not update; no shell-based pip fallback unless supported and security-reviewed on Android. Add hermetic mocked tests of all result combinations.

## U3 — Archive provenance and runtime compatibility (P1)

The GitHub `tarball_url` identifies repository contents, not necessarily the pinned wheel/dependency set used by the Chaquopy build. The updater does not validate package compatibility with its Python environment or the shipped format/capabilities contract.

**Required:** review release artifact provenance and ABI compatibility, preserve an allowlisted version policy, pin dependencies, and test `searchMedia`, `getFormats`, `downloadMedia` on synthetic/authorized fixtures before switching an active version.

## Merge gates

This plan must be split into isolated implementation PRs, starting with non-destructive staging/cleanup and truthful status reporting. **Do not replace or delete the live extractor in the course of investigating this plan.** Maintain the old build until a rollback simulation passes.
