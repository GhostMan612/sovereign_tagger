// ============================================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/forge_request.dart';
import '../core/ghost_commands.dart';
import '../core/metadata_sources.dart';
import '../core/playlists.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../core/voice_input.dart';
import '../screens/eq_presets_screen.dart';
import '../screens/main_shell.dart';
import '../screens/playback_engine_screen.dart';
import '../screens/settings_screen.dart';
import '../tabs/tab_library.dart';
import '../tabs/tab_player.dart';
import 'ghost_brain.dart';

class AppGhostWorld implements GhostWorld {
  static const Duration _cacheLife = Duration(minutes: 2);
  static const MethodChannel _ytChannel = MethodChannel('com.sovereign.tagger/ytdlp');
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');

  static int _generation = 0;
  static bool _hooked = false;
  static double _preDuckVolume = 1.0;
  int _seenGeneration = 0;

  final BuildContext Function() _context;
  List<GhostTrack>? _cache;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  AppGhostWorld(this._context) {
    _ensureHook();
    _seenGeneration = _generation;
  }

  String? get _currentPath {
    final index = AudioService.currentIndex.value;
    final list = AudioService.playlist.value;
    if (index >= 0 && index < list.length) {
      return list[index].path;
    }
    return GhostCommandBus.lastMountedForgePath;
  }

  NavigatorState? get _navigator {
    final context = _context();
    return context.mounted ? Navigator.maybeOf(context) : null;
  }

  @override
  int get currentTab => SovereignState.currentTab.value;

  @override
  bool get hasMedia => AudioService.hasMedia.value && AudioService.playlist.value.isNotEmpty;

  @override
  bool get isPlaying => AudioService.player.playing || (AudioService.videoController.value?.value.isPlaying ?? false);

  @override
  String get nowTitle => AudioService.currentTitle.value;

  @override
  String get nowArtist => AudioService.currentArtist.value;

  @override
  int get queueLength => AudioService.playlist.value.length;

  @override
  bool get shuffle => AudioService.isShuffle.value;

  @override
  String get repeat => AudioService.repeatMode.value.name;

  @override
  bool get currentIsFavorite {
    final path = _currentPath;
    return path != null && PlaylistStore.isFavorite(path);
  }

  @override
  String? get activeFilePath => _currentPath;

  @override
  Future<List<GhostTrack>> library() async {
    if (_seenGeneration != _generation) {
      _invalidate();
      _seenGeneration = _generation;
    }
    final cached = _cache;
    if (cached != null && cached.isNotEmpty && DateTime.now().difference(_cachedAt) < _cacheLife) return cached;
    try {
      final rows = await StorageClient.queryAudio();
      final tracks = rows
          .map(LibTrack.fromMap)
          .where((t) => t.path.isNotEmpty)
          .map((t) => GhostTrack(path: t.path, title: t.title, artist: t.artist, album: t.album, trackNo: t.track, discNo: t.disc))
          .toList();
      _cache = tracks;
      _cachedAt = DateTime.now();
      return tracks;
    } catch (e) {
      debugPrint('GHOST: library query failed (${_cache == null ? 'no cache yet' : 'serving ${_cachedAt.difference(DateTime.now()).inMinutes}m-old cache'}): $e');
      return cached ?? const [];
    }
  }

  void _invalidate() {
    _cache = null;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static void _ensureHook() {
    if (_hooked) return;
    _hooked = true;
    StorageClient.libraryRevision.addListener(() => _generation++);

    // Track any file sent to Forge so "loaded file" voice commands always know the target path
    SovereignState.pendingForge.addListener(() {
      final req = SovereignState.pendingForge.value;
      if (req != null && req.path.isNotEmpty) {
        GhostCommandBus.lastMountedForgePath = req.path;
      }
    });

    // Automatically duck AudioService volume during voice command recording
    VoiceInput.onRecordingStarted = () async {
      try {
        _preDuckVolume = AudioService.player.volume;
        if (_preDuckVolume > 0.2) {
          await AudioService.player.setVolume(0.18);
        }
      } catch (_) {}
    };
    VoiceInput.onRecordingStopped = () async {
      try {
        await AudioService.player.setVolume(_preDuckVolume > 0 ? _preDuckVolume : 1.0);
      } catch (_) {}
    };
  }

  void _register(List<GhostTrack> tracks) {
    for (final t in tracks) {
      AudioService.registerInfo(t.path, TrackInfo(title: t.title, artist: t.artist, album: t.album));
    }
  }

  @override
  Future<void> play() => AudioService.resume();

  @override
  Future<void> pause() => AudioService.pause();

  @override
  void next() => AudioService.nextTrack();

  @override
  void previous() => AudioService.prevTrack();

  @override
  void setShuffle(bool on) => AudioService.isShuffle.value = on;

  @override
  void setRepeat(String mode) => AudioService.repeatMode.value = PlaybackRepeat.values.byName(mode);

  @override
  void setSleepMinutes(int minutes) => AudioService.setSleepTimer(minutes);

  @override
  void setSleepAtEndOfTrack(bool on) => AudioService.setSleepAtEndOfTrack(on);

  @override
  Future<void> playTracks(List<GhostTrack> tracks, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    final ordered = List<GhostTrack>.of(tracks);
    if (shuffle) ordered.shuffle();
    final ok = await AudioService.playFiles(ordered.map((t) => File(t.path)).toList());
    if (!ok) {
      _register(ordered);
      throw StateError('The player rejected ${ordered.length} source(s) - nothing loaded.');
    }
    _register(ordered);
  }

  @override
  Future<void> queueTracks(List<GhostTrack> tracks, {bool next = false}) async {
    if (tracks.isEmpty) return;
    _register(tracks);
    if (!next) {
      await AudioService.addAllToQueue(tracks.map((t) => File(t.path)).toList());
      return;
    }
    for (final t in tracks.reversed) {
      await AudioService.playNext(File(t.path));
    }
  }

  @override
  void openTab(int index) {
    _navigator?.popUntil((route) => route.isFirst);
    SovereignState.currentTab.value = index;
  }

  void _push(Widget screen, {bool fullscreen = false}) {
    _navigator?.push(MaterialPageRoute(fullscreenDialog: fullscreen, builder: (_) => screen));
  }

  @override
  void openPlayer() => _push(const TheaterScreen(), fullscreen: true);

  @override
  void openSettings() => _push(const SettingsScreen());

  @override
  void openEq() => _push(const EqPresetsScreen());

  @override
  void openPlaybackEngine() => _push(const PlaybackEngineScreen());

  @override
  void grab(String url) {
    GhostCommandBus.lastGrabbedUrl = url;
    SovereignState.pendingGrabberUrl.value = url;
    openTab(0);
  }

  @override
  bool forgeCurrent() {
    final path = _currentPath;
    if (path == null) return false;
    GhostCommandBus.lastMountedForgePath = path;
    SovereignState.sendToForge(ForgeRequest(path: path, origin: ForgeOrigin.player, originUri: AudioService.infoFor(path)?.uri));
    return true;
  }

  @override
  bool toggleFavoriteCurrent() {
    final path = _currentPath;
    if (path == null) return false;
    PlaylistStore.toggleFavorite(path);
    return PlaylistStore.isFavorite(path);
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      await _storageChannel.invokeMethod('openUrl', {'url': url});
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==========================================================================
  // GhostBrain v2 Cross-Tab Automation Capabilities (Grabber & Forge)
  // ==========================================================================

  @override
  Future<List<GrabberSearchHit>> searchGrabber(String query, {String source = 'youtube'}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    openTab(0);
    GhostCommandBus.pendingGrabberCommand.value = GrabberCommand(
      queryOrUrl: clean,
      isSearchQuery: true,
      source: source,
      autoDownloadTopResult: false,
    );
    try {
      final raw = await _ytChannel.invokeMethod('searchMedia', {
        'query': clean,
        'source': source,
      });
      if (raw == null) return const [];
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      if (data['status'] != 'success') return const [];
      final list = (data['results'] as List<dynamic>? ?? const []);
      final hits = <GrabberSearchHit>[];
      for (final item in list) {
        if (item is! Map) continue;
        final url = (item['webpage_url'] ?? item['url'] ?? '').toString().trim();
        final title = (item['title'] ?? '').toString().trim();
        final uploader = (item['uploader'] ?? item['channel'] ?? item['artist'] ?? '').toString().trim();
        final dur = int.tryParse((item['duration'] ?? '0').toString()) ?? 0;
        if (url.isNotEmpty && title.isNotEmpty) {
          hits.add(GrabberSearchHit(
            title: title,
            artistOrChannel: uploader,
            url: url,
            durationSeconds: dur,
            source: source,
          ));
        }
      }
      if (hits.isNotEmpty) {
        SovereignState.pendingGrabberUrl.value = hits.first.url;
      }
      return hits;
    } catch (e) {
      debugPrint('GHOST: searchGrabber failed: $e');
      return const [];
    }
  }

  @override
  Future<String?> downloadInGrabber(
    String url, {
    String? label,
    bool isVideo = false,
    String mode = 'm4a',
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;
    GhostCommandBus.lastGrabbedUrl = cleanUrl;
    openTab(0);
    SovereignState.pendingGrabberUrl.value = cleanUrl;
    GhostCommandBus.pendingGrabberCommand.value = GrabberCommand(
      queryOrUrl: cleanUrl,
      isSearchQuery: false,
      mode: isVideo
          ? GrabberMediaMode.video
          : (mode == 'mp3' ? GrabberMediaMode.mp3 : GrabberMediaMode.m4a),
      autoDownloadTopResult: true,
    );

    final jobId = 'ghost_${DateTime.now().millisecondsSinceEpoch}';
    try {
      // Trigger download directly on the native ytdlp channel as well so it starts immediately
      // even if TabGrabber hasn't applied the optional GhostCommandBus listener patch yet.
      unawaited(_ytChannel.invokeMethod('downloadMedia', {
        'url': cleanUrl,
        'formatId': isVideo ? 'best' : 'bestaudio',
        'jobId': jobId,
        'isVideo': isVideo,
        'isPlaylist': cleanUrl.contains('playlist?list='),
        'mode': mode,
      }));
      return jobId;
    } catch (e) {
      debugPrint('GHOST: downloadInGrabber channel call error: $e');
      return null;
    }
  }

  @override
  Future<GhostForgeOutcome> forgeExtract({
    String? targetPath,
    String? customQuery,
    bool fetchMetadata = true,
    bool fetchLyrics = true,
    bool useAcrFingerprint = false,
  }) async {
    final path = targetPath ?? _currentPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return const GhostForgeOutcome(
        ok: false,
        summary: "No audio file is loaded or playing yet. Play a track or mount a file in FORGE first.",
      );
    }

    GhostCommandBus.lastMountedForgePath = path;
    try {
      final existingTags = await TagIO.read(path, withArtwork: false);
      final fileName = path.split('/').last;
      final baseName = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;

      var artist = (existingTags['ARTIST'] ?? '').trim();
      var title = (existingTags['TITLE'] ?? '').trim();
      var album = (existingTags['ALBUM'] ?? '').trim();
      final durationMs = int.tryParse(existingTags['DURATION_MS'] ?? '') ?? 0;

      if (customQuery != null && customQuery.trim().isNotEmpty) {
        final q = customQuery.trim();
        if (q.contains(' - ')) {
          final parts = q.split(' - ');
          artist = parts.first.trim();
          title = parts.sublist(1).join(' - ').trim();
        } else {
          title = q;
        }
      } else if (title.isEmpty) {
        if (baseName.contains(' - ')) {
          final parts = baseName.split(' - ');
          if (artist.isEmpty) artist = parts.first.trim();
          title = parts.sublist(1).join(' - ').trim();
        } else {
          title = baseName;
        }
      }

      final prefill = <String, String>{};
      String? matchedSummary;
      String? lyricsSummary;

      // 1. Optional 15s ACRCloud Audio Fingerprinting
      if (useAcrFingerprint) {
        final hit = await MetadataSources.acrIdentify(path);
        if (hit != null) {
          artist = hit.artist.isNotEmpty ? hit.artist : artist;
          title = hit.title.isNotEmpty ? hit.title : title;
          album = hit.album.isNotEmpty ? hit.album : album;
          if (hit.title.isNotEmpty) prefill['TITLE'] = hit.title;
          if (hit.artist.isNotEmpty) prefill['ARTIST'] = hit.artist;
          if (hit.album.isNotEmpty) prefill['ALBUM'] = hit.album;
          if (hit.albumArtist.isNotEmpty) prefill['ALBUMARTIST'] = hit.albumArtist;
          if (hit.year.isNotEmpty) prefill['YEAR'] = hit.year;
          if (hit.genre.isNotEmpty) prefill['GENRE'] = hit.genre;
          if (hit.trackNo.isNotEmpty) prefill['TRACK'] = hit.trackNo;
          if (hit.discNo.isNotEmpty) prefill['DISC'] = hit.discNo;
          matchedSummary = "ACRCloud fingerprint matched '${hit.artist} - ${hit.title}'";
        }
      }

      // 2. Multi-catalog Metadata & LRCLIB Search (iTunes + Deezer + MusicBrainz + LRCLIB)
      if (fetchMetadata) {
        final res = await MetadataSources.search(
          artist: artist,
          title: title,
          album: album,
          durationMs: durationMs,
        );
        if (res.candidates.isNotEmpty) {
          final best = res.candidates.first;
          if (best.title.isNotEmpty) prefill['TITLE'] = best.title;
          if (best.artist.isNotEmpty) prefill['ARTIST'] = best.artist;
          if (best.album.isNotEmpty) prefill['ALBUM'] = best.album;
          if (best.albumArtist.isNotEmpty) prefill['ALBUMARTIST'] = best.albumArtist;
          if (best.year.isNotEmpty) prefill['YEAR'] = best.year;
          if (best.genre.isNotEmpty) prefill['GENRE'] = best.genre;
          if (best.trackNo.isNotEmpty) prefill['TRACK'] = best.trackNo;
          if (best.discNo.isNotEmpty) prefill['DISC'] = best.discNo;
          artist = best.artist.isNotEmpty ? best.artist : artist;
          title = best.title.isNotEmpty ? best.title : title;
          album = best.album.isNotEmpty ? best.album : album;
          matchedSummary ??=
              "Matched '${best.artist} - ${best.title}' (${best.album.isEmpty ? best.source : best.album})";
        }
        if (res.lyricsSynced.isNotEmpty) {
          prefill['LYRICS'] = res.lyricsSynced;
          lyricsSummary = "synced LRC lyrics attached";
        } else if (res.lyricsPlain.isNotEmpty) {
          prefill['LYRICS'] = res.lyricsPlain;
          lyricsSummary = "plain lyrics attached";
        }
      }

      // 3. Dedicated Lyrics Lookup (LRCLIB / Genius fallback) if lyrics were requested and not yet populated
      if (fetchLyrics && !prefill.containsKey('LYRICS')) {
        if (title.isNotEmpty) {
          final lrc = await MetadataSources.fetchLyrics(
            artist: artist,
            title: title,
            album: album,
            durationMs: durationMs,
          );
          if (lrc.synced.isNotEmpty) {
            prefill['LYRICS'] = lrc.synced;
            lyricsSummary = "synced LRC lyrics found on LRCLIB";
          } else if (lrc.plain.isNotEmpty) {
            prefill['LYRICS'] = lrc.plain;
            lyricsSummary = "lyrics found";
          }
        }
      }

      String? suggestedName;
      final finalArtist = prefill['ARTIST'] ?? artist;
      final finalTitle = prefill['TITLE'] ?? title;
      final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')) : '';
      if (finalArtist.isNotEmpty && finalTitle.isNotEmpty) {
        final safe = '$finalArtist - $finalTitle$ext'
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        suggestedName = safe;
      }

      final autoTask = useAcrFingerprint
          ? ForgeAutoTask.acrIdentify
          : (fetchMetadata && fetchLyrics
              ? ForgeAutoTask.fullAutoTagAndLyrics
              : (fetchLyrics ? ForgeAutoTask.findLyrics : ForgeAutoTask.searchMetadata));

      SovereignState.sendToForge(
        ForgeRequest(
          path: path,
          origin: ForgeOrigin.player,
          originUri: AudioService.infoFor(path)?.uri,
          prefill: prefill,
          suggestedFileName: suggestedName,
          autoTask: autoTask,
        ),
      );

      if (prefill.isEmpty) {
        return GhostForgeOutcome(
          ok: true,
          summary:
              "Mounted '$fileName' in FORGE, but no automatic catalog match was found for '$artist - $title'. Tap SEARCH METADATA or IDENTIFY in Forge to refine.",
        );
      }

      final parts = <String>[
        if (matchedSummary != null) matchedSummary,
        if (lyricsSummary != null) lyricsSummary,
      ];
      return GhostForgeOutcome(
        ok: true,
        summary:
            "Loaded in FORGE: ${parts.join(' + ')}. Review the prefilled fields and tap SAVE & FIX ORIGINAL.",
      );
    } catch (e) {
      debugPrint('GHOST: forgeExtract failed: $e');
      return GhostForgeOutcome(
        ok: false,
        summary: "FORGE extraction fault: $e",
      );
    }
  }
}
