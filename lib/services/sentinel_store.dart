// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/sentinel_policy.dart';

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
  static const String artistAlbumArtistMismatch = 'ARTIST_ALBUM_ARTIST_MISMATCH';
  static const String nameCollision = 'NAME_COLLISION';
  static const String unreadableTags = 'UNREADABLE_TAGS';
  static const String featNotCanonical = 'FEAT_NOT_CANONICAL';
  static const String titleCaseDrift = 'TITLE_CASE_DRIFT';
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

  SentinelHit copyWith({
    String? expectedName,
    List<String>? issues,
    String? severity,
    SentinelTagSnapshot? tagSnapshot,
    Map<String, dynamic>? evidence,
    String? status,
    String? statusReason,
    String? lastSeen,
    String? scanId,
  }) {
    return SentinelHit(
      id: id,
      uri: uri,
      path: path,
      size: size,
      dateAdded: dateAdded,
      displayName: displayName,
      expectedName: expectedName ?? this.expectedName,
      issues: issues ?? this.issues,
      severity: severity ?? this.severity,
      tagSnapshot: tagSnapshot ?? this.tagSnapshot,
      evidence: evidence ?? this.evidence,
      status: status ?? this.status,
      statusReason: statusReason ?? this.statusReason,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      scanId: scanId ?? this.scanId,
    );
  }

  static String fingerprintFor(String uri, int size, int dateAdded) =>
      SentinelStore._stableHash('$uri|$size|$dateAdded');

  String get fingerprint => fingerprintFor(uri, size, dateAdded);

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
  static Map<String, String> _tagsOf(SentinelTagSnapshot tags) {
    return <String, String>{
      'TITLE': tags.title,
      'ARTIST': tags.artist,
      'ALBUM_ARTIST': tags.albumArtist,
      'ALBUM': tags.album,
      'TRACK': tags.track,
      'YEAR': tags.year,
      'GENRE': tags.genre,
      'LYRICS': tags.lyrics,
      'ARTWORK': tags.artwork ? 'true' : 'false',
    };
  }

  static String stripNoiseAndNormalizeFeat(String raw) {
    final stripped = SentinelPolicy.stripVersionNoise(raw);
    final normalized = stripped.replaceAll(
        RegExp(r'\b(?:featuring|feat\.?|\bft\b)\.?\s+', caseSensitive: false), 'ft. ');
    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String toTitleCase(String input) {
    return SentinelPolicy.titleCase(stripNoiseAndNormalizeFeat(input));
  }

  static String formatExpectedFilename({required SentinelTagSnapshot tags, required String currentFilename}) {
    return SentinelPolicy.expectedFileName(_tagsOf(tags), displayName: currentFilename);
  }

  static List<String> evaluateIssues({required SentinelTagSnapshot tags, required String displayName}) {
    return SentinelPolicy.audit(_tagsOf(tags), displayName).issues;
  }

  static String computeSeverity(List<String> issues) {
    return SentinelPolicy.severityFor(issues);
  }
}

class SentinelScanProgress {
  final String scanId;
  final String startedAt;
  final int total;
  final int scanned;
  final int hits;
  final int sampled;
  final int sampleHits;
  final List<String> pendingUris;
  final List<String> sampledUris;

  const SentinelScanProgress({
    required this.scanId,
    required this.startedAt,
    required this.total,
    required this.scanned,
    required this.hits,
    required this.sampled,
    required this.sampleHits,
    required this.pendingUris,
    this.sampledUris = const [],
  });

  Map<String, dynamic> toJson() => {
        'scanId': scanId,
        'startedAt': startedAt,
        'total': total,
        'scanned': scanned,
        'hits': hits,
        'sampled': sampled,
        'sampleHits': sampleHits,
        'pendingUris': pendingUris,
        'sampledUris': sampledUris,
      };

  factory SentinelScanProgress.fromJson(Map<String, dynamic> json) {
    final pending = <String>[];
    final rawPending = json['pendingUris'];
    if (rawPending is List) {
      for (final item in rawPending) {
        pending.add(item.toString());
      }
    }
    final sampled = <String>[];
    final rawSampled = json['sampledUris'];
    if (rawSampled is List) {
      for (final item in rawSampled) {
        sampled.add(item.toString());
      }
    }
    return SentinelScanProgress(
      scanId: (json['scanId'] ?? '').toString(),
      startedAt: (json['startedAt'] ?? '').toString(),
      total: (json['total'] is num) ? (json['total'] as num).toInt() : 0,
      scanned: (json['scanned'] is num) ? (json['scanned'] as num).toInt() : 0,
      hits: (json['hits'] is num) ? (json['hits'] as num).toInt() : 0,
      sampled: (json['sampled'] is num) ? (json['sampled'] as num).toInt() : 0,
      sampleHits: (json['sampleHits'] is num) ? (json['sampleHits'] as num).toInt() : 0,
      pendingUris: pending,
      sampledUris: sampled,
    );
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
  SentinelScanProgress? _scanProgress;
  Future<void>? _loadFuture;
  Future<void> _pendingSave = Future<void>.value();
  bool _scanning = false;
  bool _cancelRequested = false;

  bool get isScanning => _scanning;
  List<SentinelHit> get allHits => List.unmodifiable(_hits);
  SentinelScanProgress? get scanProgress => _scanProgress;

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
      _scanProgress = null;
      final rawProgress = decoded['progress'];
      if (rawProgress is Map) {
        _scanProgress = SentinelScanProgress.fromJson(rawProgress.cast<String, dynamic>());
      }
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
      'progress': _scanProgress?.toJson(),
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

  SentinelHit? byId(String id) {
    for (final h in _hits) {
      if (h.id == id) return h;
    }
    return null;
  }

  SentinelHit? byUri(String uri) {
    for (final h in _hits) {
      if (h.uri == uri) return h;
    }
    return null;
  }

  Future<void> upsertAll(List<SentinelHit> incoming) async {
    await ensureLoaded();
    for (final hit in incoming) {
      final idx = _hits.indexWhere((h) => h.id == hit.id);
      if (idx >= 0) {
        _hits[idx] = hit;
      } else {
        _hits.add(hit);
      }
    }
    await saveAtomically();
    notifyListeners();
  }

  Future<void> removeAll(List<String> ids) async {
    await ensureLoaded();
    final before = _hits.length;
    _hits.removeWhere((h) => ids.contains(h.id));
    if (_hits.length != before) {
      await saveAtomically();
      notifyListeners();
    }
  }

  Future<bool> setStatus(String hitId, String status, String reason) =>
      _transitionStatus(hitId, status: status, reason: reason);

  Future<void> markStaleForMissing(Set<String> seenUris) async {
    await ensureLoaded();
    var changed = false;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < _hits.length; i++) {
      final hit = _hits[i];
      if (hit.status == SentinelStatus.stale) continue;
      if (hit.uri.isEmpty || seenUris.contains(hit.uri)) continue;
      _hits[i] = hit.copyWith(status: SentinelStatus.stale, statusReason: 'File no longer in MediaStore', lastSeen: nowIso);
      changed = true;
    }
    if (changed) {
      await saveAtomically();
      notifyListeners();
    }
  }

  Future<void> pruneStale() async {
    await ensureLoaded();
    final before = _hits.length;
    _hits.removeWhere((h) => h.status == SentinelStatus.stale);
    if (_hits.length != before) {
      await saveAtomically();
      notifyListeners();
    }
  }

  Future<void> setScanMetadata(String scanId, String generatedAt) async {
    _lastScanId = scanId;
    _generatedAt = generatedAt;
    await saveAtomically();
  }

  Future<void> saveScanProgress(SentinelScanProgress value) async {
    _scanProgress = value;
    await saveAtomically();
  }

  Future<void> clearScanProgress() async {
    if (_scanProgress == null) return;
    _scanProgress = null;
    await saveAtomically();
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
