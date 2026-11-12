// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'speech_to_text.dart';

class SpeechFallbackCancelled implements Exception {
  const SpeechFallbackCancelled();
}

class SpeechFallbackUnavailable implements Exception {
  final Object primaryError;
  const SpeechFallbackUnavailable(this.primaryError);

  @override
  String toString() =>
      'Primary speech engine failed; offline fallback is not installed. '
      'Download the Whisper model from Settings to enable fallback. '
      'Primary error: $primaryError';
}

class SpeechFallback {
  const SpeechFallback._();

  static Future<String> transcribe(
    String wavPath, {
    required SpeechEngine primary,
    SpeechEngine? secondary,
    required bool Function() cancelled,
    void Function(SpeechEngine engine)? onActiveEngine,
    void Function(String status)? onStatus,
  }) async {
    void checkCancelled() {
      if (cancelled()) throw const SpeechFallbackCancelled();
    }

    Future<String> invoke(SpeechEngine engine, {required bool permitPrepare}) async {
      checkCancelled();
      onActiveEngine?.call(engine);
      var ready = await engine.isReady();
      checkCancelled();
      if (!ready) {
        if (!permitPrepare) {
          throw const StateError('Fallback speech model is not installed');
        }
        onStatus?.call('LOADING ${engine.label} MODEL...');
        await engine.prepare();
        checkCancelled();
        ready = await engine.isReady();
        checkCancelled();
        if (!ready) throw StateError('${engine.label} is still unavailable after preparing.');
      }
      onStatus?.call('TRANSCRIBING WITH ${engine.label}...');
      final output = await engine.transcribe(wavPath);
      checkCancelled();
      return output;
    }

    try {
      return await invoke(primary, permitPrepare: true);
    } on SpeechFallbackCancelled {
      rethrow;
    } catch (primaryError) {
      checkCancelled();
      if (secondary == null || secondary.id == primary.id) rethrow;
      bool installed;
      try {
        installed = await secondary.isReady();
      } catch (_) {
        installed = false;
      }
      checkCancelled();
      if (!installed) throw SpeechFallbackUnavailable(primaryError);
      onStatus?.call('PRIMARY SPEECH ENGINE FAILED; TRYING OFFLINE ${secondary.label}...');
      return invoke(secondary, permitPrepare: false);
    }
  }
}
