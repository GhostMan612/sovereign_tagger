// =========================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates The Past and The Past is Always Present.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pcm_recorder.dart';
import 'speech_to_text.dart';

enum VoicePhase {
  idle,
  preparing,
  listening,
  stopping,
  modelLoading,
  transcribing,
  completed,
  failed,
  canceled,
}

class VoiceInput extends ChangeNotifier {
  VoiceInput({SpeechEngine? engine}) : _engine = engine ?? SpeechEngines.preferred;

  static const MethodChannel _storage = MethodChannel('com.sovereign.tagger/storage');
  static const int sampleRate = 16000;
  static const Duration maxDuration = Duration(seconds: 12);
  static const int bytesPerSecond = sampleRate * 2;
  static const int minBytesForOneSecond = bytesPerSecond;

  /// Optional hooks wired by AppGhostWorld to duck AudioService volume while listening
  /// so music playback doesn't bleed into the microphone capture.
  static Future<void> Function()? onRecordingStarted;
  static Future<void> Function()? onRecordingStopped;

  SpeechEngine _engine;
  VoicePhase _phase = VoicePhase.idle;
  String _status = '';
  double _progress = 0.0;
  Timer? _timer;
  String? _pendingPath;
  bool _cancelRequested = false;
  bool _micBlocked = false;
  bool _disposed = false;
  int _requestId = 0;

  final StreamController<String> _transcriptController = StreamController<String>.broadcast();
  Stream<String> get onTranscript => _transcriptController.stream;

  VoicePhase get phase => _phase;
  String get status => _status;
  double get progress => _progress;
  SpeechEngine get engine => _engine;
  bool get isBusy =>
      _phase == VoicePhase.preparing ||
      _phase == VoicePhase.listening ||
      _phase == VoicePhase.stopping ||
      _phase == VoicePhase.modelLoading ||
      _phase == VoicePhase.transcribing;
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
    _requestId++;
    _cancelRequested = false;
    _status = 'PREPARING...';
    _progress = 0.0;
    _phase = VoicePhase.preparing;
    _safeNotify();

    final hasPerm = await PcmRecorder.hasPermission();
    if (!hasPerm) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied || status.isRestricted) {
          _micBlocked = true;
        }
        _status = 'MIC PERMISSION DENIED';
        _phase = VoicePhase.failed;
        _safeNotify();
        return null;
      }
    }
    _micBlocked = false;

    final baseDir = await _fetchAppDocDir();
    if (baseDir == null) {
      _status = 'STORAGE ERROR';
      _phase = VoicePhase.failed;
      _safeNotify();
      return null;
    }

    try {
      await onRecordingStarted?.call();
    } catch (_) {}

    final path = '$baseDir/voice_input.wav';
    _deleteFile(path);
    final ok = await PcmRecorder.start(path: path, sampleRate: sampleRate, channels: 1);
    if (!ok) {
      try {
        await onRecordingStopped?.call();
      } catch (_) {}
      _status = 'RECORDING FAILED TO START';
      _phase = VoicePhase.failed;
      _safeNotify();
      return null;
    }

    _pendingPath = path;
    _phase = VoicePhase.listening;
    _status = 'LISTENING...';
    _safeNotify();

    _timer?.cancel();
    _timer = Timer(maxDuration, () async {
      if (_phase == VoicePhase.listening) {
        await _stopAndTranscribe();
      }
    });

    return null;
  }

  Future<String?> _stopAndTranscribe() async {
    final currentReq = _requestId;
    _timer?.cancel();
    _timer = null;

    final path = _pendingPath;
    _pendingPath = null;

    if (path == null) {
      try {
        await onRecordingStopped?.call();
      } catch (_) {}
      _phase = VoicePhase.idle;
      _status = '';
      _safeNotify();
      return null;
    }

    _phase = VoicePhase.stopping;
    _status = 'STOPPING RECORDER...';
    _safeNotify();

    await PcmRecorder.stop();
    try {
      await onRecordingStopped?.call();
    } catch (_) {}

    if (_cancelRequested || currentReq != _requestId) {
      _deleteFile(path);
      _phase = VoicePhase.canceled;
      _status = 'CANCELED';
      _safeNotify();
      return null;
    }

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < minBytesForOneSecond) {
      _deleteFile(path);
      _phase = VoicePhase.failed;
      _status = 'SPEAK LONGER (MIN 1 SECOND)';
      _safeNotify();
      return null;
    }

    if (!await _engine.isReady()) {
      _phase = VoicePhase.modelLoading;
      _status = 'MODEL LOADING...';
      _safeNotify();
      try {
        await _engine.prepare();
      } catch (e) {
        _deleteFile(path);
        _phase = VoicePhase.failed;
        _status = 'MODEL LOAD FAILED: $e';
        _safeNotify();
        return null;
      }
    }

    if (_cancelRequested || currentReq != _requestId) {
      _deleteFile(path);
      _phase = VoicePhase.canceled;
      _status = 'CANCELED';
      _safeNotify();
      return null;
    }

    _phase = VoicePhase.transcribing;
    _status = 'TRANSCRIBING...';
    _progress = 0.5;
    _safeNotify();

    try {
      final result = await _engine.transcribe(path);
      _deleteFile(path);

      if (_cancelRequested || currentReq != _requestId) {
        _phase = VoicePhase.canceled;
        _status = 'CANCELED';
        _safeNotify();
        return null;
      }

      _progress = 1.0;

      if (result.trim().isEmpty) {
        _phase = VoicePhase.failed;
        _status = 'NO SPEECH DETECTED';
        _safeNotify();
        return null;
      }

      final normalized = _normalizeDomainTranscript(result.trim());
      _phase = VoicePhase.completed;
      _status = normalized;
      _transcriptController.add(normalized);
      _safeNotify();
      return normalized;
    } catch (e) {
      _deleteFile(path);
      if (_cancelRequested || currentReq != _requestId) {
        _phase = VoicePhase.canceled;
        _status = 'CANCELED';
      } else {
        _phase = VoicePhase.failed;
        _status = 'TRANSCRIBE ERROR: $e';
      }
      _safeNotify();
      return null;
    }
  }

  /// Corrects common speech recognition homophones for Sovereign Tagger terminology.
  static String _normalizeDomainTranscript(String raw) {
    var out = raw;
    const replacements = <String, String>{
      r'\bforged\b': 'forge',
      r'\bford\b': 'forge',
      r'\bfourth tab\b': 'forge tab',
      r'\bgrab her\b': 'grabber',
      r'\bgrab a\b': 'grabber',
      r'\blrc lib\b': 'lrclib',
      r'\bl r c lib\b': 'lrclib',
      r'\bacr cloud\b': 'acrcloud',
      r'\ba c r cloud\b': 'acrcloud',
      r'\breplay game\b': 'replaygain',
      r'\breplay gain\b': 'replaygain',
      r'\bid 3\b': 'id3',
    };
    replacements.forEach((pattern, target) {
      out = out.replaceAll(RegExp(pattern, caseSensitive: false), target);
    });
    return out;
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    _requestId++;
    _timer?.cancel();
    _timer = null;

    if (_phase == VoicePhase.listening || _phase == VoicePhase.stopping) {
      await PcmRecorder.stop();
    }
    try {
      await onRecordingStopped?.call();
    } catch (_) {}

    if (_pendingPath != null) {
      _deleteFile(_pendingPath!);
      _pendingPath = null;
    }

    try {
      await _engine.cancel();
    } catch (_) {}

    _phase = VoicePhase.canceled;
    _status = 'CANCELED';
    _progress = 0.0;
    _safeNotify();
  }

  Future<String?> _fetchAppDocDir() async {
    try {
      final String? res = await _storage.invokeMethod<String>('getAppDocDir');
      if (res != null && res.isNotEmpty && Directory(res).existsSync()) {
        return res;
      }
    } catch (_) {}

    try {
      final String? res = await _storage.invokeMethod<String>('getTempDirectory');
      if (res != null && res.isNotEmpty && Directory(res).existsSync()) {
        return res;
      }
    } catch (_) {}

    try {
      final docDir = await getApplicationDocumentsDirectory();
      if (docDir.existsSync()) return docDir.path;
    } catch (_) {}

    try {
      final tmpDir = await getTemporaryDirectory();
      if (tmpDir.existsSync()) return tmpDir.path;
    } catch (_) {}

    try {
      final sysTmp = Directory.systemTemp;
      if (sysTmp.existsSync()) return sysTmp.path;
    } catch (_) {}

    return null;
  }

  void _deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_phase == VoicePhase.listening) {
      PcmRecorder.stop();
      onRecordingStopped?.call();
    }
    if (_pendingPath != null) {
      _deleteFile(_pendingPath!);
    }
    _transcriptController.close();
    super.dispose();
  }
}
