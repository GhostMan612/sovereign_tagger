// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'embedding_model.dart';

class EmbeddingGemmaService {
  EmbeddingGemmaService._();
  static final EmbeddingGemmaService instance = EmbeddingGemmaService._();

  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/embeddings');
  static const int dims = 256;
  static const int fallbackEngineId = 1;
  static const int nativeEngineId = 2;

  bool _nativeChecked = false;
  bool _nativeAvailable = false;
  int _engineEpoch = 0;
  final ValueNotifier<bool> nativeActiveNotifier = ValueNotifier<bool>(false);

  final Map<String, Float32List> _nativeCache = <String, Float32List>{};
  final Map<String, Float32List> _fallbackCache = <String, Float32List>{};

  bool get isNativeAvailable => _nativeAvailable;
  int get engineEpoch => _engineEpoch;
  int get activeEngineId => _nativeAvailable ? nativeEngineId : fallbackEngineId;

  Future<bool> checkNativeAvailability({bool force = false}) async {
    if (_nativeChecked && !force) return _nativeAvailable;
    _nativeChecked = true;
    try {
      await EmbeddingModel.tryExtractBundledAssets();
      final res = await _channel.invokeMethod<bool>('isAvailable');
      final next = res ?? false;
      if (next != _nativeAvailable) {
        _nativeAvailable = next;
        _engineEpoch++;
        nativeActiveNotifier.value = next;
      }
    } catch (e) {
      debugPrint('EMBEDDING_GEMMA: availability check failed (using fallback): $e');
      if (_nativeAvailable) {
        _nativeAvailable = false;
        _engineEpoch++;
        nativeActiveNotifier.value = false;
      }
    }
    return _nativeAvailable;
  }

  Future<Map<String, dynamic>> queryStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      if (raw == null) return const <String, dynamic>{};
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final ready = map['filesReady'] == true || map['loaded'] == true;
      if (ready != _nativeAvailable) {
        _nativeAvailable = ready;
        _nativeChecked = true;
        _engineEpoch++;
        nativeActiveNotifier.value = ready;
      }
      return map;
    } catch (e) {
      debugPrint('EMBEDDING_GEMMA: status check failed: $e');
      return <String, dynamic>{'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> loadNativeModel({
    String? modelPath,
    String? tokenizerPath,
  }) async {
    final mPath = modelPath ?? (await EmbeddingModel.modelFile()).path;
    final tPath = tokenizerPath ?? (await EmbeddingModel.tokenizerFile()).path;
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'loadModel',
      <String, dynamic>{
        'modelPath': mPath,
        'tokenizerPath': tPath,
      },
    );
    _nativeChecked = true;
    _nativeAvailable = true;
    _nativeCache.clear();
    _engineEpoch++;
    nativeActiveNotifier.value = true;
    if (raw == null) return const <String, dynamic>{'loaded': true};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> unloadNativeModel({bool keepAvailableForLazyReload = true}) async {
    try {
      await _channel.invokeMethod<bool>('unloadModel');
    } catch (e) {
      debugPrint('EMBEDDING_GEMMA: unloadModel failed: $e');
    }
    if (!keepAvailableForLazyReload && _nativeAvailable) {
      _nativeAvailable = false;
      _engineEpoch++;
      nativeActiveNotifier.value = false;
    }
  }

  Future<Float32List> embed(
    String text, {
    bool isDocument = false,
    String? title,
  }) async {
    final normalized = _normalize(text);
    final task = isDocument ? 'document' : 'query';
    final cacheKey = '$task|${title ?? ''}|$normalized';

    if (!_nativeChecked) {
      await checkNativeAvailability();
    }

    if (_nativeAvailable) {
      final hit = _nativeCache[cacheKey];
      if (hit != null) return hit;
      try {
        final raw = await _channel.invokeMethod<List<dynamic>>(
          'embedText',
          <String, dynamic>{
            'text': text.trim(),
            'dims': dims,
            'task': task,
            if (title != null && title.isNotEmpty) 'title': title,
          },
        );
        if (raw != null && raw.isNotEmpty) {
          final vec = _decodeVector(raw);
          _putCache(_nativeCache, cacheKey, vec);
          return vec;
        }
      } catch (e) {
        debugPrint('EMBEDDING_GEMMA: native embedText fell back to offline n-gram projection: $e');
        _nativeAvailable = false;
        _engineEpoch++;
        nativeActiveNotifier.value = false;
      }
    }

    return embedSyncFallback(text);
  }

  Future<List<Float32List>> embedBatch(
    List<String> texts, {
    List<String>? titles,
    bool isDocument = true,
  }) async {
    if (texts.isEmpty) return const <Float32List>[];
    if (!_nativeChecked) {
      await checkNativeAvailability();
    }

    if (_nativeAvailable) {
      try {
        final task = isDocument ? 'document' : 'query';
        final results = <Float32List>[];
        const chunkSize = 24;
        for (var offset = 0; offset < texts.length; offset += chunkSize) {
          final end = math.min(offset + chunkSize, texts.length);
          final subTexts = texts.sublist(offset, end);
          final subTitles = titles != null && titles.length >= end
              ? titles.sublist(offset, end)
              : null;
          final rawBatch = await _channel.invokeMethod<List<dynamic>>(
            'embedBatch',
            <String, dynamic>{
              'texts': subTexts,
              if (subTitles != null) 'titles': subTitles,
              'dims': dims,
              'task': task,
            },
          );
          if (rawBatch == null || rawBatch.length != subTexts.length) {
            throw StateError('Batch size mismatch from native EmbeddingGemma bridge');
          }
          for (var i = 0; i < rawBatch.length; i++) {
            final item = rawBatch[i];
            if (item is List<dynamic>) {
              results.add(_decodeVector(item));
            } else {
              results.add(embedSyncFallback(subTexts[i]));
            }
          }
        }
        return results;
      } catch (e) {
        debugPrint('EMBEDDING_GEMMA: native embedBatch fell back to offline n-gram projection: $e');
        _nativeAvailable = false;
        _engineEpoch++;
        nativeActiveNotifier.value = false;
      }
    }

    return <Float32List>[
      for (final t in texts) embedSyncFallback(t),
    ];
  }

  Float32List embedSyncFallback(String text) {
    final norm = _normalize(text);
    final cached = _fallbackCache[norm];
    if (cached != null) return cached;

    final vec = Float32List(dims);
    if (norm.isEmpty) return vec;

    final expanded = _expandSemanticConcepts(norm);
    final words = expanded.split(' ');

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      _projectToken(vec, 'w:$w', 1.8);
      if (i + 1 < words.length) {
        _projectToken(vec, 'bi:${w}_${words[i + 1]}', 2.2);
      }
    }

    final padded = ' $norm ';
    for (var i = 0; i <= padded.length - 3; i++) {
      _projectToken(vec, 'c3:${padded.substring(i, i + 3)}', 0.65);
      if (i <= padded.length - 4) {
        _projectToken(vec, 'c4:${padded.substring(i, i + 4)}', 0.55);
      }
    }

    _l2NormalizeInPlace(vec);
    _putCache(_fallbackCache, norm, vec);
    return vec;
  }

  static double cosine(Float32List a, Float32List b) {
    final len = math.min(a.length, b.length);
    var dot = 0.0;
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  static Float32List _decodeVector(List<dynamic> raw) {
    final len = math.min(dims, raw.length);
    final vec = Float32List(dims);
    if (raw is Float32List) {
      for (var i = 0; i < len; i++) {
        vec[i] = raw[i];
      }
    } else {
      for (var i = 0; i < len; i++) {
        vec[i] = (raw[i] as num).toDouble();
      }
    }
    _l2NormalizeInPlace(vec);
    return vec;
  }

  static void _putCache(Map<String, Float32List> map, String key, Float32List vec) {
    if (map.length >= 512) {
      map.remove(map.keys.first);
    }
    map[key] = vec;
  }

  static void _projectToken(Float32List vec, String token, double weight) {
    var h1 = 0x811c9dc5;
    var h2 = 0x1b873593;
    for (var i = 0; i < token.length; i++) {
      final c = token.codeUnitAt(i);
      h1 ^= c;
      h1 = (h1 * 0x01000193) & 0x7fffffff;
      h2 ^= (c + i * 31);
      h2 = (h2 * 0x85ebca6b) & 0x7fffffff;
    }
    final idx1 = h1 % dims;
    final sign1 = (h1 & 1) == 0 ? 1.0 : -1.0;
    final idx2 = h2 % dims;
    final sign2 = (h2 & 1) == 0 ? 1.0 : -1.0;
    vec[idx1] += sign1 * weight;
    vec[idx2] += sign2 * (weight * 0.7);
  }

  static void _l2NormalizeInPlace(Float32List vec) {
    var sumSq = 0.0;
    for (var i = 0; i < vec.length; i++) {
      sumSq += vec[i] * vec[i];
    }
    if (sumSq <= 1e-12) return;
    final inv = 1.0 / math.sqrt(sumSq);
    for (var i = 0; i < vec.length; i++) {
      vec[i] *= inv;
    }
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"['`]"), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<String, String> _conceptClusters = <String, String>{
    'download': 'grab grabber fetch rip save pull youtube soundcloud',
    'rip': 'grab grabber download fetch audio youtube',
    'fetch': 'grab search metadata lyrics pull find',
    'hunt': 'search grabber youtube soundcloud find',
    'search': 'hunt find lookup query grabber metadata',
    'youtube': 'grabber hunt search video audio download',
    'soundcloud': 'grabber hunt search audio download',
    'metadata': 'forge tag tags id3 artist album title year genre',
    'tags': 'forge tag metadata id3 artist album title',
    'tag': 'forge metadata id3 artist album title',
    'id3': 'forge tag metadata artist album',
    'extract': 'forge metadata lyrics search identify pull',
    'lyrics': 'lyric lrc words synced karaoke lrclib genius forge',
    'lyric': 'lyrics lrc words synced karaoke lrclib genius forge',
    'words': 'lyrics lrc synced karaoke lrclib genius forge',
    'lrc': 'lyrics synced karaoke lrclib forge',
    'karaoke': 'lyrics synced lrc forge',
    'identify': 'acr acrcloud fingerprint recognize audio what song forge',
    'fingerprint': 'acr acrcloud identify recognize audio forge',
    'acr': 'acrcloud fingerprint identify forge',
    'acrcloud': 'acr fingerprint identify forge',
    'whisper': 'workbench transcribe speech text lrc ai',
    'transcribe': 'whisper workbench lyrics speech text',
    'replaygain': 'workbench loudness volume normalize lufs gain',
    'normalize': 'workbench replaygain loudness volume lufs',
    'loaded': 'mounted current file track song forge',
    'mounted': 'loaded current file track song forge',
    'dark': 'synthwave industrial cyberpunkelectronic night heavy moody',
    'chill': 'ambient mellow lo-fi calm atmospheric slow relax',
    'energetic': 'upbeat fast dance electronic hype bass workout',
  };

  static String _expandSemanticConcepts(String norm) {
    final tokens = norm.split(' ');
    final out = <String>[...tokens];
    for (final t in tokens) {
      final cluster = _conceptClusters[t];
      if (cluster != null) {
        out.add(cluster);
      }
    }
    return out.join(' ');
  }
}
