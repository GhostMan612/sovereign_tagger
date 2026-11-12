// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SaveResult {
  final String uri;
  final String path;
  final String displayName;
  final bool overwroteOriginal;
  final bool renamed;
  const SaveResult({required this.uri, required this.path, required this.displayName, required this.overwroteOriginal, required this.renamed});

  factory SaveResult.fromMap(Map<Object?, Object?> m, {required bool overwrote}) => SaveResult(
        uri: m['uri']?.toString() ?? '',
        path: m['path']?.toString() ?? '',
        displayName: m['displayName']?.toString() ?? '',
        overwroteOriginal: overwrote,
        renamed: m['renamed'] != 'false',
      );
}

class StorageClient {
  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/storage');
  static const EventChannel _shareChannel = EventChannel('com.sovereign.tagger/share');
  static int? _sdk;
  static String? _temp;
  static Stream<String>? _shares;

  static final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

  static void bumpLibrary() => libraryRevision.value++;

  static Stream<String> get sharedUrls => _shares ??= _shareChannel.receiveBroadcastStream().map((e) => e.toString()).asBroadcastStream();

  static Future<int> sdkInt() async {
    if (_sdk != null) return _sdk!;
    try {
      _sdk = await _channel.invokeMethod<int>('sdkInt') ?? 33;
    } catch (_) {
      _sdk = 33;
    }
    return _sdk!;
  }

  static Future<String> tempDir() async {
    if (_temp != null) return _temp!;
    _temp = (await _channel.invokeMethod('getTempDirectory')).toString();
    return _temp!;
  }

  static Future<bool> isAppStaging(String path) async {
    if (path.isEmpty) return false;
    final temp = await tempDir();
    return path.startsWith(temp) || path.contains('/Android/data/com.sovereigntagger/') || path.contains('/com.sovereigntagger/cache/');
  }

  static Future<String?> resolveMediaUri({String? identifier, String? path}) async {
    try {
      return await _channel.invokeMethod<String>('resolveMediaUri', {'identifier': identifier, 'path': path});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _legacyStoragePermission() async {
    if (await sdkInt() > 28) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<bool> requestWriteAccess(List<String> uris) async {
    if (uris.isEmpty) return true;
    if (!await _legacyStoragePermission()) return false;
    try {
      return await _channel.invokeMethod<bool>('requestWriteAccess', {'uris': uris}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestDelete(List<String> uris) async {
    if (uris.isEmpty) return true;
    if (!await _legacyStoragePermission()) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('requestDelete', {'uris': uris}) ?? false;
      if (ok) bumpLibrary();
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<SaveResult> overwriteOriginal({required String uri, required String workingPath, String? displayName}) async {
    final Map<Object?, Object?> raw = await _channel
        .invokeMethod('overwriteMedia', {'uri': uri, 'srcPath': workingPath, 'displayName': displayName})
        .timeout(
          const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException('The write-back to the original did not respond in time. The original may be incomplete; check it before saving again.'),
        );
    bumpLibrary();
    return SaveResult.fromMap(raw, overwrote: true);
  }

  static Future<SaveResult> exportToLibrary(String path, String title) async {
    final Map<Object?, Object?> raw = await _channel.invokeMethod('exportToLibrary', {'filePath': path, 'title': title});
    bumpLibrary();
    return SaveResult.fromMap(raw, overwrote: false);
  }

  static Future<String?> exportTextToDownloads({
    required String fileName,
    required String content,
    String mimeType = 'text/plain',
  }) async {
    if (!await _legacyStoragePermission()) return null;
    try {
      return await _channel.invokeMethod<String>('exportTextToDownloads', {
        'fileName': fileName,
        'mimeType': mimeType,
        'data': content,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, Object?>>> queryAudio() async {
    final List<Object?>? raw = await _channel.invokeMethod('queryAudio');
    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<Uint8List?> loadArtwork(String uri, {int size = 256}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('loadArtwork', {'uri': uri, 'size': size});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> requestPhotosPermission() async {
    final sdk = await sdkInt();
    final permission = sdk >= 33 ? Permission.photos : Permission.storage;
    var status = await permission.status;
    if (!status.isGranted) status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  static Future<List<Map<String, Object?>>> queryPhotos() async {
    final List<Object?>? raw = await _channel.invokeMethod('queryPhotos');
    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<Uint8List?> loadPhotoThumbnail(String uri, {int size = 256}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('loadPhotoThumbnail', {'uri': uri, 'size': size});
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> loadPhoto(String uri, {int maxSize = 2048}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('loadPhoto', {'uri': uri, 'maxSize': maxSize});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> exportPhotoToPictures({required String uri, String? displayName}) async {
    try {
      return await _channel.invokeMethod<String>('exportPhotoToPictures', {'uri': uri, 'displayName': displayName});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> exportPhotoFileToPictures({required String filePath, String? displayName}) async {
    try {
      return await _channel.invokeMethod<String>('exportPhotoFileToPictures', {'filePath': filePath, 'displayName': displayName});
    } catch (_) {
      return null;
    }
  }

  static Future<int> photoOrientation({required String uri}) async {
    try {
      return await _channel.invokeMethod<int>('photoOrientation', {'uri': uri}) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  static Future<bool> sharePhoto({required String uri, String mimeType = 'image/jpeg'}) async {
    try {
      return await _channel.invokeMethod<bool>('sharePhoto', {'uri': uri, 'mimeType': mimeType}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> copyToStaging(String sourcePath, {String prefix = 'forge'}) async {
    final temp = await tempDir();
    final dir = Directory('$temp/staging');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = sourcePath.split('/').last;
    final target = '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$name';
    try {
      await File(sourcePath).copy(target);
    } catch (e) {
      try {
        final partial = File(target);
        if (partial.existsSync()) partial.deleteSync();
      } catch (_) {}
      rethrow;
    }
    _sweepStaging(dir);
    return target;
  }

  static Future<String> encryptConfig(String plainText, {String? passphrase}) async {
    final res = await _channel.invokeMethod<String>('encryptConfig', {
      'data': plainText,
      if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
    });
    if (res == null || res.isEmpty) {
      throw StateError('Encryption returned empty payload');
    }
    return res;
  }

  static Future<String> decryptConfig(String cipherText, {String? passphrase}) async {
    final trimmed = cipherText.trim();
    if (trimmed.startsWith('SOV2:')) {
      final res = await _channel.invokeMethod<String>('decryptConfig', {
        'data': cipherText,
        if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
      });
      if (res == null || res.isEmpty) {
        throw StateError('Decryption failed or returned empty payload');
      }
      return res;
    }
    try {
      final xorBytes = base64Decode(trimmed);
      final bytes = xorBytes.map((b) => b ^ 0x53).toList();
      final decoded = utf8.decode(bytes);
      if (decoded.startsWith('{')) return decoded;
    } catch (_) {}
    throw ArgumentError('Unrecognized backup format or corrupted payload');
  }

  static Future<List<Map<String, String>>> recoverPendingOverwrites() async {
    final res = await _channel.invokeListMethod<Map>('recoverPendingOverwrites');
    if (res == null) {
      throw StateError('Recovery vault scan returned no result');
    }
    return res
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
        .toList();
  }

  static Future<Map<String, String>> restorePendingOverwrite(String backupPath) async {
    final Map<Object?, Object?>? res = await _channel.invokeMethod<Map<Object?, Object?>>('restorePendingOverwrite', {'backupPath': backupPath});
    bumpLibrary();
    return res?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {};
  }

  static Future<bool> discardPendingOverwrite(String backupPath) async {
    final ok = await _channel.invokeMethod<bool>('discardPendingOverwrite', {'backupPath': backupPath});
    return ok ?? false;
  }

  static Future<Map<String, Object?>> runNativeSecuritySelfTest() async {
    try {
      final Map<Object?, Object?>? res = await _channel.invokeMethod<Map<Object?, Object?>>('runNativeSecuritySelfTest');
      return res?.map((k, v) => MapEntry(k.toString(), v)) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  static void _sweepStaging(Directory dir) {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 6));
      for (final entity in dir.listSync()) {
        if (entity is File && entity.statSync().modified.isBefore(cutoff)) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
