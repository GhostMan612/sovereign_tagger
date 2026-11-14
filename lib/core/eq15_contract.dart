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
    final channelsMatch = raw['channelsMatch'] == true;
    final list = raw['gainsDb'];
    if (backend is! String ||
        !channelsMatch ||
        list is! List ||
        list.any((g) => g is! num || !g.isFinite)) {
      return const EqReadback('unavailable', false, [], channelsMatch: false);
    }
    final gains = List<double>.unmodifiable(
      list.map((g) => (g as num).toDouble()),
    );
    final chCount = raw['channelCount'];
    final ch0Raw = raw['channel0GainsDb'];
    final ch1Raw = raw['channel1GainsDb'];
    List<double>? parseChannel(Object? candidate) {
      if (candidate is! List ||
          candidate.length != gains.length ||
          candidate.any((g) => g is! num || !g.isFinite)) {
        return null;
      }
      return List<double>.unmodifiable(
        candidate.map((g) => (g as num).toDouble()),
      );
    }
    bool channelsAgree(List<double> ch0, List<double> ch1) {
      for (var i = 0; i < gains.length; i++) {
        if ((ch0[i] - ch1[i]).abs() > 0.001 || (gains[i] - ch0[i]).abs() > 0.001) {
          return false;
        }
      }
      return true;
    }
    if (backend == 'dynamics15' &&
        chCount is int &&
        chCount == 2 &&
        gains.length == EqMapper.bandFrequencies.length) {
      final ch0 = parseChannel(ch0Raw);
      final ch1 = parseChannel(ch1Raw);
      if (ch0 == null || ch1 == null || !channelsAgree(ch0, ch1)) {
        return const EqReadback('unavailable', false, [], channelsMatch: false);
      }
      return EqReadback(
        'dynamics15',
        enabled,
        gains,
        channelCount: 2,
        channelsMatch: true,
        channel0GainsDb: ch0,
        channel1GainsDb: ch1,
      );
    }
    if (backend == 'legacy' &&
        gains.isNotEmpty &&
        (chCount == null || (chCount is int && chCount == 1))) {
      List<double> ch0 = gains;
      List<double> ch1 = gains;
      if (ch0Raw != null || ch1Raw != null) {
        final parsed0 = parseChannel(ch0Raw);
        final parsed1 = parseChannel(ch1Raw);
        if (parsed0 == null || parsed1 == null || !channelsAgree(parsed0, parsed1)) {
          return const EqReadback('unavailable', false, [], channelsMatch: false);
        }
        ch0 = parsed0;
        ch1 = parsed1;
      }
      return EqReadback(
        'legacy',
        enabled,
        gains,
        channelCount: 1,
        channelsMatch: true,
        channel0GainsDb: ch0,
        channel1GainsDb: ch1,
      );
    }
    return const EqReadback('unavailable', false, [], channelsMatch: false);
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
  final int channelCount;
  final bool channelsMatch;
  final List<double> channel0GainsDb;
  final List<double> channel1GainsDb;
  const EqReadback(
    this.backend,
    this.enabled,
    this.gainsDb, {
    this.channelCount = 0,
    this.channelsMatch = false,
    this.channel0GainsDb = const [],
    this.channel1GainsDb = const [],
  });
}
