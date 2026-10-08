// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates The Past and The Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pcm_recorder.dart';
import 'speech_to_text.dart';

enum VoicePhase { idle, preparing, listening, transcribing }

class VoiceInput extends ChangeNotifier {
  VoiceInput({SpeechEngine? engine}) : _engine = engine ?? SpeechEngines.preferred;

  static const MethodChannel _storage = MethodChannel('com.sovereign.tagger/storage');
  static const int sampleRate = 16000;
  static const Duration maxDuration = Duration(seconds: 12);
  static const int bytesPerSecond = sampleRate * 2;
  static const int minBytesForOneSecond = bytesPerSecond;

  SpeechEngine _engine;
  VoicePhase _phase = VoicePhase.idle;
  String _status = '';
  double _progress = 0.0;
  Timer? _timer;
  String? _pendingPath;
  bool _cancelRequested = false;
  bool _micBlocked = false;
  bool _disposed = false;

  VoicePhase get phase => _phase;
  String get status => _status;
  double get progress => _progress;
  SpeechEngine get engine => _engine;
  bool get isBusy => _phase != VoicePhase.idle;
  bool get isListening => _phase == VoicePhase.listening;
  bool get micBlocked => _micBlocked;

  void useEngine(String id) {
    if (isBusy) return;
    final next = SpeechEngines.byId(id);
    if (next == null || identical(next, _engine)) return;
    _engine = next;
    _status = '';
    _progress = 0.0;
    _safeNotify();
  }

  Future<String?> toggle() async {
    if (_phase == VoicePhase.listening) return _stopAndTranscribe();
    if (isBusy) {
      await cancel();
      return null;
    }
    if (_micBlocked) {
      // _micBlocked latches, so re-probe before bouncing the user to Settings.
      // Otherwise granting the mic there dead-ends: every tap would re-open
      // Settings until the app was restarted.
      if (await PcmRecorder.hasPermission()) {
        _micBlocked = false;
        return _start();
      }
      _status = 'OPENING APP SETTINGS...';
      _safeNotify();
      await openAppSettings();
      return null;
    }
    return _start();
  }

  Future<String?> _start() async {
    _cancelRequested = false;
    _status = 'WAKING THE MIC...';
    _progress = 0.0;
    _phase = VoicePhase.preparing;
    _safeNotify();

    String? path;
    try {
      if (await PcmRecorder.isRecording()) {
        return _fail('THE OTHER RECORDER IS BUSY. STOP IT FIRST.');
      }

      final ok = await _ensureMic();
      if (!ok) return null;
      if (_cancelRequested) return _abandon();

      if (!await _engine.isReady()) {
        if (_cancelRequested || _disposed) return _abandon();
        final mb = (_engine.payloadBytes / 1000000).round();
        _status = 'FETCHING ${_engine.label} (${mb}MB, ONCE)...';
        _safeNotify();
        await _engine.prepare(onProgress: (stage, p) {
          if (_cancelRequested || _disposed) return;
          _progress = p;
          _status = '${_engine.label}: $stage ${(p * 100).toStringAsFixed(0)}%';
          _safeNotify();
        });
        if (_cancelRequested || _disposed) return _abandon();
      }

      final tempDir = await _storage.invokeMethod<String>('getTempDirectory');
      if (_cancelRequested || _disposed) return _abandon();
      if (tempDir == null || tempDir.isEmpty) {
        return _fail('NO TEMP DIRECTORY.');
      }

      path = '$tempDir/ghost_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      final armed = await PcmRecorder.start(path: path, sampleRate: sampleRate, channels: 1);
      if (!armed) {
        await _deleteQuietly(path);
        path = null;
        return _fail('MIC ENGINE FAILED TO ARM.');
      }
      if (_cancelRequested || _disposed) {
        await PcmRecorder.stop();
        await _deleteQuietly(path);
        path = null;
        return _abandon();
      }

      _pendingPath = path;
      _status = 'LISTENING... ${maxDuration.inSeconds}s MAX';
      _progress = 0.0;
      _phase = VoicePhase.listening;
      _safeNotify();

      _timer?.cancel();
      _timer = Timer(maxDuration, () {
        if (_phase == VoicePhase.listening) {
          unawaited(_stopAndTranscribe());
        }
      });
      return null;
    } catch (e) {
      await _deleteQuietly(path);
      if (_disposed || _cancelRequested) return null;
      return _fail('MIC FAULT: $e');
    }
  }

  Future<bool> _ensureMic() async {
    if (await PcmRecorder.hasPermission()) {
      _micBlocked = false;
      return true;
    }
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _micBlocked = false;
      return true;
    }
    _micBlocked = status.isPermanentlyDenied || status.isRestricted;
    _fail(_micBlocked
        ? 'MIC BLOCKED. TAP MIC AGAIN TO OPEN APP SETTINGS.'
        : 'MIC ACCESS DENIED.');
    return false;
  }

  Future<String?> _stopAndTranscribe() async {
    _timer?.cancel();
    _timer = null;
    _phase = VoicePhase.transcribing;
    _status = '${_engine.label} IS THINKING...';
    _progress = 0.0;
    _safeNotify();

    String? path;
    try {
      path = await PcmRecorder.stop();
      final recorded = path ?? _pendingPath;
      if (_cancelRequested || _disposed) return null;

      if (recorded == null || !File(recorded).existsSync()) {
        return _fail('NOTHING WAS RECORDED.');
      }
      if (File(recorded).lengthSync() < minBytesForOneSecond) {
        return _fail('DID NOT HEAR ANYTHING.');
      }

      final text = await _engine.transcribe(recorded);
      if (_cancelRequested || _disposed) return null;

      final trimmed = text.trim();
      if (trimmed.isEmpty || isLikelyHallucination(trimmed)) {
        return _fail('DID NOT CATCH ANY WORDS. TRY AGAIN.');
      }
      _reset();
      return trimmed;
    } catch (e) {
      if (_disposed || _cancelRequested) return null;
      return _fail(_describe(e));
    } finally {
      final victim = path ?? _pendingPath;
      _pendingPath = null;
      await _deleteQuietly(victim);
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_engine.cancel());
    if (_phase == VoicePhase.listening) {
      try {
        await PcmRecorder.stop();
      } catch (_) {}
    }
    final victim = _pendingPath;
    _pendingPath = null;
    await _deleteQuietly(victim);
    if (_disposed) return;
    _reset();
  }

  String _describe(Object e) {
    final raw = e.toString();
    if (raw.contains('no speech recognized')) return 'DID NOT CATCH ANY WORDS. TRY AGAIN.';
    if (raw.contains('not wired yet')) return '${_engine.label} IS NOT WIRED YET.';
    if (raw.contains('MissingPluginException') || raw.contains('NotImplementedError')) {
      return 'VOICE ENGINE UNAVAILABLE ON THIS BUILD.';
    }
    if (raw.contains('whisper filter returned')) return 'TRANSCRIPTION FAILED.';
    if (raw.length > 140) return 'VOICE FAULT: ${raw.substring(0, 140)}';
    return 'VOICE FAULT: $raw';
  }

  String? _abandon() {
    _timer?.cancel();
    _timer = null;
    _pendingPath = null;
    if (_disposed) return null;
    _reset();
    return null;
  }

  String? _fail(String message) {
    _status = message;
    _phase = VoicePhase.idle;
    _progress = 0.0;
    _safeNotify();
    return null;
  }

  void _reset() {
    _phase = VoicePhase.idle;
    _status = '';
    _progress = 0.0;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  static Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    _timer?.cancel();
    _timer = null;
    unawaited(cancel());
    super.dispose();
  }
}