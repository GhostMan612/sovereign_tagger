// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'sentinel_names.dart';
import 'title_cleaner.dart';

class FeatSplit {
  final String main;
  final List<String> feats;
  const FeatSplit(this.main, this.feats);
}

class SentinelAudit {
  final String expectedName;
  final List<String> issues;
  final String severity;
  const SentinelAudit({required this.expectedName, required this.issues, required this.severity});
}

class SentinelPolicy {
  static const Set<String> smallWords = {
    'a',
    'an',
    'the',
    'and',
    'but',
    'or',
    'nor',
    'for',
    'of',
    'to',
    'in',
    'on',
    'at',
    'by',
    'with',
    'from',
    'as',
    'per',
    'vs',
  };

  static const Set<String> highIssues = {
    'NAME_MISMATCH',
    'MISSING_TITLE',
    'MISSING_ALBUM_ARTIST',
    'MISSING_ALBUM',
    'ARTIST_ALBUM_ARTIST_MISMATCH',
    'NAME_COLLISION',
    'UNREADABLE_TAGS',
  };

  static const Set<String> mediumIssues = {
    'MISSING_ARTIST',
    'MISSING_TRACK',
    'MISSING_ARTWORK',
    'MISSING_LYRICS',
    'FEAT_NOT_CANONICAL',
  };

  static final RegExp _featMarker = RegExp(r'[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\b\s*', caseSensitive: false);
  static final RegExp _featSeparator = RegExp(r'\s*(?:,|&)\s*|\s+(?:and|x|with)\s+', caseSensitive: false);
  static final RegExp _bracketVersion = RegExp(
      r'\s*[\(\[\{][^\)\]\}]*\b(?:remaster(?:ed)?|deluxe|bonus\s+track|explicit|official\s+(?:video|audio)|lyric\s+video|audio)\b[^\)\]\}]*[\)\]\}]',
      caseSensitive: false);
  static final RegExp _trailingNoise = RegExp(
      r'\s*(?:[-–—]\s*)?\b(?:official\s+music\s+video|music\s+video|lyric\s+video|lyrics?|official\s+audio|audio\s+only|visualizer|video|hd|hq|4k|8k|1080p|720p|mv|explicit|clean|full\s+song|with\s+lyrics)\s*$',
      caseSensitive: false);
  static final RegExp _whitespace = RegExp(r'\s+');

  static bool isMissing(String? value) {
    if (value == null) return true;
    final v = value.trim();
    if (v.isEmpty) return true;
    final lower = v.toLowerCase();
    return lower == '<unknown>' || lower.startsWith('unknown');
  }

  static String titleCase(String raw) {
    final text = raw.trim().replaceAll(_whitespace, ' ');
    if (text.isEmpty) return '';
    final phrase = SentinelNames.formalNames[text.toLowerCase()];
    if (phrase != null) return phrase;
    final words = text.split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      out.add(_titleCaseWord(words[i], first: i == 0, last: i == words.length - 1));
    }
    return out.join(' ');
  }

  static String _titleCaseWord(String word, {required bool first, required bool last}) {
    if (word.isEmpty) return '';
    final lower = word.toLowerCase();
    final formal = SentinelNames.formalNames[lower];
    if (formal != null) return formal;
    if (lower == 'ft.' || lower == 'ft') return 'ft.';
    if (word.contains('-')) {
      final parts = word.split('-');
      final cased = <String>[];
      for (var i = 0; i < parts.length; i++) {
        cased.add(_titleCaseWord(parts[i], first: first && i == 0, last: last && i == parts.length - 1));
      }
      return cased.join('-');
    }
    if (!first && !last && smallWords.contains(lower)) return lower;
    if (lower.startsWith('mc') && lower.length > 2) return 'Mc${lower[2].toUpperCase()}${lower.substring(3)}';
    if (lower.startsWith("o'") && lower.length > 2) return "O'${lower[2].toUpperCase()}${lower.substring(3)}";
    final idx = word.indexOf(RegExp(r'[A-Za-z0-9]'));
    if (idx < 0) return word;
    final head = word.substring(0, idx);
    final letter = word[idx].toUpperCase();
    final tail = word.substring(idx + 1).toLowerCase();
    return '$head$letter$tail';
  }

  static FeatSplit splitFeaturedArtists(String raw) {
    final text = raw.trim();
    final m = _featMarker.firstMatch(text);
    if (m == null) return FeatSplit(text, const []);
    var main = text.substring(0, m.start).trim();
    main = main.replaceAll(RegExp(r'[\(\[]\s*$'), '').trim();
    var clause = text.substring(m.end).trim();
    clause = clause.replaceAll(RegExp(r'[\)\]]\s*$'), '').trim();
    if (clause.isEmpty) return FeatSplit(main, const []);
    final feats = clause.split(_featSeparator).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return FeatSplit(main, feats);
  }

  static String canonicalFeat(List<String> names) {
    if (names.isEmpty) return '';
    final cased = names.map(titleCase).toList();
    if (cased.length == 1) return ' ft. ${cased.first}';
    if (cased.length == 2) return ' ft. ${cased[0]} & ${cased[1]}';
    return ' ft. ${cased.sublist(0, cased.length - 1).join(', ')} & ${cased.last}';
  }

  static String stripVersionNoise(String title) {
    var t = title.trim();
    String? prev;
    while (prev != t) {
      prev = t;
      t = t.replaceAll(_bracketVersion, '').trim();
      t = t.replaceFirst(_trailingNoise, '').trim();
    }
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String trackNumber(String? raw) {
    if (raw == null) return '00';
    final first = raw.trim().split('/').first.trim();
    final n = int.tryParse(first);
    if (n == null) return '00';
    return n.toString().padLeft(2, '0');
  }

  static String expectedFileName(Map<String, String> tags, {String displayName = ''}) {
    final titleRaw = (tags['TITLE'] ?? '').trim();
    final artistRaw = (tags['ARTIST'] ?? '').trim();
    final albumArtistRaw = (tags['ALBUM_ARTIST'] ?? '').trim();
    final artistSplit = splitFeaturedArtists(artistRaw);
    final titleSplit = splitFeaturedArtists(titleRaw);
    final feats = artistSplit.feats.isNotEmpty ? artistSplit.feats : titleSplit.feats;
    final albumArtistMain = splitFeaturedArtists(albumArtistRaw).main;
    final albumArtist = albumArtistMain.isNotEmpty ? titleCase(albumArtistMain) : titleCase(artistSplit.main);
    final titleMain = stripVersionNoise(titleSplit.main);
    final title = titleMain.isEmpty ? '' : titleCase(titleMain) + canonicalFeat(feats);
    final track = trackNumber(tags['TRACK']);
    final ext = TitleCleaner.extensionOf(displayName);
    return TitleCleaner.buildSentinelFileName(albumArtist: albumArtist, title: title, trackNo: track, ext: ext);
  }

  static String severityFor(List<String> issues) {
    if (issues.any(highIssues.contains)) return 'high';
    if (issues.any(mediumIssues.contains)) return 'medium';
    return 'low';
  }

  static String _norm(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[\(\)\[\]]'), '').replaceAll(_whitespace, ' ').trim();
  }

  static SentinelAudit audit(Map<String, String> tags, String displayName, {bool triage = false}) {
    final issues = <String>[];
    final title = (tags['TITLE'] ?? '').trim();
    final artist = (tags['ARTIST'] ?? '').trim();
    final albumArtist = (tags['ALBUM_ARTIST'] ?? '').trim();
    final album = (tags['ALBUM'] ?? '').trim();
    final track = (tags['TRACK'] ?? '').trim();
    final year = (tags['YEAR'] ?? '').trim();
    final genre = (tags['GENRE'] ?? '').trim();
    final expected = expectedFileName(tags, displayName: displayName);
    if (displayName.isNotEmpty && displayName != expected) issues.add('NAME_MISMATCH');
    if (isMissing(title)) issues.add('MISSING_TITLE');
    if (isMissing(albumArtist) && isMissing(artist)) issues.add('MISSING_ALBUM_ARTIST');
    if (isMissing(artist) && !isMissing(albumArtist)) issues.add('MISSING_ARTIST');
    if (isMissing(album)) issues.add('MISSING_ALBUM');
    if (trackNumber(tags['TRACK']) == '00' && (track.isEmpty || int.tryParse(track.split('/').first.trim()) == null)) issues.add('MISSING_TRACK');
    if (year.isEmpty || !RegExp(r'^\d{4}$').hasMatch(year)) issues.add('MISSING_YEAR');
    if (isMissing(genre)) issues.add('MISSING_GENRE');
    if (!triage) {
      final hasArt = (tags['ARTWORK'] ?? '').toLowerCase() == 'true' || (tags['ARTWORK_BASE64'] ?? '').isNotEmpty;
      if (!hasArt) issues.add('MISSING_ARTWORK');
      final hasLyrics = (tags['LYRICS'] ?? '').trim().isNotEmpty || (tags['SIDECAR_LYRICS'] ?? '').toLowerCase() == 'true';
      if (!hasLyrics) issues.add('MISSING_LYRICS');
    }
    final artistSplit = splitFeaturedArtists(artist);
    final albumArtistMain = splitFeaturedArtists(albumArtist).main;
    if (!isMissing(artistSplit.main) && !isMissing(albumArtistMain) && titleCase(artistSplit.main) != titleCase(albumArtistMain)) {
      issues.add('ARTIST_ALBUM_ARTIST_MISMATCH');
    }
    final titleSplit = splitFeaturedArtists(title);
    final feats = artistSplit.feats.isNotEmpty ? artistSplit.feats : titleSplit.feats;
    if (feats.isNotEmpty) {
      final canonicalArtist = titleCase(artistSplit.main) + canonicalFeat(feats);
      final canonicalTitle = (stripVersionNoise(titleSplit.main).isEmpty ? '' : titleCase(stripVersionNoise(titleSplit.main))) + canonicalFeat(feats);
      if (artistSplit.feats.isEmpty || titleSplit.feats.isEmpty) {
        issues.add('FEAT_NOT_CANONICAL');
      } else if (_norm(artist) != _norm(canonicalArtist) || _norm(stripVersionNoise(title)) != _norm(canonicalTitle)) {
        issues.add('FEAT_NOT_CANONICAL');
      }
    }
    final driftFields = [stripVersionNoise(titleSplit.main), artistSplit.main, albumArtistMain, album];
    var drift = false;
    for (final field in driftFields) {
      if (field.isEmpty || isMissing(field)) continue;
      if (field != titleCase(field)) {
        drift = true;
        break;
      }
    }
    if (drift && !issues.contains('TITLE_CASE_DRIFT')) issues.add('TITLE_CASE_DRIFT');
    return SentinelAudit(expectedName: expected, issues: issues, severity: severityFor(issues));
  }
}
