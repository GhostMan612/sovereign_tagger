# Chaquopy-Aware Overlay `yt-dlp` Updater (PR #01 — CI-01)

## Problem Fixed

On Android, Chaquopy packages `yt-dlp` Python modules into immutable APK assets (`requirements-*.imy`) and extracts only non-Python data files (such as `yt_dlp/extractor/youtube/jsc/_builtin/vendor/*.js`) into `files/chaquopy/AssetFinder/requirements/yt_dlp`. Earlier `AssetFinder`-targeted in-place staging failed with `Staged package is missing __init__.py/version.py` because `.py` / `.pyc` code never resided in `AssetFinder`.

## Architecture Implemented

- **Immutable APK runtime + writable overlay (`filesDir/sovereign_py_overlay/`):**
  - `slots/<slot_id>/yt_dlp/` holds verified versioned overlays alongside `slot.json` metadata (`slot_id`, `version`, `archive_sha256`, `tree_sha256`, `requires_python`, `required_assets`).
  - `staging/<tx_id>/` isolates archive extraction and validation prior to promotion.
  - `active.json` stores atomic manifest state (`fsync` + `os.replace`) tracking `active_slot`, `previous_slot`, `pending_slot`, `last_known_good_slot`, `failed_slots`, `transaction`, `recovery_required`, `last_error`, and `rolled_back_from`.
- **Startup bootstrap before consumer imports ([`PythonRuntime.kt`](file:///c:/sovereign_tagger/android/app/src/main/kotlin/com/sovereigntagger/PythonRuntime.kt), [`overlay_bootstrap.py`](file:///c:/sovereign_tagger/android/app/src/main/python/sovereign_yt/overlay_bootstrap.py)):**
  - `MainActivity` and instrumentation harness initialize Python exclusively via `PythonRuntime.ensureInitialized(context)`, which calls `sovereign_yt.overlay_bootstrap.bootstrap(overlayRoot, BuildConfig.YTDLP_BUNDLED_VERSION)` before `sovereign_yt.bridge`, `doctor`, or any `yt_dlp` consumer is imported.
  - `BuildConfig.YTDLP_BUNDLED_VERSION` is emitted in [`android/app/build.gradle`](file:///c:/sovereign_tagger/android/app/build.gradle) from the same `ytdlpPinnedVersion` pin used by Chaquopy `pip install`.
  - No in-process hot-swapping: `updateCore` stages updates into `pending_slot` while leaving live `sys.modules['yt_dlp']` untouched (`restart_required: true`). If `yt_dlp` is already in `sys.modules` when `bootstrap()` runs, `premature_import: true` is recorded and `sys.path` is not mutated.
- **Release security & validation pipeline ([`updater.py`](file:///c:/sovereign_tagger/android/app/src/main/python/sovereign_yt/updater.py)):**
  - Enforces HTTPS-only URLs and strict GitHub host pinning (`api.github.com`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`, `codeload.github.com`) across redirects.
  - Requires non-draft, non-prerelease CalVer metadata with `yt-dlp.tar.gz`, `SHA2-256SUMS`, and detached OpenPGP V4 RSA-4096 `SHA2-256SUMS.sig` assets; verifies `SHA2-256SUMS.sig` cryptographically in pure Python against pinned `yt-dlp` release key fingerprint `AC0CBBE6848D6A873464AF4E57CF65933B5A7581` before hashing `yt-dlp.tar.gz`, verifies compressed download ceiling (`32 MiB`) and SHA-256 match, rejects path traversal/absolute paths/symlinks/hardlinks/special files/zip-bombs/ELF/PE/bytecode payloads, checks `pyproject.toml` `requires-python`, verifies release `tag_name == yt_dlp/version.py __version__`, and blocks CalVer downgrades below active or bundled `yt-dlp`.
  - Serializes cross-process manifest/slot mutations with advisory file locking (`overlay_file_lock` + `fsync_directory`), keeps read-only `get_status` side-effect-free on uninitialized overlay roots, caps quarantined `active.json.corrupt.*` files to `3`, and prunes stale `staging/` directories during startup bootstrap.
- **Automatic rollback & Option B APK-managed dependencies:**
  - Startup marks `activating` atomically prior to inserting a pending slot into `sys.path[0]`, validates `slot.json` + AST + non-Python assets + `tree_sha256` (ignoring runtime `__pycache__`), and runs an in-process `YoutubeDL` instantiation and `__file__` origin smoke test.
  - Interrupted activations or smoke/validation failures roll back cleanly to `previous_slot` or bundled `.imy` `yt_dlp`. Corrupted `active.json` is quarantined (`active.json.corrupt.*`, bounded to `3` retained files) with bundled fallback.
  - `execute_full_scorched_earth` / `updateFullStack` MethodChannel no longer invokes subprocess `pip`; it returns `{"status": "requires_apk_update", "core_updatable": true, "apk_managed_packages": ["mutagen", "lyricsgenius"]}` with zero mutation. [`settings_screen.dart`](file:///c:/sovereign_tagger/lib/screens/settings_screen.dart) displays bundled/active/source/pending/restart/rollback/recovery telemetry and documents that `mutagen` and `lyricsgenius` update via new APK builds.

## Verification

- **Python unit suite (`test/python/`):** `python -u -m unittest discover -s test/python -p "test_*.py" -v` — `31` tests OK (`18` in `test_transactional_updater.py`, covering OpenPGP V4 RSA `.sig` pinning/tamper/missing checks, cross-process `overlay_file_lock` contention, read-only no-mkdir `get_status`, `<= 3` quarantine retention, stale staging cleanup, isolated subprocess restart activation, rollback to previous slot/bundled `.imy`, premature-import detection, bomb/traversal/downgrade rejections, and non-mutating `requires_apk_update`).
- **Flutter analyzer & test suite:** `flutter analyze --no-pub --no-fatal-infos` (`No issues found!`), `flutter test --no-pub` (`212` tests passed, including updated `test/updater_settings_test.dart`).
- **Android JVM unit tests & builds:** `:app:testDebugUnitTest --no-daemon` passed (`PythonOverlayContractTest`), `flutter build apk --debug --no-pub --target-platform android-arm64` (`sha256=550b485ef8c4ebb27f505d881894f180908d05a5b569b88de18f3ff20c43dee6`) and `android-x64` (`sha256=d7e0e2d8d5aedfbcd39c63f6b1c2790c47e9944b2875727341866c53001f8bff`) passed, unsigned `:app:assembleRelease` failed closed as required, and signed R8 release packaging (`flutter build apk --release --no-pub --target-platform android-arm64` on clean `4bd7474` with an ephemeral `.p12` keystore removed right afterward) built `344.0MB` (`sha256=47a85e7b8098a4df544963a00dfa8e27e0e83b0f8394e36d9205d1a3bb750ef3`, R8 `mapping.txt` `36,118,726` bytes).
- **Isolated hardware acceptance (`com.sovereigntagger.updateracceptance`, `am force-stop` between phases):**
  - **BLU `B160V` (`7040016025040287`, Android 14 / SDK 34, full 6-phase P0–P2 run):**
    - `phase1_stageOverlayUpdateAndVerifyNoHotSwap` (`76.166s`, OK): Verified live Chaquopy `.imy` `2026.10.26 (BUNDLED)`, `updateFullStack` `requires_apk_update`, UI `CHECK FOR YT-DLP UPDATE` staging OpenPGP-signed synthetic `2099.01.02`, `PENDING OVERLAY: 2099.01.02`, and zero hot-swap.
    - `phase2_freshProcessActivatesOverlayAndStagesFaultyCandidate` (`61.851s`, OK): Verified fresh OS process imported `yt_dlp` `2099.01.02` from `filesDir/sovereign_py_overlay/slots/2099.01.02-d18425b0/`, UI `ACTIVE YT-DLP: 2099.01.02 (OVERLAY)`, and staged smoke-failing `2099.02.03`.
    - `phase3_freshProcessRollsBackBrokenPendingToPriorOverlay` (`51.757s`, OK): Verified automatic rollback to `2099.01.02 (OVERLAY)` and UI `ROLLBACK NOTICE: REVERTED FROM 2099.02.03`.
    - `phase4_corruptOverlayFallsBackToBundledImy` (`48.856s`, OK): Verified fallback from corrupted slots to bundled APK `.imy` `2026.10.26 (BUNDLED)`.
    - `phase5_liveGitHubAuthenticityAndOverlayStage` (`89.807s`, OK): Verified live HTTPS fetch from GitHub Releases API, OpenPGP V4 RSA-4096 `SHA2-256SUMS.sig` verification against pinned key `AC0CBBE6848D6A873464AF4E57CF65933B5A7581`, `SHA2-256SUMS` validation, and staging of real `yt-dlp 2026.10.26` (`slot 2026.10.26-b7cdde39`) while leaving live process runtime unswapped.
    - `phase6_liveGitHubOverlayActivatesAfterRestart` (`61.353s`, OK): Verified after `am force-stop` that fresh OS process loaded live GitHub `yt_dlp` `2026.10.26` from `slots/2026.10.26-b7cdde39/yt_dlp/__init__.py` (`inside_overlay_slots: true`, `active_source: "overlay"`) and Settings UI rendered `ACTIVE YT-DLP: 2026.10.26 (OVERLAY)`.
    - Production `com.sovereigntagger` remained untouched (`versionCode=1`, `versionName=1.0.0`, `firstInstallTime=2026-10-05 19:21:32`, `lastUpdateTime=2026-11-12 22:56:25`), and both acceptance packages were uninstalled cleanly.
  - **Moto G `ZT4222BMWN`:** Earlier 4-phase run passed on `276f6ce` (`phase1` `265.747s`, `phase2` `218.82s`, `phase3` `125.559s`, `phase4` `126.166s`); post-hardening 6-phase acceptance executed on BLU `B160V`. Installing/running the signed R8 `release` APK on device remains outside this test run.

## Deferred Scope (Separate Complete Implementation PRs)

- **PR #02:** Backup and encrypted export path isolation (`Downloads/sovereign_config.bin` collision).
- **PR #03:** On-Board Python Doctor redesign & capability diagnostics beyond overlay status hooks.
- **PR #04:** Local build/intermediate cache hygiene and repository guardrails.
