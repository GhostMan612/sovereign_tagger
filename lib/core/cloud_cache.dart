// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'cloud_settings.dart';
import 'storage_client.dart';

class CloudCache {
  static const String _dirName = 'cloud_cache';

  static Future<Directory> _dir() async {
    final base = await StorageClient.tempDir();
    final dir = Directory('$base/$_dirName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static String fileNameFor(String fileId, String name) {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${fileId}_$safe';
  }

  static Future<File?> get(String fileId, String name) async {
    final dir = await _dir();
    final file = File('${dir.path}/${fileNameFor(fileId, name)}');
    if (file.existsSync() && file.lengthSync() > 0) return file;
    return null;
  }

  static Future<String> pathFor(String fileId, String name) async {
    final dir = await _dir();
    return '${dir.path}/${fileNameFor(fileId, name)}';
  }

  static Future<File> put(String fileId, String name, File source, {Set<String> protectedPaths = const <String>{}}) async {
    final dir = await _dir();
    final target = File('${dir.path}/${fileNameFor(fileId, name)}');
    if (target.existsSync()) await target.delete();
    await source.copy(target.path);
    await _evict(dir, protectedPaths: protectedPaths);
    return target;
  }

  static Future<void> remove(String fileId, String name) async {
    final dir = await _dir();
    final file = File('${dir.path}/${fileNameFor(fileId, name)}');
    if (file.existsSync()) await file.delete();
  }

  static Future<int> sizeBytes() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<void> clear() async {
    final dir = await _dir();
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }

  static Future<void> _evict(Directory dir, {Set<String> protectedPaths = const <String>{}}) async {
    final limit = CloudSettings.cacheMb * 1024 * 1024;
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    for (final file in files) {
      if (total <= limit) break;
      if (protectedPaths.contains(file.path)) continue;
      total -= await file.length();
      await file.delete();
    }
  }

  static Future<void> evictKeeping(Set<String> protectedPaths) async {
    final dir = await _dir();
    await _evict(dir, protectedPaths: protectedPaths);
  }
}
