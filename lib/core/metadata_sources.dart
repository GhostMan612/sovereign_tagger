// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'ffmpeg_executor.dart';
import 'media_probe.dart';
import 'storage_client.dart';

class MetaCandidate {
  final String source;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String year;
  final String genre;
  final String trackNo;
  final String trackTotal;
  final String discNo;
  final String discTotal;
  final String artworkUrl;
  final int durationMs;
  final double score;

  const MetaCandidate({
    required this.source,
    required this.title,
    required this.artist,
    this.album = '',
    this.albumArtist = '',
    this.year = '',
    this.genre = '',
    this.trackNo = '',
    this.trackTotal = '',
    this.discNo = '',
    this.discTotal = '',
    this.artworkUrl = '',
    this.durationMs = 0,
    this.score = 0,
  });

  static String _s(Object? v) => (v == null || v.toString() == 'null' || v.toString() == '0') ? '' : v.toString();

  factory MetaCandidate.fromJson(Map<String, dynamic> j) => MetaCandidate(
        source: _s(j['source']),
        title: _s(j['title']),
        artist: _s(j['artist']),
        album: _s(j['album']),
        albumArtist: _s(j['album_artist']),
        year: _s(j['year']),
        genre: _s(j['genre']),
        trackNo: _s(j['track_no']),
        trackTotal: _s(j['track_total']),
        discNo: _s(j['disc_no']),
        discTotal: _s(j['disc_total']),
        artworkUrl: _s(j['artwork_url']),
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );

  Map<String, String> toTags() => {
        'TITLE': title,
        'ARTIST': artist,
        'ALBUM': album,
        'ALBUM_ARTIST': albumArtist.isNotEmpty ? albumArtist : artist,
        'YEAR': year,
        'GENRE': genre,
        'TRACK': trackNo,
        'TRACK_TOTAL': trackTotal,
        'DISC_NO': discNo,
        'DISC_TOTAL': discTotal,
      };

  String get label {
    final parts = [album, year].where((p) => p.isNotEmpty).join(' • ');
    return parts.isEmpty ? source.toUpperCase() : parts;
  }
}

class SpiderResult {
  final double confidence;
  final List<MetaCandidate> candidates;
  final String lyricsPlain;
  final String lyricsSynced;
  final String lyricsSource;
  final String queryArtist;
  final String queryTitle;
  final String queryTrackNo;
  final List<String> errors;

  const SpiderResult({
    required this.confidence,
    required this.candidates,
    required this.lyricsPlain,
    required this.lyricsSynced,
    required this.lyricsSource,
    required this.queryArtist,
    required this.queryTitle,
    required this.queryTrackNo,
    required this.errors,
  });

  MetaCandidate? get best => candidates.isEmpty ? null : candidates.first;
}

class MetadataException implements Exception {
  final String message;
  MetadataException(this.message);
  @override
  String toString() => message;
}

class MetadataSources {
  static const MethodChannel _spider = MethodChannel('com.sovereign.tagger/spider');
  static const MethodChannel _acr = MethodChannel('com.sovereign.tagger/acrcloud');

  static Future<SpiderResult> search({required String artist, required String title, String album = '', int durationMs = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final geniusKey = prefs.getString('genius_key') ?? '';
    final raw = await _spider.invokeMethod('scrape', {
      'artist': artist,
      'title': title,
      'album': album,
      'durationMs': durationMs,
      'geniusKey': geniusKey,
    });
    final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    if (data['status'] != 'success') throw MetadataException(data['message']?.toString() ?? 'Spider fault');
    final query = (data['query'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SpiderResult(
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      candidates: ((data['candidates'] as List?) ?? const []).whereType<Map>().map((m) => MetaCandidate.fromJson(m.cast<String, dynamic>())).toList(),
      lyricsPlain: data['lyrics_plain']?.toString() ?? '',
      lyricsSynced: data['lyrics_synced']?.toString() ?? '',
      lyricsSource: data['lyrics_source']?.toString() ?? '',
      queryArtist: query['artist']?.toString() ?? artist,
      queryTitle: query['title']?.toString() ?? title,
      queryTrackNo: query['track_no']?.toString() ?? '',
      errors: ((data['errors'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  static Future<({String plain, String synced})> fetchLyrics({required String artist, required String title, String album = '', int durationMs = 0}) async {
    final raw = await _spider.invokeMethod('fetchLyrics', {'artist': artist, 'title': title, 'album': album, 'durationMs': durationMs});
    final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    return (plain: data['plain']?.toString() ?? '', synced: data['synced']?.toString() ?? '');
  }

  static Future<String?> fetchArtworkBase64(String url) async {
    if (url.isEmpty) return null;
    try {
      final raw = await _spider.invokeMethod('fetchArtwork', {'url': url});
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      final b64 = data['artwork_base64']?.toString() ?? '';
      return b64.isEmpty ? null : b64;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> acrConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('acr_host') ?? '').isNotEmpty && (prefs.getString('acr_key') ?? '').isNotEmpty && (prefs.getString('acr_secret') ?? '').isNotEmpty;
  }

  static Future<MetaCandidate?> acrIdentify(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('acr_host') ?? '';
    final key = prefs.getString('acr_key') ?? '';
    final secret = prefs.getString('acr_secret') ?? '';
    if (host.isEmpty || key.isEmpty || secret.isEmpty) throw MetadataException('ACRCloud keys missing in Settings.');

    await _acr.invokeMethod('initialize', {'host': host, 'accessKey': key, 'accessSecret': secret});
    final temp = await StorageClient.tempDir();
    final wav = '$temp/acr_snippet_${DateTime.now().microsecondsSinceEpoch}.wav';
    final durationMs = await probeDurationMs(path) ?? 0;
    final start = durationMs > 50000 ? 25 : 0;
    try {
      final session = await FFmpegExecutor.execute('-y -ss $start -i "$path" -t 15 -vn -ar 8000 -ac 1 -c:a pcm_s16le "$wav"');
      if (!ReturnCode.isSuccess(session.getReturnCode())) throw MetadataException('FFmpeg snippet fault.');
      final raw = await _acr.invokeMethod('identify', {'filePath': wav});
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final status = (data['status'] as Map?)?.cast<String, dynamic>();
      if (status == null || status['code'] != 0) return null;
      final music = ((data['metadata'] as Map?)?['music'] as List?)?.whereType<Map>().toList() ?? const [];
      if (music.isEmpty) return null;
      final m = music.first.cast<String, dynamic>();
      final artists = (m['artists'] as List?)?.whereType<Map>().map((a) => a['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList() ?? const <String>[];
      final genres = (m['genres'] as List?)?.whereType<Map>().map((g) => g['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList() ?? const <String>[];
      final album = (m['album'] as Map?)?['name']?.toString() ?? '';
      final release = m['release_date']?.toString() ?? '';
      return MetaCandidate(
        source: 'acrcloud',
        title: m['title']?.toString() ?? '',
        artist: artists.join(', '),
        album: album,
        albumArtist: artists.isNotEmpty ? artists.first : '',
        year: release.length >= 4 ? release.substring(0, 4) : '',
        genre: genres.isNotEmpty ? genres.first : '',
        durationMs: (m['duration_ms'] as num?)?.toInt() ?? 0,
        score: ((m['score'] as num?)?.toDouble() ?? 100) / 100,
      );
    } finally {
      try {
        final f = File(wav);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}
