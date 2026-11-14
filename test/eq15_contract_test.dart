import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/eq15_contract.dart';
import 'package:sovereign_tagger/core/eq_mapper.dart';

void main() {
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
}
