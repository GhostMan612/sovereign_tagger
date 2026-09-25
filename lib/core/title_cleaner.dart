// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

class CleanedTrack {
  final String artist;
  final String title;
  final String trackNo;
  const CleanedTrack(this.artist, this.title, this.trackNo);
}

class TitleCleaner {
  static const String _noiseWords =
      r'official(?:\s+(?:music|lyric|lyrics|audio|hd|4k))?\s*(?:video|audio|visuali[sz]er|clip)?|'
      r'music\s+video|lyric\s+video|lyrics?\s+video|lyrics?|audio(?:\s+only)?|visuali[sz]er|'
      r'video\s+oficial|clip\s+officiel|hd|hq|4k|8k|1080p|720p|mv|m/v|explicit|clean|'
      r'full\s+song|with\s+lyrics|color\s+coded';

  static final RegExp _bracketNoise = RegExp(r'\s*[\(\[\{](?:[^\)\]\}]*?\b(?:' + _noiseWords + r')\b[^\)\]\}]*?)[\)\]\}]', caseSensitive: false);
  static final RegExp _trailingNoise = RegExp(r'\s*(?:[-|/~•:]\s*)?\b(?:' + _noiseWords + r')\s*$', caseSensitive: false);
  static final RegExp _pipeTail = RegExp(r'\s+[|｜]\s+.*$');
  static final RegExp _trackPrefix = RegExp(r'^\s*(\d{1,3})\s*(?:[-–—.)]\s+|\s+[-–—]\s+)');
  static final RegExp _feat = RegExp(r'\s*[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]?', caseSensitive: false);
  static final RegExp _versionSearch = RegExp(r'\s*[\(\[][^\)\]]*\b(?:remaster(?:ed)?|deluxe|bonus|version|edit|mono|stereo)\b[^\)\]]*[\)\]]', caseSensitive: false);
  static final RegExp _channelSuffix = RegExp(r'\s*(?:-\s*topic|vevo|official(?:\s+channel)?|\(official\))\s*$', caseSensitive: false);
  static final RegExp _split = RegExp(r'\s+[-–—]\s+|\s+[-–—]|[-–—]\s+');
  static final RegExp _channelLike = RegExp(r'vevo|topic|official|records|music|tv$', caseSensitive: false);
  static final RegExp _illegalFileChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  static String _trimEdges(String s) {
    const edge = ' -–—|~•:';
    var start = 0;
    var end = s.length;
    while (start < end && edge.contains(s[start])) {
      start++;
    }
    while (end > start && edge.contains(s[end - 1])) {
      end--;
    }
    return s.substring(start, end);
  }

  static String cleanTitle(String raw) {
    var t = raw.trim().replaceFirst(_pipeTail, '');
    String? prev;
    while (prev != t) {
      prev = t;
      t = t.replaceAll(_bracketNoise, '');
      t = t.replaceFirst(_trailingNoise, '').trim();
    }
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    return _trimEdges(t).trim();
  }

  static String cleanArtist(String raw) {
    var a = raw.trim();
    String? prev;
    while (prev != a) {
      prev = a;
      a = a.replaceFirst(_channelSuffix, '').trim();
    }
    return a;
  }

  static CleanedTrack stripTrackPrefix(String title) {
    final m = _trackPrefix.firstMatch(title);
    if (m == null) return CleanedTrack('', title, '');
    final rest = title.substring(m.end).trim();
    if (rest.isEmpty) return CleanedTrack('', title, '');
    return CleanedTrack('', rest, int.parse(m.group(1)!).toString());
  }

  static CleanedTrack splitArtistTitle(String artist, String title) {
    var a = cleanArtist(artist);
    final stripped = stripTrackPrefix(cleanTitle(title));
    var t = stripped.title;
    final channelLike = a.isEmpty || _channelLike.hasMatch(artist);
    final m = _split.firstMatch(t);
    if (m != null) {
      final left = t.substring(0, m.start).trim();
      final right = t.substring(m.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        if (channelLike || normalize(left) == normalize(a) || (normalize(a).isNotEmpty && normalize(left).contains(normalize(a)))) {
          a = left;
          t = right;
        }
      }
    }
    return CleanedTrack(cleanArtist(a), cleanTitle(t), stripped.trackNo);
  }

  static String searchForm(String text) {
    var s = text.replaceAll(_feat, '');
    s = s.replaceAll(_versionSearch, '');
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String normalize(String text) {
    var s = searchForm(text).toLowerCase();
    const accents = {'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y'};
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      buf.write(accents[ch] ?? ch);
    }
    s = buf.toString().replaceAll('&', ' and ');
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    s = s.replaceAll(RegExp(r'\bthe\b'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String sanitizeFileName(String raw) {
    var s = raw.replaceAll(_illegalFileChars, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    if (s.length > 150) s = s.substring(0, 150).trim();
    return s;
  }

  static String buildFileName({required String artist, required String title, String trackNo = '', required String ext}) {
    final a = sanitizeFileName(artist);
    final t = sanitizeFileName(title);
    var base = [if (a.isNotEmpty) a, if (t.isNotEmpty) t].join(' - ');
    if (base.isEmpty) base = 'Untitled';
    final n = trackNo.trim().split('/').first.trim();
    if (n.isNotEmpty && int.tryParse(n) != null) {
      base = '${n.padLeft(2, '0')} - $base';
    }
    final e = ext.startsWith('.') ? ext.substring(1) : ext;
    return e.isEmpty ? base : '$base.$e';
  }

  static String extensionOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String withExtension(String fileName, String ext) {
    final clean = sanitizeFileName(fileName);
    final current = extensionOf(clean);
    final base = current.isEmpty ? clean : clean.substring(0, clean.length - current.length - 1);
    return '${base.isEmpty ? 'Untitled' : base}.$ext';
  }
}
