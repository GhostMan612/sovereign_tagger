# R8 / ProGuard rules — Sovereign Tagger
#
# WHY THIS FILE EXISTS (2026-10-01):
#   `flutter build apk --release` was BROKEN and nobody knew, because only the
#   debug build had ever been built here — debug skips R8 entirely. Release runs
#   `:app:minifyReleaseWithR8`, which failed with:
#     R8: Missing class java.awt.image.BufferedImage
#     Missing class javax.imageio.ImageIO
#     Missing class javax.imageio.stream.ImageInputStream
#   jaudiotagger (the `id3` channel backend, Id3Tagger.kt) is a desktop-Java
#   library and references AWT/ImageIO for its image-based artwork helpers.
#   Those classes do not exist on Android. We never take those code paths —
#   Phase 27.9 moved artwork writing to raw FLAC/OGG picture blocks precisely so
#   it would not depend on BufferedImage — so the references are dead code and
#   R8 should be told to ignore them rather than fail the build.
#
# The three -dontwarn lines below are verbatim what R8 generated into
# build/app/outputs/mapping/release/missing_rules.txt.

-dontwarn java.awt.image.BufferedImage
-dontwarn javax.imageio.ImageIO
-dontwarn javax.imageio.stream.ImageInputStream

# Broader desktop-JAWT guard: other jaudiotagger code paths reference these, and
# R8 only reports the ones reachable from our actual call graph. Without this a
# future refactor can turn a warning back into a build break.
-dontwarn java.awt.**
-dontwarn javax.imageio.**
-dontwarn javax.swing.**

# Flutter deferred-components support: the embedding's
# DeferredComponentsManager references the Play Core split-install API, but Play
# Core is not a dependency of this app (we ship one APK, no deferred components).
# R8 therefore sees unreachable references and fails the build. Flutter's own
# guidance for this exact case is a blanket -dontwarn on the package.
# (Second R8 failure layer, discovered 2026-10-01 after fixing the jaudiotagger
# layer above — R8 reports missing classes one layer at a time.)
-dontwarn com.google.android.play.core.**

# jaudiotagger resolves some tag readers/writers reflectively (by class name
# from its tag-type registry). R8 cannot see those references and would strip or
# rename the classes, which fails at runtime rather than at build time — the worst
# failure mode, because tagging is lossless-critical here. Keep the library whole.
# Size impact is negligible: the APK already bundles ~40MB/ABI of FFmpeg plus a
# 141MB Whisper model.
-keep class org.jaudiotagger.** { *; }
-keep interface org.jaudiotagger.** { *; }
-dontwarn org.jaudiotagger.**

# The Kotlin MethodChannel bridges are called directly from Dart, but their
# MethodCallHandler implementations are resolved by name on the native side.
-keep class com.sovereigntagger.** { *; }

# Flutter/Firebase-style keep of the plugin entry points that Gradle resolves by
# reflection at build time.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
