// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'model_digest.dart';

class WhistleModel {
  static const String fileName = 'whistle.cact';
  static const String downloadUrl = 'https://huggingface.co/Cactus-Compute/whistle/resolve/main/whistle.cact';
  static const int expectedBytes = 16919407;
  static const String expectedSha256 = 'b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb';

  static bool _prepareCanceled = false;
  static HttpClient? _activeClient;
  static Future<File>? _pendingEnsure;

  static Future<File> file() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/whistle_model');
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
        onProgress?.call('Verifying bundled Whistle model', 0);
        await ModelDigest.installBytes(
          target,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          expectedBytes: expectedBytes,
          sha256Hex: expectedSha256,
        );
        return target;
      }
    } on FlutterError {
      // APKs without the bundled model use the authenticated upstream digest.
    }

    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    _activeClient = client;
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'SovereignTagger/2.0');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Whistle model download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response) {
          if (_prepareCanceled) throw const HttpException('Model preparation canceled');
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call('Downloading Whistle model', received / total);
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
        throw const HttpException('Model preparation canceled');
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
