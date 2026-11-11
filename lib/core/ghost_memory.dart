// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

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
  static Future<void>? _loadFuture;
  static Future<void> _mutationQueue = Future<void>.value();

  static List<GhostPlayRecord> get history => List.unmodifiable(_history);
  static Map<String, int> get artistCounts => Map.unmodifiable(_artistCounts);
  static Map<String, String> get nameFixes => Map.unmodifiable(_nameFixes);
  static String get lastSentinelSummary => _lastSentinelSummary;

  static Future<void> ensureLoaded() => _loadFuture ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final loadedHistory = <GhostPlayRecord>[];
      final rawHistory = prefs.getString(_playHistoryKey);
      if (rawHistory != null && rawHistory.isNotEmpty) {
        final decoded = jsonDecode(rawHistory);
        if (decoded is! List) {
          throw const FormatException('Invalid Ghost play history');
        }
        loadedHistory.addAll(decoded.whereType<Map>().map(
          (record) => GhostPlayRecord.fromJson(record.cast<String, dynamic>()),
        ));
      }

      final loadedCounts = <String, int>{};
      final rawCounts = prefs.getString(_artistCountsKey);
      if (rawCounts != null && rawCounts.isNotEmpty) {
        final decoded = jsonDecode(rawCounts);
        if (decoded is! Map) {
          throw const FormatException('Invalid Ghost artist counts');
        }
        decoded.forEach((key, value) {
          if (value is num) loadedCounts[key.toString()] = value.toInt();
        });
      }

      final loadedNameFixes = <String, String>{};
      final rawFixes = prefs.getString(_nameFixesKey);
      if (rawFixes != null && rawFixes.isNotEmpty) {
        final decoded = jsonDecode(rawFixes);
        if (decoded is! Map) {
          throw const FormatException('Invalid Ghost name corrections');
        }
        decoded.forEach((key, value) {
          loadedNameFixes[key.toString()] = value.toString();
        });
      }

      final loadedSummary = prefs.getString(_lastSentinelSummaryKey) ?? '';
      _history
        ..clear()
        ..addAll(loadedHistory.take(_maxHistory));
      _artistCounts
        ..clear()
        ..addAll(loadedCounts);
      _nameFixes
        ..clear()
        ..addAll(loadedNameFixes);
      _lastSentinelSummary = loadedSummary;
    } catch (error, stackTrace) {
      _loadFuture = null;
      debugPrint('GHOST_MEMORY: load failed: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final next = _mutationQueue.then((_) => operation());
    _mutationQueue = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('GHOST_MEMORY: mutation failed: $error');
      },
    );
    return next;
  }

  static Future<void> recordPlay({
    required String path,
    required String title,
    required String artist,
  }) => _enqueue(() async {
    await ensureLoaded();
    _history.insert(
      0,
      GhostPlayRecord(
        path: path,
        title: title,
        artist: artist,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    final normalizedArtist = artist.trim();
    if (normalizedArtist.isNotEmpty &&
        normalizedArtist.toLowerCase() != 'unknown artist') {
      _artistCounts[normalizedArtist] =
          (_artistCounts[normalizedArtist] ?? 0) + 1;
    }
    await _persist();
  });

  static Future<void> recordNameCorrection(
    String rawName,
    String canonicalName,
  ) => _enqueue(() async {
    await ensureLoaded();
    if (rawName.trim().isEmpty || canonicalName.trim().isEmpty) return;
    _nameFixes[rawName.trim().toLowerCase()] = canonicalName.trim();
    await _persist();
  });

  static Future<void> recordSentinelSummary(String summary) =>
      _enqueue(() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSentinelSummaryKey, summary);
    _lastSentinelSummary = summary;
  });

  static Future<List<GhostPlayRecord>> playedYesterday() async {
    await ensureLoaded();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = DateTime(now.year, now.month, now.day - 1);
    return _history.where((record) =>
        record.playedAtMs >= startOfYesterday.millisecondsSinceEpoch &&
        record.playedAtMs < startOfToday.millisecondsSinceEpoch).toList();
  }

  static Future<List<String>> topArtists({int limit = 5}) async {
    await ensureLoaded();
    if (limit <= 0) return const [];
    final entries = _artistCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((entry) => entry.key).toList();
  }

  static Future<void> forgetAll() => _enqueue(() async {
    try {
      await ensureLoaded();
    } catch (error) {
      debugPrint('GHOST_MEMORY: proceeding with reset after load error: $error');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playHistoryKey);
    await prefs.remove(_artistCountsKey);
    await prefs.remove(_nameFixesKey);
    await prefs.remove(_lastSentinelSummaryKey);
    _history.clear();
    _artistCounts.clear();
    _nameFixes.clear();
    _lastSentinelSummary = '';
    _loadFuture = Future<void>.value();
  });

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playHistoryKey,
      jsonEncode(_history.map((record) => record.toJson()).toList()),
    );
    await prefs.setString(_artistCountsKey, jsonEncode(_artistCounts));
    await prefs.setString(_nameFixesKey, jsonEncode(_nameFixes));
  }
}
