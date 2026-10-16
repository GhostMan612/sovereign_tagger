// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter/services.dart';

import 'ffmpeg_executor.dart';
import 'whisper_model.dart';
import 'whistle_model.dart';

abstract class SpeechEngine {
  const SpeechEngine();

  String get id;
  String get label;
  int get payloadBytes;
  Future<bool> isReady();
  Future<void> prepare({void Function(String stage, double progress)? onProgress});
  Future<String> transcribe(String wavPath, {String language = 'en'});
  Future<void> cancel() async {}
}

class WhistleKeywords {
  static const String domainKeywords =
      'Sovereign Tagger\n'
      'Ghost\n'
      'Grabber\n'
      'Forge\n'
      'Workbench\n'
      'ReplayGain\n'
      'LRCLIB\n'
      'Genius\n'
      'ACRCloud\n'
      'metadata\n'
      'album artwork\n'
      'lyrics\n'
      'playlist\n'
      'equalizer';
}

class WhistleEngine implements SpeechEngine {
  WhistleEngine();

  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/whistle');
  static bool? _cachedSupported;

  @override
  String get id => 'whistle';

  @override
  String get label => 'WHISTLE';

  @override
  int get payloadBytes => WhistleModel.minBytes;

  static Future<bool> isSupported() async {
    if (_cachedSupported != null) return _cachedSupported!;
    try {
      _cachedSupported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _cachedSupported = false;
    }
    return _cachedSupported!;
  }

  @override
  Future<bool> isReady() async {
    final supported = await isSupported();
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> prepare({void Function(String stage, double progress)? onProgress}) async {
    final supported = await isSupported();
    if (!supported) {
      throw UnsupportedError('Whistle native engine is not supported on this device architecture');
    }
    final modelFile = await WhistleModel.ensure(onProgress: onProgress);
    onProgress?.call('Loading Whistle into memory', 0.9);
    final loaded = await _channel.invokeMethod<bool>('loadModel', {'path': modelFile.path});
    if (loaded != true) {
      throw StateError('Failed to load Whistle weights into native runtime');
    }
    onProgress?.call('Whistle ready', 1.0);
  }

  @override
  Future<void> cancel() async {
    await WhistleModel.cancelPrepare();
  }

  @override
  Future<String> transcribe(String wavPath, {String language = 'en'}) async {
    final supported = await isSupported();
    if (!supported) {
      throw UnsupportedError('Whistle is not supported on this device architecture');
    }
    if (!await isReady()) {
      await prepare();
    }
    final String? res = await _channel.invokeMethod<String>('transcribe', {
      'wavPath': wavPath,
      'language': language,
      'keywords': WhistleKeywords.domainKeywords,
    });
    if (res == null || res.trim().isEmpty) {
      throw StateError('no speech recognized');
    }
    return res.trim();
  }
}

class WhisperFfmpegEngine implements SpeechEngine {
  WhisperFfmpegEngine();

  String? _activeTranscriptionDescription;

  @override
  String get id => 'whisper';

  @override
  String get label => 'WHISPER';

  @override
  int get payloadBytes => WhisperModel.minBytes;

  @override
  Future<bool> isReady() => WhisperModel.isReady();

  @override
  Future<void> prepare({void Function(String stage, double progress)? onProgress}) async {
    await WhisperModel.ensure(onProgress: onProgress);
  }

  @override
  Future<void> cancel() async {
    await WhisperModel.cancelPrepare();
    if (_activeTranscriptionDescription != null) {
      FFmpegExecutor.cancelCurrent(description: _activeTranscriptionDescription);
    }
  }

  @override
  Future<String> transcribe(String wavPath, {String language = 'en'}) async {
    final model = await WhisperModel.ensure();
    final srt = File('$wavPath.srt');
    final description = 'voice_whisper_${DateTime.now().microsecondsSinceEpoch}';
    _activeTranscriptionDescription = description;

    try {
      final session = await FFmpegExecutor.execute(
        '-y -i "$wavPath" -vn '
        "-af \"whisper=model='${model.path}':language=$language:destination='${srt.path}':format=srt\" "
        '-f null -',
        description: description,
      );

      if (!ReturnCode.isSuccess(session.getReturnCode()) || !srt.existsSync()) {
        throw StateError('whisper filter returned ${session.getReturnCode()}');
      }

      final text = srtToPlainText(await srt.readAsString());
      if (text.trim().isEmpty || isLikelyHallucination(text.trim())) {
        throw StateError('no speech recognized');
      }
      return text;
    } finally {
      if (_activeTranscriptionDescription == description) {
        _activeTranscriptionDescription = null;
      }
      try {
        if (srt.existsSync()) await srt.delete();
      } catch (_) {}
    }
  }
}

String srtToPlainText(String srt) {
  final lines = srt.split(RegExp(r'\r?\n'));
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    if (line.contains('-->')) continue;
    if (RegExp(r'^\d+$').hasMatch(line) && _nextIsTiming(lines, i)) continue;
    final cleaned = line
        .replaceAll(RegExp(r'<\|[^>]*\|>'), '')
        .replaceAll(RegExp(r'\[_?[A-Z0-9_ ]+\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) continue;
    out.add(cleaned);
  }
  return out.join(' ');
}

bool _nextIsTiming(List<String> lines, int index) {
  for (var j = index + 1; j < lines.length; j++) {
    final probe = lines[j].trim();
    if (probe.isEmpty) continue;
    return probe.contains('-->');
  }
  return false;
}

const Set<String> _silencePhrases = {
  'thank you',
  'thanks',
  'thank you very much',
  'thanks for watching',
  'thanks for watching!',
  'please subscribe',
  'please subscribe to my channel',
  'subtitles by the amaraorg community',
  'subtitles by the amaraorg community translation team',
  'transcription by castingwords',
  'wwwamaraorg',
  'bye',
  'bye bye',
  'music',
  'applause',
  'silence',
  'blank audio',
  'inaudible',
};

bool isLikelyHallucination(String text) {
  final normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return true;
  return _silencePhrases.contains(normalized);
}

class SpeechEngines {
  const SpeechEngines._();

  static final WhistleEngine _whistle = WhistleEngine();
  static final WhisperFfmpegEngine _whisper = WhisperFfmpegEngine();

  static final List<SpeechEngine> all = [_whistle, _whisper];

  static SpeechEngine get preferred => _whistle;

  static SpeechEngine? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }
}
