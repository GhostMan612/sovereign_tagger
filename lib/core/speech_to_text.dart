// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

import 'ffmpeg_executor.dart';
import 'whisper_model.dart';

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

class SpeechEngineNotWired implements SpeechEngine {
  const SpeechEngineNotWired({
    required this.id,
    required this.label,
    required this.payloadBytes,
    required this.wiring,
  });

  @override
  final String id;
  @override
  final String label;
  @override
  final int payloadBytes;
  final String wiring;

  @override
  Future<bool> isReady() async => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> prepare({void Function(String stage, double progress)? onProgress}) async {
    throw UnsupportedError('$label is not wired yet. Needs: $wiring');
  }

  @override
  Future<String> transcribe(String wavPath, {String language = 'en'}) async {
    throw UnsupportedError('$label is not wired yet. Needs: $wiring');
  }
}

class WhistleEngine extends SpeechEngineNotWired {
  const WhistleEngine()
      : super(
          id: 'whistle',
          label: 'WHISTLE',
          payloadBytes: 16900000,
          wiring: 'NDK + CMake + JNI bridge to needle_load/needle_transcribe, '
              'plus whistle.cact from huggingface.co/Cactus-Compute/whistle',
        );
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

  static final List<SpeechEngine> all = [WhisperFfmpegEngine(), WhistleEngine()];

  static SpeechEngine get preferred => WhisperFfmpegEngine();

  static SpeechEngine? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }
}