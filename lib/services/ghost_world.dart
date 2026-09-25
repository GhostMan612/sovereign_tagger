// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/forge_request.dart';
import '../core/playlists.dart';
import '../core/storage_client.dart';
import '../screens/eq_presets_screen.dart';
import '../screens/main_shell.dart';
import '../screens/playback_engine_screen.dart';
import '../screens/settings_screen.dart';
import '../tabs/tab_library.dart';
import '../tabs/tab_player.dart';
import 'ghost_brain.dart';

class AppGhostWorld implements GhostWorld {
  static const Duration _cacheLife = Duration(minutes: 2);

  final BuildContext Function() _context;
  List<GhostTrack>? _cache;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  AppGhostWorld(this._context);

  String? get _currentPath {
    final index = AudioService.currentIndex.value;
    final list = AudioService.playlist.value;
    return index >= 0 && index < list.length ? list[index].path : null;
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
  Future<List<GhostTrack>> library() async {
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
    } catch (_) {
      return cached ?? const [];
    }
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
    _register(ordered);
    await AudioService.playFiles(ordered.map((t) => File(t.path)).toList());
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
    SovereignState.pendingGrabberUrl.value = url;
    openTab(0);
  }

  @override
  bool forgeCurrent() {
    final path = _currentPath;
    if (path == null) return false;
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
      await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('openUrl', {'url': url});
      return true;
    } catch (_) {
      return false;
    }
  }
}
