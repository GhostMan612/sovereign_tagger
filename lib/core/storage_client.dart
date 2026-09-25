// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SaveResult {
  final String uri;
  final String path;
  final String displayName;
  final bool overwroteOriginal;
  const SaveResult({required this.uri, required this.path, required this.displayName, required this.overwroteOriginal});

  factory SaveResult.fromMap(Map<Object?, Object?> m, {required bool overwrote}) => SaveResult(
        uri: m['uri']?.toString() ?? '',
        path: m['path']?.toString() ?? '',
        displayName: m['displayName']?.toString() ?? '',
        overwroteOriginal: overwrote,
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
    final Map<Object?, Object?> raw = await _channel.invokeMethod('overwriteMedia', {'uri': uri, 'srcPath': workingPath, 'displayName': displayName});
    bumpLibrary();
    return SaveResult.fromMap(raw, overwrote: true);
  }

  static Future<SaveResult> exportToLibrary(String path, String title) async {
    final Map<Object?, Object?> raw = await _channel.invokeMethod('exportToLibrary', {'filePath': path, 'title': title});
    bumpLibrary();
    return SaveResult.fromMap(raw, overwrote: false);
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

  static Future<String> copyToStaging(String sourcePath, {String prefix = 'forge'}) async {
    final temp = await tempDir();
    final dir = Directory('$temp/staging');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = sourcePath.split('/').last;
    final target = '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$name';
    await File(sourcePath).copy(target);
    return target;
  }
}
