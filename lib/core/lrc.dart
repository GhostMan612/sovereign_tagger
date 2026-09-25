// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

class LrcLine {
  final Duration stamp;
  final String text;
  const LrcLine(this.stamp, this.text);
}

class Lrc {
  static final RegExp _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _offset = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false, multiLine: true);

  static bool isSynced(String text) {
    var hits = 0;
    for (final line in text.split('\n')) {
      if (_stamp.hasMatch(line)) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  static List<LrcLine> parse(String raw) {
    final offsetMatch = _offset.firstMatch(raw);
    final offsetMs = offsetMatch == null ? 0 : int.tryParse(offsetMatch.group(1)!) ?? 0;
    final out = <LrcLine>[];
    for (final line in raw.replaceAll('\r', '').split('\n')) {
      final matches = _stamp.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.replaceAll(_stamp, '').trim();
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final frac = m.group(3) ?? '0';
        final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
        var total = Duration(minutes: minutes, seconds: seconds, milliseconds: ms) - Duration(milliseconds: offsetMs);
        if (total.isNegative) total = Duration.zero;
        out.add(LrcLine(total, text));
      }
    }
    out.sort((a, b) => a.stamp.compareTo(b.stamp));
    return out;
  }

  static String stripTimestamps(String raw) {
    return raw
        .replaceAll('\r', '')
        .split('\n')
        .where((l) => !RegExp(r'^\s*\[[a-zA-Z]+:.*\]\s*$').hasMatch(l))
        .map((l) => l.replaceAll(_stamp, '').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String formatStamp(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hundredths = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$hundredths]';
  }

  static int activeIndex(List<LrcLine> lines, Duration position) {
    var lo = 0;
    var hi = lines.length - 1;
    var res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].stamp <= position) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return res;
  }
}
