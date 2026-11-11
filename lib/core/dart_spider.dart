// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class DartSpider {
  static const String _userAgent = 'SovereignTagger/2.0 (https://github.com/GhostMan612/sovereign_tagger)';
  static const int _timeoutSeconds = 10;
  static const int _maxArtBytes = 8 * 1024 * 1024;

  static const String _noiseWords =
      r'official(?:\s+(?:music|lyric|lyrics|audio|hd|4k))?\s*(?:video|audio|visuali[sz]er|clip)?|'
      r'music\s+video|lyric\s+video|lyrics?\s+video|lyrics?|audio(?:\s+only)?|visuali[sz]er|'
      r'video\s+oficial|clip\s+officiel|hd|hq|4k|8k|1080p|720p|mv|m/v|explicit|clean|'
      r'full\s+song|with\s+lyrics|color\s+coded';

  static final RegExp _bracketNoise = RegExp(
    r'\s*[\(\[\{](?:[^\)\]\}]*?\b(?:' + _noiseWords + r')\b[^\)\]\}]*?)[\)\]\}]',
    caseSensitive: false,
  );
  static final RegExp _trailingNoise = RegExp(
    r'\s*(?:[-|/~•:]\s*)?\b(?:' + _noiseWords + r')\s*$',
    caseSensitive: false,
  );
  static final RegExp _pipeTail = RegExp(r'\s+[|｜]\s+.*$');
  static final RegExp _trackPrefix = RegExp(r'^\s*(\d{1,3})\s*(?:[-–—.)]\s+|\s+[-–—]\s+)');
  static final RegExp _feat = RegExp(r"\s*[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\s+[^\)\]]*[\)\]]?", caseSensitive: false);
  static final RegExp _versionSearch = RegExp(r'\s*[\(\[][^\)\]]*\b(?:remaster(?:ed)?|deluxe|bonus|version|edit|mono|stereo)\b[^\)\]]*[\)\]]', caseSensitive: false);
  static final RegExp _channelSuffix = RegExp(r'\s*(?:-\s*topic|vevo|official(?:\s+channel)?|\(official\))\s*$', caseSensitive: false);
  static final RegExp _split = RegExp(r'\s+[-–—]\s+|\s+[-–—]|[-–—]\s+');

  static const Map<String, String> _diacritics = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'ǎ': 'a', 'ȁ': 'a', 'ȃ': 'a', 'ạ': 'a', 'ả': 'a', 'ấ': 'a', 'ầ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a', 'ắ': 'a', 'ằ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
    'ď': 'd', 'đ': 'd', 'ð': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', 'ȅ': 'e', 'ȇ': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ế': 'e', 'ề': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h', 'ħ': 'h',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i', 'ị': 'i', 'ỉ': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l',
    'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n', 'ŉ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'ǒ': 'o', 'ȍ': 'o', 'ȏ': 'o', 'ọ': 'o', 'ỏ': 'o', 'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o', 'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
    'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ș': 's', 'ſ': 's',
    'ţ': 't', 'ť': 't', 'ŧ': 't', 'ț': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ǔ': 'u', 'ȕ': 'u', 'ȗ': 'u', 'ụ': 'u', 'ủ': 'u', 'ứ': 'u', 'ừ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ŵ': 'w',
    'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
    'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'þ': 'th',
  };

  static const List<String> _versionWords = [
    'live', 'remix', 'acoustic', 'instrumental', 'karaoke', 'cover', 'demo', 'sped', 'slowed', 'nightcore', 'reverb', 'mix', 'unplugged', 'orchestral', 'piano',
  ];
  static const Map<String, double> _albumWords = {
    'soundtrack': 0.05, 'karaoke': 0.08, 'tribute': 0.06, 'hits': 0.03, 'greatest': 0.03, 'collection': 0.02, 'compilation': 0.04, 'live': 0.04, 'anniversary': 0.01, 'deluxe': 0.005, 'edition': 0.005, 'various': 0.05,
  };

  static String _stripDiacritics(String text) {
    final lower = text.toLowerCase();
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      final mapped = _diacritics[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (ch.codeUnitAt(0) < 128) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  static Set<String> _words(String text) => text.split(' ').where((w) => w.isNotEmpty).toSet();

  static String cleanTitle(String? raw) {
    var t = (raw ?? '').trim();
    var prev = '';
    while (prev != t) {
      prev = t;
      t = t.replaceAll(_bracketNoise, '');
      t = t.replaceAll(_trailingNoise, '').trim();
    }
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    t = t.replaceAll(RegExp(r'^[ \t\-–—|~•:]+'), '');
    t = t.replaceAll(RegExp(r'[ \t\-–—|~•:]+$'), '');
    return t.trim();
  }

  static String cleanArtist(String? raw) {
    var a = (raw ?? '').trim();
    var prev = '';
    while (prev != a) {
      prev = a;
      a = a.replaceAll(_channelSuffix, '').trim();
    }
    return a;
  }

  static ({String title, String trackNo}) stripTrackPrefix(String? title) {
    final t = title ?? '';
    final m = _trackPrefix.firstMatch(t);
    if (m == null) return (title: t, trackNo: '');
    final rest = t.substring(m.end).trim();
    if (rest.isEmpty) return (title: t, trackNo: '');
    return (title: rest, trackNo: int.parse(m.group(1)!).toString());
  }

  static ({String artist, String title, String trackNo}) splitArtistTitle(String? artist, String? title) {
    var a = cleanArtist(artist);
    var t = cleanTitle(title);
    final stripped = stripTrackPrefix(t);
    t = stripped.title;
    final trackNo = stripped.trackNo;
    final channelLike = a.isEmpty || RegExp(r'vevo|topic|official|records|music|tv$', caseSensitive: false).hasMatch(artist ?? '');
    final m = _split.firstMatch(t);
    if (m != null) {
      final left = t.substring(0, m.start).trim();
      final right = t.substring(m.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        if (channelLike || _norm(left) == _norm(a) || _norm(left).contains(_norm(a))) {
          a = left;
          t = right;
        }
      }
    }
    return (artist: cleanArtist(a), title: cleanTitle(t), trackNo: trackNo);
  }

  static String searchForm(String? text) {
    var s = (text ?? '').replaceAll(_feat, '');
    s = s.replaceAll(_versionSearch, '');
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String _norm(String text) {
    var s = _stripDiacritics(searchForm(text));
    s = s.replaceAll('&', ' and ');
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    s = s.replaceAll(RegExp(r'\bthe\b'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static double similarity(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return 0.0;
    if (na == nb) return 1.0;
    final ratio = _sequenceRatio(na, nb);
    final ta = _words(na);
    final tb = _words(nb);
    final small = ta.length <= tb.length ? ta : tb;
    final big = ta.length <= tb.length ? tb : ta;
    var containment = small.isEmpty ? 0.0 : small.intersection(big).length / small.length;
    if (containment == 1.0) {
      containment = 0.92 + 0.08 * (small.length / (big.isEmpty ? 1 : big.length));
    }
    final viaContainment = containment * 0.97;
    return ratio > viaContainment ? ratio : viaContainment;
  }

  static double _sequenceRatio(String a, String b) {
    final matched = _matchingBlocksLength(a, b);
    final total = a.length + b.length;
    if (total == 0) return 1.0;
    return 2.0 * matched / total;
  }

  static int _matchingBlocksLength(String a, String b) {
    var total = 0;
    final stack = <List<int>>[
      [0, a.length, 0, b.length],
    ];
    while (stack.isNotEmpty) {
      final range = stack.removeLast();
      final aLo = range[0];
      final aHi = range[1];
      final bLo = range[2];
      final bHi = range[3];
      final m = _longestMatch(a, b, aLo, aHi, bLo, bHi);
      final i = m[0];
      final j = m[1];
      final size = m[2];
      if (size == 0) continue;
      total += size;
      if (aLo < i && bLo < j) stack.add([aLo, i, bLo, j]);
      if (i + size < aHi && j + size < bHi) stack.add([i + size, aHi, j + size, bHi]);
    }
    return total;
  }

  static List<int> _longestMatch(String a, String b, int aLo, int aHi, int bLo, int bHi) {
    var bestI = aLo;
    var bestJ = bLo;
    var bestSize = 0;
    final bIndex = <int, List<int>>{};
    for (var j = bLo; j < bHi; j++) {
      (bIndex[b.codeUnitAt(j)] ??= []).add(j);
    }
    for (var i = aLo; i < aHi; i++) {
      final js = bIndex[a.codeUnitAt(i)];
      if (js == null) continue;
      for (final j in js) {
        var size = 0;
        while (i + size < aHi && j + size < bHi && a.codeUnitAt(i + size) == b.codeUnitAt(j + size)) {
          size++;
        }
        if (size > bestSize) {
          bestI = i;
          bestJ = j;
          bestSize = size;
        }
      }
    }
    return [bestI, bestJ, bestSize];
  }

  static double? _durationScore(int queryMs, int candMs) {
    if (queryMs == 0 || candMs == 0) return null;
    final diff = (queryMs - candMs).abs() / 1000.0;
    if (diff <= 2) return 1.0;
    if (diff >= 20) return 0.0;
    return 1.0 - (diff - 2) / 18.0;
  }

  static double _versionPenalty(Map<String, dynamic> cand, String title) {
    final wanted = _words(_norm(title));
    final got = _words(_norm(cand['title']?.toString() ?? ''));
    var penalty = 0.0;
    for (final w in _versionWords) {
      if (got.contains(w) && !wanted.contains(w)) penalty += 0.08;
    }
    final album = _words(_norm(cand['album']?.toString() ?? ''));
    for (final entry in _albumWords.entries) {
      if (album.contains(entry.key) && !wanted.contains(entry.key)) penalty += entry.value;
    }
    return penalty > 0.3 ? 0.3 : penalty;
  }

  static double scoreCandidate(Map<String, dynamic> cand, String artist, String title, int durationMs) {
    final searchTitle = (cand['search_title']?.toString() ?? '');
    final titleForSim = searchTitle.isNotEmpty ? searchTitle : (cand['title']?.toString() ?? '');
    final parts = <(double, double)>[
      (0.5, similarity(titleForSim, title) - _versionPenalty(cand, title)),
    ];
    if (artist.isNotEmpty) {
      parts.add((0.35, similarity(cand['artist']?.toString() ?? '', artist)));
    }
    final d = _durationScore(durationMs, (cand['duration_ms'] as num?)?.toInt() ?? 0);
    if (d != null) parts.add((0.15, d));
    final total = parts.fold(0.0, (sum, p) => sum + p.$1);
    if (total == 0) return 0.0;
    final value = parts.fold(0.0, (sum, p) => sum + p.$1 * p.$2) / total;
    return (value * 10000).round() / 10000;
  }

  static String _s(Object? v) {
    if (v == null) return '';
    if (v is num && v == 0) return '';
    return v.toString();
  }

  static String _yearPrefix(Object? v) {
    final s = v?.toString() ?? '';
    return s.length >= 4 ? s.substring(0, 4) : s;
  }

  static Future<List<int>> _getBytes(Uri uri, {required String accept, int timeoutSeconds = _timeoutSeconds, int? limit, Map<String, String>? extraHeaders}) async {
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSeconds);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, accept);
      extraHeaders?.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close().timeout(Duration(seconds: timeoutSeconds));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode} from $uri');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(Duration(seconds: timeoutSeconds))) {
        bytes.addAll(chunk);
        if (limit != null && bytes.length > limit) {
          throw HttpException('Response over limit from $uri');
        }
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  static Future<dynamic> _getJson(Uri uri, {int timeoutSeconds = _timeoutSeconds, Map<String, String>? extraHeaders}) async {
    final bytes = await _getBytes(uri, accept: 'application/json', timeoutSeconds: timeoutSeconds, extraHeaders: extraHeaders);
    return jsonDecode(utf8.decode(bytes));
  }

  static Future<String> _getText(Uri uri, {int timeoutSeconds = _timeoutSeconds}) async {
    final bytes = await _getBytes(uri, accept: 'text/html,application/xhtml+xml', timeoutSeconds: timeoutSeconds);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _queryString(Map<String, String> params) {
    return params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
  }

  static Future<List<Map<String, dynamic>>> _itunes(String artist, String title) async {
    final term = Uri.encodeComponent('$artist $title'.trim());
    final data = await _getJson(Uri.parse('https://itunes.apple.com/search?term=$term&entity=song&limit=10'));
    final out = <Map<String, dynamic>>[];
    final results = ((data as Map?)?['results'] as List?) ?? const [];
    for (final r in results) {
      final m = (r as Map).cast<String, dynamic>();
      if (m['kind'] != 'song') continue;
      final art = m['artworkUrl100']?.toString() ?? '';
      out.add({
        'source': 'itunes',
        'id': _s(m['trackId']),
        'title': m['trackName']?.toString() ?? '',
        'search_title': (m['trackCensoredName']?.toString() ?? '').isNotEmpty ? m['trackCensoredName'].toString() : (m['trackName']?.toString() ?? ''),
        'artist': m['artistName']?.toString() ?? '',
        'album': m['collectionName']?.toString() ?? '',
        'album_artist': (m['collectionArtistName']?.toString() ?? '').isNotEmpty ? m['collectionArtistName'].toString() : (m['artistName']?.toString() ?? ''),
        'year': _yearPrefix(m['releaseDate']),
        'genre': m['primaryGenreName']?.toString() ?? '',
        'track_no': _s(m['trackNumber']),
        'track_total': _s(m['trackCount']),
        'disc_no': _s(m['discNumber']),
        'disc_total': _s(m['discCount']),
        'duration_ms': (m['trackTimeMillis'] as num?)?.toInt() ?? 0,
        'artwork_url': art.isEmpty ? '' : art.replaceAll('100x100bb', '1200x1200bb'),
        'isrc': '',
      });
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _deezer(String artist, String title) async {
    final q = Uri.encodeComponent('$artist $title'.trim());
    final data = await _getJson(Uri.parse('https://api.deezer.com/search?q=$q&limit=10'));
    final out = <Map<String, dynamic>>[];
    final results = ((data as Map?)?['data'] as List?) ?? const [];
    for (final r in results) {
      final m = (r as Map).cast<String, dynamic>();
      final album = (m['album'] as Map?)?.cast<String, dynamic>() ?? const {};
      final artistMap = (m['artist'] as Map?)?.cast<String, dynamic>() ?? const {};
      out.add({
        'source': 'deezer',
        'id': _s(m['id']),
        'title': m['title']?.toString() ?? '',
        'search_title': (m['title_short']?.toString() ?? '').isNotEmpty ? m['title_short'].toString() : (m['title']?.toString() ?? ''),
        'artist': artistMap['name']?.toString() ?? '',
        'album': album['title']?.toString() ?? '',
        'album_artist': artistMap['name']?.toString() ?? '',
        'album_id': _s(album['id']),
        'year': '',
        'genre': '',
        'track_no': '',
        'track_total': '',
        'disc_no': '',
        'disc_total': '',
        'duration_ms': ((m['duration'] as num?)?.toInt() ?? 0) * 1000,
        'artwork_url': (album['cover_xl']?.toString() ?? '').isNotEmpty
            ? album['cover_xl'].toString()
            : ((album['cover_big']?.toString() ?? '').isNotEmpty ? album['cover_big'].toString() : ''),
        'isrc': m['isrc']?.toString() ?? '',
      });
    }
    return out;
  }

  static Future<Map<String, dynamic>> _deezerDetails(Map<String, dynamic> cand) async {
    try {
      final id = cand['id']?.toString() ?? '';
      if (id.isEmpty) return cand;
      final t = await _getJson(Uri.parse('https://api.deezer.com/track/$id'));
      final tm = (t as Map).cast<String, dynamic>();
      final trackNo = _s(tm['track_position']);
      if (trackNo.isNotEmpty) cand['track_no'] = trackNo;
      final discNo = _s(tm['disk_number']);
      if (discNo.isNotEmpty) cand['disc_no'] = discNo;
      final year = _yearPrefix(tm['release_date']);
      if (year.isNotEmpty) cand['year'] = year;
      final isrc = tm['isrc']?.toString() ?? '';
      if (isrc.isNotEmpty) cand['isrc'] = isrc;
      final album = (tm['album'] as Map?)?.cast<String, dynamic>() ?? const {};
      if ((album['title']?.toString() ?? '').isNotEmpty) cand['album'] = album['title'].toString();
      final albumId = album['id']?.toString() ?? cand['album_id']?.toString() ?? '';
      if (albumId.isNotEmpty) {
        final a = await _getJson(Uri.parse('https://api.deezer.com/album/$albumId'));
        final am = (a as Map).cast<String, dynamic>();
        final genres = ((am['genres'] as Map?)?['data'] as List?) ?? const [];
        if (genres.isNotEmpty) {
          final firstGenre = (genres.first as Map)['name']?.toString() ?? '';
          if (firstGenre.isNotEmpty) cand['genre'] = firstGenre;
        }
        if (am['nb_tracks'] != null) cand['track_total'] = (am['nb_tracks'] as num).toInt().toString();
        final albumArtist = ((am['artist'] as Map?)?['name']?.toString()) ?? '';
        if (albumArtist.isNotEmpty) cand['album_artist'] = albumArtist;
        if ((cand['year']?.toString() ?? '').isEmpty) {
          final albumYear = _yearPrefix(am['release_date']);
          if (albumYear.isNotEmpty) cand['year'] = albumYear;
        }
      }
    } catch (_) {}
    return cand;
  }

  static String _releaseKey(Map<String, dynamic> r) {
    final rg = (r['release-group'] as Map?)?.cast<String, dynamic>() ?? const {};
    final secondary = (rg['secondary-types'] as List?) ?? const [];
    final official = r['status'] == 'Official' ? '0' : '1';
    final sec = secondary.isNotEmpty ? '1' : '0';
    const kinds = {'Album': '0', 'EP': '1', 'Single': '2'};
    final kind = kinds[rg['primary-type']?.toString()] ?? '3';
    final date = r['date']?.toString() ?? '9999';
    return '$official$sec$kind$date';
  }

  static Map<String, dynamic>? _pickRelease(List<dynamic> releases) {
    if (releases.isEmpty) return null;
    final sorted = releases.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    sorted.sort((a, b) => _releaseKey(a).compareTo(_releaseKey(b)));
    return sorted.isEmpty ? null : sorted.first;
  }

  static String _creditName(List<dynamic> credit) {
    final buf = StringBuffer();
    for (final c in credit.whereType<Map>()) {
      buf.write(c['name']?.toString() ?? '');
      buf.write(c['joinphrase']?.toString() ?? '');
    }
    return buf.toString().trim();
  }

  static Future<List<Map<String, dynamic>>> _musicbrainz(String artist, String title) async {
    String lucene(String text) => searchForm(text).replaceAll('\\', ' ').replaceAll('"', ' ').trim();
    var query = 'recording:"${lucene(title)}"';
    if (artist.isNotEmpty) query += ' AND artist:"${lucene(artist)}"';
    final data = await _getJson(Uri.parse('https://musicbrainz.org/ws/2/recording?fmt=json&limit=8&query=${Uri.encodeComponent(query)}'));
    final out = <Map<String, dynamic>>[];
    final recordings = ((data as Map?)?['recordings'] as List?) ?? const [];
    for (final r in recordings) {
      final m = (r as Map).cast<String, dynamic>();
      final credit = (m['artist-credit'] as List?) ?? const [];
      final artistName = _creditName(credit);
      final rel = _pickRelease((m['releases'] as List?) ?? const []);
      var trackNo = '';
      var discNo = '';
      var trackTotal = '';
      var album = '';
      var albumArtist = '';
      var year = '';
      if (rel != null) {
        album = rel['title']?.toString() ?? '';
        final relCredit = (rel['artist-credit'] as List?) ?? credit;
        albumArtist = _creditName(relCredit);
        year = _yearPrefix(rel['date']);
        final media = (rel['media'] as List?) ?? const [];
        if (media.isNotEmpty) {
          final mm = (media.first as Map).cast<String, dynamic>();
          discNo = _s(mm['position']);
          trackTotal = _s(mm['track-count']);
          final tracks = (mm['track'] as List?) ?? const [];
          if (tracks.isNotEmpty) {
            trackNo = _s((tracks.first as Map)['number']);
          }
        }
      }
      final first = _yearPrefix(m['first-release-date']);
      final rg = ((rel ?? const {})['release-group'] as Map?)?.cast<String, dynamic>() ?? const {};
      final secondary = ((rg['secondary-types'] as List?) ?? const []).map((t) => t.toString().toLowerCase()).toList();
      final disamb = (m['disambiguation']?.toString() ?? '').toLowerCase();
      var penalty = 0.0;
      if (secondary.contains('live') || disamb.contains('live')) penalty += 0.08;
      if (secondary.any((t) => ['compilation', 'soundtrack', 'remix', 'dj-mix', 'mixtape/street'].contains(t))) penalty += 0.04;
      if (rel != null && rel['status'] != null && rel['status'] != 'Official') penalty += 0.03;
      out.add({
        'source': 'musicbrainz',
        'penalty': penalty,
        'id': m['id']?.toString() ?? '',
        'title': m['title']?.toString() ?? '',
        'search_title': m['title']?.toString() ?? '',
        'artist': artistName,
        'album': album,
        'album_artist': albumArtist,
        'year': first.isNotEmpty ? first : year,
        'genre': '',
        'track_no': trackNo,
        'track_total': trackTotal,
        'disc_no': discNo,
        'disc_total': '',
        'duration_ms': (m['length'] as num?)?.toInt() ?? 0,
        'artwork_url': (rel != null && (rel['id']?.toString() ?? '').isNotEmpty) ? 'https://coverartarchive.org/release/${rel['id']}/front-500' : '',
        'isrc': '',
      });
    }
    return out;
  }

  static Map<String, dynamic>? _lrclibPick(List<dynamic>? items, String artist, String title, int durationMs) {
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final item in items ?? const []) {
      final it = (item as Map).cast<String, dynamic>();
      if (it['instrumental'] == true) continue;
      var s = scoreCandidate(
        {
          'title': it['trackName']?.toString() ?? '',
          'artist': it['artistName']?.toString() ?? '',
          'duration_ms': (((it['duration'] as num?)?.toDouble() ?? 0.0) * 1000).toInt(),
        },
        artist,
        title,
        durationMs,
      );
      if ((it['syncedLyrics']?.toString() ?? '').isNotEmpty) s += 0.02;
      if (s > bestScore) {
        best = it;
        bestScore = s;
      }
    }
    return bestScore >= 0.72 ? best : null;
  }

  static Future<({String plain, String synced, String source})> fetchLyrics({required String artist, required String title, String album = '', int durationMs = 0}) async {
    final split = splitArtistTitle(artist, title);
    final a = split.artist;
    final t = split.title;
    Map<String, dynamic>? hit;
    try {
      final params = <String, String>{'artist_name': a, 'track_name': searchForm(t)};
      if (album.isNotEmpty) params['album_name'] = album;
      if (durationMs != 0) params['duration'] = (durationMs / 1000).round().toString();
      try {
        final data = await _getJson(Uri.parse('https://lrclib.net/api/get?${_queryString(params)}'));
        if (data is Map<String, dynamic>) hit = data;
      } catch (_) {
        hit = null;
      }
      if (hit == null || ((hit['plainLyrics']?.toString() ?? '').isEmpty && (hit['syncedLyrics']?.toString() ?? '').isEmpty)) {
        try {
          final q = _queryString({'track_name': searchForm(t), 'artist_name': a});
          final items = await _getJson(Uri.parse('https://lrclib.net/api/search?$q'));
          hit = _lrclibPick(items is List ? items : null, a, t, durationMs);
        } catch (_) {
          hit = null;
        }
      }
      if (hit == null) {
        try {
          final q = _queryString({'q': '$a ${searchForm(t)}'.trim()});
          final items = await _getJson(Uri.parse('https://lrclib.net/api/search?$q'));
          hit = _lrclibPick(items is List ? items : null, a, t, durationMs);
        } catch (_) {
          hit = null;
        }
      }
    } catch (_) {
      hit = null;
    }
    if (hit == null) return (plain: '', synced: '', source: '');
    var plain = (hit['plainLyrics']?.toString() ?? '').trim();
    final synced = (hit['syncedLyrics']?.toString() ?? '').trim();
    if (plain.isEmpty && synced.isNotEmpty) {
      plain = synced.replaceAll(RegExp(r'^\s*\[[0-9:.]+\]\s*', multiLine: true), '').trim();
    }
    return (plain: plain, synced: synced, source: 'lrclib');
  }

  static String _cleanGenius(String text) {
    if (text.isEmpty) return '';
    var t = text;
    final headText = t.length > 400 ? t.substring(0, 400) : t;
    final head = RegExp(r'Lyrics(?=\[|\n|[A-Z])').firstMatch(headText);
    if (head != null && (t.substring(0, head.start).contains('Contributor') || head.start < 200)) {
      t = t.substring(head.end);
    }
    t = t.replaceAll(RegExp(r'\d*\s*Embed\s*$'), '');
    t = t.replaceAll('You might also like', '\n');
    t = t.replaceAll(RegExp(r'See .{1,80} LiveGet tickets as low as \$\d+'), '');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  static String _decodeHtmlEntities(String s) {
    var out = s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out;
  }

  static String _extractLyricsHtml(String html) {
    final parts = <String>[];
    final container = RegExp(r'<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>', dotAll: true);
    for (final m in container.allMatches(html)) {
      var inner = m.group(1) ?? '';
      inner = inner.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      inner = inner.replaceAll(RegExp(r'<[^>]*>'), '');
      parts.add(_decodeHtmlEntities(inner));
    }
    return parts.join('\n');
  }

  static Future<String> _geniusLyrics(String token, String artist, String title) async {
    try {
      final data = await _getJson(
        Uri.parse('https://api.genius.com/search?q=${Uri.encodeQueryComponent(searchForm(title))}'),
        extraHeaders: {'Authorization': 'Bearer $token'},
      );
      final hits = (((data as Map?)?['response'] as Map?)?['hits'] as List?) ?? const [];
      for (final h in hits) {
        final result = ((h as Map?)?['result'] as Map?)?.cast<String, dynamic>();
        if (result == null) continue;
        final songTitle = result['title']?.toString() ?? '';
        final songArtist = ((result['primary_artist'] as Map?)?['name']?.toString()) ?? '';
        if (similarity(songTitle, title) < 0.6) continue;
        if (artist.isNotEmpty && similarity(songArtist, artist) < 0.6) continue;
        final url = result['url']?.toString() ?? '';
        if (url.isEmpty) return '';
        final html = await _getText(Uri.parse(url));
        return _cleanGenius(_extractLyricsHtml(html));
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, dynamic>> scrapeMetadata({required String artist, required String title, String album = '', int durationMs = 0, String geniusToken = ''}) async {
    if (title.trim().isEmpty) {
      return {'status': 'error', 'message': 'Title required.'};
    }
    final dur = durationMs;
    final split = splitArtistTitle(artist, title);
    final a = split.artist;
    final t = split.title;
    final trackFromTitle = split.trackNo;
    final qArtist = searchForm(a);
    final qTitle = searchForm(t);
    final candidates = <Map<String, dynamic>>[];
    final errors = <String>[];
    final sources = <String, Future<List<Map<String, dynamic>>> Function()>{
      'itunes': () => _itunes(qArtist, qTitle),
      'deezer': () => _deezer(qArtist, qTitle),
      'musicbrainz': () => _musicbrainz(qArtist, qTitle),
    };
    for (final entry in sources.entries) {
      try {
        candidates.addAll(await entry.value());
      } catch (e) {
        errors.add('${entry.key}: $e');
      }
    }
    for (final c in candidates) {
      final penalty = (c['penalty'] as num?)?.toDouble() ?? 0.0;
      var s = scoreCandidate(c, a, t, dur) - penalty;
      if (c['source'] == 'itunes') s += 0.004;
      if (c['source'] == 'deezer') s += 0.002;
      c['score'] = s;
    }
    candidates.sort((x, y) => ((y['score'] as num?)?.toDouble() ?? 0.0).compareTo((x['score'] as num?)?.toDouble() ?? 0.0));
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final c in candidates) {
      final key = '${_norm(c['title']?.toString() ?? '')}|${_norm(c['artist']?.toString() ?? '')}|${_norm(c['album']?.toString() ?? '')}';
      if (seen.contains(key)) continue;
      seen.add(key);
      unique.add(c);
    }
    final top = unique.take(10).toList();
    for (final c in top.take(3)) {
      if (c['source'] == 'deezer') await _deezerDetails(c);
    }
    final best = top.isEmpty ? null : top.first;
    final rawConfidence = best == null ? 0.0 : ((best['score'] as num?)?.toDouble() ?? 0.0);
    final confidence = min(1.0, (rawConfidence * 1000).round() / 1000);
    final useBest = best != null && confidence >= 0.8;
    final lyrArtist = useBest ? (best!['artist']?.toString() ?? '') : a;
    final lyrTitle = useBest
        ? ((best!['search_title']?.toString() ?? '').isNotEmpty ? best!['search_title'].toString() : (best!['title']?.toString() ?? ''))
        : t;
    final lyrAlbum = useBest ? (best!['album']?.toString() ?? '') : album;
    final lyrDuration = dur != 0 ? dur : (useBest ? (best!['duration_ms'] as num?)?.toInt() ?? 0 : 0);
    var lyrics = await fetchLyrics(artist: lyrArtist, title: lyrTitle, album: lyrAlbum, durationMs: lyrDuration);
    if (lyrics.plain.isEmpty && geniusToken.isNotEmpty) {
      final plain = await _geniusLyrics(geniusToken, lyrArtist, lyrTitle);
      if (plain.isNotEmpty) lyrics = (plain: plain, synced: '', source: 'genius');
    }
    final b = best ?? <String, dynamic>{};
    final bestTitle = b['title']?.toString() ?? '';
    final bestArtist = b['artist']?.toString() ?? '';
    final bestTrackNo = b['track_no']?.toString() ?? '';
    return {
      'status': 'success',
      'query': {'artist': a, 'title': t, 'track_no': trackFromTitle},
      'confidence': confidence,
      'best': best,
      'candidates': top,
      'lyrics_plain': lyrics.plain,
      'lyrics_synced': lyrics.synced,
      'lyrics_source': lyrics.source,
      'errors': errors,
      'title': bestTitle.isNotEmpty ? bestTitle : t,
      'artist': bestArtist.isNotEmpty ? bestArtist : a,
      'album': b['album']?.toString() ?? '',
      'album_artist': b['album_artist']?.toString() ?? '',
      'year': b['year']?.toString() ?? '',
      'genre': b['genre']?.toString() ?? '',
      'track_no': bestTrackNo.isNotEmpty ? bestTrackNo : trackFromTitle,
      'disc_no': b['disc_no']?.toString() ?? '',
      'lyrics': lyrics.synced.isNotEmpty ? lyrics.synced : lyrics.plain,
      'artwork_url': b['artwork_url']?.toString() ?? '',
    };
  }

  static Future<String?> fetchArtwork(String url) async {
    if (url.isEmpty) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final data = await _getBytes(Uri.parse(url), accept: 'image/*', timeoutSeconds: 15, limit: _maxArtBytes);
        if (data.length < 256) throw const HttpException('Artwork payload too small');
        return base64Encode(data);
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return null;
  }
}
