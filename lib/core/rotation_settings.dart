// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RotationSettings {
  static const String _lockKey = 'player_lock_fullscreen_rotation';

  static final ValueNotifier<bool> lockFullscreenVideo = ValueNotifier<bool>(false);

  static Future<void> load(SharedPreferences prefs) async {
    lockFullscreenVideo.value = prefs.getBool(_lockKey) ?? false;
  }

  static Future<void> setLockFullscreenVideo(bool v) async {
    lockFullscreenVideo.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_lockKey, v);
  }
}