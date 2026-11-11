// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class _DownloadCandidate {
  final String sourceName;
  final String url;
  final bool usesHfToken;

  const _DownloadCandidate({
    required this.sourceName,
    required this.url,
    this.usesHfToken = false,
  });
}

class EmbeddingModel {
  static const String modelFileName = 'embeddinggemma-300m_seq256_mixed-precision.tflite';
  static const String upstreamModelFileName = 'embeddinggemma-300M_seq256_mixed-precision.tflite';
  static const String tokenizerFileName = 'sentencepiece.model';

  static const String repoUrl = 'https://huggingface.co/litert-community/embeddinggemma-300m';
  static const String hfTokensUrl = 'https://huggingface.co/settings/tokens';

  static const String modelDownloadUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite?download=true';
  static const String tokenizerDownloadUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model?download=true';

  static const List<_DownloadCandidate> _tokenizerCandidates = [
    _DownloadCandidate(
      sourceName: 'Hugging Face',
      url: tokenizerDownloadUrl,
      usesHfToken: true,
    ),
    _DownloadCandidate(
      sourceName: 'ModelScope Mirror',
      url: 'https://www.modelscope.cn/models/litert-community/embeddinggemma-300m/resolve/master/sentencepiece.model',
    ),
    _DownloadCandidate(
      sourceName: 'ModelScope API',
      url: 'https://www.modelscope.cn/api/v1/models/litert-community/embeddinggemma-300m/repo?Revision=master&FilePath=sentencepiece.model',
    ),
  ];

  static const List<_DownloadCandidate> _modelCandidates = [
    _DownloadCandidate(
      sourceName: 'Hugging Face',
      url: modelDownloadUrl,
      usesHfToken: true,
    ),
    _DownloadCandidate(
      sourceName: 'ModelScope Mirror',
      url: 'https://www.modelscope.cn/models/litert-community/embeddinggemma-300m/resolve/master/embeddinggemma-300M_seq256_mixed-precision.tflite',
    ),
    _DownloadCandidate(
      sourceName: 'ModelScope API',
      url: 'https://www.modelscope.cn/api/v1/models/litert-community/embeddinggemma-300m/repo?Revision=master&FilePath=embeddinggemma-300M_seq256_mixed-precision.tflite',
    ),
    _DownloadCandidate(
      sourceName: 'Hugging Face (alt case)',
      url: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300m_seq256_mixed-precision.tflite?download=true',
      usesHfToken: true,
    ),
  ];

  static const int minModelBytes = 16 * 1024 * 1024;
  static const int minTokenizerBytes = 100 * 1024;

  static bool _downloadCanceled = false;
  static HttpClient? _activeClient;

  static String _sanitizeToken(String? raw) {
    var t = (raw ?? '').trim();
    if (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }
    return t;
  }

  static bool _isHuggingFaceAuthHost(String host) {
    final h = host.toLowerCase();
    return h == 'huggingface.co' || h.endsWith('.huggingface.co');
  }

  static Future<Directory> directory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/embedding_gemma');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<File> modelFile() async {
    final dir = await directory();
    return File('${dir.path}/$modelFileName');
  }

  static Future<File> tokenizerFile() async {
    final dir = await directory();
    return File('${dir.path}/$tokenizerFileName');
  }

  static Future<bool> isModelPresent() async {
    final f = await modelFile();
    return f.existsSync() && f.lengthSync() >= minModelBytes;
  }

  static Future<bool> isTokenizerPresent() async {
    final f = await tokenizerFile();
    return f.existsSync() && f.lengthSync() >= minTokenizerBytes;
  }

  static Future<bool> areFilesReady() async {
    return (await isModelPresent()) && (await isTokenizerPresent());
  }

  static Future<void> tryExtractBundledAssets({
    void Function(String stage, double progress)? onProgress,
  }) async {
    final mTarget = await modelFile();
    final tTarget = await tokenizerFile();
    if (!tTarget.existsSync() || tTarget.lengthSync() < minTokenizerBytes) {
      try {
        final data = await rootBundle.load('assets/models/$tokenizerFileName');
        if (data.lengthInBytes >= minTokenizerBytes) {
          onProgress?.call('Extracting bundled SentencePiece tokenizer', 0.1);
          await _atomicWriteBytes(
            tTarget,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            minTokenizerBytes,
          );
        }
      } catch (e) {
        debugPrint('EMBEDDING_MODEL: no bundled tokenizer asset ($e)');
      }
    }
    if (!mTarget.existsSync() || mTarget.lengthSync() < minModelBytes) {
      for (final assetName in [modelFileName, upstreamModelFileName]) {
        try {
          final data = await rootBundle.load('assets/models/$assetName');
          if (data.lengthInBytes >= minModelBytes) {
            onProgress?.call('Extracting bundled EmbeddingGemma model', 0.5);
            await _atomicWriteBytes(
              mTarget,
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              minModelBytes,
            );
            break;
          }
        } catch (e) {
          debugPrint('EMBEDDING_MODEL: no bundled model asset $assetName ($e)');
        }
      }
    }
  }

  static Future<void> download({
    String? hfToken,
    void Function(String stage, double progress)? onProgress,
  }) async {
    _downloadCanceled = false;
    final cleanToken = _sanitizeToken(hfToken);
    await tryExtractBundledAssets(onProgress: onProgress);

    final tTarget = await tokenizerFile();
    if (!tTarget.existsSync() || tTarget.lengthSync() < minTokenizerBytes) {
      await _downloadWithFallback(
        candidates: _orderedCandidates(_tokenizerCandidates, cleanToken),
        target: tTarget,
        minBytes: minTokenizerBytes,
        hfToken: cleanToken,
        label: 'SentencePiece tokenizer',
        progressStart: 0.0,
        progressSpan: 0.06,
        onProgress: onProgress,
      );
    }

    final mTarget = await modelFile();
    if (!mTarget.existsSync() || mTarget.lengthSync() < minModelBytes) {
      await _downloadWithFallback(
        candidates: _orderedCandidates(_modelCandidates, cleanToken),
        target: mTarget,
        minBytes: minModelBytes,
        hfToken: cleanToken,
        label: 'EmbeddingGemma-300M (.tflite)',
        progressStart: 0.06,
        progressSpan: 0.94,
        onProgress: onProgress,
      );
    }
    onProgress?.call('EmbeddingGemma files verified', 1.0);
  }

  static List<_DownloadCandidate> _orderedCandidates(
    List<_DownloadCandidate> list,
    String cleanToken,
  ) {
    if (cleanToken.isNotEmpty) return list;
    final mirrorsFirst = list.where((c) => !c.usesHfToken).toList();
    final hfAfter = list.where((c) => c.usesHfToken).toList();
    return [...mirrorsFirst, ...hfAfter];
  }

  static Future<void> _downloadWithFallback({
    required List<_DownloadCandidate> candidates,
    required File target,
    required int minBytes,
    required String hfToken,
    required String label,
    required double progressStart,
    required double progressSpan,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final failures = <String>[];
    for (final candidate in candidates) {
      if (_downloadCanceled) {
        throw const HttpException('Model download canceled');
      }
      onProgress?.call('Connecting to ${candidate.sourceName} ($label)', progressStart);
      try {
        await _downloadSingleFile(
          url: candidate.url,
          target: target,
          minBytes: minBytes,
          hfToken: candidate.usesHfToken ? hfToken : '',
          label: 'Downloading $label [${candidate.sourceName}]',
          progressStart: progressStart,
          progressSpan: progressSpan,
          onProgress: onProgress,
        );
        return;
      } catch (e) {
        if (_downloadCanceled) {
          throw const HttpException('Model download canceled');
        }
        debugPrint('EMBEDDING_MODEL: ${candidate.sourceName} failed for $label: $e');
        failures.add('${candidate.sourceName}: $e');
      }
    }
    final summary = failures.join(' | ');
    if (summary.contains('401') || summary.contains('403')) {
      throw HttpException(
        'Hugging Face gated repo rejected access (401/403) and mirror fallback failed. '
        'Accept the Gemma license at huggingface.co/litert-community/embeddinggemma-300m, '
        'enable gated-repo Read access on your hf_ token, or use IMPORT .TFLITE + TOKENIZER. ($summary)',
      );
    }
    throw HttpException('$label download failed across all mirrors ($summary)');
  }

  static Future<void> cancelDownload() async {
    _downloadCanceled = true;
    _activeClient?.close(force: true);
  }

  static Future<File> importLocalModel(String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) {
      throw const FileSystemException('Selected .tflite file does not exist');
    }
    final len = src.lengthSync();
    if (len < minModelBytes) {
      throw FileSystemException(
        'Selected .tflite is too small (${(len / (1024 * 1024)).toStringAsFixed(1)} MB; expected >= 16 MB)',
      );
    }
    final target = await modelFile();
    await _atomicCopy(src, target, minModelBytes);
    return target;
  }

  static Future<File> importLocalTokenizer(String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) {
      throw const FileSystemException('Selected tokenizer file does not exist');
    }
    final len = src.lengthSync();
    if (len < minTokenizerBytes) {
      throw FileSystemException(
        'Selected tokenizer is too small (${(len / 1024).toStringAsFixed(0)} KB; expected >= 100 KB)',
      );
    }
    final target = await tokenizerFile();
    await _atomicCopy(src, target, minTokenizerBytes);
    return target;
  }

  static Future<void> deleteInstalledWeights() async {
    final m = await modelFile();
    final t = await tokenizerFile();
    if (m.existsSync()) {
      await m.delete();
    }
    if (t.existsSync()) {
      await t.delete();
    }
  }

  static Future<void> _atomicWriteBytes(File target, Uint8List bytes, int minBytes) async {
    final part = File('${target.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    if (part.lengthSync() < minBytes) {
      await part.delete();
      throw const FileSystemException('Staged model write failed size verification');
    }
    await part.rename(target.path);
  }

  static Future<void> _atomicCopy(File src, File target, int minBytes) async {
    if (src.absolute.path == target.absolute.path) return;
    final part = File('${target.path}.part');
    if (part.existsSync()) {
      await part.delete();
    }
    await src.copy(part.path);
    if (!part.existsSync() || part.lengthSync() < minBytes) {
      if (part.existsSync()) await part.delete();
      throw const FileSystemException('Staged copy failed size verification');
    }
    await part.rename(target.path);
  }

  static Future<HttpClientResponse> _openFollowingRedirects(
    HttpClient client,
    Uri initialUri,
    String cleanToken,
  ) async {
    var currentUri = initialUri;
    for (var hop = 0; hop < 10; hop++) {
      if (_downloadCanceled) {
        throw const HttpException('Model download canceled');
      }
      final req = await client.getUrl(currentUri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0 (Android; LiteRT)');
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      if (cleanToken.isNotEmpty && _isHuggingFaceAuthHost(currentUri.host)) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $cleanToken');
      }
      final resp = await req.close();
      final code = resp.statusCode;
      if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        final location = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (location == null || location.isEmpty) {
          throw HttpException('Redirect HTTP $code missing Location header');
        }
        currentUri = currentUri.resolve(location);
        continue;
      }
      return resp;
    }
    throw const HttpException('Too many HTTP redirects while resolving model download');
  }

  static Future<void> _downloadSingleFile({
    required String url,
    required File target,
    required int minBytes,
    required String hfToken,
    required String label,
    required double progressStart,
    required double progressSpan,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _activeClient = client;
    try {
      final resp = await _openFollowingRedirects(client, Uri.parse(url), hfToken);
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode} (gated auth/license required)');
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final contentType = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
      if (contentType.contains('text/html')) {
        await resp.drain<void>();
        throw const HttpException('Received HTML gate page instead of binary model');
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in resp) {
          if (_downloadCanceled) {
            throw const HttpException('Model download canceled');
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final frac = (received / total).clamp(0.0, 1.0);
            onProgress?.call(label, progressStart + frac * progressSpan);
          } else {
            onProgress?.call('$label (${(received / (1024 * 1024)).toStringAsFixed(1)} MB)', progressStart);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (!part.existsSync() || part.lengthSync() < minBytes) {
        final got = part.existsSync() ? part.lengthSync() : 0;
        if (part.existsSync()) await part.delete();
        throw FileSystemException('Incomplete payload ($got bytes)');
      }
      await part.rename(target.path);
    } catch (e) {
      if (part.existsSync()) {
        try {
          await part.delete();
        } catch (delErr) {
          debugPrint('EMBEDDING_MODEL: failed to clean partial file: $delErr');
        }
      }
      if (_downloadCanceled) {
        throw const HttpException('Model download canceled');
      }
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
    }
  }
}
