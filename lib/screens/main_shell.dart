// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' as audioservice;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/audio_handler.dart';
import '../core/forge_request.dart';
import '../core/playback_fx.dart';
import '../core/playlists.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../tabs/tab_grabber.dart';
import '../tabs/tab_forge.dart';
import '../tabs/tab_pipeline.dart';
import '../tabs/tab_workbench.dart';
import '../tabs/tab_player.dart';
import '../tabs/tab_library.dart';
import '../widgets/machine_rain.dart';
import '../widgets/ghost_avatar.dart';
import '../widgets/ghost_chat_overlay.dart';
import '../core/tap_feedback.dart';
import '../core/ghost_settings.dart';
import 'settings_screen.dart';

class SovereignState {
  static final ValueNotifier<ForgeRequest?> pendingForge = ValueNotifier<ForgeRequest?>(null);
  static final ValueNotifier<String?> pendingGrabberUrl = ValueNotifier<String?>(null);
  static final ValueNotifier<int> currentTab = ValueNotifier<int>(0);
  static final ValueNotifier<Color> accentColor = ValueNotifier<Color>(const Color(0xFFFF003C));

  static void sendToForge(ForgeRequest request) {
    pendingForge.value = request;
    currentTab.value = 1;
  }
}

enum PlaybackRepeat { off, all, one }

class TrackInfo {
  final String title;
  final String artist;
  final String album;
  final String? uri;
  final int durationMs;
  const TrackInfo({required this.title, this.artist = '', this.album = '', this.uri, this.durationMs = 0});
}

class AudioService {
  static final AudioPlayer player = AudioPlayer(audioPipeline: PlaybackFx.createPipeline());
  static final ConcatenatingAudioSource _audioSource = ConcatenatingAudioSource(children: []);
  static final ValueNotifier<VideoPlayerController?> videoController = ValueNotifier<VideoPlayerController?>(null);

  static final ValueNotifier<String> currentTitle = ValueNotifier<String>("NO AUDIO LOADED");
  static final ValueNotifier<String> currentArtist = ValueNotifier<String>("[ System Idle. Tap To Mount Media. ]");
  static final ValueNotifier<String> currentLyrics = ValueNotifier<String>("");
  static final ValueNotifier<bool> hasMedia = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isVideo = ValueNotifier<bool>(false);
  static final ValueNotifier<Image?> coverArtImage = ValueNotifier<Image?>(null);

  static final ValueNotifier<List<File>> playlist = ValueNotifier<List<File>>([]);
  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(-1);

  static final ValueNotifier<PlaybackRepeat> repeatMode = ValueNotifier<PlaybackRepeat>(PlaybackRepeat.off);
  static final ValueNotifier<bool> isShuffle = ValueNotifier<bool>(false);

  static final ValueNotifier<int> sleepTimerMinutes = ValueNotifier<int>(0);
  static final ValueNotifier<bool> sleepAtEndOfTrack = ValueNotifier<bool>(false);
  static final ValueNotifier<double> speedFactor = ValueNotifier<double>(1.0);
  static final ValueNotifier<int> infoRevision = ValueNotifier<int>(0);
  static final Map<String, TrackInfo> _info = {};

  static Timer? sleepTimer;
  static DateTime? _sleepDeadline;
  static bool _wantPlaying = false;
  static int _loadToken = 0;
  static String _loadedKey = "";
  static DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  static String _countedPath = "";
  static String _artCacheKey = "";
  static SovereignAudioHandler? _audioHandler;
  static SovereignAudioHandler? get audioHandler => _audioHandler;
  static const MethodChannel _widgetChannel = MethodChannel('com.sovereign.tagger/widget');
  static const Set<String> videoExtensions = {'mp4', 'mkv', 'webm', 'mov'};
  static const Set<String> mediaExtensions = {'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'mp4', 'mkv', 'webm', 'mov'};

  static bool _isVideoPath(String path) => videoExtensions.contains(path.split('.').last.toLowerCase());

  static bool get isPlaying => isVideo.value ? (videoController.value?.value.isPlaying ?? false) : player.playing;

  static TrackInfo? infoFor(String path) => _info[path];

  static void registerInfo(String path, TrackInfo info) {
    _info[path] = info;
  }

  static Future<TrackInfo> ensureInfo(String path) async {
    final existing = _info[path];
    if (existing != null) return existing;
    final name = path.split('/').last;
    if (_isVideoPath(path)) {
      final info = TrackInfo(title: name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name);
      _info[path] = info;
      return info;
    }
    final tags = await TagIO.read(path);
    final info = TrackInfo(
      title: (tags['TITLE'] ?? '').isNotEmpty ? tags['TITLE']! : (name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name),
      artist: tags['ARTIST'] ?? '',
      album: tags['ALBUM'] ?? '',
      durationMs: int.tryParse(tags['DURATION_MS'] ?? '') ?? 0,
    );
    _info[path] = info;
    infoRevision.value++;
    return info;
  }

  static Future<void> _queueLock = Future.value();
  static Future<T> _withQueueLock<T>(Future<T> Function() action) async {
    final prev = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;
    await prev;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  static void setSleepTimer(int minutes) {
    sleepTimer?.cancel();
    sleepTimer = null;
    _sleepDeadline = null;
    sleepAtEndOfTrack.value = false;
    PlaybackFx.setSleepFactor(1.0);
    sleepTimerMinutes.value = minutes;
    if (minutes <= 0) return;
    _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
    sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final deadline = _sleepDeadline;
      if (deadline == null) return;
      final remaining = deadline.difference(DateTime.now());
      sleepTimerMinutes.value = remaining.inSeconds <= 0 ? 0 : (remaining.inSeconds / 60).ceil();
      if (remaining.inSeconds <= 20) PlaybackFx.setSleepFactor(remaining.inMilliseconds / 20000);
      if (remaining <= Duration.zero) {
        sleepTimer?.cancel();
        sleepTimer = null;
        _sleepDeadline = null;
        pause().then((_) => PlaybackFx.setSleepFactor(1.0));
      }
    });
  }

  static void setSleepAtEndOfTrack(bool enabled) {
    setSleepTimer(0);
    sleepAtEndOfTrack.value = enabled;
  }

  static Future<void> initializeGlobalListener() async {
    await player.setAudioSource(_audioSource);
    await PlaybackFx.init(player);

    player.sequenceStateStream.listen((sequenceState) {
      final seqEmpty = sequenceState == null || sequenceState.sequence.isEmpty;
      if (seqEmpty && playlist.value.isEmpty) {
        hasMedia.value = false;
      } else if (!seqEmpty && currentIndex.value >= 0) {
        hasMedia.value = true;
      }
    });

    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < playlist.value.length) {
        _ensureLoaded(index);
      }
    });

    player.positionDiscontinuityStream.listen((d) {
      if (d.reason == PositionDiscontinuityReason.autoAdvance && sleepAtEndOfTrack.value) {
        sleepAtEndOfTrack.value = false;
        pause();
      }
    });

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !isVideo.value) {
        if (player.hasNext) return;
        _wantPlaying = false;
        player.pause();
        final idx = currentIndex.value;
        if (idx >= 0 && idx < playlist.value.length) {
          player.seek(Duration.zero, index: idx);
        }
        if (sleepAtEndOfTrack.value) sleepAtEndOfTrack.value = false;
      }
      if (!state.playing) _persistQueue();
      _audioHandler?.refreshState();
      _pushWidget();
    });

    repeatMode.addListener(() {
      if (isVideo.value && videoController.value != null) {
        videoController.value!.setLooping(repeatMode.value == PlaybackRepeat.one);
      }
      switch (repeatMode.value) {
        case PlaybackRepeat.off:
          player.setLoopMode(LoopMode.off);
          break;
        case PlaybackRepeat.all:
          player.setLoopMode(LoopMode.all);
          break;
        case PlaybackRepeat.one:
          player.setLoopMode(LoopMode.one);
          break;
      }
    });

    isShuffle.addListener(() async {
      if (isShuffle.value) await player.shuffle();
      await player.setShuffleModeEnabled(isShuffle.value);
    });

    player.positionStream.listen((pos) {
      if (!player.playing) return;
      final now = DateTime.now();
      if (now.difference(_lastPersist) > const Duration(seconds: 5)) _persistQueue();
      final idx = currentIndex.value;
      if (pos > const Duration(seconds: 30) && idx >= 0 && idx < playlist.value.length) {
        final path = playlist.value[idx].path;
        if (_countedPath != path) {
          _countedPath = path;
          PlaylistStore.recordPlay(path);
        }
      }
    });

    speedFactor.addListener(() {
      player.setSpeed(speedFactor.value);
    });

    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getDouble('playback_speed');
      if (saved != null && saved > 0) speedFactor.value = saved;
    });

    await restorePersistedQueue();
  }

  static Future<void> _ensureLoaded(int index) async {
    if (index < 0 || index >= playlist.value.length) return;
    final key = playlist.value[index].path;
    if (key == _loadedKey) {
      currentIndex.value = index;
      return;
    }
    await _onIndexChanged(index);
  }

  static Future<void> _onIndexChanged(int index) async {
    final token = ++_loadToken;
    _loadedKey = playlist.value[index].path;
    currentIndex.value = index;
    final path = playlist.value[index].path;
    final info = _info[path];
    currentTitle.value = info?.title ?? path.split('/').last;
    currentArtist.value = info?.artist.isNotEmpty == true ? info!.artist : "MOUNTING PAYLOAD...";
    currentLyrics.value = "";
    coverArtImage.value = null;
    hasMedia.value = true;
    _countedPath = _countedPath == path ? path : "";

    if (_isVideoPath(path)) {
      isVideo.value = true;
      currentArtist.value = "[ VIDEO STREAM ]";
      if (player.playing) await player.pause();
      WakelockPlus.enable();
      final old = videoController.value;
      videoController.value = null;
      await old?.dispose();
      final vc = VideoPlayerController.file(File(path));
      try {
        await vc.initialize();
      } catch (_) {
        await vc.dispose();
        return;
      }
      if (token != _loadToken) {
        await vc.dispose();
        return;
      }
      await vc.setLooping(repeatMode.value == PlaybackRepeat.one);
      await vc.setPlaybackSpeed(speedFactor.value);
      var finished = false;
      vc.addListener(() {
        if (!vc.value.isInitialized || finished) return;
        if (repeatMode.value == PlaybackRepeat.one) return;
        if (vc.value.duration > Duration.zero && vc.value.position >= vc.value.duration) {
          finished = true;
          nextTrack();
        }
      });
      videoController.value = vc;
      if (_wantPlaying) await vc.play();
      _updateHandlerItem(path, currentTitle.value, "", null);
    } else {
      isVideo.value = false;
      WakelockPlus.disable();
      final old = videoController.value;
      videoController.value = null;
      await old?.dispose();
      if (_wantPlaying && !player.playing) player.play();
      await _readTags(path, token);
    }
    _persistQueue();
    _pushWidget();
  }

  static Future<void> initAudioHandler() async {
    if (_audioHandler != null) return;
    try {
      _audioHandler = await audioservice.AudioService.init(
        builder: () => SovereignAudioHandler(
          player,
          TransportCallbacks(
            play: resume,
            pause: pause,
            stop: stopPlayer,
            next: () async => nextTrack(),
            previous: () async => prevTrack(),
            seek: seek,
            skipToIndex: playIndex,
            isPlaying: () => isPlaying,
          ),
        ),
        config: const audioservice.AudioServiceConfig(
          androidNotificationChannelId: 'com.sovereign.tagger.audio',
          androidNotificationChannelName: 'Sovereign Tagger',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
        ),
      );
      await _syncHandlerQueue();
    } catch (_) {}
  }

  static Future<void> _syncHandlerQueue() async {
    final h = _audioHandler;
    if (h == null) return;
    try {
      final items = playlist.value.map((f) {
        final info = _info[f.path];
        return SovereignAudioHandler.buildItem(f.path, title: info?.title, artist: info?.artist, album: info?.album);
      }).toList();
      await h.syncQueue(items);
    } catch (_) {}
  }

  static void _updateHandlerItem(String path, String title, String artist, Uri? artUri, {String? album}) {
    final h = _audioHandler;
    if (h == null) return;
    try {
      h.updateNowPlaying(SovereignAudioHandler.buildItem(path, title: title, artist: artist, album: album, artUri: artUri, duration: player.duration));
    } catch (_) {}
  }

  static void _pushWidget() {
    try {
      _widgetChannel.invokeMethod('update', {
        'title': hasMedia.value ? currentTitle.value : '',
        'artist': hasMedia.value ? currentArtist.value : '',
        'playing': isPlaying,
      });
    } catch (_) {}
  }

  static AudioSource _taggedSource(File f) => AudioSource.uri(Uri.file(f.path), tag: f.path);

  static Future<void> replacePlaylist(List<File> files, {int startIndex = 0, Duration startPosition = Duration.zero, bool autoplay = false}) async {
    return _withQueueLock(() async {
      _wantPlaying = autoplay;
      playlist.value = files;
      final sources = files.map(_taggedSource).toList();
      await _audioSource.clear();
      await _audioSource.addAll(sources);
      if (files.isNotEmpty) {
        final idx = startIndex.clamp(0, files.length - 1);
        _loadedKey = "";
        await player.seek(startPosition, index: idx);
        await _ensureLoaded(idx);
        if (autoplay && !_isVideoPath(files[idx].path)) player.play();
      } else {
        currentIndex.value = -1;
      }
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> playFiles(List<File> files, {int startIndex = 0}) => replacePlaylist(files, startIndex: startIndex, autoplay: true);

  static Future<void> playNext(File file) async {
    return _withQueueLock(() async {
      final currentList = List<File>.from(playlist.value);
      if (currentList.isEmpty) {
        playlist.value = [file];
        await _audioSource.clear();
        await _audioSource.add(_taggedSource(file));
        _loadedKey = "";
        await player.seek(Duration.zero, index: 0);
        await _ensureLoaded(0);
        _persistQueue();
        await _syncHandlerQueue();
        return;
      }
      final insertIdx = (currentIndex.value + 1).clamp(0, currentList.length);
      currentList.insert(insertIdx, file);
      playlist.value = currentList;
      await _audioSource.insert(insertIdx, _taggedSource(file));
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> addToQueue(File file) => addAllToQueue([file]);

  static Future<void> addAllToQueue(List<File> files) async {
    if (files.isEmpty) return;
    return _withQueueLock(() async {
      final wasEmpty = playlist.value.isEmpty;
      playlist.value = [...playlist.value, ...files];
      await _audioSource.addAll(files.map(_taggedSource).toList());
      if (wasEmpty) {
        _loadedKey = "";
        await player.seek(Duration.zero, index: 0);
        await _ensureLoaded(0);
      }
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> playNow(File file) async {
    final idx = playlist.value.indexWhere((f) => f.path == file.path);
    if (idx >= 0) {
      await playIndex(idx);
      return;
    }
    await playNext(file);
    final newIdx = playlist.value.indexWhere((f) => f.path == file.path);
    if (newIdx >= 0) await playIndex(newIdx);
  }

  static Future<void> replacePathInQueue(String oldPath, String newPath) async {
    if (oldPath.isEmpty || oldPath == newPath) return;
    PlaylistStore.replacePath(oldPath, newPath);
    final moved = _info.remove(oldPath);
    if (moved != null) _info[newPath] = moved;
    if (!playlist.value.any((f) => f.path == oldPath)) return;
    return _withQueueLock(() async {
      final list = List<File>.from(playlist.value);
      final cur = currentIndex.value;
      final wasPlaying = player.playing;
      final pos = player.position;
      for (var i = 0; i < list.length; i++) {
        if (list[i].path != oldPath) continue;
        list[i] = File(newPath);
        await _audioSource.removeAt(i);
        await _audioSource.insert(i, _taggedSource(list[i]));
        if (i == cur) {
          playlist.value = List<File>.from(list);
          await player.seek(pos, index: i);
          _loadedKey = newPath;
          if (wasPlaying) player.play();
        }
      }
      playlist.value = list;
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> refreshNowPlaying() async {
    final idx = currentIndex.value;
    if (idx < 0 || idx >= playlist.value.length) return;
    final path = playlist.value[idx].path;
    _info.remove(path);
    _artCacheKey = "";
    if (!_isVideoPath(path)) await _readTags(path, _loadToken);
    infoRevision.value++;
  }

  static Future<void> pickAndEnqueue() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      if (result == null) return;
      final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).where((file) => mediaExtensions.contains(file.path.split('.').last.toLowerCase())).toList();
      await addAllToQueue(files);
    } catch (_) {}
  }

  static Future<void> moveAfterCurrent(int index) async {
    return _withQueueLock(() async {
      final cur = currentIndex.value;
      final n = playlist.value.length;
      if (index < 0 || index >= n || index == cur || index == cur + 1) return;

      final list = List<File>.from(playlist.value);
      final item = list.removeAt(index);
      final newCur = (index < cur) ? cur - 1 : cur;
      int insertAt = newCur + 1;
      if (insertAt > list.length) insertAt = list.length;
      list.insert(insertAt, item);
      playlist.value = list;
      currentIndex.value = newCur;

      await _audioSource.move(index, insertAt);
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> persistNow() => _persistQueue(force: true);

  static Future<void> _persistQueue({bool force = false}) async {
    _lastPersist = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (playlist.value.isEmpty) {
        await prefs.remove('persist_queue');
        return;
      }
      final payload = jsonEncode({
        'paths': playlist.value.map((f) => f.path).toList(),
        'index': currentIndex.value,
        'positionMs': isVideo.value ? (videoController.value?.value.position.inMilliseconds ?? 0) : player.position.inMilliseconds,
      });
      await prefs.setString('persist_queue', payload);
    } catch (_) {}
  }

  static Future<bool> restorePersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('persist_queue');
      if (raw == null || raw.isEmpty) return false;
      final data = jsonDecode(raw);
      final paths = (data['paths'] as List<dynamic>? ?? []).cast<String>();
      if (paths.isEmpty) return false;
      final files = <File>[];
      var idx = (data['index'] as int?) ?? 0;
      for (var i = 0; i < paths.length; i++) {
        final f = File(paths[i]);
        if (f.existsSync()) {
          files.add(f);
        } else if (i < idx) {
          idx--;
        }
      }
      if (files.isEmpty) return false;
      if (idx < 0 || idx >= files.length) idx = 0;
      final posMs = (data['positionMs'] as int?) ?? 0;
      await replacePlaylist(files, startIndex: idx, startPosition: Duration(milliseconds: posMs));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> reorderPlaylist(int oldIndex, int newIndex) async {
    return _withQueueLock(() async {
      int adjustedNewIndex = newIndex;
      if (oldIndex < adjustedNewIndex) {
        adjustedNewIndex -= 1;
      }
      if (oldIndex == adjustedNewIndex) return;
      final currentList = List<File>.from(playlist.value);
      final item = currentList.removeAt(oldIndex);
      currentList.insert(adjustedNewIndex, item);
      final cur = currentIndex.value;
      int newCur = cur;
      if (oldIndex == cur) {
        newCur = adjustedNewIndex;
      } else if (oldIndex < cur && adjustedNewIndex >= cur) {
        newCur = cur - 1;
      } else if (oldIndex > cur && adjustedNewIndex <= cur) {
        newCur = cur + 1;
      }
      playlist.value = currentList;
      currentIndex.value = newCur;

      await _audioSource.move(oldIndex, adjustedNewIndex);
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> removeFromPlaylist(int index) async {
    return _withQueueLock(() async {
      if (index < 0 || index >= playlist.value.length) return;
      final currentList = List<File>.from(playlist.value);
      currentList.removeAt(index);
      final wasCurrent = currentIndex.value == index;
      playlist.value = currentList;
      await _audioSource.removeAt(index);

      if (currentList.isEmpty) {
        await _resetToIdle();
      } else if (wasCurrent) {
        final next = index < currentList.length ? index : index - 1;
        await player.seek(Duration.zero, index: next);
        if (_wantPlaying && !_isVideoPath(currentList[next].path)) player.play();
      } else if (currentIndex.value > index) {
        currentIndex.value -= 1;
      }
      _persistQueue();
      await _syncHandlerQueue();
    });
  }

  static Future<void> removePathsFromQueue(Set<String> paths) async {
    for (var i = playlist.value.length - 1; i >= 0; i--) {
      if (paths.contains(playlist.value[i].path)) await removeFromPlaylist(i);
    }
  }

  static Future<void> pickSingleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        await playFiles([File(result.files.single.path!)]);
      }
    } catch (_) {}
  }

  static Future<void> pickMultipleFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).where((file) => mediaExtensions.contains(file.path.split('.').last.toLowerCase())).toList();
        if (files.isNotEmpty) await playFiles(files);
      }
    } catch (_) {}
  }

  static Future<void> playIndex(int index) async {
    if (index < 0 || index >= playlist.value.length) return;
    _wantPlaying = true;
    final targetIsVideo = _isVideoPath(playlist.value[index].path);
    if (isVideo.value) await videoController.value?.pause();
    hasMedia.value = true;
    try {
      if (index == currentIndex.value && player.currentIndex == index) {
        if (isVideo.value) {
          await videoController.value?.seekTo(Duration.zero);
          await videoController.value?.play();
        } else {
          await player.seek(Duration.zero, index: index);
          player.play();
        }
        return;
      }
      await player.seek(Duration.zero, index: index);
      if (!targetIsVideo) player.play();
    } catch (_) {}
  }

  static Future<void> resume() async {
    _wantPlaying = true;
    if (isVideo.value && videoController.value != null) {
      await videoController.value!.play();
      _audioHandler?.refreshState();
      _pushWidget();
      return;
    }
    if (player.processingState == ProcessingState.completed) {
      final idx = currentIndex.value;
      if (idx >= 0 && idx < playlist.value.length) {
        await playIndex(idx);
        return;
      }
    }
    player.play();
  }

  static Future<void> pause() async {
    _wantPlaying = false;
    if (isVideo.value && videoController.value != null) {
      await videoController.value!.pause();
      _audioHandler?.refreshState();
      _pushWidget();
    }
    await player.pause();
    _persistQueue();
  }

  static Future<void> seek(Duration position) async {
    if (isVideo.value && videoController.value != null) {
      await videoController.value!.seekTo(position);
    } else {
      await player.seek(position);
    }
  }

  static void togglePlayPause() {
    isPlaying ? pause() : resume();
  }

  static void nextTrack() {
    if (playlist.value.isEmpty) return;
    _wantPlaying = true;
    if (player.hasNext) {
      player.seekToNext().then((_) {
        final idx = player.currentIndex ?? 0;
        if (idx < playlist.value.length && !_isVideoPath(playlist.value[idx].path)) player.play();
      });
    } else {
      final first = player.effectiveIndices?.firstOrNull ?? 0;
      _wantPlaying = false;
      player.pause();
      videoController.value?.pause();
      player.seek(Duration.zero, index: first);
    }
  }

  static void prevTrack() {
    if (playlist.value.isEmpty) return;
    if (isVideo.value && videoController.value != null) {
      if (videoController.value!.value.position > const Duration(seconds: 3)) {
        videoController.value!.seekTo(Duration.zero);
        return;
      }
    } else if (player.position > const Duration(seconds: 3)) {
      player.seek(Duration.zero);
      return;
    }
    if (player.hasPrevious) {
      _wantPlaying = true;
      player.seekToPrevious().then((_) {
        final idx = player.currentIndex ?? 0;
        if (idx < playlist.value.length && !_isVideoPath(playlist.value[idx].path)) player.play();
      });
    } else {
      seek(Duration.zero);
    }
  }

  static Future<void> stopPlayer() async {
    _wantPlaying = false;
    try {
      await player.pause();
      await player.seek(Duration.zero);
    } catch (_) {}
    await videoController.value?.pause();
    await videoController.value?.seekTo(Duration.zero);
    WakelockPlus.disable();
    _persistQueue();
    _pushWidget();
  }

  static Future<void> _resetToIdle() async {
    _wantPlaying = false;
    try {
      await player.stop();
    } catch (_) {}
    final old = videoController.value;
    videoController.value = null;
    await old?.dispose();
    WakelockPlus.disable();
    isVideo.value = false;
    currentTitle.value = "NO AUDIO LOADED";
    currentArtist.value = "[ System Idle. Tap To Mount Media. ]";
    currentLyrics.value = "";
    coverArtImage.value = null;
    hasMedia.value = false;
    currentIndex.value = -1;
    _loadedKey = "";
    _pushWidget();
  }

  static Future<void> clearPlaylist() async {
    await _withQueueLock(() async {
      playlist.value = [];
      await _audioSource.clear();
      await _resetToIdle();
    });
    _persistQueue();
    await _syncHandlerQueue();
  }

  static Future<void> setPlaybackSpeed(double s) async {
    speedFactor.value = s;
    await videoController.value?.setPlaybackSpeed(s);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playback_speed', s);
    } catch (_) {}
  }

  static Future<Uri?> _artUriFor(String path, List<int> bytes) async {
    try {
      final key = "${path.hashCode}_${bytes.length}";
      final temp = await StorageClient.tempDir();
      final dir = Directory('$temp/art_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/$key.jpg');
      if (_artCacheKey != key) {
        for (final f in dir.listSync()) {
          if (f is File && f.path != file.path) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
        if (!file.existsSync()) await file.writeAsBytes(bytes, flush: true);
        _artCacheKey = key;
      }
      return Uri.file(file.path);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _readTags(String path, int token) async {
    try {
      final tags = await TagIO.read(path);
      if (token != _loadToken) return;
      final name = path.split('/').last;
      final title = (tags["TITLE"]?.isNotEmpty ?? false) ? tags["TITLE"]! : (name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name);
      final artist = tags["ARTIST"] ?? "";
      currentTitle.value = title;
      currentArtist.value = artist.isNotEmpty ? artist : "[ UNKNOWN ARTIST ]";
      currentLyrics.value = tags["LYRICS"] ?? "";
      _info[path] = TrackInfo(title: title, artist: artist, album: tags['ALBUM'] ?? '', uri: _info[path]?.uri, durationMs: int.tryParse(tags['DURATION_MS'] ?? '') ?? 0);
      infoRevision.value++;
      PlaybackFx.applyTrackGain(tags);
      Uri? artUri;
      final art = tags["ARTWORK_BASE64"] ?? "";
      if (art.isNotEmpty) {
        final bytes = base64Decode(art);
        coverArtImage.value = Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
        artUri = await _artUriFor(path, bytes);
      }
      if (token != _loadToken) return;
      _updateHandlerItem(path, title, artist, artUri, album: tags['ALBUM']);
      _pushWidget();
    } catch (e) {
      if (token == _loadToken) currentArtist.value = "[ UNKNOWN AUDIO ]";
    }
  }

  static void hapticTap() => TapFeedback.machineTap();
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  double? _miniDragPercent;
  StreamSubscription<String>? _shareSub;
  late final GlobalKey<GhostAvatarState> _ghostKey = GlobalKey<GhostAvatarState>();
  late final GhostAvatarController _ghostController = GhostAvatarController(_ghostKey);

  final List<Widget> _tabs = [
    const TabGrabber(),
    const TabForge(),
    const TabPipeline(),
    const TabWorkbench(),
    const TabLibrary(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlaylistStore.load();
    AudioService.initializeGlobalListener();
    AudioService.initAudioHandler();
    SovereignState.currentTab.addListener(_onTabChanged);
    _shareSub = StorageClient.sharedUrls.listen((url) {
      SovereignState.pendingGrabberUrl.value = url;
      SovereignState.currentTab.value = 0;
    }, onError: (_) {});
    SharedPreferences.getInstance().then((prefs) {
      GhostSettings.load(prefs);
      if (!GhostSettings.firstLaunchComplete.value && GhostSettings.visible.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ghostController.materialize();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    SovereignState.currentTab.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      AudioService.persistNow();
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _openTheater() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => const TheaterScreen(),
    ));
  }

  Widget _miniArt(Color themeColor) {
    return ValueListenableBuilder<Image?>(
      valueListenable: AudioService.coverArtImage,
      builder: (context, image, _) {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(4)),
          clipBehavior: Clip.antiAlias,
          child: image != null ? Image(image: image.image, fit: BoxFit.cover, gaplessPlayback: true) : Icon(Icons.keyboard_arrow_up, color: themeColor),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(
              'SOVEREIGN TAGGER',
              style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, letterSpacing: 1.5)
            ),
            backgroundColor: Colors.black,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: themeColor.withValues(alpha: 0.3), height: 1.0),
            ),
            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: GhostSettings.visible,
                builder: (context, ghostVisible, _) {
                  return IconButton(
                    icon: Icon(ghostVisible ? Icons.auto_awesome : Icons.auto_awesome_outlined, color: ghostVisible ? themeColor : Colors.white24),
                    tooltip: ghostVisible ? "HIDE GHOST" : "SUMMON GHOST",
                    onPressed: () => GhostSettings.setVisible(!ghostVisible),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.settings, color: themeColor),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                },
              )
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: SovereignState.currentTab,
                  builder: (context, tab, _) {
                    final variant = switch (tab) {
                      0 => BackdropVariant.grabber,
                      1 => BackdropVariant.forge,
                      2 => BackdropVariant.pipeline,
                      3 => BackdropVariant.workbench,
                      _ => BackdropVariant.generic,
                    };
                    return AmbientBackdrop(accentColor: themeColor, variant: variant);
                  },
                ),
              ),
              Column(
                children: [
                  Expanded(
                    child: IndexedStack(
                      index: SovereignState.currentTab.value,
                      children: _tabs,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AudioService.hasMedia,
                    builder: (context, hasMedia, child) {
                      return GestureDetector(
                        onTap: _openTheater,
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity == null) return;
                          if (details.primaryVelocity! > 300) {
                            AudioService.prevTrack();
                          } else if (details.primaryVelocity! < -300) {
                            AudioService.nextTrack();
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            border: Border(top: BorderSide(color: themeColor.withValues(alpha: 0.5))),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasMedia)
                                ValueListenableBuilder<bool>(
                                  valueListenable: AudioService.isVideo,
                                  builder: (context, isVideo, child) {
                                    if (isVideo) {
                                      return ValueListenableBuilder<VideoPlayerController?>(
                                        valueListenable: AudioService.videoController,
                                        builder: (context, controller, child) {
                                          if (controller == null) return const SizedBox(height: 16);
                                          return ValueListenableBuilder<VideoPlayerValue>(
                                            valueListenable: controller,
                                            builder: (context, value, child) {
                                              final position = value.position;
                                              final duration = value.duration;
                                              double progress = 0.0;
                                              if (duration.inMilliseconds > 0) {
                                                progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                                              }
                                              return _buildMiniProgressBar(progress, duration, themeColor, (ms) => controller.seekTo(Duration(milliseconds: ms)));
                                            },
                                          );
                                        }
                                      );
                                    }
                                    return StreamBuilder<Duration>(
                                      stream: AudioService.player.positionStream,
                                      builder: (context, snapshot) {
                                        final position = snapshot.data ?? Duration.zero;
                                        final duration = AudioService.player.duration ?? Duration.zero;
                                        double progress = 0.0;
                                        if (duration.inMilliseconds > 0) {
                                          progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                                        }
                                        return _buildMiniProgressBar(progress, duration, themeColor, (ms) => AudioService.player.seek(Duration(milliseconds: ms)));
                                      },
                                    );
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Row(
                                  children: [
                                    _miniArt(themeColor),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ValueListenableBuilder<String>(
                                            valueListenable: AudioService.currentTitle,
                                            builder: (context, title, child) {
                                              return AutoScrollText(
                                                text: title,
                                                style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white),
                                                textAlign: TextAlign.left,
                                              );
                                            }
                                          ),
                                          ValueListenableBuilder<String>(
                                            valueListenable: AudioService.currentArtist,
                                            builder: (context, artist, child) {
                                              if (artist.isEmpty) return const SizedBox.shrink();
                                              return AutoScrollText(
                                                text: artist,
                                                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor),
                                                textAlign: TextAlign.left,
                                              );
                                            }
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasMedia) ...[
                                      const IconButton(
                                        icon: Icon(Icons.skip_previous, color: Colors.white70, size: 26),
                                        onPressed: AudioService.prevTrack,
                                      ),
                                      _MiniPlayButton(themeColor: themeColor),
                                      const IconButton(
                                        icon: Icon(Icons.skip_next, color: Colors.white70, size: 26),
                                        onPressed: AudioService.nextTrack,
                                      ),
                                    ] else ...[
                                      IconButton(
                                        icon: Icon(Icons.library_music, color: themeColor, size: 28),
                                        tooltip: "OPEN LIBRARY",
                                        onPressed: () => SovereignState.currentTab.value = 4,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.file_open, color: themeColor, size: 26),
                                        tooltip: "Load Files",
                                        onPressed: AudioService.pickMultipleFiles,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                ],
              ),
              ValueListenableBuilder<bool>(
                valueListenable: GhostSettings.visible,
                builder: (context, visible, _) {
                  if (!visible) return const SizedBox.shrink();
                  return Positioned(
                    right: 16,
                    bottom: 100,
                    child: GhostChatOverlay(
                      accentColor: SovereignState.accentColor,
                      ghostController: _ghostController,
                      ghostKey: _ghostKey,
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: SovereignState.currentTab.value,
            onTap: (index) => SovereignState.currentTab.value = index,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.black,
            selectedItemColor: themeColor,
            unselectedItemColor: Colors.white38,
            selectedLabelStyle: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.download), label: 'GRABBER'),
              BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: 'FORGE'),
              BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion), label: 'BATCH'),
              BottomNavigationBarItem(icon: Icon(Icons.build), label: 'WORKBENCH'),
              BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'LIBRARY'),
            ],
          ),
        );
      }
    );
  }

  Widget _buildMiniProgressBar(double progress, Duration duration, Color themeColor, Function(int) onSeek) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekTo(Offset local) {
          final percent = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          if (duration.inMilliseconds > 0) onSeek((duration.inMilliseconds * percent).round());
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition),
          onHorizontalDragEnd: (details) {
            if (duration.inMilliseconds <= 0) return;
            final override = _miniDragPercent;
            if (override != null) {
              onSeek((duration.inMilliseconds * override).round());
              _miniDragPercent = null;
            }
          },
          onHorizontalDragUpdate: (details) {
            _miniDragPercent = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
          },
          child: Container(
            height: 16,
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 3,
              width: double.infinity,
              color: Colors.white12,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: themeColor,
                    boxShadow: [
                      BoxShadow(color: themeColor, blurRadius: 4.0, spreadRadius: 1.0),
                    ]
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayButton extends StatelessWidget {
  final Color themeColor;
  const _MiniPlayButton({required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioService.isVideo,
      builder: (context, isVideo, _) {
        if (isVideo) {
          return ValueListenableBuilder<VideoPlayerController?>(
            valueListenable: AudioService.videoController,
            builder: (context, controller, _) {
              if (controller == null) return SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))));
              return ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) => IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: themeColor, size: 32),
                  onPressed: AudioService.togglePlayPause,
                ),
              );
            },
          );
        }
        return StreamBuilder<PlayerState>(
          stream: AudioService.player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return IconButton(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: themeColor, size: 32),
              onPressed: AudioService.togglePlayPause,
            );
          },
        );
      },
    );
  }
}

class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  const AutoScrollText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
  });

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  late ScrollController _scrollController;
  bool _isScrolling = false;
  int _scrollId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _startScrollCycle();
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _scrollId++;
      _isScrolling = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _startScrollCycle();
    }
  }

  void _startScrollCycle() {
    final currentId = _scrollId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || currentId != _scrollId) return;
      try {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      } catch (_) {}

      _isScrolling = true;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || currentId != _scrollId) return;

      while (mounted && _isScrolling && _scrollId == currentId) {
        if (!_scrollController.hasClients) {
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }

        try {
          final maxScroll = _scrollController.position.maxScrollExtent;
          if (maxScroll > 0) {
            final durationMs = (maxScroll * 30).toInt();
            await _scrollController.animateTo(
              maxScroll,
              duration: Duration(milliseconds: durationMs),
              curve: Curves.linear,
            );

            if (!mounted || !_scrollController.hasClients || !_isScrolling || _scrollId != currentId) break;

            _scrollController.jumpTo(0);
            await Future.delayed(const Duration(seconds: 2));
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollId++;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleanText = widget.text.replaceAll('\n', ' ').replaceAll('\r', '');

    return LayoutBuilder(
      builder: (context, constraints) {
        final TextPainter textPainter = TextPainter(
          text: TextSpan(text: cleanText, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: double.infinity);

        final bool overflows = textPainter.size.width > constraints.maxWidth;
        textPainter.dispose();

        if (!overflows) {
          return SizedBox(
            width: constraints.maxWidth,
            child: Text(
              cleanText,
              style: widget.style,
              textAlign: widget.textAlign,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          );
        }

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Text(cleanText, style: widget.style, maxLines: 1, softWrap: false),
              const SizedBox(width: 60.0),
              Text(cleanText, style: widget.style, maxLines: 1, softWrap: false),
              const SizedBox(width: 60.0),
            ],
          ),
        );
      }
    );
  }
}
