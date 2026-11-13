# Vendored packages

## audio_waveforms

`audio_waveforms` is vendored here because the newest pub release (2.0.2,
published 2026-01-09) still applies the legacy Kotlin Gradle Plugin (KGP) in
`android/build.gradle`. Flutter fails over to legacy KGP while any plugin in
the build applies it, and future Flutter versions will refuse to build.

The upstream package has no release that supports Built-in Kotlin, so this
copy is 2.0.2 with only its Gradle setup migrated:

- dropped the `buildscript` block (AGP + KGP classpaths) — the app's
  `settings.gradle.kts` pluginManagement and AGP 9's built-in Kotlin supply
  both;
- removed `apply plugin: 'kotlin-android'`;
- replaced `kotlinOptions { jvmTarget = '1.8' }` with the built-in
  `kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }` DSL;
- raised `compileOptions` to Java 17 to match the app and avoid an
  inconsistent JVM-target error.

Dart (`lib/`), Android (`android/`) and iOS (`ios/`) sources are unchanged from
2.0.2. `example/`, `preview/` and `doc/` are omitted because they are not part
of the published plugin payload.

The app pins it with a `dependency_overrides` entry in `pubspec.yaml`. When
upstream ships a Built-in Kotlin release, delete this directory and the
override, and bump `audio_waveforms` normally.

To refresh from upstream:

```powershell
flutter pub cache add audio_waveforms --version <new-version>
$src = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\audio_waveforms-<new-version>"
# copy lib/, android/, ios/, pubspec.yaml, LICENSE, README.md, CHANGELOG.md
# then re-apply the Gradle migration above
```
