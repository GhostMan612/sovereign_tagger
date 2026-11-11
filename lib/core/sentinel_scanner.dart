// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'embedding_service.dart';
import 'ffmpeg_executor.dart';
import 'sentinel_policy.dart';
import 'storage_client.dart';
import 'tag_io.dart';
import '../services/sentinel_store.dart';

class SentinelProgress {
  final int scanned;
  final int total;
  final int hits;
  final int sampled;
  final int sampleHits;
  const SentinelProgress({required this.scanned, required this.total, required this.hits, required this.sampled, required this.sampleHits});
}

class SentinelScanSummary {
  final String scanId;
  final String startedAt;
  final String finishedAt;
  final int total;
  final int scanned;
  final int skipped;
  final int hits;
  final int sampleSize;
  final int sampleHits;
  final String status;
  const SentinelScanSummary({
    required this.scanId,
    required this.startedAt,
    required this.finishedAt,
    required this.total,
    required this.scanned,
    required this.skipped,
    required this.hits,
    required this.sampleSize,
    required this.sampleHits,
    required this.status,
  });
}

class _MediaRow {
  final String uri;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int track;
  final int year;
  final int dateAdded;
  final String mime;
  final int size;
  final String displayName;
  const _MediaRow({
    required this.uri,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.track,
    required this.year,
    required this.dateAdded,
    required this.mime,
    required this.size,
    required this.displayName,
  });
}

class SentinelScanner {
  static const int batchSize = 10;
  static const double sampleRate = 0.05;
  static const int minSample = 20;

  final SentinelStore store = SentinelStore.instance;
  bool _scanning = false;
  bool _cancelRequested = false;

  bool get isScanning => _scanning;

  void cancel() {
    _cancelRequested = true;
  }

  static String _asString(Map<String, Object?> row, String key) {
    final v = row[key];
    if (v == null) return '';
    return v.toString();
  }

  static int _asInt(Map<String, Object?> row, String key) {
    final v = row[key];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static SentinelTagSnapshot _snapshotOf(Map<String, String> tags) {
    return SentinelTagSnapshot(
      title: tags['TITLE'] ?? '',
      artist: tags['ARTIST'] ?? '',
      albumArtist: tags['ALBUM_ARTIST'] ?? '',
      album: tags['ALBUM'] ?? '',
      track: tags['TRACK'] ?? '',
      year: tags['YEAR'] ?? '',
      genre: tags['GENRE'] ?? '',
      lyrics: tags['LYRICS'] ?? '',
      artwork: tags['ARTWORK'] == 'true',
    );
  }

  static bool _hasSidecarLyrics(String audioPath) {
    final dot = audioPath.lastIndexOf('.');
    if (dot <= 0) return false;
    final stem = audioPath.substring(0, dot);
    for (final ext in const <String>['.lrc', '.txt']) {
      try {
        final f = File('$stem$ext');
        if (f.existsSync() && f.lengthSync() <= 128 * 1024) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _freeEmbeddingRamIfLow() async {
    try {
      final status = await EmbeddingGemmaService.instance.queryStatus();
      final loaded = status['loaded'] == true;
      if (!loaded) return;
      final availMb = (status['availRamMb'] as num?)?.toInt() ?? 2048;
      final lowMemory = status['lowMemory'] == true;
      if (lowMemory || availMb < 650) {
        debugPrint('SENTINEL_SCAN: free RAM $availMb MB — unloading EmbeddingGemma before scan');
        await EmbeddingGemmaService.instance.unloadNativeModel(keepAvailableForLazyReload: true);
      }
    } catch (e) {
      debugPrint('SENTINEL_SCAN: embedding RAM check failed: $e');
    }
  }

  Future<SentinelScanSummary> run({
    bool fullRescan = false,
    bool resume = false,
    void Function(SentinelProgress progress)? onProgress,
  }) async {
    if (_scanning) throw StateError('A Sentinel scan is already running');
    _scanning = true;
    _cancelRequested = false;
    final startedAt = DateTime.now().toIso8601String();
    try {
      await store.ensureLoaded();
      await store.pruneStale();
      await _freeEmbeddingRamIfLow();
      final rows = await StorageClient.queryAudio();
      final media = rows.map((row) {
        return _MediaRow(
          uri: _asString(row, 'uri'),
          path: _asString(row, 'path'),
          title: _asString(row, 'title'),
          artist: _asString(row, 'artist'),
          album: _asString(row, 'album'),
          albumArtist: _asString(row, 'albumArtist'),
          genre: _asString(row, 'genre'),
          track: _asInt(row, 'track'),
          year: _asInt(row, 'year'),
          dateAdded: _asInt(row, 'dateAdded'),
          mime: _asString(row, 'mime'),
          size: _asInt(row, 'size'),
          displayName: _asString(row, 'displayName'),
        );
      }).toList();
      media.sort((a, b) => a.uri.compareTo(b.uri));
      final seenUris = media.map((r) => r.uri).where((u) => u.isNotEmpty).toSet();
      final byUri = <String, _MediaRow>{};
      for (final row in media) {
        if (row.uri.isNotEmpty) byUri[row.uri] = row;
      }
      var scanId = 'sentinel-${DateTime.now().millisecondsSinceEpoch}';
      var scanned = 0;
      var hitCount = 0;
      var sampled = 0;
      var sampleHits = 0;
      var skipped = 0;
      var total = 0;
      List<_MediaRow> worklist;
      Set<String> sampledUris = {};
      final prior = resume ? store.scanProgress : null;
      if (prior != null && prior.pendingUris.isNotEmpty) {
        scanId = prior.scanId;
        total = prior.total;
        scanned = prior.scanned;
        hitCount = prior.hits;
        sampled = prior.sampled;
        sampleHits = prior.sampleHits;
        sampledUris = prior.sampledUris.toSet();
        worklist = [];
        for (final uri in prior.pendingUris) {
          final row = byUri[uri];
          if (row != null) worklist.add(row);
        }
      } else {
        final candidates = <_MediaRow>[];
        final clean = <_MediaRow>[];
        final superseded = <String>[];
        for (final row in media) {
          if (row.uri.isEmpty) {
            candidates.add(row);
            continue;
          }
          final id = SentinelHit.fingerprintFor(row.uri, row.size, row.dateAdded);
          final byUriHit = store.byUri(row.uri);
          if (byUriHit != null && byUriHit.id != id) {
            superseded.add(byUriHit.id);
          }
          final existing = store.byId(id);
          if (!fullRescan &&
              existing != null &&
              existing.status != 'open' &&
              existing.status != 'in_forge' &&
              existing.status != 'in_pipeline' &&
              existing.status != 'stale' &&
              existing.fingerprint == id) {
            skipped++;
            continue;
          }
          final triageTags = <String, String>{
            'TITLE': row.title,
            'ARTIST': row.artist,
            'ALBUM_ARTIST': row.albumArtist,
            'ALBUM': row.album,
            'TRACK': row.track == 0 ? '' : row.track.toString(),
            'YEAR': row.year == 0 ? '' : row.year.toString(),
            'GENRE': row.genre,
          };
          final triage = SentinelPolicy.audit(triageTags, row.displayName, triage: true);
          if (triage.issues.isNotEmpty) {
            candidates.add(row);
          } else {
            clean.add(row);
          }
        }
        final wantSample = (clean.length * sampleRate).ceil();
        final takeSample = wantSample < minSample ? (minSample < clean.length ? minSample : clean.length) : wantSample;
        clean.shuffle(Random());
        final sampleRows = clean.take(takeSample).toList();
        sampledUris = sampleRows.map((r) => r.uri).where((u) => u.isNotEmpty).toSet();
        worklist = [...candidates, ...sampleRows];
        total = worklist.length;
        if (superseded.isNotEmpty) {
          await store.removeAll(superseded);
        }
      }
      var status = 'completed';
      var index = 0;
      while (index < worklist.length) {
        if (_cancelRequested) {
          status = 'cancelled';
          break;
        }
        if (FFmpegExecutor.isBusy) {
          status = 'blocked';
          break;
        }
        final end = (index + batchSize < worklist.length) ? index + batchSize : worklist.length;
        final batch = worklist.sublist(index, end);
        final batchHits = <SentinelHit>[];
        for (final row in batch) {
          final result = await _auditRow(row, scanId, sampledUris.contains(row.uri));
          scanned++;
          if (sampledUris.contains(row.uri)) {
            sampled++;
            if (result != null) sampleHits++;
          }
          if (result != null) {
            batchHits.add(result);
            hitCount++;
          }
        }
        if (batchHits.isNotEmpty) {
          await store.upsertAll(batchHits);
        }
        index = end;
        final pending = worklist.sublist(index).map((r) => r.uri).where((u) => u.isNotEmpty).toList();
        await store.saveScanProgress(SentinelScanProgress(
          scanId: scanId,
          startedAt: startedAt,
          total: total,
          scanned: scanned,
          hits: hitCount,
          sampled: sampled,
          sampleHits: sampleHits,
          pendingUris: pending,
          sampledUris: sampledUris.toList(),
        ));
        onProgress?.call(SentinelProgress(scanned: scanned, total: total, hits: hitCount, sampled: sampled, sampleHits: sampleHits));
        await Future<void>.delayed(Duration.zero);
      }
      if (status == 'completed') {
        await _applyCollisions(scanId);
        await store.markStaleForMissing(seenUris);
        await store.clearScanProgress();
        await store.setScanMetadata(scanId, DateTime.now().toIso8601String());
        hitCount = store.allHits.where((h) => h.scanId == scanId && h.status != 'resolved').length;
      }
      return SentinelScanSummary(
        scanId: scanId,
        startedAt: startedAt,
        finishedAt: DateTime.now().toIso8601String(),
        total: total,
        scanned: scanned,
        skipped: skipped,
        hits: hitCount,
        sampleSize: sampled,
        sampleHits: sampleHits,
        status: status,
      );
    } finally {
      _scanning = false;
    }
  }

  Future<SentinelHit?> rescanOne(SentinelHit hit) async {
    if (_scanning) throw StateError('A Sentinel scan is already running');
    await store.ensureLoaded();
    final row = _MediaRow(
      uri: hit.uri,
      path: hit.path,
      title: hit.tagSnapshot.title,
      artist: hit.tagSnapshot.artist,
      album: hit.tagSnapshot.album,
      albumArtist: hit.tagSnapshot.albumArtist,
      genre: hit.tagSnapshot.genre,
      track: int.tryParse(hit.tagSnapshot.track) ?? 0,
      year: int.tryParse(hit.tagSnapshot.year) ?? 0,
      dateAdded: hit.dateAdded,
      mime: '',
      size: hit.size,
      displayName: hit.displayName,
    );
    final result = await _auditRow(row, hit.scanId, false);
    if (result != null) {
      await store.upsertAll([result]);
      await _applyCollisions(result.scanId);
      return store.byId(result.id);
    }
    return store.byId(hit.id);
  }

  Future<SentinelHit?> _auditRow(_MediaRow row, String scanId, bool sampled) async {
    final now = DateTime.now().toIso8601String();
    final id = SentinelHit.fingerprintFor(row.uri, row.size, row.dateAdded);
    final existing = store.byId(id);
    final keepStatus = existing != null &&
        (existing.status == SentinelStatus.ignored || existing.status == SentinelStatus.uncompletable);
    final stickyStatus = keepStatus ? existing.status : SentinelStatus.open;
    final stickyReason = keepStatus ? existing.statusReason : '';
    if (row.path.isEmpty) {
      final snapshot = <String, String>{
        'TITLE': row.title,
        'ARTIST': row.artist,
        'ALBUM_ARTIST': row.albumArtist,
        'ALBUM': row.album,
        'TRACK': row.track == 0 ? '' : row.track.toString(),
        'YEAR': row.year == 0 ? '' : row.year.toString(),
        'GENRE': row.genre,
        'LYRICS': '',
        'ARTWORK': 'false',
      };
      return SentinelHit(
        id: id,
        uri: row.uri,
        path: row.path,
        size: row.size,
        dateAdded: row.dateAdded,
        displayName: row.displayName,
        expectedName: SentinelPolicy.expectedFileName(snapshot, displayName: row.displayName),
        issues: const ['UNREADABLE_TAGS'],
        severity: 'high',
        tagSnapshot: _snapshotOf(snapshot),
        evidence: {'mediaStoreTitle': row.title, 'sidecarLyrics': false, 'sampled': sampled, 'reason': 'NO_FILE_PATH'},
        status: stickyStatus,
        statusReason: stickyReason,
        firstSeen: existing?.firstSeen ?? now,
        lastSeen: now,
        scanId: scanId,
      );
    }
    final tags = await TagIO.read(row.path, withArtwork: false);
    if (tags.isEmpty) {
      final snapshot = <String, String>{
        'TITLE': row.title,
        'ARTIST': row.artist,
        'ALBUM_ARTIST': row.albumArtist,
        'ALBUM': row.album,
        'TRACK': row.track == 0 ? '' : row.track.toString(),
        'YEAR': row.year == 0 ? '' : row.year.toString(),
        'GENRE': row.genre,
        'LYRICS': '',
        'ARTWORK': 'false',
      };
      return SentinelHit(
        id: id,
        uri: row.uri,
        path: row.path,
        size: row.size,
        dateAdded: row.dateAdded,
        displayName: row.displayName,
        expectedName: SentinelPolicy.expectedFileName(snapshot, displayName: row.displayName),
        issues: const ['UNREADABLE_TAGS'],
        severity: 'high',
        tagSnapshot: _snapshotOf(snapshot),
        evidence: {'mediaStoreTitle': row.title, 'sidecarLyrics': false, 'sampled': sampled, 'reason': 'TAG_READ_EMPTY'},
        status: stickyStatus,
        statusReason: stickyReason,
        firstSeen: existing?.firstSeen ?? now,
        lastSeen: now,
        scanId: scanId,
      );
    }
    var hasArt = false;
    var artworkVia = 'tags';
    try {
      final withArt = await TagIO.read(row.path, withArtwork: true);
      hasArt = (withArt['ARTWORK_BASE64'] ?? '').isNotEmpty;
    } catch (_) {
      hasArt = false;
    }
    if (!hasArt && row.uri.isNotEmpty) {
      try {
        final thumb = await StorageClient.loadArtwork(row.uri, size: 64);
        if (thumb != null && thumb.isNotEmpty) {
          hasArt = true;
          artworkVia = 'thumbnail';
        }
      } catch (_) {}
    }
    final sidecar = _hasSidecarLyrics(row.path);
    final snapshot = <String, String>{
      'TITLE': tags['TITLE'] ?? '',
      'ARTIST': tags['ARTIST'] ?? '',
      'ALBUM_ARTIST': tags['ALBUM_ARTIST'] ?? '',
      'ALBUM': tags['ALBUM'] ?? '',
      'TRACK': tags['TRACK'] ?? '',
      'YEAR': tags['YEAR'] ?? '',
      'GENRE': tags['GENRE'] ?? '',
      'LYRICS': tags['LYRICS'] ?? '',
      'ARTWORK': hasArt ? 'true' : 'false',
    };
    final auditTags = Map<String, String>.from(snapshot);
    auditTags['SIDECAR_LYRICS'] = sidecar ? 'true' : 'false';
    final audit = SentinelPolicy.audit(auditTags, row.displayName);
    final issues = List<String>.from(audit.issues);
    if (!TagIO.canWrite(row.path)) issues.add('UNWRITABLE_FORMAT');
    if (issues.isEmpty) {
      if (existing != null && existing.status != 'resolved') {
        return existing.copyWith(
          expectedName: audit.expectedName,
          issues: const [],
          severity: 'low',
          tagSnapshot: _snapshotOf(snapshot),
          evidence: {'mediaStoreTitle': row.title, 'sidecarLyrics': sidecar, 'sampled': sampled, 'artworkVia': artworkVia},
          status: 'resolved',
          statusReason: '',
          lastSeen: now,
          scanId: scanId,
        );
      }
      return null;
    }
    return SentinelHit(
      id: id,
      uri: row.uri,
      path: row.path,
      size: row.size,
      dateAdded: row.dateAdded,
      displayName: row.displayName,
      expectedName: audit.expectedName,
      issues: issues,
      severity: SentinelPolicy.severityFor(issues),
      tagSnapshot: _snapshotOf(snapshot),
      evidence: {'mediaStoreTitle': row.title, 'sidecarLyrics': sidecar, 'sampled': sampled, 'artworkVia': artworkVia},
      status: stickyStatus,
      statusReason: stickyReason,
      firstSeen: existing?.firstSeen ?? now,
      lastSeen: now,
      scanId: scanId,
    );
  }

  Future<void> _applyCollisions(String scanId) async {
    final groups = <String, List<SentinelHit>>{};
    for (final hit in store.allHits) {
      if (hit.status == 'resolved' || hit.status == 'stale') continue;
      if (hit.expectedName.isEmpty) continue;
      groups.putIfAbsent(hit.expectedName, () => []).add(hit);
    }
    final updates = <SentinelHit>[];
    for (final entry in groups.entries) {
      if (entry.value.length < 2) {
        for (final hit in entry.value) {
          if (hit.issues.contains('NAME_COLLISION')) {
            final issues = List<String>.from(hit.issues)..remove('NAME_COLLISION');
            updates.add(hit.copyWith(issues: issues, severity: SentinelPolicy.severityFor(issues)));
          }
        }
        continue;
      }
      for (final hit in entry.value) {
        if (!hit.issues.contains('NAME_COLLISION')) {
          final issues = List<String>.from(hit.issues)..add('NAME_COLLISION');
          updates.add(hit.copyWith(issues: issues, severity: SentinelPolicy.severityFor(issues)));
        }
      }
    }
    if (updates.isNotEmpty) await store.upsertAll(updates);
  }
}
