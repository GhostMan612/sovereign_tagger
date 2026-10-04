// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
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
  static const int minBytes = 16000;

  SpeechEngine _engine;
  VoicePhase _phase = VoicePhase.idle;
  String _status = '';
  double _progress = 0.0;
  Timer? _timer;
  String? _pendingPath;

  VoicePhase get phase => _phase;
  String get status => _status;
  double get progress => _progress;
  SpeechEngine get engine => _engine;
  bool get isBusy => _phase != VoicePhase.idle;
  bool get isListening => _phase == VoicePhase.listening;

  void useEngine(String id) {
    final next = SpeechEngines.byId(id);
    if (next == null) return;
    _engine = next;
    _status = '';
    _progress = 0.0;
    notifyListeners();
  }

  Future<String?> toggle() async {
    if (_phase == VoicePhase.listening) return _stopAndTranscribe();
    if (isBusy) return null;
    return _start();
  }

  Future<String?> _start() async {
    _status = 'WAKING THE MIC...';
    _progress = 0.0;
    _phase = VoicePhase.preparing;
    notifyListeners();

    try {
      if (await PcmRecorder.isRecording()) {
        return _fail('THE OTHER RECORDER IS BUSY. STOP IT FIRST.');
      }

      if (!await PcmRecorder.hasPermission()) {
        final granted = await Permission.microphone.request();
        if (!granted.isGranted) return _fail('MIC ACCESS DENIED.');
      }

      if (!await _engine.isReady()) {
        final mb = (_engine.payloadBytes / 1000000).round();
        _status = 'FETCHING ${_engine.label} (${mb}MB, ONCE)...';
        notifyListeners();
        await _engine.prepare(onProgress: (stage, p) {
          _progress = p;
          _status = '${_engine.label}: $stage ${(p * 100).toStringAsFixed(0)}%';
          notifyListeners();
        });
      }

      final tempDir = await _storage.invokeMethod<String>('getTempDirectory');
      if (tempDir == null || tempDir.isEmpty) {
        return _fail('NO TEMP DIRECTORY.');
      }

      final path = '$tempDir/ghost_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      final ok = await PcmRecorder.start(path: path, sampleRate: sampleRate, channels: 1);
      if (!ok) return _fail('MIC ENGINE FAILED TO ARM.');

      _pendingPath = path;
      _status = 'LISTENING... ${maxDuration.inSeconds}s MAX';
      _progress = 0.0;
      _phase = VoicePhase.listening;
      notifyListeners();

      _timer?.cancel();
      _timer = Timer(maxDuration, () {
        if (_phase == VoicePhase.listening) {
          unawaited(_stopAndTranscribe());
        }
      });
      return null;
    } catch (e) {
      return _fail('MIC FAULT: $e');
    }
  }

  Future<String?> _stopAndTranscribe() async {
    _timer?.cancel();
    _timer = null;
    _phase = VoicePhase.transcribing;
    _status = '${_engine.label} IS THINKING...';
    _progress = 0.0;
    notifyListeners();

    String? path;
    try {
      path = await PcmRecorder.stop();
      final recorded = path ?? _pendingPath;
      if (recorded == null || !File(recorded).existsSync()) {
        return _fail('NOTHING WAS RECORDED.');
      }
      if (File(recorded).lengthSync() < minBytes) {
        return _fail('DID NOT HEAR ANYTHING.');
      }
      final text = await _engine.transcribe(recorded);
      _reset();
      return text;
    } catch (e) {
      return _fail(_describe(e));
    } finally {
      final victim = path ?? _pendingPath;
      _pendingPath = null;
      if (victim != null) {
        try {
          final f = File(victim);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    if (_phase == VoicePhase.listening) {
      try {
        await PcmRecorder.stop();
      } catch (_) {}
    }
    final victim = _pendingPath;
    _pendingPath = null;
    if (victim != null) {
      try {
        final f = File(victim);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    _reset();
  }

  String _describe(Object e) {
    final raw = e.toString();
    if (raw.contains('no speech recognised')) return 'DID NOT CATCH ANY WORDS. TRY AGAIN.';
    if (raw.contains('not wired yet')) return '${_engine.label} IS NOT WIRED YET.';
    if (raw.contains('MissingPluginException') || raw.contains('NotImplementedError')) {
      return 'VOICE ENGINE UNAVAILABLE ON THIS BUILD.';
    }
    if (raw.contains('whisper filter returned')) return 'TRANSCRIPTION FAILED.';
    if (raw.length > 140) return 'VOICE FAULT: ${raw.substring(0, 140)}';
    return 'VOICE FAULT: $raw';
  }

  String? _fail(String message) {
    _status = message;
    _phase = VoicePhase.idle;
    _progress = 0.0;
    notifyListeners();
    return null;
  }

  void _reset() {
    _phase = VoicePhase.idle;
    _status = '';
    _progress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}