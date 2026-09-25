// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'feedback_settings.dart';
import 'sfx_synth.dart';

export 'sfx_synth.dart' show SfxId;

class Sfx {
  static const MethodChannel _channel = MethodChannel('com.sovereign.tagger/sfx');
  static const String _bankVersion = 'sfx_v1';
  static const int _dedupeMs = 60;

  static const Map<SfxId, double> _volume = {
    SfxId.tap: 0.5,
    SfxId.select: 0.55,
    SfxId.deselect: 0.5,
    SfxId.confirm: 0.6,
    SfxId.back: 0.5,
    SfxId.error: 0.6,
    SfxId.whoosh: 0.35,
    SfxId.open: 0.55,
    SfxId.close: 0.5,
    SfxId.type: 0.25,
    SfxId.message: 0.5,
    SfxId.success: 0.6,
    SfxId.glitch: 0.45,
  };

  static const Map<SfxId, double> _pitchJitter = {
    SfxId.tap: 0.04,
    SfxId.type: 0.1,
    SfxId.select: 0.02,
    SfxId.deselect: 0.02,
  };

  static final math.Random _rng = math.Random();
  static final Map<SfxId, int> _lastPlayed = {};
  static final Stopwatch _clock = Stopwatch()..start();
  static Future<void>? _loading;
  static bool _ready = false;

  static Future<void> init() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/$_bankVersion');
      final missing = SfxId.values.any((id) => !File('${dir.path}/${id.name}.wav').existsSync());
      if (missing) {
        final bank = await Isolate.run(SfxSynth.renderAllWav);
        dir.createSync(recursive: true);
        for (final entry in bank.entries) {
          await File('${dir.path}/${entry.key.name}.wav').writeAsBytes(entry.value, flush: true);
        }
        _removeStaleBanks(base);
      }
      await _channel.invokeMethod('load', {
        'sounds': {for (final id in SfxId.values) id.name: '${dir.path}/${id.name}.wav'},
      });
      _ready = true;
    } catch (_) {}
  }

  static void _removeStaleBanks(Directory base) {
    try {
      for (final entry in base.listSync()) {
        final name = entry.path.split('/').last;
        if (entry is Directory && name.startsWith('sfx_') && name != _bankVersion) {
          entry.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  static void play(SfxId id, {double volume = 1.0}) {
    if (!_ready || !FeedbackSettings.sound.value) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayed[id];
    if (last != null && now - last < _dedupeMs) return;
    _lastPlayed[id] = now;
    final jitter = _pitchJitter[id] ?? 0.0;
    final rate = jitter == 0 ? 1.0 : 1.0 + (_rng.nextDouble() * 2 - 1) * jitter;
    _channel.invokeMethod('play', {
      'name': id.name,
      'volume': ((_volume[id] ?? 0.5) * volume).clamp(0.0, 1.0),
      'rate': rate,
    }).catchError((_) => null);
  }
}
