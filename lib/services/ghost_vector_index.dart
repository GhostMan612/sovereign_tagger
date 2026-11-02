// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/embedding_model.dart';
import '../core/embedding_service.dart';
import '../core/tag_io.dart';
import 'ghost_brain.dart';

class GhostSemanticMatch {
  final GhostTrack track;
  final double score;
  final String snippet;

  const GhostSemanticMatch({
    required this.track,
    required this.score,
    required this.snippet,
  });
}

class GhostVectorIndexState {
  final int indexedCount;
  final int totalCount;
  final int engineId;
  final bool isIndexing;
  final double progress;
  final String statusText;

  const GhostVectorIndexState({
    this.indexedCount = 0,
    this.totalCount = 0,
    this.engineId = EmbeddingGemmaService.fallbackEngineId,
    this.isIndexing = false,
    this.progress = 0.0,
    this.statusText = 'Vector index idle.',
  });

  GhostVectorIndexState copyWith({
    int? indexedCount,
    int? totalCount,
    int? engineId,
    bool? isIndexing,
    double? progress,
    String? statusText,
  }) {
    return GhostVectorIndexState(
      indexedCount: indexedCount ?? this.indexedCount,
      totalCount: totalCount ?? this.totalCount,
      engineId: engineId ?? this.engineId,
      isIndexing: isIndexing ?? this.isIndexing,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
    );
  }
}

class _VectorRecord {
  final String path;
  final int modifiedMs;
  final int snippetHash;
  final String snippet;
  final Float32List vector;

  const _VectorRecord({
    required this.path,
    required this.modifiedMs,
    required this.snippetHash,
    required this.snippet,
    required this.vector,
  });
}

class GhostVectorIndex {
  GhostVectorIndex._();
  static final GhostVectorIndex instance = GhostVectorIndex._();

  static const int _magic = 0x47564543;
  static const int _formatVersion = 1;
  static const String _fileName = 'ghost_vectors.bin';

  static final RegExp _lrcTimeTag = RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]');
  static final RegExp _lrcMetaTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');

  final ValueNotifier<GhostVectorIndexState> state =
      ValueNotifier<GhostVectorIndexState>(const GhostVectorIndexState());

  final Map<String, _VectorRecord> _records = <String, _VectorRecord>{};
  int _loadedEngineId = 0;
  bool _diskLoaded = false;
  bool _cancelRequested = false;

  Future<File> _indexFile() async {
    final dir = await EmbeddingModel.directory();
    return File('${dir.path}/$_fileName');
  }

  void cancelIndexing() {
    _cancelRequested = true;
  }

  Future<void> loadFromDiskIfNeeded() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    try {
      final f = await _indexFile();
      if (!f.existsSync()) return;
      final bytes = await f.readAsBytes();
      if (bytes.length < 20) return;
      final bd = ByteData.sublistView(bytes);
      final magic = bd.getUint32(0, Endian.little);
      final ver = bd.getUint32(4, Endian.little);
      final engId = bd.getUint32(8, Endian.little);
      final dims = bd.getUint32(12, Endian.little);
      final count = bd.getUint32(16, Endian.little);
      if (magic != _magic || ver != _formatVersion || dims != EmbeddingGemmaService.dims) {
        return;
      }

      var offset = 20;
      final loaded = <String, _VectorRecord>{};
      for (var i = 0; i < count; i++) {
        if (offset + 2 > bytes.length) break;
        final pathLen = bd.getUint16(offset, Endian.little);
        offset += 2;
        if (offset + pathLen + 2 > bytes.length) break;
        final path = utf8.decode(bytes.sublist(offset, offset + pathLen), allowMalformed: true);
        offset += pathLen;
        final snipLen = bd.getUint16(offset, Endian.little);
        offset += 2;
        if (offset + snipLen + 12 + dims * 4 > bytes.length) break;
        final snippet = utf8.decode(bytes.sublist(offset, offset + snipLen), allowMalformed: true);
        offset += snipLen;
        final modMs = bd.getInt64(offset, Endian.little);
        offset += 8;
        final hash = bd.getUint32(offset, Endian.little);
        offset += 4;
        final vec = Float32List(dims);
        for (var d = 0; d < dims; d++) {
          vec[d] = bd.getFloat32(offset, Endian.little);
          offset += 4;
        }
        loaded[path] = _VectorRecord(
          path: path,
          modifiedMs: modMs,
          snippetHash: hash,
          snippet: snippet,
          vector: vec,
        );
      }

      _records
        ..clear()
        ..addAll(loaded);
      _loadedEngineId = engId;
      state.value = state.value.copyWith(
        indexedCount: _records.length,
        totalCount: _records.length,
        engineId: engId,
        statusText: _records.isEmpty
            ? 'Vector index empty.'
            : 'Loaded ${_records.length} track vectors (${engId == EmbeddingGemmaService.nativeEngineId ? 'LiteRT 256-D' : 'Fallback 256-D'}).',
      );
    } catch (e) {
      debugPrint('GHOST_VECTOR_INDEX: failed reading ghost_vectors.bin: $e');
    }
  }

  Future<int> ensureIndexed(
    List<GhostTrack> library, {
    bool forceRebuild = false,
    bool readEmbeddedLyrics = true,
  }) async {
    await loadFromDiskIfNeeded();
    if (library.isEmpty) {
      state.value = state.value.copyWith(
        indexedCount: 0,
        totalCount: 0,
        statusText: 'Library empty — nothing to index.',
      );
      return 0;
    }
    if (state.value.isIndexing) return _records.length;

    final embedder = EmbeddingGemmaService.instance;
    await embedder.checkNativeAvailability();
    final targetEngineId = embedder.activeEngineId;
    final engineChanged = _loadedEngineId != targetEngineId;

    _cancelRequested = false;
    final validPaths = <String>{for (final t in library) t.path};
    _records.removeWhere((k, _) => !validPaths.contains(k));

    final pendingTracks = <GhostTrack>[];
    final pendingModMs = <int>[];
    for (final track in library) {
      var modMs = 0;
      try {
        final f = File(track.path);
        if (f.existsSync()) {
          modMs = f.lastModifiedSync().millisecondsSinceEpoch;
        }
      } catch (e) {
        debugPrint('GHOST_VECTOR_INDEX: stat failed on ${track.path}: $e');
      }
      final existing = _records[track.path];
      if (forceRebuild || engineChanged || existing == null || existing.modifiedMs != modMs) {
        pendingTracks.add(track);
        pendingModMs.add(modMs);
      }
    }

    if (pendingTracks.isEmpty) {
      _loadedEngineId = targetEngineId;
      state.value = state.value.copyWith(
        indexedCount: _records.length,
        totalCount: library.length,
        engineId: targetEngineId,
        isIndexing: false,
        progress: 1.0,
        statusText: '${_records.length} tracks indexed (${targetEngineId == EmbeddingGemmaService.nativeEngineId ? 'LiteRT 256-D' : 'Fallback 256-D'}).',
      );
      return _records.length;
    }

    if (engineChanged || forceRebuild) {
      _records.clear();
    }

    state.value = state.value.copyWith(
      isIndexing: true,
      indexedCount: _records.length,
      totalCount: library.length,
      engineId: targetEngineId,
      progress: 0.01,
      statusText: 'Indexing 0 / ${pendingTracks.length} tracks...',
    );

    const batchSize = 24;
    var processed = 0;
    try {
      for (var start = 0; start < pendingTracks.length; start += batchSize) {
        if (_cancelRequested) {
          throw StateError('Vector indexing canceled');
        }
        final end = math.min(start + batchSize, pendingTracks.length);
        final batchTracks = pendingTracks.sublist(start, end);
        final batchDocs = <String>[];
        final batchTitles = <String>[];
        final batchSnippets = <String>[];

        for (final t in batchTracks) {
          final doc = await _buildDocumentForTrack(t, readTags: readEmbeddedLyrics);
          batchDocs.add(doc.fullText);
          batchTitles.add(t.title);
          batchSnippets.add(doc.snippet);
        }

        final vectors = await embedder.embedBatch(
          batchDocs,
          titles: batchTitles,
          isDocument: true,
        );

        for (var i = 0; i < batchTracks.length; i++) {
          final tr = batchTracks[i];
          _records[tr.path] = _VectorRecord(
            path: tr.path,
            modifiedMs: pendingModMs[start + i],
            snippetHash: _fnv32(batchDocs[i]),
            snippet: batchSnippets[i],
            vector: vectors[i],
          );
        }

        processed = end;
        final frac = processed / pendingTracks.length;
        state.value = state.value.copyWith(
          indexedCount: _records.length,
          totalCount: library.length,
          engineId: embedder.activeEngineId,
          isIndexing: true,
          progress: frac.clamp(0.0, 1.0),
          statusText: 'Indexing $processed / ${pendingTracks.length} tracks...',
        );
        await Future<void>.delayed(Duration.zero);
      }

      _loadedEngineId = embedder.activeEngineId;
      await _persistToDisk(_loadedEngineId);
      state.value = state.value.copyWith(
        indexedCount: _records.length,
        totalCount: library.length,
        engineId: _loadedEngineId,
        isIndexing: false,
        progress: 1.0,
        statusText: 'INDEXED ${_records.length} TRACKS ✓ (${_loadedEngineId == EmbeddingGemmaService.nativeEngineId ? 'LiteRT 256-D' : 'Fallback 256-D'})',
      );
    } catch (e) {
      debugPrint('GHOST_VECTOR_INDEX: indexing interrupted: $e');
      if (_records.isNotEmpty) {
        _loadedEngineId = embedder.activeEngineId;
        await _persistToDisk(_loadedEngineId);
      }
      state.value = state.value.copyWith(
        indexedCount: _records.length,
        totalCount: library.length,
        isIndexing: false,
        progress: 0.0,
        statusText: '$e',
      );
    }
    return _records.length;
  }

  Future<List<GhostSemanticMatch>> search(
    List<GhostTrack> library,
    String query, {
    int topK = 5,
  }) async {
    if (library.isEmpty || query.trim().isEmpty) return const <GhostSemanticMatch>[];
    await loadFromDiskIfNeeded();

    final embedder = EmbeddingGemmaService.instance;
    await embedder.checkNativeAvailability();

    if (_records.isEmpty || _loadedEngineId != embedder.activeEngineId) {
      final fastTagRead = library.length <= 160;
      await ensureIndexed(library, readEmbeddedLyrics: fastTagRead);
    }

    final queryEngineBefore = embedder.activeEngineId;
    final queryVec = await embedder.embed(query, isDocument: false);
    final queryEngineAfter = embedder.activeEngineId;

    if (queryEngineAfter != _loadedEngineId) {
      await ensureIndexed(library, forceRebuild: true, readEmbeddedLyrics: false);
    } else if (queryEngineBefore != queryEngineAfter) {
      await ensureIndexed(library, forceRebuild: true, readEmbeddedLyrics: false);
    }

    final qLower = query.toLowerCase();
    final qWords = qLower
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toList();

    final trackByPath = <String, GhostTrack>{for (final t in library) t.path: t};
    final matches = <GhostSemanticMatch>[];

    for (final entry in _records.entries) {
      final track = trackByPath[entry.key];
      if (track == null) continue;
      final rec = entry.value;
      var score = EmbeddingGemmaService.cosine(queryVec, rec.vector);
      if (qWords.isNotEmpty && rec.snippet.isNotEmpty) {
        final snipLower = rec.snippet.toLowerCase();
        var hits = 0;
        for (final w in qWords) {
          if (snipLower.contains(w)) hits++;
        }
        if (hits > 0) {
          score += 0.14 * (hits / qWords.length);
        }
      }
      matches.add(GhostSemanticMatch(
        track: track,
        score: score,
        snippet: rec.snippet,
      ));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(topK).toList();
  }

  Future<void> _persistToDisk(int engineId) async {
    try {
      final target = await _indexFile();
      final tmp = File('${target.path}.tmp');
      final builder = BytesBuilder(copy: false);

      final header = ByteData(20);
      header.setUint32(0, _magic, Endian.little);
      header.setUint32(4, _formatVersion, Endian.little);
      header.setUint32(8, engineId, Endian.little);
      header.setUint32(12, EmbeddingGemmaService.dims, Endian.little);
      header.setUint32(16, _records.length, Endian.little);
      builder.add(header.buffer.asUint8List());

      for (final rec in _records.values) {
        final pathBytes = utf8.encode(rec.path);
        final snipBytes = utf8.encode(rec.snippet);
        final meta = ByteData(4 + pathBytes.length + snipBytes.length + 12 + EmbeddingGemmaService.dims * 4);
        var off = 0;
        meta.setUint16(off, pathBytes.length, Endian.little);
        off += 2;
        final buf = meta.buffer.asUint8List();
        buf.setRange(off, off + pathBytes.length, pathBytes);
        off += pathBytes.length;
        meta.setUint16(off, snipBytes.length, Endian.little);
        off += 2;
        buf.setRange(off, off + snipBytes.length, snipBytes);
        off += snipBytes.length;
        meta.setInt64(off, rec.modifiedMs, Endian.little);
        off += 8;
        meta.setUint32(off, rec.snippetHash, Endian.little);
        off += 4;
        for (var d = 0; d < EmbeddingGemmaService.dims; d++) {
          meta.setFloat32(off, d < rec.vector.length ? rec.vector[d] : 0.0, Endian.little);
          off += 4;
        }
        builder.add(buf);
      }

      final payload = builder.takeBytes();
      await tmp.writeAsBytes(payload, flush: true);
      if (!tmp.existsSync() || tmp.lengthSync() != payload.length) {
        if (tmp.existsSync()) await tmp.delete();
        throw const FileSystemException('ghost_vectors.bin staging verification failed');
      }
      await tmp.rename(target.path);
    } catch (e) {
      debugPrint('GHOST_VECTOR_INDEX: failed writing ghost_vectors.bin: $e');
    }
  }

  static Future<({String fullText, String snippet})> _buildDocumentForTrack(
    GhostTrack track, {
    required bool readTags,
  }) async {
    var genre = '';
    var comment = '';
    var lyrics = '';

    final sidecarLrc = _readSidecarLyrics(track.path);
    if (sidecarLrc.isNotEmpty) {
      lyrics = sidecarLrc;
    }

    if (readTags) {
      final tags = await TagIO.read(track.path, withArtwork: false);
      genre = (tags['GENRE'] ?? '').trim();
      comment = (tags['COMMENT'] ?? '').trim();
      if (lyrics.isEmpty) {
        lyrics = _cleanLyrics(tags['LYRICS'] ?? '');
      }
    }

    if (lyrics.length > 650) {
      lyrics = lyrics.substring(0, 650);
    }

    final parts = <String>[
      track.title,
      if (track.artist.isNotEmpty && !track.artist.toLowerCase().startsWith('unknown'))
        'by ${track.artist}',
      if (track.album.isNotEmpty && !track.album.toLowerCase().startsWith('unknown'))
        'album ${track.album}',
      if (genre.isNotEmpty) 'genre $genre',
      if (comment.isNotEmpty && comment.length <= 160) comment,
      if (lyrics.isNotEmpty) 'lyrics: $lyrics',
    ];
    final full = parts.join(' | ');
    final snipParts = <String>[
      if (genre.isNotEmpty) genre,
      if (lyrics.isNotEmpty) (lyrics.length > 140 ? '${lyrics.substring(0, 140)}...' : lyrics),
    ];
    return (fullText: full, snippet: snipParts.join(' • '));
  }

  static String _readSidecarLyrics(String audioPath) {
    final dot = audioPath.lastIndexOf('.');
    if (dot <= 0) return '';
    final stem = audioPath.substring(0, dot);
    for (final ext in const <String>['.lrc', '.txt']) {
      try {
        final f = File('$stem$ext');
        if (f.existsSync() && f.lengthSync() <= 128 * 1024) {
          return _cleanLyrics(f.readAsStringSync());
        }
      } catch (_) {}
    }
    return '';
  }

  static String _cleanLyrics(String raw) {
    if (raw.trim().isEmpty) return '';
    final lines = <String>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _lrcMetaTag.hasMatch(trimmed)) continue;
      final stripped = trimmed.replaceAll(_lrcTimeTag, '').trim();
      if (stripped.isNotEmpty) {
        lines.add(stripped);
      }
    }
    return lines.join(' ');
  }

  static int _fnv32(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
