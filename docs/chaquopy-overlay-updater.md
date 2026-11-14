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
  - Requires non-draft, non-prerelease CalVer metadata with both `yt-dlp.tar.gz` and `SHA2-256SUMS` assets, verifies compressed download ceiling (`32 MiB`) and cryptographic SHA-256 match, rejects path traversal/absolute paths/symlinks/hardlinks/special files/zip-bombs/ELF/PE/bytecode payloads, checks `pyproject.toml` `requires-python`, verifies release `tag_name == yt_dlp/version.py __version__`, and blocks CalVer downgrades below active or bundled `yt-dlp`.
- **Automatic rollback & Option B APK-managed dependencies:**
  - Startup marks `activating` atomically prior to inserting a pending slot into `sys.path[0]`, validates `slot.json` + AST + non-Python assets + `tree_sha256` (ignoring runtime `__pycache__`), and runs an in-process `YoutubeDL` instantiation and `__file__` origin smoke test.
  - Interrupted activations or smoke/validation failures roll back cleanly to `previous_slot` or bundled `.imy` `yt_dlp`. Corrupted `active.json` is quarantined (`active.json.corrupt.*`) with bundled fallback.
  - `execute_full_scorched_earth` / `updateFullStack` MethodChannel no longer invokes subprocess `pip`; it returns `{"status": "requires_apk_update", "core_updatable": true, "apk_managed_packages": ["mutagen", "lyricsgenius"]}` with zero mutation. [`settings_screen.dart`](file:///c:/sovereign_tagger/lib/screens/settings_screen.dart) displays bundled/active/source/pending/restart/rollback/recovery telemetry and documents that `mutagen` and `lyricsgenius` update via new APK builds.

## Verification

- **Python unit suite (`test/python/`):** `python -m unittest discover -s test/python -p "test_*.py" -v` — `28` tests OK (including real isolated Python subprocess restart activation, rollback to previous slot, rollback to bundled `.imy`, premature-import detection, security/bomb/downgrade rejections, concurrency serialization, and non-mutating `requires_apk_update`).
- **Flutter analyzer & test suite:** `flutter analyze --no-pub --no-fatal-infos` (`No issues found!`), `flutter test --no-pub` (`212` tests passed, including updated `test/updater_settings_test.dart`).
- **Android JVM unit tests & builds:** `:app:testDebugUnitTest --no-daemon` passed (`PythonOverlayContractTest`), `flutter build apk --debug --no-pub --target-platform android-arm64` (`sha256=550b485ef8c4ebb27f505d881894f180908d05a5b569b88de18f3ff20c43dee6`) and `android-x64` (`sha256=d7e0e2d8d5aedfbcd39c63f6b1c2790c47e9944b2875727341866c53001f8bff`) passed, and unsigned `:app:assembleRelease` failed closed as required.
- **Isolated Moto G hardware acceptance (`ZT4222BMWN`, Android `com.sovereigntagger.updateracceptance`):**
  - `phase1_stageOverlayUpdateAndVerifyNoHotSwap` (`265.747s`, OK): Verified live Chaquopy `.imy` `2026.10.26 (BUNDLED)`, `updateFullStack` `requires_apk_update`, UI `CHECK FOR YT-DLP UPDATE` staging synthetic `2099.01.02`, `PENDING OVERLAY: 2099.01.02`, and zero hot-swap.
  - `phase2_freshProcessActivatesOverlayAndStagesFaultyCandidate` (`218.82s`, OK after `am force-stop`): Verified fresh OS process imported `yt_dlp` `2099.01.02` from `filesDir/sovereign_py_overlay/slots/`, UI `ACTIVE YT-DLP: 2099.01.02 (OVERLAY)`, and staged smoke-failing `2099.02.03`.
  - `phase3_freshProcessRollsBackBrokenPendingToPriorOverlay` (`125.559s`, OK after `am force-stop`): Verified automatic rollback to `2099.01.02 (OVERLAY)` and UI `ROLLBACK NOTICE: REVERTED FROM 2099.02.03`.
  - `phase4_corruptOverlayFallsBackToBundledImy` (`126.166s`, OK after `am force-stop`): Verified fallback from corrupted slots to bundled APK `.imy` `2026.10.26 (BUNDLED)`.
  - Production `com.sovereigntagger` remained untouched (`versionCode=1`, `versionName=1.0.0`, `firstInstallTime=2026-10-04 16:04:52`, `lastUpdateTime=2026-11-14 12:34:50`), and both acceptance packages were uninstalled cleanly.

## Deferred Scope (Separate Complete Implementation PRs)

- **PR #02:** Backup and encrypted export path isolation (`Downloads/sovereign_config.bin` collision).
- **PR #03:** On-Board Python Doctor redesign & capability diagnostics beyond overlay status hooks.
- **PR #04:** Local build/intermediate cache hygiene and repository guardrails.
