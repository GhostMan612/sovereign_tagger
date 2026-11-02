// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class EmbeddingModel {
  static const String modelFileName = 'embeddinggemma-300m_seq256_mixed-precision.tflite';
  static const String tokenizerFileName = 'sentencepiece.model';

  static const String repoUrl = 'https://huggingface.co/litert-community/embeddinggemma-300m';
  static const String modelDownloadUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300m_seq256_mixed-precision.tflite';
  static const String tokenizerDownloadUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

  static const int minModelBytes = 16 * 1024 * 1024;
  static const int minTokenizerBytes = 100 * 1024;

  static bool _downloadCanceled = false;
  static HttpClient? _activeClient;

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
      try {
        final data = await rootBundle.load('assets/models/$modelFileName');
        if (data.lengthInBytes >= minModelBytes) {
          onProgress?.call('Extracting bundled EmbeddingGemma model', 0.5);
          await _atomicWriteBytes(
            mTarget,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            minModelBytes,
          );
        }
      } catch (e) {
        debugPrint('EMBEDDING_MODEL: no bundled model asset ($e)');
      }
    }
  }

  static Future<void> download({
    String? hfToken,
    void Function(String stage, double progress)? onProgress,
  }) async {
    _downloadCanceled = false;
    await tryExtractBundledAssets(onProgress: onProgress);

    final tTarget = await tokenizerFile();
    if (!tTarget.existsSync() || tTarget.lengthSync() < minTokenizerBytes) {
      await _downloadSingleFile(
        url: tokenizerDownloadUrl,
        target: tTarget,
        minBytes: minTokenizerBytes,
        hfToken: hfToken,
        label: 'Downloading SentencePiece tokenizer',
        progressStart: 0.0,
        progressSpan: 0.06,
        onProgress: onProgress,
      );
    }

    final mTarget = await modelFile();
    if (!mTarget.existsSync() || mTarget.lengthSync() < minModelBytes) {
      await _downloadSingleFile(
        url: modelDownloadUrl,
        target: mTarget,
        minBytes: minModelBytes,
        hfToken: hfToken,
        label: 'Downloading EmbeddingGemma-300M (.tflite)',
        progressStart: 0.06,
        progressSpan: 0.94,
        onProgress: onProgress,
      );
    }
    onProgress?.call('EmbeddingGemma files verified', 1.0);
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

  static Future<void> _downloadSingleFile({
    required String url,
    required File target,
    required int minBytes,
    required String? hfToken,
    required String label,
    required double progressStart,
    required double progressSpan,
    void Function(String stage, double progress)? onProgress,
  }) async {
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _activeClient = client;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0');
      final cleanToken = hfToken?.trim() ?? '';
      if (cleanToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $cleanToken');
      }
      final resp = await req.close();
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw HttpException(
          'HF license gate (HTTP ${resp.statusCode}). Accept Gemma license on huggingface.co/litert-community/embeddinggemma-300m and paste a Read Token, or use IMPORT .TFLITE + TOKENIZER.',
        );
      }
      if (resp.statusCode != 200) {
        throw HttpException('$label failed: HTTP ${resp.statusCode}');
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
        if (part.existsSync()) await part.delete();
        throw FileSystemException('$label incomplete (${part.existsSync() ? part.lengthSync() : 0} bytes)');
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
