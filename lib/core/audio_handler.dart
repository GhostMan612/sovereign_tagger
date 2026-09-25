// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class SovereignAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player;

  SovereignAudioHandler(this.player) {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    
    player.currentIndexStream.listen((index) {
      if (index == null || queue.value.isEmpty) return;
      if (index < 0 || index >= queue.value.length) return;
      mediaItem.add(queue.value[index]);
    });

    player.sequenceStateStream.listen((state) {
      if (state == null) return;
      final seq = state.sequence;
      if (seq.isEmpty) return;
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }

  MediaItem _fileToMediaItem(String path, {String? title, String? artist}) {
    final fileName = path.split('/').last;
    final name = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    String displayTitle = title?.isNotEmpty == true ? title! : name;
    String displayArtist = artist?.isNotEmpty == true ? artist! : "Sovereign Tagger";
    return MediaItem(
      id: path,
      album: "Sovereign Tagger",
      title: displayTitle,
      artist: displayArtist,
      artUri: null,
      duration: player.duration,
    );
  }

  Future<void> syncQueue(List<String> paths, {Map<String, Map<String, String>>? tagMap}) async {
    final items = paths.map((p) {
      final tags = tagMap?[p];
      return _fileToMediaItem(p, title: tags?['TITLE'], artist: tags?['ARTIST']);
    }).toList();
    queue.add(items);
    if (items.isNotEmpty) {
      final idx = player.currentIndex ?? 0;
      if (idx >= 0 && idx < items.length) {
        mediaItem.add(items[idx]);
      }
    }
  }

  Future<void> updateNowPlaying(String path, {String? title, String? artist}) async {
    mediaItem.add(_fileToMediaItem(path, title: title, artist: artist));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() => player.seekToPrevious();

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);
}
