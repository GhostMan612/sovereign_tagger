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
import 'package:permission_handler/permission_handler.dart';

class SovereignState {
  static final ValueNotifier<String> pendingForgePath = ValueNotifier<String>("");
  static final ValueNotifier<int> currentTab = ValueNotifier<int>(0);
  static final ValueNotifier<Color> accentColor = ValueNotifier<Color>(const Color(0xFFFF003C));
}

enum PlaybackRepeat { off, all, one }

class AudioService {
  static final AudioPlayer player = AudioPlayer();
  static final ConcatenatingAudioSource _audioSource = ConcatenatingAudioSource(children: []);
  static final ValueNotifier<VideoPlayerController?> videoController = ValueNotifier<VideoPlayerController?>(null);

  static final ValueNotifier<String> currentTitle = ValueNotifier<String>("NO AUDIO LOADED");
  static final ValueNotifier<String> currentArtist = ValueNotifier<String>("[ System Idle. Tap To Mount Media. ]");
  static final ValueNotifier<bool> hasMedia = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isVideo = ValueNotifier<bool>(false);
  static final ValueNotifier<Image?> coverArtImage = ValueNotifier<Image?>(null);

  static final ValueNotifier<List<File>> playlist = ValueNotifier<List<File>>([]);
  static final ValueNotifier<int> currentIndex = ValueNotifier<int>(-1);
  
  static final ValueNotifier<PlaybackRepeat> repeatMode = ValueNotifier<PlaybackRepeat>(PlaybackRepeat.off);
  static final ValueNotifier<bool> isShuffle = ValueNotifier<bool>(false);
  
  static final ValueNotifier<int> sleepTimerMinutes = ValueNotifier<int>(0);
  static final ValueNotifier<double> speedFactor = ValueNotifier<double>(1.0);
  static Timer? sleepTimer;
  static Timer? _persistDebounce;
  static SovereignAudioHandler? _audioHandler;
  static SovereignAudioHandler? get audioHandler => _audioHandler;

  static const MethodChannel _id3Channel = MethodChannel('com.sovereign.tagger/id3');

  static void setSleepTimer(int minutes) {
    sleepTimer?.cancel();
    sleepTimerMinutes.value = minutes;
    if (minutes > 0) {
      sleepTimer = Timer(Duration(minutes: minutes), () {
        stopPlayer();
        sleepTimerMinutes.value = 0;
      });
    }
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

  static Future<void> initializeGlobalListener() async {
    await player.setAudioSource(_audioSource);

    player.sequenceStateStream.listen((sequenceState) {
      final seqEmpty = sequenceState == null || sequenceState.sequence.isEmpty;
      if (seqEmpty && playlist.value.isEmpty) {
        hasMedia.value = false;
      } else if (!seqEmpty && currentIndex.value >= 0) {
        hasMedia.value = true;
      }
    });

    player.currentIndexStream.listen((index) async {
      if (index != null && index >= 0 && index < playlist.value.length) {
        final isCurrentlyPlaying = player.playing;
        
        currentIndex.value = index;
        final path = playlist.value[index].path;
        final ext = path.split('.').last.toLowerCase();

        currentTitle.value = path.split('/').last.toUpperCase();
        currentArtist.value = "MOUNTING PAYLOAD...";
        coverArtImage.value = null;
        hasMedia.value = true;

        if (['mp4', 'mkv', 'webm'].contains(ext)) {
          isVideo.value = true;
          currentArtist.value = "[ VIDEO STREAM ]";
          
          if (isCurrentlyPlaying) {
             player.pause(); 
          }

          WakelockPlus.enable();
          
          videoController.value?.dispose();
          final vc = VideoPlayerController.file(File(path));
          await vc.initialize();
          await vc.setLooping(repeatMode.value == PlaybackRepeat.one);
          
          if (isCurrentlyPlaying) {
             vc.play();
          }
          
          bool isFinished = false;
          vc.addListener(() {
            if (vc.value.isInitialized && !isFinished) {
              if (repeatMode.value == PlaybackRepeat.one) return; 
              
              if (vc.value.position >= vc.value.duration && vc.value.duration > Duration.zero) {
                isFinished = true;
                nextTrack();
              }
            }
          });
          videoController.value = vc;
        } else {
          isVideo.value = false;
          WakelockPlus.disable();
          videoController.value?.dispose();
          videoController.value = null;
          
          _readTags(path);
          if (isCurrentlyPlaying) {
             player.play();
          }
        }
      }
    });

    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && !isVideo.value) {
        // End of queue: rewind current track + pause, but KEEP the loaded
        // state (title/art/mini-player) like commercial players do. Never
        // reset to idle here — that desyncs hasMedia/coverArt from playback.
        if (player.hasNext) return;
        player.pause();
        final idx = currentIndex.value;
        if (idx >= 0 && idx < playlist.value.length) {
          player.seek(Duration.zero, index: idx);
        }
      }
    });

    repeatMode.addListener(() {
      if (isVideo.value && videoController.value != null) {
        videoController.value!.setLooping(repeatMode.value == PlaybackRepeat.one);
      }
      switch(repeatMode.value) {
        case PlaybackRepeat.off: player.setLoopMode(LoopMode.off); break;
        case PlaybackRepeat.all: player.setLoopMode(LoopMode.all); break;
        case PlaybackRepeat.one: player.setLoopMode(LoopMode.one); break;
      }
    });

    isShuffle.addListener(() {
      player.setShuffleModeEnabled(isShuffle.value);
    });

    player.positionStream.listen((_) {
      if (player.playing) _schedulePersist();
    });

    speedFactor.addListener(() {
      player.setSpeed(speedFactor.value);
    });

    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getDouble('playback_speed');
      if (saved != null && saved > 0) speedFactor.value = saved;
    });

    restorePersistedQueue().then((restored) {
      if (!restored) autoMountMusicFolder();
    });
  }

  static Future<void> initAudioHandler() async {
    if (_audioHandler != null) return;
    try {
      _audioHandler = await audioservice.AudioService.init(
        builder: () => SovereignAudioHandler(player),
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
      final paths = playlist.value.map((f) => f.path).toList();
      await h.syncQueue(paths);
      if (currentIndex.value >= 0 && currentIndex.value < paths.length) {
        await h.updateNowPlaying(paths[currentIndex.value]);
      }
    } catch (_) {}
  }

  static AudioSource _taggedSource(File f) => AudioSource.uri(Uri.file(f.path));

  static Future<void> replacePlaylist(List<File> files, {int startIndex = 0, Duration startPosition = Duration.zero}) async {
    return _withQueueLock(() async {
      playlist.value = files;
      final sources = files.map(_taggedSource).toList();
      await _audioSource.clear();
      await _audioSource.addAll(sources);
      if (files.isNotEmpty) {
        final idx = startIndex.clamp(0, files.length - 1);
        currentIndex.value = idx;
        await player.seek(startPosition, index: idx);
      }
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static Future<void> playNext(File file) async {
    return _withQueueLock(() async {
      final currentList = List<File>.from(playlist.value);
      if (currentList.isEmpty) {
        // avoid nested lock deadlock: handle empty without re-entering lock
        playlist.value = [file];
        final sources = [file].map(_taggedSource).toList();
        await _audioSource.clear();
        await _audioSource.addAll(sources);
        currentIndex.value = 0;
        await player.seek(Duration.zero, index: 0);
        _schedulePersist();
        await _syncHandlerQueue();
        return;
      }
      final insertIdx = (currentIndex.value + 1).clamp(0, currentList.length);
      currentList.insert(insertIdx, file);
      playlist.value = currentList;
      await _audioSource.insert(insertIdx, _taggedSource(file));
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static Future<void> addToQueue(File file) async {
    return _withQueueLock(() async {
      final currentList = List<File>.from(playlist.value);
      if (currentList.isEmpty) {
        playlist.value = [file];
        final sources = [file].map(_taggedSource).toList();
        await _audioSource.clear();
        await _audioSource.addAll(sources);
        currentIndex.value = 0;
        await player.seek(Duration.zero, index: 0);
        _schedulePersist();
        await _syncHandlerQueue();
        return;
      }
      currentList.add(file);
      playlist.value = currentList;
      await _audioSource.add(_taggedSource(file));
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static Future<void> pickAndEnqueue() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      if (result == null) return;
      final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).where((file) {
        final ext = file.path.split('.').last.toLowerCase();
        return ['mp3', 'flac', 'm4a', 'wav', 'ogg', 'mp4', 'mkv', 'webm'].contains(ext);
      }).toList();
      for (final f in files) {
        await addToQueue(f);
      }
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
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () { _persistQueue(); });
  }

  static Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (playlist.value.isEmpty) {
        await prefs.remove('persist_queue');
        return;
      }
      final payload = jsonEncode({
        'paths': playlist.value.map((f) => f.path).toList(),
        'index': currentIndex.value,
        'positionMs': player.position.inMilliseconds,
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
      final files = paths.map((p) => File(p)).where((f) => f.existsSync()).toList();
      if (files.isEmpty) return false;
      int idx = (data['index'] as int?) ?? 0;
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
      final currentList = List<File>.from(playlist.value);
      final item = currentList.removeAt(oldIndex);
      currentList.insert(adjustedNewIndex, item);
      playlist.value = currentList;

      await _audioSource.move(oldIndex, adjustedNewIndex);
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static Future<void> removeFromPlaylist(int index) async {
    return _withQueueLock(() async {
      final currentList = List<File>.from(playlist.value);
      currentList.removeAt(index);
      playlist.value = currentList;
      await _audioSource.removeAt(index);
      
      if (currentList.isEmpty) {
        await stopPlayer();
      } else if (currentIndex.value == index) {
        if (index < currentList.length) {
          await playIndex(index);
        } else {
          await playIndex(index - 1);
        }
      } else if (currentIndex.value > index) {
        currentIndex.value -= 1;
      }
      _schedulePersist();
      await _syncHandlerQueue();
    });
  }

  static Future<void> autoMountMusicFolder() async {
    try {
      if (await Permission.audio.isDenied) await Permission.audio.request();
      if (await Permission.videos.isDenied) await Permission.videos.request();
      if (await Permission.storage.isDenied) await Permission.storage.request();
    } catch (_) {}
    final List<String> targetPaths = [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ];

    List<File> foundFiles = [];

    for (String path in targetPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          await for (var entity in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
            if (entity is File) {
              final ext = entity.path.split('.').last.toLowerCase();
              if (['mp3', 'flac', 'm4a', 'wav', 'ogg', 'mp4', 'mkv', 'webm'].contains(ext)) {
                foundFiles.add(entity);
              }
            }
          }
        }
      } catch (_) {}
    }

    if (foundFiles.isNotEmpty && playlist.value.isEmpty) {
      replacePlaylist(foundFiles);
    }
  }

  static Future<void> pickSingleFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        await replacePlaylist([File(result.files.single.path!)]);
      }
    } catch (_) {}
  }

  static Future<void> pickMultipleFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).where((file) {
          final ext = file.path.split('.').last.toLowerCase();
          return ['mp3', 'flac', 'm4a', 'wav', 'ogg', 'mp4', 'mkv', 'webm'].contains(ext);
        }).toList();

        if (files.isNotEmpty) {
          await replacePlaylist(files);
        }
      }
    } catch (_) {}
  }

  static Future<void> playIndex(int index) async {
    if (index < 0 || index >= playlist.value.length) return;

    if (isVideo.value && videoController.value != null) {
      videoController.value?.pause();
    }

    currentIndex.value = index;
    hasMedia.value = true;
    if (player.processingState == ProcessingState.completed) {
      try { await player.seek(Duration.zero, index: index); } catch (_) {}
    }

    try {
      await player.seek(Duration.zero, index: index);
      player.play();
      if (isVideo.value && videoController.value != null) {
        videoController.value?.play();
      }
    } catch (_) {}
  }

  static void nextTrack() {
    if (playlist.value.isEmpty) return;

    if (player.hasNext) {
        player.seekToNext();
        player.play();
        if (isVideo.value && videoController.value != null) videoController.value?.play();
    } else {
        stopPlayer();
    }
  }

  static void prevTrack() {
    if (playlist.value.isEmpty) return;

    if (isVideo.value && videoController.value != null) {
      if (videoController.value!.value.position > const Duration(seconds: 3)) {
        videoController.value!.seekTo(Duration.zero);
        return;
      }
    } else if (!isVideo.value) {
      if (player.position > const Duration(seconds: 3)) {
        player.seek(Duration.zero);
        return;
      }
    }

    if (player.hasPrevious) {
        player.seekToPrevious();
        player.play();
        if (isVideo.value && videoController.value != null) videoController.value?.play();
    }
  }

  static Future<void> stopPlayer() async {
    try { await player.stop(); } catch (_) {}
    videoController.value?.pause();
    WakelockPlus.disable();
    
    isVideo.value = false;
    currentTitle.value = "NO AUDIO LOADED";
    currentArtist.value = "[ System Idle. Tap To Mount Media. ]";
    coverArtImage.value = null;
    hasMedia.value = false;
  }

  static Future<void> clearPlaylist() async {
    await stopPlayer();
    playlist.value = [];
    await _audioSource.clear();
    currentIndex.value = -1;
    _schedulePersist();
    await _syncHandlerQueue();
  }

  static Future<void> setPlaybackSpeed(double s) async {
    speedFactor.value = s;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playback_speed', s);
    } catch (_) {}
  }

  static Future<void> _readTags(String path) async {
    try {
      final Map<Object?, Object?> rawTags = await _id3Channel.invokeMethod('readTags', {'filePath': path});
      final tags = rawTags.map((key, value) => MapEntry(key.toString(), value.toString()));

      if (tags["TITLE"]?.isNotEmpty ?? false) currentTitle.value = tags["TITLE"]!;
      if (tags["ARTIST"]?.isNotEmpty ?? false) currentArtist.value = tags["ARTIST"]!;
      if (tags["ARTWORK_BASE64"] != null && tags["ARTWORK_BASE64"]!.isNotEmpty) {
        coverArtImage.value = Image.memory(base64Decode(tags["ARTWORK_BASE64"]!), fit: BoxFit.contain);
      } else if ((tags["TITLE"]?.isEmpty ?? true) && (tags["ARTIST"]?.isEmpty ?? true)) {
        currentArtist.value = "[ UNKNOWN AUDIO ]";
      }
      if (_audioHandler != null) {
        try {
          await _audioHandler!.updateNowPlaying(path, title: tags["TITLE"], artist: tags["ARTIST"]);
        } catch (_) {}
      }
    } catch (e) {
      currentArtist.value = "[ UNKNOWN AUDIO ]";
    }
  }

  static void togglePlayPause() {
    if (isVideo.value && videoController.value != null) {
      final vc = videoController.value!;
      vc.value.isPlaying ? vc.pause() : vc.play();
    } else {
      if (player.processingState == ProcessingState.completed) {
        final idx = currentIndex.value;
        if (idx >= 0 && idx < playlist.value.length) {
          playIndex(idx);
          return;
        }
      }
      player.playing ? player.pause() : player.play();
    }
  }

  static void hapticTap() => TapFeedback.machineTap();
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  double? _miniDragPercent;
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
    AudioService.initializeGlobalListener();
    AudioService.initAudioHandler();
    SovereignState.currentTab.addListener(_onTabChanged);
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
    SovereignState.currentTab.removeListener(_onTabChanged);
    super.dispose();
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
                                      if (controller == null) return const SizedBox.shrink();
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
                                } else {
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
                                }
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.keyboard_arrow_up, color: themeColor),
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
                                  ValueListenableBuilder<bool>(
                                    valueListenable: AudioService.isVideo,
                                    builder: (context, isVideo, child) {
                                      if (isVideo) {
                                        return ValueListenableBuilder<VideoPlayerController?>(
                                          valueListenable: AudioService.videoController,
                                          builder: (context, controller, child) {
                                            if (controller == null) return const SizedBox.shrink();
                                            return ValueListenableBuilder<VideoPlayerValue>(
                                              valueListenable: controller,
                                              builder: (context, value, child) {
                                                return IconButton(
                                                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: themeColor, size: 32),
                                                  onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
                                                );
                                              }
                                            );
                                          }
                                        );
                                      } else {
                                        return StreamBuilder<PlayerState>(
                                          stream: AudioService.player.playerStateStream,
                                          builder: (context, snapshot) {
                                            final playing = snapshot.data?.playing ?? false;
                                            return IconButton(
                                              icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: themeColor, size: 32),
                                              onPressed: () => playing ? AudioService.player.pause() : AudioService.player.play(),
                                            );
                                          }
                                        );
                                      }
                                    }
                                  ),
                                ] else ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.file_open, color: themeColor, size: 28),
                                        tooltip: "Load Single File",
                                        onPressed: AudioService.pickSingleFile,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.library_music, color: themeColor, size: 28),
                                        tooltip: "Load Batch Into The Machine",
                                        onPressed: AudioService.pickMultipleFiles,
                                      ),
                                    ],
                                  )
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
              BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion), label: 'PIPELINE'),
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
        // TextPainter is short-lived here; GC reclaims. No dispose needed for non-cached painters.

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