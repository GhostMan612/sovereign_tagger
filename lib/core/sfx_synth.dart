// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'dart:typed_data';

enum SfxId { tap, select, deselect, confirm, back, error, whoosh, open, close, type, message, success, glitch }

class SfxSynth {
  static const int sampleRate = 48000;
  static const double _twoPi = math.pi * 2;

  static Map<SfxId, Uint8List> renderAllWav() => {for (final id in SfxId.values) id: toWav(render(id))};

  static Float64List render(SfxId id) {
    switch (id) {
      case SfxId.tap:
        final out = _buffer(70);
        _mix(out, _noise(ms: 12, lowHz: 3000, highHz: 9000, tauMs: 2.5, seed: 11), 0, 0.55);
        _mix(out, _tone(ms: 60, f0: 2200, f1: 1650, tauMs: 13, fmRatio: 2.0, fmIndex: 0.8, fmTauMs: 7), 0, 0.8);
        _mix(out, _tone(ms: 40, f0: 440, f1: 380, tauMs: 9), 0, 0.25);
        return _finish(out, 0.8);
      case SfxId.select:
        final out = _buffer(120);
        _mix(out, _tone(ms: 60, f0: 1320, f1: 1320, tauMs: 20, wave: _Wave.triangle, fmRatio: 2.0, fmIndex: 0.3, fmTauMs: 15), 0, 0.8);
        _mix(out, _tone(ms: 80, f0: 1980, f1: 1980, tauMs: 24, wave: _Wave.triangle, fmRatio: 2.0, fmIndex: 0.3, fmTauMs: 15), 32, 0.75);
        _mix(out, _noise(ms: 8, lowHz: 3000, highHz: 8000, tauMs: 2, seed: 21), 0, 0.3);
        return _finish(out, 0.75);
      case SfxId.deselect:
        final out = _buffer(120);
        _mix(out, _tone(ms: 60, f0: 1760, f1: 1760, tauMs: 20, wave: _Wave.triangle, fmRatio: 2.0, fmIndex: 0.3, fmTauMs: 15), 0, 0.75);
        _mix(out, _tone(ms: 80, f0: 1175, f1: 1175, tauMs: 24, wave: _Wave.triangle, fmRatio: 2.0, fmIndex: 0.3, fmTauMs: 15), 32, 0.8);
        _mix(out, _noise(ms: 8, lowHz: 3000, highHz: 8000, tauMs: 2, seed: 22), 0, 0.3);
        return _finish(out, 0.7);
      case SfxId.confirm:
        final out = _buffer(420);
        _mix(out, _bell(ms: 360, freq: 1046.5, tauMs: 120), 0, 0.8);
        _mix(out, _bell(ms: 340, freq: 1568.0, tauMs: 120), 70, 0.75);
        _mix(out, _bell(ms: 280, freq: 2093.0, tauMs: 90), 140, 0.4);
        _mix(out, _noise(ms: 10, lowHz: 4000, highHz: 10000, tauMs: 2.5, seed: 31), 0, 0.25);
        _echo(out, delayMs: 90, feedback: 0.25, mix: 0.2);
        return _finish(out, 0.8);
      case SfxId.back:
        final out = _buffer(160);
        _mix(out, _tone(ms: 150, f0: 1400, f1: 700, tauMs: 40, wave: _Wave.triangle), 0, 0.8);
        _mix(out, _noise(ms: 10, lowHz: 2500, highHz: 7000, tauMs: 2.5, seed: 41), 0, 0.35);
        return _finish(out, 0.7);
      case SfxId.error:
        final out = _buffer(300);
        _mix(out, _buzz(ms: 120, freq: 196, tauMs: 70), 0, 0.8);
        _mix(out, _buzz(ms: 140, freq: 185, tauMs: 80), 150, 0.8);
        return _finish(out, 0.7);
      case SfxId.whoosh:
        final out = _buffer(360);
        _mix(out, _sweptNoise(ms: 340, fromHz: 500, toHz: 3500, seed: 51), 0, 0.9);
        _mix(out, _tone(ms: 300, f0: 180, f1: 60, tauMs: 140, attackMs: 60), 0, 0.2);
        return _finish(out, 0.6);
      case SfxId.open:
        final out = _buffer(600);
        const notes = [1046.5, 1318.5, 1568.0, 2093.0];
        for (var i = 0; i < notes.length; i++) {
          _mix(out, _bell(ms: 420, freq: notes[i], tauMs: 140), 55.0 * i, 0.7 - i * 0.08);
        }
        _mix(out, _noise(ms: 420, lowHz: 6000, highHz: 11000, tauMs: 150, attackMs: 20, seed: 61), 0, 0.08);
        _echo(out, delayMs: 110, feedback: 0.3, mix: 0.25);
        return _finish(out, 0.75);
      case SfxId.close:
        final out = _buffer(420);
        const notes = [1568.0, 1318.5, 1046.5];
        for (var i = 0; i < notes.length; i++) {
          _mix(out, _bell(ms: 300, freq: notes[i], tauMs: 100), 55.0 * i, 0.7 - i * 0.1);
        }
        _echo(out, delayMs: 100, feedback: 0.25, mix: 0.2);
        return _finish(out, 0.7);
      case SfxId.type:
        final out = _buffer(30);
        _mix(out, _noise(ms: 20, lowHz: 2500, highHz: 6000, tauMs: 2.5, seed: 71), 0, 0.8);
        _mix(out, _tone(ms: 20, f0: 2600, f1: 2400, tauMs: 4), 0, 0.3);
        return _finish(out, 0.55);
      case SfxId.message:
        final out = _buffer(240);
        _mix(out, _chirp(ms: 220), 0, 0.8);
        _mix(out, _tone(ms: 200, f0: 440, f1: 587, tauMs: 70, wave: _Wave.triangle, attackMs: 4), 0, 0.2);
        return _finish(out, 0.7);
      case SfxId.success:
        final out = _buffer(720);
        const notes = [1046.5, 1318.5, 1568.0, 1975.5, 2093.0];
        for (var i = 0; i < notes.length; i++) {
          _mix(out, _bell(ms: 520, freq: notes[i], tauMs: 220), 70.0 * i, 0.65 - i * 0.05);
        }
        _echo(out, delayMs: 120, feedback: 0.3, mix: 0.25);
        return _finish(out, 0.8);
      case SfxId.glitch:
        return _finish(_crushedSweep(ms: 320, seed: 81), 0.6);
    }
  }

  static Uint8List toWav(Float64List samples) {
    final dataBytes = samples.length * 2;
    final bytes = ByteData(44 + dataBytes);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(44 + i * 2, v, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static Float64List _buffer(double ms) => Float64List((ms * sampleRate / 1000).round());

  static int _samples(double ms) => (ms * sampleRate / 1000).round();

  static double _wave(_Wave wave, double phase) {
    switch (wave) {
      case _Wave.sine:
        return math.sin(phase);
      case _Wave.triangle:
        return 2 / math.pi * math.asin(math.sin(phase));
    }
  }

  static double _env(int i, double attackMs, double tauMs) {
    final t = i / sampleRate * 1000;
    final attack = attackMs <= 0 ? 1.0 : (t / attackMs).clamp(0.0, 1.0);
    return attack * math.exp(-t / tauMs);
  }

  static Float64List _tone({
    required double ms,
    required double f0,
    required double f1,
    required double tauMs,
    _Wave wave = _Wave.sine,
    double attackMs = 0.8,
    double fmRatio = 0,
    double fmIndex = 0,
    double fmTauMs = 1,
  }) {
    final n = _samples(ms);
    final out = Float64List(n);
    var phase = 0.0;
    var modPhase = 0.0;
    for (var i = 0; i < n; i++) {
      final progress = n <= 1 ? 0.0 : i / (n - 1);
      final freq = f0 * math.pow(f1 / f0, progress);
      var fm = 0.0;
      if (fmIndex > 0) {
        modPhase += _twoPi * freq * fmRatio / sampleRate;
        fm = fmIndex * math.exp(-(i / sampleRate * 1000) / fmTauMs) * math.sin(modPhase);
      }
      phase += _twoPi * freq / sampleRate;
      out[i] = _wave(wave, phase + fm) * _env(i, attackMs, tauMs);
    }
    return _release(out);
  }

  static Float64List _bell({required double ms, required double freq, required double tauMs}) {
    final n = _samples(ms);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final index = 2.2 * math.exp(-t * 1000 / (tauMs * 0.5));
      final mod = math.sin(_twoPi * freq * 3.5 * t) * index;
      final body = math.sin(_twoPi * freq * t + mod);
      final shimmer = math.sin(_twoPi * freq * 1.003 * t) * 0.3;
      out[i] = (body + shimmer) * _env(i, 1.2, tauMs);
    }
    return _release(out);
  }

  static Float64List _buzz({required double ms, required double freq, required double tauMs}) {
    final n = _samples(ms);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      var v = 0.0;
      for (var h = 1; h <= 13; h += 2) {
        v += math.sin(_twoPi * freq * h * t) / h;
      }
      final tremolo = 0.75 + 0.25 * math.sin(_twoPi * 30 * t);
      out[i] = v * tremolo * _env(i, 3, tauMs);
    }
    return _release(out, ms: 18);
  }

  static Float64List _chirp({required double ms}) {
    final n = _samples(ms);
    final out = Float64List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final glide = (t / 0.06).clamp(0.0, 1.0);
      final base = 880 * math.pow(1175 / 880, glide);
      final vibrato = 1 + 0.015 * math.sin(_twoPi * 7 * t) * glide;
      phase += _twoPi * base * vibrato / sampleRate;
      out[i] = math.sin(phase) * _env(i, 3, 70);
    }
    return _release(out);
  }

  static Float64List _noise({
    required double ms,
    required double lowHz,
    required double highHz,
    required double tauMs,
    required int seed,
    double attackMs = 0.3,
  }) {
    final n = _samples(ms);
    final out = Float64List(n);
    final rng = math.Random(seed);
    final hpAlpha = _onePoleAlpha(lowHz);
    final lpAlpha = _onePoleAlpha(highHz);
    var hpLow = 0.0;
    var lp = 0.0;
    for (var i = 0; i < n; i++) {
      final white = rng.nextDouble() * 2 - 1;
      hpLow += hpAlpha * (white - hpLow);
      final high = white - hpLow;
      lp += lpAlpha * (high - lp);
      out[i] = lp * 2.2 * _env(i, attackMs, tauMs);
    }
    return _release(out);
  }

  static Float64List _sweptNoise({required double ms, required double fromHz, required double toHz, required int seed}) {
    final n = _samples(ms);
    final out = Float64List(n);
    final rng = math.Random(seed);
    var low = 0.0;
    var band = 0.0;
    const damping = 0.6;
    for (var i = 0; i < n; i++) {
      final progress = i / n;
      final cutoff = fromHz * math.pow(toHz / fromHz, progress);
      final f = 2 * math.sin(math.pi * cutoff / sampleRate);
      final white = rng.nextDouble() * 2 - 1;
      low += f * band;
      final high = white - low - damping * band;
      band += f * high;
      final shape = math.pow(math.sin(math.pi * math.pow(progress, 0.7)), 2).toDouble();
      out[i] = band * shape;
    }
    return out;
  }

  static Float64List _crushedSweep({required double ms, required int seed}) {
    final n = _samples(ms);
    final out = Float64List(n);
    final rng = math.Random(seed);
    const steps = [220.0, 880.0, 330.0, 1760.0, 440.0, 660.0, 1320.0];
    final stepLen = _samples(18);
    var phase = 0.0;
    var held = 0.0;
    var freq = steps[0];
    var nextHold = 0;
    for (var i = 0; i < n; i++) {
      if (i % stepLen == 0) freq = steps[rng.nextInt(steps.length)];
      phase += freq / sampleRate;
      if (i >= nextHold) {
        nextHold = i + 4 + rng.nextInt(5);
        final saw = (phase % 1.0) * 2 - 1;
        final noise = rng.nextDouble() < 0.08 ? rng.nextDouble() * 2 - 1 : 0.0;
        held = ((saw * 0.7 + noise * 0.5) * 16).roundToDouble() / 16;
      }
      out[i] = held * _env(i, 2, 140);
    }
    return _release(out, ms: 12);
  }

  static Float64List _release(Float64List out, {double ms = 6}) {
    final len = math.min(_samples(ms), out.length ~/ 3);
    for (var k = 0; k < len; k++) {
      final i = out.length - 1 - k;
      out[i] *= 0.5 - 0.5 * math.cos(math.pi * k / len);
    }
    return out;
  }

  static double _onePoleAlpha(double cutoffHz) {
    final x = math.exp(-_twoPi * cutoffHz / sampleRate);
    return 1 - x;
  }

  static void _mix(Float64List target, Float64List source, double offsetMs, double gain) {
    final start = _samples(offsetMs);
    for (var i = 0; i < source.length; i++) {
      final j = start + i;
      if (j >= target.length) break;
      target[j] += source[i] * gain;
    }
  }

  static void _echo(Float64List buffer, {required double delayMs, required double feedback, required double mix}) {
    final delay = _samples(delayMs);
    if (delay <= 0) return;
    final wet = Float64List(buffer.length);
    for (var i = 0; i < buffer.length; i++) {
      final back = i - delay;
      if (back >= 0) wet[i] = buffer[back] + wet[back] * feedback;
    }
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] += wet[i] * mix;
    }
  }

  static Float64List _finish(Float64List buffer, double peak) {
    var mean = 0.0;
    for (final v in buffer) {
      mean += v;
    }
    mean /= buffer.isEmpty ? 1 : buffer.length;
    var maxAbs = 0.0;
    for (var i = 0; i < buffer.length; i++) {
      final v = _softClip(buffer[i] - mean);
      buffer[i] = v;
      if (v.abs() > maxAbs) maxAbs = v.abs();
    }
    final scale = maxAbs > 0 ? peak / maxAbs : 1.0;
    final fadeIn = _samples(1.5);
    final fadeOut = _samples(4);
    for (var i = 0; i < buffer.length; i++) {
      var g = scale;
      if (i < fadeIn) g *= i / fadeIn;
      final fromEnd = buffer.length - 1 - i;
      if (fromEnd < fadeOut) g *= fromEnd / fadeOut;
      buffer[i] *= g;
    }
    return buffer;
  }

  static double _softClip(double x) {
    if (x > 3) return 1;
    if (x < -3) return -1;
    final x2 = x * x;
    return x * (27 + x2) / (27 + 9 * x2);
  }
}

enum _Wave { sine, triangle }
