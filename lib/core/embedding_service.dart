// ============================================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================================

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// On-device semantic embedding engine for GhostBrain v2.
///
/// Architecture:
/// 1. Primary Native Engine: Attempts to invoke the 'com.sovereign.tagger/embeddings'
///    MethodChannel backed by Google AI Edge LiteRT (EmbeddingGemma-300M / EmbeddingGemma-2-270M)
///    truncated via Matryoshka Representation Learning (MRL) to [dims] (256 dimensions).
/// 2. Zero-Dependency Offline Fallback: When the native LiteRT model is not yet installed
///    or unloaded to conserve RAM during heavy FFmpeg/Whisper jobs, automatically falls back
///    to a deterministic 256-dim L2-normalized signed random-projection character/word n-gram
///    embedding vector so semantic cosine routing works out of the box with 0 MB overhead.
class EmbeddingGemmaService {
  EmbeddingGemmaService._();
  static final EmbeddingGemmaService instance = EmbeddingGemmaService._();

  static const MethodChannel _channel =
      MethodChannel('com.sovereign.tagger/embeddings');

  /// Matryoshka target dimensionality (128, 256, 512, or 768).
  static const int dims = 256;

  bool _nativeChecked = false;
  bool _nativeAvailable = false;
  final Map<String, Float32List> _cache = <String, Float32List>{};

  bool get isNativeAvailable => _nativeAvailable;

  /// Probes whether the native EmbeddingGemma LiteRT bridge is registered.
  Future<bool> checkNativeAvailability() async {
    if (_nativeChecked) return _nativeAvailable;
    _nativeChecked = true;
    try {
      final res = await _channel.invokeMethod<bool>('isAvailable');
      _nativeAvailable = res ?? false;
    } catch (_) {
      _nativeAvailable = false;
    }
    return _nativeAvailable;
  }

  /// Embeds [text] into an L2-normalized [dims]-dimensional vector.
  Future<Float32List> embed(String text) async {
    final normalized = _normalize(text);
    final cached = _cache[normalized];
    if (cached != null) return cached;

    if (!_nativeChecked) {
      await checkNativeAvailability();
    }

    if (_nativeAvailable) {
      try {
        final raw = await _channel.invokeMethod<List<dynamic>>(
          'embedText',
          <String, dynamic>{'text': normalized, 'dims': dims},
        );
        if (raw != null && raw.isNotEmpty) {
          final vec = Float32List(math.min(dims, raw.length));
          for (var i = 0; i < vec.length; i++) {
            vec[i] = (raw[i] as num).toDouble();
          }
          _l2NormalizeInPlace(vec);
          _putCache(normalized, vec);
          return vec;
        }
      } catch (_) {
        _nativeAvailable = false;
      }
    }

    final fallback = embedSyncFallback(normalized);
    _putCache(normalized, fallback);
    return fallback;
  }

  /// Synchronous 256-d L2-normalized feature-hashed n-gram + semantic concept projection.
  /// Provides fast (<0.2ms) offline vector similarity when native weights are unloaded.
  Float32List embedSyncFallback(String text) {
    final norm = _normalize(text);
    final cached = _cache[norm];
    if (cached != null) return cached;

    final vec = Float32List(dims);
    if (norm.isEmpty) return vec;

    final expanded = _expandSemanticConcepts(norm);
    final words = expanded.split(' ');

    // 1. Word unigrams & bigrams with higher weight
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;
      _projectToken(vec, 'w:$w', 1.8);
      if (i + 1 < words.length) {
        _projectToken(vec, 'bi:${w}_${words[i + 1]}', 2.2);
      }
    }

    // 2. Character trigrams & 4-grams for Whisper typo / homophone resilience
    final padded = ' $norm ';
    for (var i = 0; i <= padded.length - 3; i++) {
      _projectToken(vec, 'c3:${padded.substring(i, i + 3)}', 0.65);
      if (i <= padded.length - 4) {
        _projectToken(vec, 'c4:${padded.substring(i, i + 4)}', 0.55);
      }
    }

    _l2NormalizeInPlace(vec);
    _putCache(norm, vec);
    return vec;
  }

  /// Computes cosine similarity in [-1.0, 1.0] between two L2-normalized vectors.
  static double cosine(Float32List a, Float32List b) {
    final len = math.min(a.length, b.length);
    var dot = 0.0;
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  void _putCache(String key, Float32List vec) {
    if (_cache.length >= 512) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = vec;
  }

  static void _projectToken(Float32List vec, String token, double weight) {
    // FNV-1a 32-bit two-choice hashing with signed Rademacher projection
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
