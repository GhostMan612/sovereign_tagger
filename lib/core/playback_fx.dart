// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'eq_mapper.dart';

class PlaybackFx {
  static final AndroidEqualizer equalizer = AndroidEqualizer();
  static final AndroidLoudnessEnhancer loudness = AndroidLoudnessEnhancer();

  static final ValueNotifier<List<double>> eqGains = ValueNotifier<List<double>>(List<double>.filled(15, 0.0));
  static final ValueNotifier<bool> eqEnabled = ValueNotifier<bool>(false);
  static final ValueNotifier<List<double>> deviceBands = ValueNotifier<List<double>>(const []);
  static final ValueNotifier<String> replayGainMode = ValueNotifier<String>('track');
  static final ValueNotifier<double> replayGainPreamp = ValueNotifier<double>(0.0);
  static final ValueNotifier<double> fadeSeconds = ValueNotifier<double>(0.0);

  static AudioPlayer? _player;
  static AndroidEqualizerParameters? _params;
  static double _rgVolume = 1.0;
  static double _rgBoostDb = 0.0;
  static double _fadeFactor = 1.0;
  static double _sleepFactor = 1.0;
  static double _lastVolume = -1;
  static int? _lastIndex;
  static Map<String, String> _lastTags = const {};

  static AudioPipeline createPipeline() => AudioPipeline(androidAudioEffects: [loudness, equalizer]);

  static Future<void> init(AudioPlayer player) async {
    _player = player;
    try {
      final prefs = await SharedPreferences.getInstance();
      final gains = List<double>.generate(15, (i) => prefs.getDouble('eq15_band_$i') ?? 0.0);
      eqGains.value = gains;
      eqEnabled.value = prefs.getBool('eq_enabled') ?? gains.any((g) => g != 0);
      replayGainMode.value = prefs.getString('rg_mode') ?? 'track';
      replayGainPreamp.value = prefs.getDouble('rg_preamp') ?? 0.0;
      fadeSeconds.value = prefs.getDouble('crossfade_duration') ?? 0.0;
    } catch (_) {}

    player.positionStream.listen(_onPosition);
    player.currentIndexStream.listen((index) {
      if (index != _lastIndex) {
        _lastIndex = index;
        _fadeFactor = fadeSeconds.value > 0 ? 0.0 : 1.0;
        _pushVolume();
      }
    });
    unawaited(_activateEq());
  }

  static Future<void> _activateEq() async {
    try {
      _params = await equalizer.parameters;
      deviceBands.value = _params!.bands.map((b) => b.centerFrequency).toList();
      await applyEq();
    } catch (_) {}
  }

  static Future<void> applyEq() async {
    try {
      await equalizer.setEnabled(eqEnabled.value);
      final params = _params;
      if (params == null || !eqEnabled.value) return;
      final minDb = params.minDecibels;
      final maxDb = params.maxDecibels;
      final mapped = EqMapper.mapToDevice(eqGains.value, params.bands.map((b) => b.centerFrequency).toList(), minDb, maxDb);
      for (var i = 0; i < params.bands.length; i++) {
        await params.bands[i].setGain(mapped[i]);
      }
    } catch (_) {}
  }

  static Future<void> setEqGains(List<double> gains, {bool persist = false}) async {
    eqGains.value = List<double>.from(gains);
    await applyEq();
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 15; i++) {
        await prefs.setDouble('eq15_band_$i', gains[i]);
      }
    }
  }

  static Future<void> setEqEnabled(bool enabled) async {
    eqEnabled.value = enabled;
    await applyEq();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('eq_enabled', enabled);
  }

  static Future<void> setReplayGainMode(String mode) async {
    replayGainMode.value = mode;
    applyTrackGain(_lastTags);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rg_mode', mode);
  }

  static Future<void> setReplayGainPreamp(double db) async {
    replayGainPreamp.value = db;
    applyTrackGain(_lastTags);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('rg_preamp', db);
  }

  static Future<void> setFadeSeconds(double seconds) async {
    fadeSeconds.value = seconds;
    if (seconds <= 0) {
      _fadeFactor = 1.0;
      _pushVolume();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('crossfade_duration', seconds);
  }

  static void applyTrackGain(Map<String, String> tags) {
    _lastTags = tags;
    final mode = replayGainMode.value;
    var gain = double.nan;
    var peak = 0.0;
    if (mode != 'off') {
      final albumGain = EqMapper.parseGainDb(tags['REPLAYGAIN_ALBUM_GAIN']);
      final trackGain = EqMapper.parseGainDb(tags['REPLAYGAIN_TRACK_GAIN']);
      final useAlbum = mode == 'album' && !albumGain.isNaN;
      gain = useAlbum ? albumGain : trackGain;
      peak = double.tryParse((useAlbum ? tags['REPLAYGAIN_ALBUM_PEAK'] : tags['REPLAYGAIN_TRACK_PEAK']) ?? '') ?? 0.0;
    }
    final rg = EqMapper.replayGain(gainDb: gain, peak: peak, preampDb: gain.isNaN ? 0 : replayGainPreamp.value);
    _rgVolume = rg.volume;
    _rgBoostDb = rg.boostDb;
    _applyBoost();
    _pushVolume();
  }

  static Future<void> _applyBoost() async {
    try {
      if (_rgBoostDb > 0.05) {
        await loudness.setTargetGain(_rgBoostDb);
        await loudness.setEnabled(true);
      } else {
        await loudness.setEnabled(false);
      }
    } catch (_) {}
  }

  static void setSleepFactor(double factor) {
    _sleepFactor = factor.clamp(0.0, 1.0);
    _pushVolume();
  }

  static void _onPosition(Duration position) {
    final player = _player;
    final fade = fadeSeconds.value;
    if (player == null || fade <= 0) return;
    final duration = player.duration;
    final fadeMs = fade * 1000;
    var factor = 1.0;
    if (position.inMilliseconds < fadeMs) {
      factor = position.inMilliseconds / fadeMs;
    }
    if (duration != null && duration > Duration.zero && (player.hasNext || player.loopMode == LoopMode.one)) {
      final remaining = (duration - position).inMilliseconds;
      if (remaining < fadeMs) {
        final out = remaining / fadeMs;
        if (out < factor) factor = out;
      }
    }
    _fadeFactor = factor.clamp(0.05, 1.0);
    _pushVolume();
  }

  static void _pushVolume() {
    final player = _player;
    if (player == null) return;
    final v = (_rgVolume * _fadeFactor * _sleepFactor).clamp(0.0, 1.0);
    if ((v - _lastVolume).abs() < 0.01 && v != 0 && v != 1) return;
    if (v == _lastVolume) return;
    _lastVolume = v;
    player.setVolume(v);
  }
}
