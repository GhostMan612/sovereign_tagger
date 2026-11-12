// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/speech_fallback.dart';
import 'package:sovereign_tagger/core/speech_to_text.dart';

class StubSpeechEngine implements SpeechEngine {
  StubSpeechEngine({
    required this.id,
    this.ready = true,
    this.failPrepare = false,
    this.failTranscribe = false,
    this.transcript = 'forge audio',
  });

  @override
  final String id;
  final bool ready;
  final bool failPrepare;
  final bool failTranscribe;
  final String transcript;
  int calls = 0;
  int prepares = 0;
  String? usedWavPath;

  @override
  String get label => id.toUpperCase();

  @override
  int get payloadBytes => 1;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<void> prepare({void Function(String, double)? onProgress}) async {
    prepares++;
    if (failPrepare) throw StateError('cannot load engine');
  }

  @override
  Future<String> transcribe(String wavPath, {String language = 'en'}) async {
    calls++;
    usedWavPath = wavPath;
    if (failTranscribe) throw StateError('transcription failed');
    return transcript;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('successful Whistle transcription never invokes Whisper', () async {
    final primary = StubSpeechEngine(id: 'whistle');
    final secondary = StubSpeechEngine(id: 'whisper');
    final result = await SpeechFallback.transcribe(
      '/cache/test.wav',
      primary: primary,
      secondary: secondary,
      cancelled: () => false,
    );
    expect(result, 'forge audio');
    expect(primary.calls, 1);
    expect(secondary.calls, 0);
  });

  test('Whistle transcription exception retries installed Whisper exactly once', () async {
    final primary = StubSpeechEngine(id: 'whistle', failTranscribe: true);
    final secondary = StubSpeechEngine(id: 'whisper', transcript: 'grabber music');
    final result = await SpeechFallback.transcribe(
      '/cache/same.wav',
      primary: primary,
      secondary: secondary,
      cancelled: () => false,
    );
    expect(result, 'grabber music');
    expect(primary.calls, 1);
    expect(secondary.calls, 1);
    expect(primary.usedWavPath, secondary.usedWavPath);
    expect(secondary.prepares, 0);
  });

  test('Whistle model error falls back only to already-installed Whisper', () async {
    final primary = StubSpeechEngine(id: 'whistle', ready: false, failPrepare: true);
    final secondary = StubSpeechEngine(id: 'whisper');
    final result = await SpeechFallback.transcribe(
      '/cache/wav.wav', primary: primary, secondary: secondary,
      cancelled: () => false,
    );
    expect(result, 'forge audio');
    expect(primary.prepares, 1);
    expect(secondary.calls, 1);
  });

  test('missing Whisper model is never downloaded automatically', () async {
    final primary = StubSpeechEngine(id: 'whistle', failTranscribe: true);
    final secondary = StubSpeechEngine(id: 'whisper', ready: false);
    await expectLater(
      SpeechFallback.transcribe(
        '/cache/wav.wav', primary: primary, secondary: secondary,
        cancelled: () => false,
      ),
      throwsA(isA<SpeechFallbackUnavailable>()),
    );
    expect(secondary.prepares, 0);
    expect(secondary.calls, 0);
  });

  test('operator cancellation never triggers a fallback', () async {
    final primary = StubSpeechEngine(id: 'whistle', failTranscribe: true);
    final secondary = StubSpeechEngine(id: 'whisper');
    var checks = 0;
    await expectLater(
      SpeechFallback.transcribe(
        '/cache/wav.wav',
        primary: primary,
        secondary: secondary,
        cancelled: () => ++checks >= 3,
      ),
      throwsA(isA<SpeechFallbackCancelled>()),
    );
    expect(secondary.calls, 0);
  });

  test('fallback status identifies the actual engine', () async {
    final primary = StubSpeechEngine(id: 'whistle', failTranscribe: true);
    final secondary = StubSpeechEngine(id: 'whisper');
    final labels = <String>[];
    await SpeechFallback.transcribe(
      '/cache/wav.wav', primary: primary, secondary: secondary,
      cancelled: () => false, onStatus: labels.add,
    );
    expect(labels.join(' '), contains('TRYING OFFLINE WHISPER'));
    expect(labels.last, contains('TRANSCRIBING WITH WHISPER'));
  });
}
