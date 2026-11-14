# Sovereign Tagger — Transactional Updater Rollback & Isolated Moto G Acceptance

## Rollback safety and recovery preservation

Prior to this hardening pass, failed recovery in `android/app/src/main/python/sovereign_yt/updater.py` could drop exception context and clean up temporary artifacts too broadly, while concurrent UI or channel calls could overlap inside `_swap()`.

The transactional updater now enforces:

- **Pre-rename journal and serialization (`_TRANSACTION_LOCK`)**: `_swap()` records `backup_pending` before renaming the live package to `.sovereign_backup`, then `backup_done`, then `committed`; `_restore_orphaned_backup()` recovers unrecorded `.sovereign_backup` directories. Public entry points (`execute_scorched_earth()`, `execute_full_scorched_earth()`, and `recover()`) serialize on `_TRANSACTION_LOCK`.
- **Fail-closed verification in `_recover()` and `_execute_scorched_earth()`**: Cleanup in `_recover()` (`shutil.rmtree(...)`) no longer ignores deletion errors, verifies the live package directory and package structure/version/byte-compilation via `_verify_package(target)` before removing `.sovereign_backup`, `.sovereign_new`, or the transaction journal, and raises `UpdateError` with backup and journal retained if the live package cannot be verified.
- **Explicit recovery-required reporting**: When `_execute_scorched_earth()` encounters an exception whose recovery attempt also fails, it retains both `.sovereign_backup` and `sovereign_update_state.json` and returns JSON with `status="error"`, `recovery_required=True`, and `recovery_error`. `execute_full_scorched_earth()` surfaces core failures (including `recovery_required=True`) without invoking `update_python_stack()`.
- **Settings UI propagation (`lib/screens/settings_screen.dart`)**: Both `CHECK FOR YT-DLP UPDATE` (`updateCore`) and `FULL STACK REFRESH (YT-DLP + DEPS)` (`updateFullStack`) disable both controls while in flight, check `mounted` before state updates, display `RECOVERY REQUIRED: <message>. Backup retained; retry after resolving the storage fault.` when `recovery_required == true`, and leave controls re-enabled for retry.

## Production vs isolated acceptance wiring

`MainActivity.kt` delegates `updateCore` and `updateFullStack` to `CoreUpdaterBridge.execute(ytUpdaterModule, fullStack)`:

- **Production builds (`debug`, `release`, `profile`)**: `android/app/src/production/kotlin/com/sovereigntagger/CoreUpdaterBridge.kt` directly invokes `execute_scorched_earth` or `execute_full_scorched_earth`.
- **Acceptance build (`updaterAcceptance`)**: Configured in `android/app/build.gradle` with `applicationIdSuffix ".updateracceptance"` (distinct Android UID) and compiled only with `-PupdaterAcceptanceTest=true`. Its `CoreUpdaterBridge.kt` fails closed (`IllegalStateException`) if `BuildConfig.APPLICATION_ID != "com.sovereigntagger.updateracceptance"` or if no instrumentation fixture is registered.

## Host verification gates (clean local runs)

All host gates passed locally on clean checkout `80d85462b4fb848657936a733850d5128d950e0d`:

- **Static hygiene check**: Genesis headers, zero comments after line 4 on new `.dart`/`.kt`/`.py` files, and zero mojibake across all modified/added code and test files passed (verified at `1c9bae7` + clean `build.gradle` check at `80d8546`).
- **Python unit tests (`python -m unittest discover -s test/python -p "test_*.py" -v`)**: **37/37 passed** (`test/python/test_transactional_updater.py`: **24/24**), plus **15/15 consecutive stress runs** of `test_transactional_updater.py` passed.
- **Flutter analysis (`flutter analyze --no-pub`)**: **No issues found!**.
- **Flutter test suite (`flutter test --no-pub`)**: **213/213 passed** (0 skipped, 0 failed), including **7** UI state/disposal/retry widget tests in `test/updater_settings_test.dart`.
- **Android debug build (`flutter build apk --debug --no-pub --target-platform android-arm64`)**: Built `app-debug.apk` (SHA-256 `9ced77fa31cd74e0312aafa11a092f0bae9802ef5fefb5f039236f8710858c51`, `source_sha: 80d85462b4fb848657936a733850d5128d950e0d`, `source_dirty: false`).
- **Android JVM unit build/tests (`gradlew.bat :app:testDebugUnitTest --console=plain`)**: **BUILD SUCCESSFUL** with `src/production/kotlin/com/sovereigntagger/CoreUpdaterBridge.kt`.
- **Gradle CI compatibility note (`80d8546`)**: `create("updaterAcceptance")` and `updaterAcceptance*` dependency substitution in `android/app/build.gradle` are gated behind `if (updaterAcceptanceTest)` (`-PupdaterAcceptanceTest=true`) so Flutter 3.50.0 plugin subprojects (`:android_file_picker`) do not inherit `applicationIdSuffix ".updateracceptance"` during normal/CI builds. `:app:packageUpdaterAcceptance` and `:app:packageUpdaterAcceptanceAndroidTest` also compiled cleanly at `80d8546`.

## Recorded isolated device acceptance (Moto G — Android 16 / API 36)

### Build provenance & isolation checks

- **Clean code commit (`fix/p0-updater-crash-window-serialization`)**: `1c9bae7a9c55fd22837c693f61d389ac14257edf` (`source_dirty: false`; `80d8546` only gated `updaterAcceptance` in `android/app/build.gradle` behind `-PupdaterAcceptanceTest=true` and did not alter app/test runtime code)
- **Acceptance package**: `com.sovereigntagger.updateracceptance` (installed from `android/gradlew.bat :app:installUpdaterAcceptance :app:installUpdaterAcceptanceAndroidTest -PupdaterAcceptanceTest=true -Ptarget=test/device/updater_acceptance_main.dart`)
- **Installed base APK SHA-256 on device**: `a95e424d5d96970104fc07ff5e2ee0654a4cf204f9fb0088cff150e94d95b507`
- **Target handset**: Moto G (`ZT4222BMWN`, `model: moto_g___2025`, `product: kansas_g_sys`)
- **Production app isolation (`com.sovereigntagger`)**: `distinct_application_uid: true`, `original_package_unchanged: true`; verified unchanged before and after all runs (`appId=10821`, `versionCode=1`, `firstInstallTime=2026-10-04 16:04:52`, `lastUpdateTime=2026-11-14 02:34:52` / `1794645292929`).
- **Unconfigured fail-closed check**: `unconfigured_bridge_blocked: true` (both `fullStack=false` and `fullStack=true` threw `IllegalStateException` before fixture registration).
- **Chaquopy runtime stability**: Bundled `yt_dlp` `2026.10.26` (`code_sha256: c2b67b5ce23538c222cbf010dd31c4dc2dcf6728c04f1230b741a91770eb9065`) remained untouched across every phase (`runtime_import_fingerprint_unchanged: true`); compiled `sovereign_yt.updater._execute_scorched_earth` bytecode `code_sha256: 49a8fd8d7a5154fac9a8371679364ca2afe7ffa33c8ce8369e9519a26b0d27f1`.

### Executed UIAutomator phases (`UpdaterAcceptanceTest`)

1. **Cross-process rollback failure and restart recovery (`phase=failure` -> `am force-stop` -> `phase=restart`)**:
   - `failed_restore` (`pid: 28002`): Tapped `CHECK FOR YT-DLP UPDATE` under `SettingsScreen` with injected `OSError("SAMPLE FIXTURE RESTORE FAILURE")` on backup restore. Verified `target_exists: false`, `backup_exists: true` (`backup_sha256 == expected_backup_sha256 == e902e55605547af3ba807c34a298751782d8459d873175964fbb6f905c23c45b`), `journal_exists: true` (`journal_phase: "backup_done"`), `staging_exists: true`, `recovery_required: true`, and UI scroll/visibility of `"RECOVERY REQUIRED"`.
   - `preserved_after_process_restart` (`pid: 29049 != 28002`): After `am force-stop com.sovereigntagger.updateracceptance`, verified backup digest, journal (`backup_done`), and staging remained intact in the new OS process before tapping retry.
   - `retry_success` (`pid: 29049`): Tapped `CHECK FOR YT-DLP UPDATE` again without the injected rename fault; verified recovery + synthetic update committed (`version: "2026.11.14"`, `tag: "SAMPLE_RELEASE"`, `target_exists: true`) and cleanup completed (`backup_exists: false`, `journal_exists: false`, `staging_exists: false`).
2. **End-to-end consolidated flow (`phase=all`, `pm clear` first, `pid: 29955`)**:
   - Verified `initial_success` (`2026.01.01 -> 2026.11.14`) -> `failed_restore` (`backup_sha256: e902e55605547af3ba807c34a298751782d8459d873175964fbb6f905c23c45b`, `recovery_required: true`) -> `retry_success` (`2026.11.14`, artifacts cleared).
3. **Device cleanup**:
   - Uninstalled `com.sovereigntagger.updateracceptance.test` and `com.sovereigntagger.updateracceptance`; `adb -s ZT4222BMWN shell pm list packages com.sovereigntagger` reported only `package:com.sovereigntagger`.

## Known limitations / unverified scope

- **Fixture-isolated target and transport**: On-device acceptance runs inside `com.sovereigntagger.updateracceptance` against a private `filesDir/updater_acceptance/...` synthetic package using a test fixture that patches `updater._fetch_release` (`fixture://SAMPLE_RELEASE` returning an in-memory `.tar.gz`) and `updater.os.rename` (`failure` mode only). Live GitHub API/tarball downloads and live mutation of Chaquopy's installed `requirements/yt_dlp` directory on the phone were not executed.
- **Full-stack `pip` upgrade/rollback on device**: `updaterAcceptance` rejects `fullStack=true`; core `recovery_required` propagation in `execute_full_scorched_earth()` and Settings UI handling for `updateFullStack` are verified by Python (`test_full_stack_surfaces_core_recovery_failure_without_upgrading_helpers`) and Flutter widget tests (`test/updater_settings_test.dart`), whereas live PyPI/pip upgrades on Android remain unverified on hardware.
- **Build variant & commit delta**: Device acceptance ran at clean commit `1c9bae7` using the `updaterAcceptance` debuggable test build type (`matchingFallbacks = ["debug"]`), not a signed `release` APK. On-device UIAutomator tests were not re-executed after `80d8546` (which only gated `updaterAcceptance` in `android/app/build.gradle`; `ZT4222BMWN` disconnected from USB prior to post-build install), though `:app:packageUpdaterAcceptance` and `:app:packageUpdaterAcceptanceAndroidTest` packaged cleanly at `80d8546`.
