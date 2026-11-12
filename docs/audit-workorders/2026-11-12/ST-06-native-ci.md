# ST-06 — Add native Android, Kotlin, C++, Chaquopy and ABI CI gates

> **Priority:** P1  
> **Status:** SPECIFICATION ONLY — this PR does not change runtime behavior  
> **Verified audit baseline:** `0253a994a702cee8b3f834cb8dfb6edd7333fd81`  
> **Audit:** Sovereign Tagger remote deep sweep, 2026-11-12  
> **Integration:** draft plan must result in separate implementation PR(s), tested and approved independently.

## Source evidence and problem
Existing green CI runs Flutter analyzer and tests plus Python doctor, but never compiles Kotlin/JNI/NDK and embedded Chaquopy Python; no APK/ABI regression coverage.

- [.github/workflows/dart.yml](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.github/workflows/dart.yml)
- [android/app/src/main/cpp/CMakeLists.txt](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/src/main/cpp/CMakeLists.txt)
- [android/app/build.gradle](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/app/build.gradle)
- [android/settings.gradle.kts](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/android/settings.gradle.kts)

## Intended implementation touch surfaces
- `.github/workflows/android-native.yml (new)`
- `.github/workflows/dart.yml`
- `android/app/src/test/** (new)`
- `test/native_contract/** (new)`
- `docs/ci-gates.md (new)`

## Detailed work order
1. Keep fast existing Dart/Python workflow; add independently required Android job using JDK/Android SDK/NDK/CMake/Flutter/Gradle version matrix pinned from repo.
2. Run assembleDebug for arm64-v8a and x86_64 with network/build caching and executable artifact manifest; do not require production signing secrets.
3. Compile JNI sovereign_whistle using imported needle ARM64 archive; verify x86_64 stub returns unsupported rather than loading a missing binary.
4. Test native MethodChannel method-name/argument contract against Dart callers; cover storage, ytdlp, pCloud auth, embedding, STT, ACRCloud boundaries with test fixtures.
5. Run Android unit tests and at least emulator instrumentation covering failure injection, OS backup rules, native model capability and MediaStore APIs.
6. Record actual APK size/ABI contents, critical FFmpeg filter availability, fixed Python wheel dependencies and dependency hashes.
7. Separate required CI gates from hardware-only smoke and prohibit misleading 'full tested' sign-off based on Dart-only green.

## Negative and regression test matrix
- [ ] Deliberately break Kotlin import/JNI symbol/method-channel name and demonstrate CI red.
- [ ] Build both intended ABIs; verify no accidental armeabi/x86 native output inclusion unless explicitly configured.
- [ ] Exercise Gradle cache restore with clean build and version pin mismatch.

## Acceptance criteria and evidence required
- [ ] A successful run produces compilable Android ARM64 and x86_64 APKs, native reports and artifact metadata.
- [ ] No secrets in CI logs/artifacts; baseline build on hosted runner reproduced.
- [ ] Physical Moto G/BLU smoke as separate approval gate.
- [ ] CI output and exact commit SHA attached to implementation PR; reviewer checks observed results rather than trusting a narrative.
- [ ] Explicit change-set audit for backward compatibility, operator visibility, failure containment, security and data preservation.
- [ ] If Android native/FFmpeg/MediaStore changes, a successful Flutter-only CI run does not close the Android hardware gate.

## Dependencies and release order
Needed before merging Kotlin/Gradle/NDK modifying code work orders.

## Rollback / failure policy
Keep original Flutter workflow functioning while native job stabilizes; temporary optional native job explicitly labeled nonblocking until green.

## Documentation closeout
Update `.blueprints/CURRENT_STATE.md`, `.blueprints/ROADMAP.md`, `SESSION_HANDOFF.md` and affected API guidance **only after code, tests and device gates land**. Keep this spec marked open until the implementation PR has a verified merge commit. No production credential or private media is required in test fixtures.
