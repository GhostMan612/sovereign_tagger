// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'eq_mapper.dart';

class Eq15Contract {
  static const minDb = -12.0;
  static const maxDb = 12.0;

  static List<double> validateGains(List<double> gains) {
    if (gains.length != EqMapper.bandFrequencies.length ||
        gains.any((gain) => !gain.isFinite)) {
      throw ArgumentError.value(gains, 'gains', 'Expected exactly 15 finite EQ gains');
    }
    return List<double>.unmodifiable(
      gains.map((gain) => gain.clamp(minDb, maxDb).toDouble()),
    );
  }

  static EqCapability parseCapabilities(Map<Object?, Object?>? raw) {
    if (raw == null) return const EqCapability('unavailable', []);
    final backend = raw['engine'];
    final list = raw['bands'];
    if (list is! List || list.any((band) => band is! num || !band.isFinite)) {
      return const EqCapability('unavailable', []);
    }
    final frequencies = List<double>.unmodifiable(
      list.map((band) => (band as num).toDouble()),
    );
    if (backend == 'dynamics15' &&
        frequencies.length == EqMapper.bandFrequencies.length &&
        _matchingNativeCenters(frequencies)) {
      return EqCapability('dynamics15', frequencies);
    }
    if (backend == 'legacy' && frequencies.isNotEmpty) {
      return EqCapability('legacy', frequencies);
    }
    return const EqCapability('unavailable', []);
  }

  static bool _matchingNativeCenters(List<double> hz) {
    for (var i = 0; i < hz.length; i++) {
      if ((hz[i] - EqMapper.bandFrequencies[i]).abs() > 0.1) return false;
    }
    return true;
  }

  static EqReadback parseReadback(Map<Object?, Object?>? raw) {
    if (raw == null) return const EqReadback('unavailable', false, []);
    final backend = raw['engine'];
    final enabled = raw['enabled'] == true;
    final list = raw['gainsDb'];
    if (backend is! String ||
        list is! List ||
        list.any((g) => g is! num || !g.isFinite)) {
      return const EqReadback('unavailable', false, []);
    }
    final gains = List<double>.unmodifiable(
      list.map((g) => (g as num).toDouble()),
    );
    if (backend == 'dynamics15' && gains.length == EqMapper.bandFrequencies.length) {
      return EqReadback('dynamics15', enabled, gains);
    }
    if (backend == 'legacy' && gains.isNotEmpty) {
      return EqReadback('legacy', enabled, gains);
    }
    return const EqReadback('unavailable', false, []);
  }
}

class EqCapability {
  final String backend;
  final List<double> bandsHz;
  const EqCapability(this.backend, this.bandsHz);
  bool get independent => backend == 'dynamics15';
  bool get available => backend == 'dynamics15' || backend == 'legacy';
}

class EqReadback {
  final String backend;
  final bool enabled;
  final List<double> gainsDb;
  const EqReadback(this.backend, this.enabled, this.gainsDb);
}
