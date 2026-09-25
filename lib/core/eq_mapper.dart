// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;

class EqMapper {
  static const List<int> bandFrequencies = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

  static double gainAt(List<double> gains15, double frequencyHz) {
    if (gains15.length != bandFrequencies.length) return 0;
    if (frequencyHz <= bandFrequencies.first) return gains15.first;
    if (frequencyHz >= bandFrequencies.last) return gains15.last;
    final lf = math.log(frequencyHz);
    for (var i = 0; i < bandFrequencies.length - 1; i++) {
      final f0 = bandFrequencies[i].toDouble();
      final f1 = bandFrequencies[i + 1].toDouble();
      if (frequencyHz >= f0 && frequencyHz <= f1) {
        final t = (lf - math.log(f0)) / (math.log(f1) - math.log(f0));
        return gains15[i] + (gains15[i + 1] - gains15[i]) * t;
      }
    }
    return 0;
  }

  static List<double> mapToDevice(List<double> gains15, List<double> deviceCenters, double minDb, double maxDb) {
    return [for (final c in deviceCenters) gainAt(gains15, c).clamp(minDb, maxDb).toDouble()];
  }

  static double parseGainDb(String? raw) {
    if (raw == null) return double.nan;
    final m = RegExp(r'[-+]?\d+(?:\.\d+)?').firstMatch(raw);
    if (m == null) return double.nan;
    return double.tryParse(m.group(0)!) ?? double.nan;
  }

  static ({double volume, double boostDb}) replayGain({required double gainDb, double peak = 0, double preampDb = 0}) {
    if (gainDb.isNaN) return (volume: 1.0, boostDb: 0.0);
    var g = gainDb + preampDb;
    if (peak > 0) {
      final ceiling = -20 * math.log(peak) / math.ln10;
      if (g > ceiling) g = ceiling;
    }
    if (g <= 0) return (volume: math.pow(10, g / 20).toDouble(), boostDb: 0.0);
    return (volume: 1.0, boostDb: g);
  }
}
