// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/services.dart';
import 'feedback_settings.dart';
import 'sfx.dart';

class TapFeedback {
  static final Stopwatch _clock = Stopwatch()..start();
  static int _lastHaptic = -1000;

  static void _haptic(Future<void> Function() pulse) {
    if (!FeedbackSettings.haptics.value) return;
    final now = _clock.elapsedMilliseconds;
    if (now - _lastHaptic < 50) return;
    _lastHaptic = now;
    pulse();
  }

  static void machineTap() {
    _haptic(HapticFeedback.selectionClick);
    Sfx.play(SfxId.tap);
  }

  static void machineBoop() {
    _haptic(HapticFeedback.mediumImpact);
    Sfx.play(SfxId.message);
  }

  static void machineConfirm() {
    _haptic(HapticFeedback.heavyImpact);
    Sfx.play(SfxId.confirm);
  }

  static void machineError() {
    HapticFeedback.vibrate();
    Sfx.play(SfxId.error);
  }

  static void play(SfxId id, {Future<void> Function()? haptic}) {
    if (haptic != null) _haptic(haptic);
    Sfx.play(id);
  }
}
