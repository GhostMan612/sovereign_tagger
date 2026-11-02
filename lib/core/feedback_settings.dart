// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedbackSettings {
  static const String _burstKey = 'fx_visual_burst';
  static const String _ringKey = 'fx_visual_ring';
  static const String _pulseKey = 'fx_visual_pulse';
  static const String _soundKey = 'fx_sound';
  static const String _hapticKey = 'fx_haptics';
  static const String _backdropKey = 'fx_backdrop_enabled';
  static const String _backdropIntensityKey = 'fx_backdrop_intensity';

  static final ValueNotifier<bool> burst = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> ring = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> pulse = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> sound = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> haptics = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> backdrop = ValueNotifier<bool>(true);
  static final ValueNotifier<double> backdropIntensity = ValueNotifier<double>(0.90);

  static Future<void> load(SharedPreferences prefs) async {
    burst.value = prefs.getBool(_burstKey) ?? true;
    ring.value = prefs.getBool(_ringKey) ?? true;
    pulse.value = prefs.getBool(_pulseKey) ?? true;
    sound.value = prefs.getBool(_soundKey) ?? true;
    haptics.value = prefs.getBool(_hapticKey) ?? false;
    backdrop.value = prefs.getBool(_backdropKey) ?? true;
    backdropIntensity.value = (prefs.getDouble(_backdropIntensityKey) ?? 0.90).clamp(0.20, 1.50);
  }

  static Future<void> setBurst(bool v) async {
    burst.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_burstKey, v);
  }

  static Future<void> setRing(bool v) async {
    ring.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_ringKey, v);
  }

  static Future<void> setPulse(bool v) async {
    pulse.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_pulseKey, v);
  }

  static Future<void> setSound(bool v) async {
    sound.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_soundKey, v);
  }

  static Future<void> setHaptics(bool v) async {
    haptics.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_hapticKey, v);
  }

  static Future<void> setBackdrop(bool v) async {
    backdrop.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_backdropKey, v);
  }

  static Future<void> setBackdropIntensity(double v, {bool persist = true}) async {
    final clamped = v.clamp(0.20, 1.50);
    backdropIntensity.value = clamped;
    if (!persist) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_backdropIntensityKey, clamped);
  }
}
