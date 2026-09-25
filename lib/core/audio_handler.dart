// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class TransportCallbacks {
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function() stop;
  final Future<void> Function() next;
  final Future<void> Function() previous;
  final Future<void> Function(Duration position) seek;
  final Future<void> Function(int index) skipToIndex;
  final bool Function() isPlaying;

  const TransportCallbacks({
    required this.play,
    required this.pause,
    required this.stop,
    required this.next,
    required this.previous,
    required this.seek,
    required this.skipToIndex,
    required this.isPlaying,
  });
}

class SovereignAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;
  final TransportCallbacks transport;
  MediaItem? _current;

  SovereignAudioHandler(this.player, this.transport) {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    player.playbackEventStream.listen((event) => playbackState.add(_transformEvent(event)));
    player.playingStream.listen((_) => playbackState.add(_transformEvent(player.playbackEvent)));

    player.durationStream.listen((d) {
      final item = _current;
      if (item == null || d == null || item.duration == d) return;
      _current = item.copyWith(duration: d);
      mediaItem.add(_current);
    });
  }

  void refreshState() => playbackState.add(_transformEvent(player.playbackEvent));

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = transport.isPlaying();
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }

  static MediaItem buildItem(String path, {String? title, String? artist, String? album, Uri? artUri, Duration? duration}) {
    final fileName = path.split('/').last;
    final name = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    return MediaItem(
      id: path,
      title: (title?.isNotEmpty ?? false) ? title! : name,
      artist: (artist?.isNotEmpty ?? false) ? artist! : null,
      album: (album?.isNotEmpty ?? false) ? album! : null,
      artUri: artUri,
      duration: duration,
    );
  }

  Future<void> syncQueue(List<MediaItem> items) async {
    queue.add(items);
  }

  Future<void> updateNowPlaying(MediaItem item) async {
    _current = item.duration == null && player.duration != null ? item.copyWith(duration: player.duration) : item;
    mediaItem.add(_current);
  }

  @override
  Future<void> play() => transport.play();

  @override
  Future<void> pause() => transport.pause();

  @override
  Future<void> stop() => transport.stop();

  @override
  Future<void> seek(Duration position) => transport.seek(position);

  @override
  Future<void> skipToNext() => transport.next();

  @override
  Future<void> skipToPrevious() => transport.previous();

  @override
  Future<void> skipToQueueItem(int index) => transport.skipToIndex(index);

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
}
