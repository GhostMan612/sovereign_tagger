// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/eq15_contract.dart';
import 'package:sovereign_tagger/core/eq_mapper.dart';
import 'package:sovereign_tagger/core/playback_fx.dart';
import 'package:sovereign_tagger/screens/eq_presets_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('15 playback sliders have a stable frequency contract', () {
    expect(EqMapper.bandFrequencies, [
      25, 40, 63, 100, 160, 250, 400, 630,
      1000, 1600, 2500, 4000, 6300, 10000, 16000,
    ]);
  });

  test('validates all fifteen independent gains without downsampling', () {
    final source = List<double>.generate(15, (i) => i - 7.0);
    final gains = Eq15Contract.validateGains(source);
    expect(gains, source);
    expect(gains.length, 15);
    expect(() => gains[0] = 5.0, throwsUnsupportedError);
  });

  test('limits gain to safe UI bounds', () {
    final source = List<double>.filled(15, 0);
    source[0] = -30;
    source[14] = 30;
    final result = Eq15Contract.validateGains(source);
    expect(result.first, -12);
    expect(result.last, 12);
  });

  test('rejects incorrect length and nonfinite gains', () {
    expect(() => Eq15Contract.validateGains([0, 1]), throwsArgumentError);
    for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
      final source = List<double>.filled(15, 0);
      source[8] = bad;
      expect(() => Eq15Contract.validateGains(source), throwsArgumentError);
    }
  });

  test('reports independent DSP only for all 15 expected native centers', () {
    final valid = Eq15Contract.parseCapabilities({
      'engine': 'dynamics15',
      'bands': EqMapper.bandFrequencies,
    });
    expect(valid.independent, isTrue);
    expect(valid.available, isTrue);
    expect(valid.bandsHz.length, 15);
    final bogus = Eq15Contract.parseCapabilities({
      'engine': 'dynamics15',
      'bands': [100, 200, 300, 400, 500],
    });
    expect(bogus.independent, isFalse);
    expect(bogus.available, isFalse);
  });

  test('reports legacy 5-band capability honestly, never as DSP', () {
    final legacy = Eq15Contract.parseCapabilities({
      'engine': 'legacy',
      'bands': [60, 230, 910, 3600, 14000],
    });
    expect(legacy.available, isTrue);
    expect(legacy.independent, isFalse);
    expect(legacy.backend, 'legacy');
  });

  test('null, unknown and malformed capabilities fail closed', () {
    expect(Eq15Contract.parseCapabilities(null).available, isFalse);
    expect(Eq15Contract.parseCapabilities({'engine': 'dynamics15', 'bands': []}).available, isFalse);
    expect(Eq15Contract.parseCapabilities({'engine': 'future', 'bands': [1, 2]}).available, isFalse);
    expect(Eq15Contract.parseCapabilities({'engine': 'legacy', 'bands': [double.nan]}).available, isFalse);
  });

  test('parses live readback for dynamics15, legacy and malformed payloads', () {
    final fifteen = List<double>.generate(15, (i) => i == 4 ? 12.0 : (i == 6 ? -6.0 : 0.0));
    final dsp = Eq15Contract.parseReadback({
      'engine': 'dynamics15',
      'enabled': true,
      'channelCount': 2,
      'channelsMatch': true,
      'gainsDb': fifteen,
      'channel0GainsDb': fifteen,
      'channel1GainsDb': fifteen,
    });
    expect(dsp.backend, 'dynamics15');
    expect(dsp.enabled, isTrue);
    expect(dsp.channelCount, 2);
    expect(dsp.channelsMatch, isTrue);
    expect(dsp.gainsDb, fifteen);
    expect(dsp.channel0GainsDb, fifteen);
    expect(dsp.channel1GainsDb, fifteen);

    final leg = Eq15Contract.parseReadback({
      'engine': 'legacy',
      'enabled': false,
      'channelCount': 1,
      'channelsMatch': true,
      'gainsDb': [1.0, 2.0, 0.0, -1.0, 0.5],
    });
    expect(leg.backend, 'legacy');
    expect(leg.enabled, isFalse);
    expect(leg.channelCount, 1);
    expect(leg.channelsMatch, isTrue);
    expect(leg.gainsDb.length, 5);

    final diverged = List<double>.from(fifteen);
    diverged[4] = 0.0;
    final fourteen = fifteen.sublist(0, 14);

    for (final bad in [
      null,
      <Object?, Object?>{},
      {'engine': 'dynamics15', 'enabled': true, 'gainsDb': [1.0, 2.0]},
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': List<double>.filled(15, double.nan),
        'channel0GainsDb': fifteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 1,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fourteen,
        'channel1GainsDb': fifteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': fourteen,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': false,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': diverged,
      },
      {
        'engine': 'dynamics15',
        'enabled': true,
        'channelCount': 2,
        'channelsMatch': true,
        'gainsDb': fifteen,
        'channel0GainsDb': fifteen,
        'channel1GainsDb': diverged,
      },
      {'engine': 'legacy', 'enabled': true, 'channelsMatch': true, 'gainsDb': <double>[]},
      {'engine': 'legacy', 'enabled': true, 'gainsDb': [1.0, 2.0]},
      {'engine': 'legacy', 'enabled': true, 'channelCount': 2, 'channelsMatch': true, 'gainsDb': [1.0, 2.0]},
      {'engine': 'legacy', 'enabled': true, 'channelsMatch': true, 'gainsDb': [1.0, 2.0], 'channel0GainsDb': [1.0, 2.0]},
      {'engine': 'future', 'enabled': true, 'channelsMatch': true, 'gainsDb': [0.0]},
    ]) {
      final parsed = Eq15Contract.parseReadback(bad);
      expect(parsed.backend, 'unavailable');
      expect(parsed.enabled, isFalse);
      expect(parsed.channelCount, 0);
      expect(parsed.channelsMatch, isFalse);
      expect(parsed.gainsDb, isEmpty);
    }
  });

  test('PlaybackFx transitions eqBackend to error on failed applyEq and recovers', () async {
    const channel = MethodChannel('com.sovereign.tagger/audio_fx');
    var mode = 'ok';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'attachSession') {
        return {
          'engine': 'dynamics15',
          'bands': EqMapper.bandFrequencies,
        };
      }
      if (call.method == 'applyEq') {
        if (mode == 'false') return false;
        if (mode == 'throw') {
          throw PlatformException(code: 'DSP_ERR', message: 'effect failed');
        }
        return true;
      }
      if (call.method == 'applyLoudness') return true;
      return null;
    });

    try {
      await PlaybackFx.attachSession(42);
      expect(PlaybackFx.eqBackend.value, 'dynamics15');

      mode = 'false';
      expect(await PlaybackFx.applyEq(), isFalse);
      expect(PlaybackFx.eqBackend.value, 'error');

      mode = 'throw';
      expect(await PlaybackFx.applyEq(), isFalse);
      expect(PlaybackFx.eqBackend.value, 'error');

      mode = 'ok';
      expect(await PlaybackFx.applyEq(), isTrue);
      expect(PlaybackFx.eqBackend.value, 'dynamics15');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('EqPresetsScreen dispatches coalesced live applyEq updates during Slider onChanged', (tester) async {
    const channel = MethodChannel('com.sovereign.tagger/audio_fx');
    final recordedGains = <List<double>>[];
    Completer<bool>? pendingApply;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'attachSession') {
        return {
          'engine': 'dynamics15',
          'bands': EqMapper.bandFrequencies,
        };
      }
      if (call.method == 'applyEq') {
        final args = call.arguments as Map<Object?, Object?>;
        final gains = (args['gainsDb'] as List<Object?>).map((e) => (e as num).toDouble()).toList();
        recordedGains.add(gains);
        final pending = pendingApply;
        if (pending != null) {
          return await pending.future;
        }
        return true;
      }
      if (call.method == 'applyLoudness') return true;
      return null;
    });

    try {
      PlaybackFx.eqGains.value = List<double>.filled(15, 0.0);
      PlaybackFx.eqEnabled.value = true;
      await PlaybackFx.attachSession(42);
      recordedGains.clear();

      await tester.pumpWidget(const MaterialApp(home: EqPresetsScreen()));
      await tester.pump();

      Slider firstSlider() => tester.widgetList<Slider>(find.byType(Slider)).first;

      pendingApply = Completer<bool>();
      firstSlider().onChanged?.call(5.0);
      await tester.pump();
      expect(recordedGains.length, 1);
      expect(recordedGains.first[0], 5.0);

      firstSlider().onChanged?.call(6.0);
      firstSlider().onChanged?.call(8.0);
      await tester.pump();
      expect(recordedGains.length, 1);

      final inflight = pendingApply;
      pendingApply = null;
      inflight.complete(true);
      await tester.pump();
      await tester.pump();

      expect(recordedGains.length, 2);
      expect(recordedGains.last[0], 8.0);
    } finally {
      PlaybackFx.eqGains.value = List<double>.filled(15, 0.0);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
