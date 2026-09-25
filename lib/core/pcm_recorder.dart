// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';

class PcmRecorder {
  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/pcm_recorder');
  static const EventChannel _eventChannel = EventChannel('com.sovereign.tagger/pcm_events');

  static Stream<int> amplitudes() {
    return _eventChannel.receiveBroadcastStream().map((d) => (d as num).toInt());
  }

  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isRecording() async {
    try {
      return await _channel.invokeMethod<bool>('isRecording') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start({required String path, int sampleRate = 48000, int channels = 1}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('startRecording', {
        'path': path,
        'sampleRate': sampleRate,
        'channels': channels,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> stop() async {
    try {
      return await _channel.invokeMethod<String>('stopRecording');
    } catch (_) {
      return null;
    }
  }
}
