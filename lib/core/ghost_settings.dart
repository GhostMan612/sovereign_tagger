// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GhostSettings {
  static const String _reduceMotionKey = 'ghost_reduce_motion';
  static const String _visibleKey = 'ghost_visible';
  static const String _autoExpandKey = 'ghost_auto_expand';
  static const String _firstLaunchKey = 'ghost_first_launch_complete_v2';

  static final Completer<void> _ready = Completer<void>();

  static bool get isReady => _ready.isCompleted;
  static Future<void> ready() => _ready.future;

  static final ValueNotifier<bool> _reduceMotion = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> _visible = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> _autoExpand = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> _firstLaunchComplete = ValueNotifier<bool>(false);

  static ValueNotifier<bool> get reduceMotion => _reduceMotion;
  static ValueNotifier<bool> get visible => _visible;
  static ValueNotifier<bool> get autoExpand => _autoExpand;
  static ValueNotifier<bool> get firstLaunchComplete => _firstLaunchComplete;

  static Future<void> load(SharedPreferences prefs) async {
    _reduceMotion.value = prefs.getBool(_reduceMotionKey) ?? false;
    _visible.value = prefs.getBool(_visibleKey) ?? true;
    _autoExpand.value = prefs.getBool(_autoExpandKey) ?? true;
    _firstLaunchComplete.value = prefs.getBool(_firstLaunchKey) ?? false;
    if (!_ready.isCompleted) _ready.complete();
  }

  static Future<void> _persist(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('GHOST: setting "$key"=$value applied in memory but FAILED to persist, it will revert on next launch: $e');
    }
  }

  static Future<void> setReduceMotion(bool value) async {
    _reduceMotion.value = value;
    await _persist(_reduceMotionKey, value);
  }

  static Future<void> setVisible(bool value) async {
    _visible.value = value;
    await _persist(_visibleKey, value);
  }

  static Future<void> setAutoExpand(bool value) async {
    _autoExpand.value = value;
    await _persist(_autoExpandKey, value);
  }

  static Future<void> setFirstLaunchComplete() async {
    _firstLaunchComplete.value = true;
    await _persist(_firstLaunchKey, true);
  }

  static Future<void> clearFirstLaunchComplete() async {
    _firstLaunchComplete.value = false;
    await _persist(_firstLaunchKey, false);
  }
}