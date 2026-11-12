// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'model_digest.dart';

class WhisperModel {
  static const String fileName = 'ggml-base.en.bin';
  static const String downloadUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';
  static const int expectedBytes = 147964211;
  static const int minBytes = expectedBytes;
  static const String expectedSha256 = 'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002';

  static bool _prepareCanceled = false;
  static HttpClient? _activeClient;
  static Future<File>? _pendingEnsure;

  static Future<File> file() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/whisper_model');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$fileName');
  }

  static Future<bool> isReady() async {
    final f = await file();
    return ModelDigest.matches(f, bytes: expectedBytes, sha256Hex: expectedSha256);
  }

  static Future<File> ensure({void Function(String stage, double progress)? onProgress}) {
    return _pendingEnsure ??= _ensureOnce(onProgress).whenComplete(() => _pendingEnsure = null);
  }

  static Future<File> _ensureOnce(void Function(String stage, double progress)? onProgress) async {
    final target = await file();
    if (await ModelDigest.matches(target, bytes: expectedBytes, sha256Hex: expectedSha256)) return target;
    _prepareCanceled = false;

    try {
      final data = await rootBundle.load('assets/models/$fileName');
      if (data.lengthInBytes == expectedBytes) {
        onProgress?.call('Verifying bundled Whisper model', 0);
        await ModelDigest.installBytes(
          target,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          expectedBytes: expectedBytes,
          sha256Hex: expectedSha256,
        );
        return target;
      }
    } on FlutterError {
      // Most installations fetch Whisper on demand rather than bundling it.
    }

    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _activeClient = client;
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0');
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('Model download failed: HTTP ${response.statusCode}');
      final total = response.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response) {
          if (_prepareCanceled) throw HttpException('Model preparation canceled');
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call('Downloading model', received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await ModelDigest.installVerifiedPart(
        target,
        part,
        expectedBytes: expectedBytes,
        sha256Hex: expectedSha256,
      );
      _prepareCanceled = false;
      return target;
    } catch (e) {
      if (_prepareCanceled) {
        try {
          if (part.existsSync()) part.deleteSync();
        } catch (_) {}
        throw HttpException('Model preparation canceled');
      }
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  static Future<void> cancelPrepare() async {
    _prepareCanceled = true;
    _activeClient?.close(force: true);
  }
}
