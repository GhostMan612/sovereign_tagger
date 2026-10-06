// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class WhisperModel {
  static const String fileName = 'ggml-base.en.bin';
  static const String downloadUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';
  static const int minBytes = 140000000;

  static bool _prepareCanceled = false;
  static HttpClient? _activeClient;

  static Future<File> file() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/whisper_model');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$fileName');
  }

  static Future<bool> isReady() async {
    final f = await file();
    return f.existsSync() && f.lengthSync() >= minBytes;
  }

  static Future<File> ensure({void Function(String stage, double progress)? onProgress}) async {
    final target = await file();
    if (target.existsSync() && target.lengthSync() >= minBytes) return target;
    _prepareCanceled = false;

    try {
      final data = await rootBundle.load('assets/models/$fileName');
      if (data.lengthInBytes >= minBytes) {
        onProgress?.call('Extracting bundled model', 0);
        await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
        return target;
      }
    } catch (_) {}

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
      if (part.lengthSync() < minBytes) throw const FileSystemException('Model download incomplete');
      await part.rename(target.path);
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
