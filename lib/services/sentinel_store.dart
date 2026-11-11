// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SentinelIssue {
  static const String nameMismatch = 'NAME_MISMATCH';
  static const String missingTitle = 'MISSING_TITLE';
  static const String missingArtist = 'MISSING_ARTIST';
  static const String missingAlbumArtist = 'MISSING_ALBUM_ARTIST';
  static const String missingAlbum = 'MISSING_ALBUM';
  static const String missingTrack = 'MISSING_TRACK';
  static const String missingYear = 'MISSING_YEAR';
  static const String missingGenre = 'MISSING_GENRE';
  static const String missingLyrics = 'MISSING_LYRICS';
  static const String missingArtwork = 'MISSING_ARTWORK';
}

class SentinelStatus {
  static const String open = 'open';
  static const String inForge = 'in_forge';
  static const String inPipeline = 'in_pipeline';
  static const String resolved = 'resolved';
  static const String ignored = 'ignored';
  static const String uncompletable = 'uncompletable';
  static const String stale = 'stale';
}

class SentinelUncompletableReason {
  static const String noCatalogMatch = 'NO_CATALOG_MATCH';
  static const String noLyricsSource = 'NO_LYRICS_SOURCE';
  static const String noArtworkSource = 'NO_ARTWORK_SOURCE';
}

class SentinelTagSnapshot {
  final String title;
  final String artist;
  final String albumArtist;
  final String album;
  final String track;
  final String year;
  final String genre;
  final String lyrics;
  final bool artwork;

  const SentinelTagSnapshot({
    this.title = '',
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.track = '',
    this.year = '',
    this.genre = '',
    this.lyrics = '',
    this.artwork = false,
  });

  bool get isComplete =>
      title.trim().isNotEmpty &&
      artist.trim().isNotEmpty &&
      albumArtist.trim().isNotEmpty &&
      album.trim().isNotEmpty &&
      track.trim().isNotEmpty &&
      year.trim().isNotEmpty &&
      genre.trim().isNotEmpty &&
      lyrics.trim().isNotEmpty &&
      artwork;

  Map<String, dynamic> toJson() => {
        'TITLE': title,
        'ARTIST': artist,
        'ALBUM_ARTIST': albumArtist,
        'ALBUM': album,
        'TRACK': track,
        'YEAR': year,
        'GENRE': genre,
        'LYRICS': lyrics,
        'ARTWORK': artwork,
      };

  factory SentinelTagSnapshot.fromJson(Map<String, dynamic> json) {
    return SentinelTagSnapshot(
      title: (json['TITLE'] ?? '').toString(),
      artist: (json['ARTIST'] ?? '').toString(),
      albumArtist: (json['ALBUM_ARTIST'] ?? '').toString(),
      album: (json['ALBUM'] ?? '').toString(),
      track: (json['TRACK'] ?? '').toString(),
      year: (json['YEAR'] ?? '').toString(),
      genre: (json['GENRE'] ?? '').toString(),
      lyrics: (json['LYRICS'] ?? '').toString(),
      artwork: json['ARTWORK'] == true,
    );
  }
}

class SentinelHit {
  final String id;
  final String uri;
  final String path;
  final int size;
  final int dateAdded;
  final String displayName;
  final String expectedName;
  final List<String> issues;
  final String severity;
  final SentinelTagSnapshot tagSnapshot;
  final Map<String, dynamic> evidence;
  final String status;
  final String statusReason;
  final String firstSeen;
  final String lastSeen;
  final String scanId;

  const SentinelHit({
    required this.id,
    required this.uri,
    required this.path,
    required this.size,
    required this.dateAdded,
    required this.displayName,
    required this.expectedName,
    required this.issues,
    required this.severity,
    required this.tagSnapshot,
    this.evidence = const {},
    this.status = SentinelStatus.open,
    this.statusReason = '',
    required this.firstSeen,
    required this.lastSeen,
    required this.scanId,
  });

  SentinelHit copyWith({String? status, String? statusReason, String? lastSeen, String? scanId}) {
    return SentinelHit(
      id: id,
      uri: uri,
      path: path,
      size: size,
      dateAdded: dateAdded,
      displayName: displayName,
      expectedName: expectedName,
      issues: issues,
      severity: severity,
      tagSnapshot: tagSnapshot,
      evidence: evidence,
      status: status ?? this.status,
      statusReason: statusReason ?? this.statusReason,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      scanId: scanId ?? this.scanId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'path': path,
        'size': size,
        'dateAdded': dateAdded,
        'displayName': displayName,
        'expectedName': expectedName,
        'issues': issues,
        'severity': severity,
        'tagSnapshot': tagSnapshot.toJson(),
        'evidence': evidence,
        'status': status,
        'statusReason': statusReason,
        'firstSeen': firstSeen,
        'lastSeen': lastSeen,
        'scanId': scanId,
      };

  factory SentinelHit.fromJson(Map<String, dynamic> json) {
    final rawIssues = (json['issues'] as List?) ?? const [];
    final rawTag = (json['tagSnapshot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawEvidence = (json['evidence'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SentinelHit(
      id: (json['id'] ?? '').toString(),
      uri: (json['uri'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      size: (json['size'] is num) ? (json['size'] as num).toInt() : 0,
      dateAdded: (json['dateAdded'] is num) ? (json['dateAdded'] as num).toInt() : 0,
      displayName: (json['displayName'] ?? '').toString(),
      expectedName: (json['expectedName'] ?? '').toString(),
      issues: rawIssues.map((e) => e.toString()).toList(),
      severity: (json['severity'] ?? 'medium').toString(),
      tagSnapshot: SentinelTagSnapshot.fromJson(rawTag),
      evidence: rawEvidence,
      status: (json['status'] ?? SentinelStatus.open).toString(),
      statusReason: (json['statusReason'] ?? '').toString(),
      firstSeen: (json['firstSeen'] ?? '').toString(),
      lastSeen: (json['lastSeen'] ?? '').toString(),
      scanId: (json['scanId'] ?? '').toString(),
    );
  }
}

class SentinelSummary {
  final int totalHits;
  final Map<String, int> byStatus;
  final Map<String, int> byIssue;
  final String? lastScanId;
  final String? generatedAt;

  const SentinelSummary({
    required this.totalHits,
    required this.byStatus,
    required this.byIssue,
    this.lastScanId,
    this.generatedAt,
  });

  int get openCount => byStatus[SentinelStatus.open] ?? 0;
  int get missingArtCount => byIssue[SentinelIssue.missingArtwork] ?? 0;
  int get missingLyricsCount => byIssue[SentinelIssue.missingLyrics] ?? 0;
  int get badNamesCount => byIssue[SentinelIssue.nameMismatch] ?? 0;
  int get uncompletableCount => byStatus[SentinelStatus.uncompletable] ?? 0;
}

class SentinelNamingPolicy {
  static const Set<String> _smallWords = {
    'a', 'an', 'the', 'and', 'but', 'or', 'nor', 'for', 'of',
    'to', 'in', 'on', 'at', 'by', 'with', 'from', 'as', 'per', 'vs', 'ft.',
  };

  static const Map<String, String> _properExceptions = {
    'dmx': 'DMX', 'ac/dc': 'AC/DC', 'mcdonald': 'McDonald', "o'brien": "O'Brien",
    '2pac': '2Pac', 'll': 'LL', 'dj': 'DJ', 'ep': 'EP', 'lp': 'LP',
    'ii': 'II', 'iii': 'III', 'iv': 'IV',
  };

  static final List<RegExp> _noisePatterns = [
    RegExp(r'\(\s*remaster(?:ed)?(?:\s+\d{4})?\s*\)', caseSensitive: false),
    RegExp(r'\[\s*remaster(?:ed)?(?:\s+\d{4})?\s*\]', caseSensitive: false),
    RegExp(r'\(\s*deluxe(?:\s+edition|\s+version)?\s*\)', caseSensitive: false),
    RegExp(r'\[\s*deluxe(?:\s+edition|\s+version)?\s*\]', caseSensitive: false),
    RegExp(r'\(\s*bonus\s+track\s*\)', caseSensitive: false),
    RegExp(r'\[\s*explicit\s*\]', caseSensitive: false),
    RegExp(r'\(\s*explicit\s*\)', caseSensitive: false),
    RegExp(r'\(\s*official\s+(?:music\s+)?video\s*\)', caseSensitive: false),
    RegExp(r'\[\s*official\s+(?:music\s+)?video\s*\]', caseSensitive: false),
    RegExp(r'\(\s*official\s+audio\s*\)', caseSensitive: false),
    RegExp(r'\[\s*official\s+audio\s*\]', caseSensitive: false),
    RegExp(r'\(\s*lyric(?:s)?\s+video\s*\)', caseSensitive: false),
    RegExp(r'\(\s*audio\s*\)', caseSensitive: false),
  ];

  static String stripNoiseAndNormalizeFeat(String raw) {
    var out = raw;
    for (final rx in _noisePatterns) {
      out = out.replaceAll(rx, '');
    }
    out = out.replaceAll(RegExp(r'\b(?:featuring|feat\.?|\bft\b)\.?\s+', caseSensitive: false), 'ft. ');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String toTitleCase(String input) {
    final cleaned = stripNoiseAndNormalizeFeat(input);
    if (cleaned.isEmpty) return '';
    final words = cleaned.split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final rawWord = words[i];
      if (rawWord.isEmpty) continue;
      final lower = rawWord.toLowerCase();
      if (lower == 'ft.' || lower == 'ft') {
        out.add('ft.');
        continue;
      }
      if (_properExceptions.containsKey(lower)) {
        out.add(_properExceptions[lower]!);
        continue;
      }
      if (i > 0 && i < words.length - 1 && _smallWords.contains(lower)) {
        out.add(lower);
        continue;
      }
      out.add(_capitalizeToken(rawWord));
    }
    return out.join(' ').replaceAll(RegExp(r'\bLl Cool J\b', caseSensitive: false), 'LL Cool J');
  }

  static String _capitalizeToken(String token) {
    if (token.isEmpty) return token;
    final lower = token.toLowerCase();
    if (_properExceptions.containsKey(lower)) return _properExceptions[lower]!;
    if (lower.startsWith('mc') && lower.length > 2) return 'Mc${lower[2].toUpperCase()}${lower.substring(3)}';
    if (lower.startsWith("o'") && lower.length > 2) return "O'${lower[2].toUpperCase()}${lower.substring(3)}";
    return '${token[0].toUpperCase()}${token.substring(1).toLowerCase()}';
  }

  static String formatExpectedFilename({required SentinelTagSnapshot tags, required String currentFilename}) {
    final extIndex = currentFilename.lastIndexOf('.');
    final ext = extIndex > 0 ? currentFilename.substring(extIndex + 1).toLowerCase() : 'mp3';
    final rawTrack = tags.track.trim().split('/').first.trim();
    final trackNum = int.tryParse(rawTrack) ?? 0;
    final trackPadded = trackNum > 0 ? trackNum.toString().padLeft(2, '0') : '00';
    final primaryArtist = tags.albumArtist.trim().isNotEmpty
        ? tags.albumArtist.trim()
        : (tags.artist.trim().isNotEmpty ? tags.artist.trim() : 'Unknown Artist');
    return '$trackPadded - ${toTitleCase(primaryArtist)} - ${toTitleCase(tags.title.trim().isNotEmpty ? tags.title.trim() : 'Untitled')}.$ext';
  }

  static List<String> evaluateIssues({required SentinelTagSnapshot tags, required String displayName}) {
    final issues = <String>[];
    if (displayName != formatExpectedFilename(tags: tags, currentFilename: displayName)) {
      issues.add(SentinelIssue.nameMismatch);
    }
    if (tags.title.trim().isEmpty) issues.add(SentinelIssue.missingTitle);
    if (tags.artist.trim().isEmpty) issues.add(SentinelIssue.missingArtist);
    if (tags.albumArtist.trim().isEmpty) issues.add(SentinelIssue.missingAlbumArtist);
    if (tags.album.trim().isEmpty) issues.add(SentinelIssue.missingAlbum);
    if (tags.track.trim().isEmpty) issues.add(SentinelIssue.missingTrack);
    if (tags.year.trim().isEmpty) issues.add(SentinelIssue.missingYear);
    if (tags.genre.trim().isEmpty) issues.add(SentinelIssue.missingGenre);
    if (tags.lyrics.trim().isEmpty) issues.add(SentinelIssue.missingLyrics);
    if (!tags.artwork) issues.add(SentinelIssue.missingArtwork);
    return issues;
  }

  static String computeSeverity(List<String> issues) {
    if (issues.contains(SentinelIssue.missingTitle) ||
        issues.contains(SentinelIssue.missingArtist) ||
        issues.contains(SentinelIssue.nameMismatch) ||
        issues.length >= 3) {
      return 'high';
    }
    return issues.length == 2 ? 'medium' : 'low';
  }
}

class SentinelStore extends ChangeNotifier {
  SentinelStore._();
  static final SentinelStore instance = SentinelStore._();

  static const int schemaVersion = 1;
  static const String fileName = 'sentinel_hits.json';
  static bool Function()? isHeavyOperationActive;
  static void Function(SentinelHit hit)? onOpenInForge;
  static Future<void> Function(List<SentinelHit> hits)? onSendToPipeline;

  final List<SentinelHit> _hits = <SentinelHit>[];
  String? _lastScanId;
  String? _generatedAt;
  Future<void>? _loadFuture;
  Future<void> _pendingSave = Future<void>.value();
  bool _scanning = false;
  bool _cancelRequested = false;

  bool get isScanning => _scanning;
  List<SentinelHit> get allHits => List.unmodifiable(_hits);

  Future<File> _resolveStoreFile() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$fileName');
  }

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final file = await _resolveStoreFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Sentinel store is not an object');
      }
      if (decoded['schemaVersion'] != schemaVersion) {
        throw const FormatException('Unsupported Sentinel store schema');
      }
      final rawHits = decoded['hits'];
      if (rawHits is! List) {
        throw const FormatException('Sentinel store hits are missing');
      }
      final loadedHits = rawHits
          .whereType<Map>()
          .map((entry) => SentinelHit.fromJson(entry.cast<String, dynamic>()))
          .toList();
      _hits
        ..clear()
        ..addAll(loadedHits);
      _lastScanId = decoded['scanId']?.toString();
      _generatedAt = decoded['generatedAt']?.toString();
      notifyListeners();
    } catch (error, stackTrace) {
      _loadFuture = null;
      debugPrint('SENTINEL: Failed to load $fileName: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> saveAtomically() {
    final next = _pendingSave.then((_) => _writeSnapshot());
    _pendingSave = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('SENTINEL: Atomic save failed: $error');
      },
    );
    return next;
  }

  Future<void> _writeSnapshot() async {
    final file = await _resolveStoreFile();
    final partFile = File('${file.path}.part');
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'scanId': _lastScanId ?? nowIso,
      'generatedAt': _generatedAt ?? nowIso,
      'hits': _hits.map((hit) => hit.toJson()).toList(),
    };
    await partFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await partFile.rename(file.path);
  }

  Future<SentinelSummary> sentinelSummary() async {
    await ensureLoaded();
    final byStatus = <String, int>{};
    final byIssue = <String, int>{};
    for (final h in _hits) {
      byStatus[h.status] = (byStatus[h.status] ?? 0) + 1;
      if (h.status == SentinelStatus.open) {
        for (final issue in h.issues) {
          byIssue[issue] = (byIssue[issue] ?? 0) + 1;
        }
      }
    }
    return SentinelSummary(
      totalHits: _hits.length,
      byStatus: byStatus,
      byIssue: byIssue,
      lastScanId: _lastScanId,
      generatedAt: _generatedAt,
    );
  }

  Future<List<SentinelHit>> sentinelHits({String? issue, String? severity, String? status = SentinelStatus.open, int limit = 10}) async {
    await ensureLoaded();
    final filtered = _hits.where((h) {
      if (status != null && status.isNotEmpty && h.status != status) return false;
      if (severity != null && severity.isNotEmpty && h.severity != severity) return false;
      if (issue != null && issue.isNotEmpty && !h.issues.contains(issue)) return false;
      return true;
    }).toList();
    return (limit > 0 && filtered.length > limit) ? filtered.sublist(0, limit) : filtered;
  }

  Future<SentinelHit?> sentinelHit(String id) async {
    await ensureLoaded();
    for (final h in _hits) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<SentinelSummary> sentinelScan({Future<List<Map<String, dynamic>>> Function()? trackProvider}) async {
    await ensureLoaded();
    if (trackProvider == null) {
      throw StateError('SCAN BLOCKED: A track provider is required.');
    }
    if (_scanning) return sentinelSummary();
    if (isHeavyOperationActive?.call() == true) {
      throw StateError('SCAN BLOCKED: Forge, Pipeline, or FFmpeg is currently active.');
    }
    _scanning = true;
    _cancelRequested = false;
    notifyListeners();
    final scanId = DateTime.now().toUtc().toIso8601String();
    final previousHits = List<SentinelHit>.of(_hits);
    final previousScanId = _lastScanId;
    final previousGeneratedAt = _generatedAt;
    try {
        final rawTracks = await trackProvider();
        final existingById = <String, SentinelHit>{for (final h in _hits) h.id: h};
        final nextHits = <SentinelHit>[];
        for (var i = 0; i < rawTracks.length; i++) {
          if (_cancelRequested || isHeavyOperationActive?.call() == true) {
            throw StateError('SCAN CANCELLED: Existing results were preserved.');
          }
          if (i > 0 && i % 25 == 0) await Future<void>.delayed(const Duration(milliseconds: 8));
          final item = rawTracks[i];
          final path = (item['path'] ?? '').toString();
          final uri = (item['uri'] ?? path).toString();
          final size = (item['size'] is num) ? (item['size'] as num).toInt() : 0;
          final dateAdded = (item['dateAdded'] is num) ? (item['dateAdded'] as num).toInt() : 0;
          final displayName = (item['displayName'] ?? path.split(RegExp(r'[/\\]')).last).toString();
          final id = _stableHash('$uri|$size|$dateAdded');
          final prev = existingById[id];
          if (prev != null && (prev.status == SentinelStatus.uncompletable || prev.status == SentinelStatus.ignored)) {
            nextHits.add(prev.copyWith(lastSeen: scanId, scanId: scanId));
            continue;
          }
          final snapshot = SentinelTagSnapshot(
            title: (item['title'] ?? '').toString(),
            artist: (item['artist'] ?? '').toString(),
            albumArtist: (item['albumArtist'] ?? item['artist'] ?? '').toString(),
            album: (item['album'] ?? '').toString(),
            track: (item['track'] ?? '').toString(),
            year: (item['year'] ?? '').toString(),
            genre: (item['genre'] ?? '').toString(),
            lyrics: (item['lyrics'] ?? '').toString(),
            artwork: item['artwork'] == true,
          );
          final issues = SentinelNamingPolicy.evaluateIssues(tags: snapshot, displayName: displayName);
          if (issues.isEmpty) continue;
          nextHits.add(SentinelHit(
            id: id,
            uri: uri,
            path: path,
            size: size,
            dateAdded: dateAdded,
            displayName: displayName,
            expectedName: SentinelNamingPolicy.formatExpectedFilename(tags: snapshot, currentFilename: displayName),
            issues: issues,
            severity: SentinelNamingPolicy.computeSeverity(issues),
            tagSnapshot: snapshot,
            evidence: {'mediaStoreTitle': snapshot.title, 'sidecarLyrics': false, 'sampled': false},
            status: SentinelStatus.open,
            statusReason: '',
            firstSeen: prev?.firstSeen ?? scanId,
            lastSeen: scanId,
            scanId: scanId,
          ));
        }
        if (_cancelRequested || isHeavyOperationActive?.call() == true) {
          throw StateError('SCAN CANCELLED: Existing results were preserved.');
        }
        _hits
          ..clear()
          ..addAll(nextHits);
        _lastScanId = scanId;
        _generatedAt = scanId;
        await saveAtomically();
    } catch (_) {
      _hits
        ..clear()
        ..addAll(previousHits);
      _lastScanId = previousScanId;
      _generatedAt = previousGeneratedAt;
      rethrow;
    } finally {
      _scanning = false;
      notifyListeners();
    }
    return sentinelSummary();
  }

  void cancelScan() => _cancelRequested = true;

  Future<bool> sentinelOpenInForge(String hitId) async {
    await ensureLoaded();
    final idx = _hits.indexWhere((h) => h.id == hitId);
    if (idx < 0 || _hits[idx].path.isEmpty) return false;
    final hit = _hits[idx];
    final handler = onOpenInForge;
    if (handler == null) return false;
    handler(hit);
    _hits[idx] = hit.copyWith(status: SentinelStatus.inForge, lastSeen: DateTime.now().toUtc().toIso8601String());
    await saveAtomically();
    notifyListeners();
    return true;
  }

  Future<int> sentinelSendToPipeline(List<String> hitIds) async {
    await ensureLoaded();
    final handler = onSendToPipeline;
    if (handler == null) return 0;
    final selected = _hits.where((hit) => hitIds.contains(hit.id)).toList();
    if (selected.isEmpty) return 0;
    await handler(List<SentinelHit>.unmodifiable(selected));
    var count = 0;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < _hits.length; i++) {
      if (hitIds.contains(_hits[i].id)) {
        _hits[i] = _hits[i].copyWith(status: SentinelStatus.inPipeline, lastSeen: nowIso);
        count++;
      }
    }
    if (count > 0) {
      await saveAtomically();
      notifyListeners();
    }
    return count;
  }

  Future<bool> sentinelMarkUncompletable(String hitId, String reason) =>
      _transitionStatus(hitId, status: SentinelStatus.uncompletable, reason: reason.trim().isEmpty ? SentinelUncompletableReason.noCatalogMatch : reason.trim());

  Future<bool> sentinelIgnore(String hitId, String reason) =>
      _transitionStatus(hitId, status: SentinelStatus.ignored, reason: reason.trim().isEmpty ? 'OPERATOR_IGNORED' : reason.trim());

  Future<bool> _transitionStatus(String hitId, {required String status, required String reason}) async {
    await ensureLoaded();
    final idx = _hits.indexWhere((h) => h.id == hitId);
    if (idx < 0) return false;
    _hits[idx] = _hits[idx].copyWith(status: status, statusReason: reason, lastSeen: DateTime.now().toUtc().toIso8601String());
    await saveAtomically();
    notifyListeners();
    return true;
  }

  static String _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'hit_${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
