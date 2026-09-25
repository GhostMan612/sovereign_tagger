// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'title_cleaner.dart';

class TagIO {
  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/id3');

  static const Set<String> writableExtensions = {'mp3', 'm4a', 'm4b', 'mp4', 'flac', 'ogg', 'wav', 'aif', 'aiff', 'wma', 'dsf'};

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
    try {
      final ok = await _channel.invokeMethod('writeTags', {'filePath': path, 'metadata': metadata});
      return ok == true;
    } catch (_) {
      return false;
    }
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
