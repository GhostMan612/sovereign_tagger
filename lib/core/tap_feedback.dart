// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'feedback_settings.dart';

class TapFeedback {
  static final AudioPlayer _player = AudioPlayer();
  static const String _tickB64 = 'UklGRgQCAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YeABAAAAAK0pwyW3+MvTNN9NDp8tFxsf6xrSNevdGgstEA7k3+jU7viAJBwoAAAQ2NHb+wZaKmsfTfJP1A/m/hPyK+gTSebj1Ivyuh48KcQGFd2h2QAAMiaaIlP5gtf34RgNwynMGOXsAtb77JEYLynbDKfin9iK+VchoSQAAIvb+t5eBqImqByC8yvYWug4EgooIhKV6L/YwPP3G4UlKAY+4BzdAAC3InEf8Pk527rk4wvoJYAWq+7q2cHuRRZTJaYLa+VW3Cf6Lh4mIQAABt8j4sIF6yLlGbf0Btym6nIQIiRcEOHqmtz19DQZziGLBWfjl+AAADwfSByM+vDefeeuCgwiNBRx8NLdh/D5E3ghcAou6A3gw/oFG6sdAACB4kzlJQU0HyIX7PXi3/LsrA46IJYOLe124Cr2cRYXHu8EkOYS5AAAwRsfGSn7p+JA6nkJMB7oETfyu+FN8q0RnB07CfHqxONg+9wXMBoAAPzldeiJBH0bXhQh977jPu/mDFIc0Ax471LkX/euE2AaUgS56Y3nAABGGPYVxfte5gPtRAhUGpwP/fOi5RP0Yg/AGQYItO185/z7sxS1FgAAd+me6+0DxhebEVb4meeJ8SALaRgKC8TxLuiU+OsQqRa2A+LsCOs=';
  static const String _boopB64 = 'UklGRuQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YcADAAAAAMUs7ERsPcYZY+oCxcG6RdCh++UoUkPTPogdxe4CyP+6p81b9+0kekHxPxghJPMuy4W7S8sy8+IgZj/IQHUkfPeCzlC8Mcks78gcGj1WQZsnx/v60V69W8dL66QYmTqdQYcqAACQ1a2+ysWT53sU5zedQTktJARC2TrAfcQH5FEQCDVZQa0vMAgJ3QLCdsOr4CwMADLRQOMxHgzh4ALEtMKB3Q8I0i4IQNgz6w/H5DfGNsKM2v8DhSsAP401kxO16J3I/MHO1wAAGii6PQE3FBen7DHLBcJJ1Rf8lyQ6PDI4aRqY8O/NT8L+0kb4ASGDOiI5kR2E9NPQ2MLw0JL0Wx2XONA5iCBn+NnToMMez/7wqhl5Nj46TSM8/P3Wo8SKzY7t8hUuNGs63CUAADza38U1zEXqOBK4MVk6NSivA5DdUsceyybnfw4bLwo6VipFB/bg+chGyjPkzQpbLH45Piy+Cmnk0cqryW7hJAd8Kbk47C0ZDuXn18xOydreiQOBJrs3Xi9QEWfrCM8uyXncAABvI4g2ljBiFOruYNFJyUzajPxJICI1kjFLF2ry3NOeyVXYMfkUHYszUzIKGuP1d9YrypTW8fXUGccx2TKcHFL5MNnvygvV0fKLFtkvJjP/HrL8Adzny7nT0u9AE8MtOTMxIQAA594RzaDS9+z0D4krFTMyIzkD3uFqzr/RROqtDC4pujIAJVoG4uTwzxXRuudtCbYmKzKZJl8J8Oeg0aPQW+U5BiUkaTH/J0YMBOt402fQKOMTA30hdzAvKQ0PGe5z1WDQJOEAAMQeVi8rKq8RLfGP143QUN8C/fsbCi7xKi0UPPTI2e3QrN0c+icZlCyDK4IWQvcc3H7ROdxR90wW+CriK68YPfqH3j7S+Nqj9G0TOCkNLLEaKP0E4SvT6dkV8o4QWCcHLIYcAACS40LUC9mq77ENWiXRKy4ewwIs5oLVX9hi7dsKQSNrK6kfbwXP6OfW5NdB6w4IEiHYKvUgAAh363DYmtdH6U4Fzh4aKhIidAoi7hjaf9d3550CehwzKQAjyQzM8N7bktfQ5QAAGRolKL8j/Q5x877d0tdT5Hj9rRfyJlEkDhEP9rXfPdgD4wf7OxWdJbQk+xKi+MHh0dje4bD4xRIpJOskwhQo+93jjdnl4HX2TxCXIvUkYhad/Qjmb9oY4Fn02w3sINUk2xcAAD3odNt231zybgsqH4wkKxlNAnrqmtwA34HwCAlUHRwkUhqEBLzs39203sjurwZtG4UjUBugBv/uP98=';
  static bool _playerReady = false;

  static Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }

  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void heavy() => HapticFeedback.heavyImpact();
  static void selection() => HapticFeedback.selectionClick();

  static Future<void> _playB64(String b64) async {
    try {
      if (!_playerReady) {
        _playerReady = true;
      }
      final uri = Uri.parse('data:audio/wav;base64,$b64');
      await _player.setAudioSource(AudioSource.uri(uri));
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {}
  }

  static void machineTap() {
    if (FeedbackSettings.haptics.value) HapticFeedback.selectionClick();
    if (FeedbackSettings.sound.value) _playB64(_tickB64);
  }

  static void machineBoop() {
    if (FeedbackSettings.haptics.value) HapticFeedback.mediumImpact();
    if (FeedbackSettings.sound.value) _playB64(_boopB64);
  }

  static void machineConfirm() {
    if (FeedbackSettings.haptics.value) HapticFeedback.heavyImpact();
    if (FeedbackSettings.sound.value) _playB64(_boopB64);
  }

  static void machineError() {
    HapticFeedback.vibrate();
  }
}