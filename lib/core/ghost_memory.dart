// ===================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ===================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GhostPlayRecord {
  final String path;
  final String title;
  final String artist;
  final int playedAtMs;

  const GhostPlayRecord({
    required this.path,
    required this.title,
    required this.artist,
    required this.playedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'artist': artist,
        'playedAtMs': playedAtMs,
      };

  factory GhostPlayRecord.fromJson(Map<String, dynamic> json) {
    return GhostPlayRecord(
      path: (json['path'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      playedAtMs: (json['playedAtMs'] is num) ? (json['playedAtMs'] as num).toInt() : 0,
    );
  }
}

class GhostMemory {
  static const String _playHistoryKey = 'ghost_memory_play_history_v1';
  static const String _artistCountsKey = 'ghost_memory_artist_counts_v1';
  static const String _nameFixesKey = 'ghost_memory_name_fixes_v1';
  static const String _lastSentinelSummaryKey = 'ghost_memory_last_sentinel_v1';
  static const int _maxHistory = 120;

  static final List<GhostPlayRecord> _history = <GhostPlayRecord>[];
  static final Map<String, int> _artistCounts = <String, int>{};
  static final Map<String, String> _nameFixes = <String, String>{};
  static String _lastSentinelSummary = '';
  static bool _loaded = false;

  static List<GhostPlayRecord> get history => List.unmodifiable(_history);
  static Map<String, int> get artistCounts => Map.unmodifiable(_artistCounts);
  static Map<String, String> get nameFixes => Map.unmodifiable(_nameFixes);
  static String get lastSentinelSummary => _lastSentinelSummary;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHistory = prefs.getString(_playHistoryKey);
      if (rawHistory != null && rawHistory.isNotEmpty) {
        final decoded = jsonDecode(rawHistory);
        if (decoded is List) {
          _history
            ..clear()
            ..addAll(decoded.whereType<Map>().map((m) => GhostPlayRecord.fromJson(m.cast<String, dynamic>())));
        }
      }
      final rawCounts = prefs.getString(_artistCountsKey);
      if (rawCounts != null && rawCounts.isNotEmpty) {
        final decoded = jsonDecode(rawCounts);
        if (decoded is Map) {
          _artistCounts.clear();
          decoded.forEach((k, v) {
            if (v is num) _artistCounts[k.toString()] = v.toInt();
          });
        }
      }
      final rawFixes = prefs.getString(_nameFixesKey);
      if (rawFixes != null && rawFixes.isNotEmpty) {
        final decoded = jsonDecode(rawFixes);
        if (decoded is Map) {
          _nameFixes.clear();
          decoded.forEach((k, v) => _nameFixes[k.toString()] = v.toString());
        }
      }
      _lastSentinelSummary = prefs.getString(_lastSentinelSummaryKey) ?? '';
    } catch (e) {
      debugPrint('GHOST_MEMORY: load failed: $e');
    }
  }

  static Future<void> recordPlay({required String path, required String title, required String artist}) async {
    await ensureLoaded();
    _history.insert(0, GhostPlayRecord(path: path, title: title, artist: artist, playedAtMs: DateTime.now().millisecondsSinceEpoch));
    if (_history.length > _maxHistory) _history.removeRange(_maxHistory, _history.length);
    final normArtist = artist.trim();
    if (normArtist.isNotEmpty && normArtist.toLowerCase() != 'unknown artist') {
      _artistCounts[normArtist] = (_artistCounts[normArtist] ?? 0) + 1;
    }
    await _persist();
  }

  static Future<void> recordNameCorrection(String rawName, String canonicalName) async {
    await ensureLoaded();
    if (rawName.trim().isEmpty || canonicalName.trim().isEmpty) return;
    _nameFixes[rawName.trim().toLowerCase()] = canonicalName.trim();
    await _persist();
  }

  static Future<void> recordSentinelSummary(String summary) async {
    await ensureLoaded();
    _lastSentinelSummary = summary;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSentinelSummaryKey, summary);
    } catch (_) {}
  }

  static Future<List<GhostPlayRecord>> playedYesterday() async {
    await ensureLoaded();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    return _history.where((r) => r.playedAtMs >= startOfYesterday.millisecondsSinceEpoch && r.playedAtMs < startOfToday.millisecondsSinceEpoch).toList();
  }

  static Future<List<String>> topArtists({int limit = 5}) async {
    await ensureLoaded();
    final entries = _artistCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }

  static Future<void> forgetAll() async {
    _history.clear();
    _artistCounts.clear();
    _nameFixes.clear();
    _lastSentinelSummary = '';
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_playHistoryKey);
      await prefs.remove(_artistCountsKey);
      await prefs.remove(_nameFixesKey);
      await prefs.remove(_lastSentinelSummaryKey);
    } catch (e) {
      debugPrint('GHOST_MEMORY: forgetAll failed: $e');
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_playHistoryKey, jsonEncode(_history.map((e) => e.toJson()).toList()));
      await prefs.setString(_artistCountsKey, jsonEncode(_artistCounts));
      await prefs.setString(_nameFixesKey, jsonEncode(_nameFixes));
    } catch (e) {
      debugPrint('GHOST_MEMORY: persist failed: $e');
    }
  }
}
