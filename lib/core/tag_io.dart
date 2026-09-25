// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/services.dart';
import 'ffmpeg_executor.dart';
import 'title_cleaner.dart';

class TagIO {
  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/id3');

  static const Set<String> writableExtensions = {'mp3', 'm4a', 'm4b', 'mp4', 'flac', 'ogg', 'wav', 'aif', 'aiff', 'wma', 'dsf'};
  static const Set<String> _mp4Extensions = {'m4a', 'm4b', 'mp4'};

  static const List<String> editableKeys = [
    'TITLE', 'ARTIST', 'ALBUM', 'ALBUM_ARTIST', 'YEAR', 'GENRE', 'TRACK', 'TRACK_TOTAL', 'DISC_NO', 'DISC_TOTAL',
    'COMPOSER', 'PRODUCER', 'COMMENT', 'LANGUAGE', 'ENCODER', 'LYRICS', 'ARTWORK_BASE64',
  ];

  static bool canWrite(String path) => writableExtensions.contains(TitleCleaner.extensionOf(path));

  static Future<Map<String, String>> read(String path, {bool withArtwork = true}) async {
    try {
      final Map<Object?, Object?>? raw = await _channel.invokeMethod('readTags', {'filePath': path, 'skipArtwork': !withArtwork});
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {
      return {};
    }
  }

  static Future<bool> write(String path, Map<String, String> metadata) async {
    final isMp4 = _mp4Extensions.contains(TitleCleaner.extensionOf(path));
    if (isMp4 && await isFragmentedMp4(path)) await _flattenMp4(path);
    if (await _writeOnce(path, metadata)) return true;
    if (!isMp4 || !await _flattenMp4(path)) return false;
    return _writeOnce(path, metadata);
  }

  static Future<bool> isFragmentedMp4(String path) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final length = await raf.length();
      var offset = 0;
      for (var i = 0; i < 32 && offset + 8 <= length; i++) {
        await raf.setPosition(offset);
        final head = await raf.read(16);
        if (head.length < 8) break;
        var size = (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
        final type = String.fromCharCodes(head.sublist(4, 8));
        if (type == 'moof' || type == 'mvex') return true;
        if (size == 1 && head.length >= 16) {
          size = 0;
          for (var b = 8; b < 16; b++) {
            size = (size << 8) | head[b];
          }
        }
        if (size < 8) break;
        offset += size;
      }
    } catch (_) {
    } finally {
      await raf?.close();
    }
    return false;
  }

  static Future<bool> _writeOnce(String path, Map<String, String> metadata) async {
    try {
      final ok = await _channel.invokeMethod('writeTags', {'filePath': path, 'metadata': metadata});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _flattenMp4(String path) async {
    final ext = TitleCleaner.extensionOf(path);
    final flat = '${path.substring(0, path.length - ext.length - 1)}_flat${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      final session = await FFmpegExecutor.execute('-y -i "$path" -map 0 -c copy -movflags +faststart "$flat"');
      if (ReturnCode.isSuccess(session.getReturnCode()) && File(flat).existsSync() && File(flat).lengthSync() > 0) {
        await File(flat).rename(path);
        return true;
      }
    } catch (_) {}
    try {
      File(flat).deleteSync();
    } catch (_) {}
    return false;
  }

  static String _normalized(String key, String value) {
    final v = value.trim();
    if (key == 'TRACK' || key == 'DISC_NO') {
      final n = int.tryParse(v.split('/').first.trim());
      return n == null ? v : n.toString();
    }
    if (key == 'YEAR') return v.length >= 4 ? v.substring(0, 4) : v;
    return v;
  }

  static List<String> verify(Map<String, String> wanted, Map<String, String> back) {
    final mismatches = <String>[];
    for (final key in const ['TITLE', 'ARTIST', 'ALBUM', 'ALBUM_ARTIST', 'YEAR', 'GENRE', 'TRACK', 'DISC_NO']) {
      if (!wanted.containsKey(key)) continue;
      if (_normalized(key, wanted[key] ?? '') != _normalized(key, back[key] ?? '')) mismatches.add(key);
    }
    if ((wanted['ARTWORK_BASE64'] ?? '').isNotEmpty && (back['ARTWORK_BASE64'] ?? '').isEmpty) mismatches.add('ARTWORK');
    if ((wanted['LYRICS'] ?? '').trim().isNotEmpty && (back['LYRICS'] ?? '').trim().isEmpty) mismatches.add('LYRICS');
    return mismatches;
  }
}
