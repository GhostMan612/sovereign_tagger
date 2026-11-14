import 'eq_mapper.dart';

/// Single source of truth for the 15 playback sliders and native FX contract.
/// The Android backend applies these gains directly on API 28+; a separately
/// labeled compatibility engine maps them only when DynamicsProcessing fails.
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
}

class EqCapability {
  final String backend;
  final List<double> bandsHz;
  const EqCapability(this.backend, this.bandsHz);
  bool get independent => backend == 'dynamics15';
  bool get available => backend == 'dynamics15' || backend == 'legacy';
}
