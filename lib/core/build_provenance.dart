// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';

/// Source-to-APK identity recorded at build time by
/// `writeSovereignBuildManifest` in `android/app/build.gradle`.
///
/// The Gradle build refuses to run when the commit SHA cannot be resolved, so
/// [sourceSha] is expected to be present on any real install. [load] still
/// degrades to `null` where the channel is absent (tests, non-Android hosts).
class BuildProvenance {
  const BuildProvenance({
    required this.sourceSha,
    required this.sourceDirty,
    required this.versionCode,
    required this.versionName,
    required this.buildAbis,
    required this.builtAtUtc,
  });

  final String sourceSha;
  final bool sourceDirty;
  final int versionCode;
  final String versionName;
  final String buildAbis;
  final String builtAtUtc;

  static const MethodChannel _channel =
      MethodChannel('com.sovereign.tagger/storage');

  /// Fetches the build identity, or `null` when it is unavailable.
  static Future<BuildProvenance?> load() async {
    try {
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getBuildProvenance');
      if (raw == null) return null;
      final sha = raw['sourceSha']?.toString() ?? '';
      if (sha.isEmpty) return null;
      return BuildProvenance(
        sourceSha: sha,
        sourceDirty: raw['sourceDirty'] == true,
        versionCode: int.tryParse(raw['versionCode']?.toString() ?? '') ?? 0,
        versionName: raw['versionName']?.toString() ?? '',
        buildAbis: raw['buildAbis']?.toString() ?? '',
        builtAtUtc: raw['builtAtUtc']?.toString() ?? '',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// True when the identity is complete enough to audit a device install.
  bool get isComplete => sourceSha.length == 40 && versionName.isNotEmpty;

  /// One-line identity for the startup log.
  String get identityLine => 'sha=$sourceSha'
      '${sourceDirty ? ' (dirty tree)' : ''} '
      'version=$versionName($versionCode) '
      'abis=$buildAbis built=$builtAtUtc';
}
