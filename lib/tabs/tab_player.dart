// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import '../screens/main_shell.dart';
import '../screens/playback_engine_screen.dart';
import '../screens/eq_presets_screen.dart';

class TheaterScreen extends StatelessWidget {
  const TheaterScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours > 0 ? '${d.inHours}:' : '';
    return '$hours$minutes:$seconds';
  }

  void _seekVideo(VideoPlayerController controller, int seconds) {
    final newPos = controller.value.position + Duration(seconds: seconds);
    controller.seekTo(newPos);
  }

  void _showTrackMenu(BuildContext context, File file, int index, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: themeColor.withValues(alpha: 0.5)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4, width: 40,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: Icon(Icons.edit_note, color: themeColor),
                title: const Text("SEND TO FORGE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("Export to ID3 Workspace", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor.withValues(alpha: 0.7), fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  SovereignState.pendingForgePath.value = file.path;
                  SovereignState.currentTab.value = 1;
                },
              ),
              ListTile(
                leading: Icon(Icons.low_priority, color: themeColor),
                title: const Text("PLAY NEXT", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("Queue Immediately After Current Track", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor.withValues(alpha: 0.7), fontSize: 12)),
                onTap: () {
                  AudioService.moveAfterCurrent(index);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                title: const Text("REMOVE FROM THE MACHINE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent, fontWeight: FontWeight.bold)),
                subtitle: const Text("Delete from active queue", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 12)),
                onTap: () {
                  AudioService.removeFromPlaylist(index);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }
    );
  }

  void _showQueueSheet(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: themeColor.withValues(alpha: 0.5))),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: AudioService.pickSingleFile,
                        icon: Icon(Icons.file_open, color: themeColor),
                        label: Text("MOUNT SINGLE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: AudioService.pickMultipleFiles,
                        icon: const Icon(Icons.library_music, color: Colors.cyanAccent),
                        label: const Text("MOUNT BATCH", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent)),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.7))),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 4.0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => AudioService.pickAndEnqueue(),
                    icon: Icon(Icons.playlist_add, color: themeColor),
                    label: Text("ENQUEUE FILES (APPEND)", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor.withValues(alpha: 0.5))),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20.0, right: 16.0, bottom: 4.0, top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("> ACTIVE PLAYLIST", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: themeColor)),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                      onPressed: () {
                        AudioService.clearPlaylist();
                        Navigator.pop(context);
                      },
                      tooltip: "PURGE THE MACHINE",
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<File>>(
                  valueListenable: AudioService.playlist,
                  builder: (context, playlist, child) {
                    if (playlist.isEmpty) {
                      return const Center(child: Text("> System Idle. Playlist Empty.", style: TextStyle(fontFamily: 'VT323', fontSize: 16, color: Colors.white54)));
                    }
                    return ValueListenableBuilder<int>(
                      valueListenable: AudioService.currentIndex,
                      builder: (context, currentIndex, child) {
                        return ListView.builder(
                          itemCount: playlist.length,
                          itemBuilder: (context, index) {
                            final file = playlist[index];
                            final isPlaying = index == currentIndex;
                            final isVidExt = file.path.endsWith('.mp4') || file.path.endsWith('.mkv') || file.path.endsWith('.webm');
                            final itemColor = isVidExt ? Colors.cyanAccent : themeColor;
                            
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                tileColor: isPlaying ? itemColor.withValues(alpha: 0.1) : Colors.transparent,
                                leading: Icon(
                                  isVidExt ? Icons.movie : Icons.audiotrack,
                                  color: isPlaying ? itemColor : Colors.white54,
                                ),
                                title: Text(
                                  file.path.split('/').last.toUpperCase(), 
                                  maxLines: 1, 
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: 'ShareTechMono', color: isPlaying ? itemColor : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal),
                                ),
                                 onTap: () => AudioService.playIndex(index),
                                 onLongPress: () => _showTrackMenu(context, file, index, themeColor),
                               ),
                             );
                           },
                         );
                       }
                     );
                   }
                 ),
               ),
             ],
           ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, accentColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.keyboard_arrow_down, size: 32, color: accentColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text("SOVEREIGN MULTIPLEX", style: TextStyle(fontFamily: 'ShareTechMono', color: accentColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.purpleAccent),
                tooltip: "15-BAND EQUALIZER",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqPresetsScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.merge_type, color: Colors.cyanAccent),
                tooltip: "PLAYBACK ENGINE",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaybackEngineScreen())),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: accentColor.withValues(alpha: 0.3), height: 1.0),
            ),
          ),
          body: ValueListenableBuilder<bool>(
            valueListenable: AudioService.isVideo,
            builder: (context, isVideo, child) {
              final themeColor = isVideo ? Colors.cyanAccent : accentColor;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! > 300) {
                          AudioService.prevTrack();
                        } else if (details.primaryVelocity! < -300) {
                          AudioService.nextTrack();
                        }
                      },
                      child: isVideo 
                        ? Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: ValueListenableBuilder<VideoPlayerController?>(
                                valueListenable: AudioService.videoController,
                                builder: (context, controller, child) {
                                  if (controller == null || !controller.value.isInitialized) {
                                    return Center(child: CircularProgressIndicator(color: themeColor));
                                  }
                                  return Container(
                                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: controller.value.aspectRatio,
                                        child: ClipRRect(borderRadius: BorderRadius.circular(16), child: VideoPlayer(controller)),
                                      ),
                                    ),
                                  );
                                }
                              ),
                          )
                        : _DoubleTapSeek(
                            onLeft: () => AudioService.player.seek(AudioService.player.position - const Duration(seconds: 10)),
                            onRight: () => AudioService.player.seek(AudioService.player.position + const Duration(seconds: 10)),
                            child: Container(
                              color: Colors.black,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ValueListenableBuilder<Image?>(
                                    valueListenable: AudioService.coverArtImage,
                                    builder: (context, image, child) {
                                      if (image != null) {
                                        return Container(
                                          color: Colors.black,
                                          alignment: Alignment.center,
                                          child: InteractiveViewer(
                                            minScale: 1.0,
                                            maxScale: 3.0,
                                            child: Image(
                                              image: image.image,
                                              fit: BoxFit.contain,
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                        );
                                      }
                                      return Center(child: Icon(Icons.music_note, size: 160, color: themeColor.withValues(alpha: 0.12)));
                                    },
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                                          stops: const [0.55, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4), border: Border.all(color: themeColor.withValues(alpha: 0.3))),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.zoom_out_map, size: 12, color: themeColor.withValues(alpha: 0.7)),
                                        const SizedBox(width: 4),
                                        Text("PINCH TO ZOOM • DOUBLE-TAP SEEK", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: themeColor.withValues(alpha: 0.7))),
                                      ]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ),
                  ),
                  
                  if (!isVideo) ...[
                    ValueListenableBuilder<String>(
                      valueListenable: AudioService.currentTitle,
                      builder: (context, title, child) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: AutoScrollText(
                          text: title.toUpperCase(),
                          style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      )
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<String>(
                      valueListenable: AudioService.currentArtist,
                      builder: (context, artist, child) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: AutoScrollText(
                          text: artist.toUpperCase(),
                          style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, color: themeColor),
                          textAlign: TextAlign.center,
                        ),
                      )
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    const SizedBox(height: 16),
                  ],

                  if (isVideo) ...[
                    ValueListenableBuilder<VideoPlayerController?>(
                      valueListenable: AudioService.videoController,
                      builder: (context, controller, child) {
                        if (controller == null) return const SizedBox.shrink();
                        return ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: controller,
                          builder: (context, value, child) {
                            return _buildSliderControls(
                              context: context,
                              position: value.position,
                              duration: value.duration,
                              isPlaying: value.isPlaying,
                              themeColor: themeColor,
                              onSeek: (ms) => controller.seekTo(Duration(milliseconds: ms)),
                              onRewind: () => _seekVideo(controller, -10),
                              onFastForward: () => _seekVideo(controller, 10),
                              onPlayPause: () => value.isPlaying ? controller.pause() : controller.play(),
                              isVideoMode: true,
                              controller: controller,
                              onShowQueue: () => _showQueueSheet(context, themeColor),
                            );
                          }
                        );
                      }
                    ),
                  ] else ...[
                    StreamBuilder<Duration>(
                      stream: AudioService.player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final duration = AudioService.player.duration ?? Duration.zero;
                        return StreamBuilder<PlayerState>(
                          stream: AudioService.player.playerStateStream,
                          builder: (context, stateSnapshot) {
                            final playing = stateSnapshot.data?.playing ?? false;
                            return _buildSliderControls(
                              context: context,
                              position: position,
                              duration: duration,
                              isPlaying: playing,
                              themeColor: themeColor,
                              onSeek: (ms) => AudioService.player.seek(Duration(milliseconds: ms)),
                              onRewind: () => AudioService.player.seek(position - const Duration(seconds: 10)),
                              onFastForward: () => AudioService.player.seek(position + const Duration(seconds: 10)),
                              onPlayPause: () {
                                if (AudioService.player.processingState == ProcessingState.completed) {
                                  final idx = AudioService.currentIndex.value;
                                  if (idx >= 0 && idx < AudioService.playlist.value.length) {
                                    AudioService.playIndex(idx);
                                    return;
                                  }
                                }
                                playing ? AudioService.player.pause() : AudioService.player.play();
                              },
                              isVideoMode: false,
                              controller: null,
                              onShowQueue: () => _showQueueSheet(context, themeColor),
                            );
                          }
                        );
                      }
                    ),
                  ],
                ],
              );
            }
          ),
        );
      }
    );
  }

  Widget _buildSliderControls({
    required BuildContext context,
    required Duration position,
    required Duration duration,
    required bool isPlaying,
    required Color themeColor,
    required Function(int) onSeek,
    required VoidCallback onRewind,
    required VoidCallback onFastForward,
    required VoidCallback onPlayPause,
    required bool isVideoMode,
    required VideoPlayerController? controller,
    required VoidCallback onShowQueue,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
              activeTrackColor: themeColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: themeColor,
            ),
            child: _SeekSlider(
              position: position,
              duration: duration,
              onSeek: onSeek,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
              Text(_formatDuration(duration), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AudioService.isShuffle,
                builder: (context, shuffle, child) => IconButton(
                  icon: Icon(Icons.shuffle, size: 28, color: shuffle ? themeColor : Colors.white54),
                  onPressed: () => AudioService.isShuffle.value = !shuffle,
                )
              ),
              const IconButton(
                icon: Icon(Icons.skip_previous, size: 40, color: Colors.white), 
                onPressed: AudioService.prevTrack,
              ),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 84, color: themeColor),
                onPressed: onPlayPause,
              ),
              const IconButton(
                icon: Icon(Icons.skip_next, size: 40, color: Colors.white), 
                onPressed: AudioService.nextTrack,
              ),
              ValueListenableBuilder<PlaybackRepeat>(
                valueListenable: AudioService.repeatMode,
                builder: (context, repeat, child) => IconButton(
                  icon: Icon(
                    repeat == PlaybackRepeat.one ? Icons.repeat_one : Icons.repeat, 
                    size: 28, 
                    color: repeat != PlaybackRepeat.off ? themeColor : Colors.white54
                  ),
                  onPressed: () {
                    if (repeat == PlaybackRepeat.off) {
                      AudioService.repeatMode.value = PlaybackRepeat.all;
                    } else if (repeat == PlaybackRepeat.all) {
                      AudioService.repeatMode.value = PlaybackRepeat.one;
                    } else {
                      AudioService.repeatMode.value = PlaybackRepeat.off;
                    }
                  },
                )
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 28.0, top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const IconButton(
                icon: Icon(Icons.stop, size: 28, color: Colors.redAccent),
                onPressed: AudioService.stopPlayer,
                tooltip: "HALT PLAYBACK",
              ),
              ValueListenableBuilder<int>(
                valueListenable: AudioService.sleepTimerMinutes,
                builder: (context, mins, child) => IconButton(
                  icon: Icon(Icons.bedtime, size: 26, color: mins > 0 ? themeColor : Colors.white70),
                  onPressed: () => _showSleepSheet(context, themeColor),
                  tooltip: mins > 0 ? "SLEEP TIMER: $mins MIN" : "SLEEP TIMER",
                ),
              ),
              if (!isVideoMode)
                IconButton(
                  icon: const Icon(Icons.lyrics, size: 26, color: Colors.white70),
                  onPressed: () => _showLyricsSheet(context, themeColor),
                  tooltip: "SYNCED LYRICS",
                )
              else
                const SizedBox(width: 48),
              if (isVideoMode && controller != null)
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 28, color: Colors.white70),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => FullScreenVideoScreen(controller: controller),
                    ));
                  },
                ),
              IconButton(
                icon: const Icon(Icons.speed, size: 26, color: Colors.white70),
                onPressed: () => _showSpeedSheet(context, themeColor),
                tooltip: "PLAYBACK SPEED",
              ),
              IconButton(
                icon: const Icon(Icons.queue_music, size: 28, color: Colors.white70),
                onPressed: onShowQueue,
                tooltip: "OPEN MACHINE QUEUE",
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSleepSheet(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: themeColor.withValues(alpha: 0.5)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: AudioService.sleepTimerMinutes,
          builder: (context, current, child) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("SLEEP TIMER", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 16, color: themeColor)),
                const SizedBox(height: 4),
                Text(current > 0 ? "ACTIVE: HALT IN $current MIN" : "INACTIVE", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'VT323', fontSize: 15, color: current > 0 ? themeColor : Colors.white54)),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final m in [15, 30, 45, 60, 90])
                      OutlinedButton(
                        onPressed: () { AudioService.setSleepTimer(m); Navigator.pop(sheetContext); },
                        style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor.withValues(alpha: 0.6))),
                        child: Text("$m MIN", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
                      ),
                    OutlinedButton(
                      onPressed: () { AudioService.setSleepTimer(0); Navigator.pop(sheetContext); },
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                      child: const Text("OFF", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: themeColor.withValues(alpha: 0.5)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<double>(
          valueListenable: AudioService.speedFactor,
          builder: (context, current, child) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("PLAYBACK SPEED", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 16, color: themeColor)),
                const SizedBox(height: 4),
                Text("CURRENT: ${current.toStringAsFixed(2)}x", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 15, color: Colors.white54)),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final s in [0.50, 0.75, 1.00, 1.25, 1.50, 2.00])
                      OutlinedButton(
                        onPressed: () { AudioService.setPlaybackSpeed(s); Navigator.pop(sheetContext); },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: current == s ? themeColor : themeColor.withValues(alpha: 0.4)),
                          backgroundColor: current == s ? themeColor.withValues(alpha: 0.15) : Colors.transparent,
                        ),
                        child: Text("${s.toStringAsFixed(2)}x", style: TextStyle(fontFamily: 'ShareTechMono', color: current == s ? themeColor : Colors.white70)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLyricsSheet(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.97),
          border: Border(top: BorderSide(color: themeColor.withValues(alpha: 0.5))),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _LyricsSheet(themeColor: themeColor),
      ),
    );
  }
}

class FullScreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;

  const FullScreenVideoScreen({super.key, required this.controller});

  @override
  State<FullScreenVideoScreen> createState() => _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<FullScreenVideoScreen> {
  bool _showControls = true;
  BoxFit _currentFit = BoxFit.contain;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    if (widget.controller.value.aspectRatio < 1.0) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _toggleZoom() {
    setState(() {
      _currentFit = _currentFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTap: _toggleZoom,
        child: Stack(
          children: [
            Center(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: _currentFit,
                  child: SizedBox(
                    width: widget.controller.value.size.width,
                    height: widget.controller.value.size.height,
                    child: VideoPlayer(widget.controller),
                  ),
                ),
              ),
            ),
            if (_showControls)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: IconButton(
                              icon: const Icon(Icons.fullscreen_exit, size: 32, color: Colors.cyanAccent),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: IconButton(
                              icon: Icon(_currentFit == BoxFit.cover ? Icons.zoom_in_map : Icons.zoom_out_map, size: 32, color: Colors.white70),
                              onPressed: _toggleZoom,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.replay_10, size: 48, color: Colors.cyanAccent),
                            onPressed: () => widget.controller.seekTo(widget.controller.value.position - const Duration(seconds: 10)),
                          ),
                          const SizedBox(width: 32),
                          ValueListenableBuilder(
                            valueListenable: widget.controller,
                            builder: (context, VideoPlayerValue value, child) {
                              return IconButton(
                                icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 80, color: Colors.cyanAccent),
                                onPressed: () {
                                  value.isPlaying ? widget.controller.pause() : widget.controller.play();
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            icon: const Icon(Icons.forward_10, size: 48, color: Colors.cyanAccent),
                            onPressed: () => widget.controller.seekTo(widget.controller.value.position + const Duration(seconds: 10)),
                          ),
                        ],
                      ),
                      ValueListenableBuilder(
                        valueListenable: widget.controller,
                        builder: (context, VideoPlayerValue value, child) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 16.0),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                                activeTrackColor: Colors.cyanAccent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.cyanAccent,
                              ),
                              child: _SeekSlider(
                                position: value.position,
                                duration: value.duration,
                                onSeek: (ms) => widget.controller.seekTo(Duration(milliseconds: ms)),
                                activeColor: Colors.cyanAccent,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoubleTapSeek extends StatelessWidget {
  final Widget child;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _DoubleTapSeek({required this.child, required this.onLeft, required this.onRight});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) {
            if (details.localPosition.dx < constraints.maxWidth / 2) {
              onLeft();
            } else {
              onRight();
            }
          },
          onDoubleTap: () {},
          child: child,
        );
      },
    );
  }
}

class _LyricLine {
  final Duration stamp;
  final String text;
  _LyricLine(this.stamp, this.text);
}

class _LyricsSheet extends StatefulWidget {
  final Color themeColor;
  const _LyricsSheet({required this.themeColor});

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  static const double _rowHeight = 42.0;
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Duration>? _posSub;
  List<_LyricLine> _lines = [];
  bool _parsed = false;
  int _activeIdx = -1;

  @override
  void initState() {
    super.initState();
    _parse();
    _posSub = AudioService.player.positionStream.listen((pos) => _updateActive(pos));
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    try {
      final idx = AudioService.currentIndex.value;
      if (idx < 0 || idx >= AudioService.playlist.value.length) {
        if (mounted) setState(() => _parsed = true);
        return;
      }
      final path = AudioService.playlist.value[idx].path;
      final dot = path.lastIndexOf('.');
      final lrcPath = dot > 0 ? "${path.substring(0, dot)}.lrc" : "$path.lrc";
      final f = File(lrcPath);
      if (!f.existsSync()) {
        if (mounted) setState(() => _parsed = true);
        return;
      }
      final raw = await f.readAsString();
      final reg = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
      final List<_LyricLine> out = [];
      for (final line in raw.split('\n')) {
        final matches = reg.allMatches(line).toList();
        if (matches.isEmpty) continue;
        final text = line.replaceAll(reg, '').trim();
        if (text.isEmpty) continue;
        for (final m in matches) {
          final minutes = int.parse(m.group(1)!);
          final seconds = int.parse(m.group(2)!);
          final fracStr = m.group(3) ?? "0";
          final ms = int.parse(fracStr.padRight(3, '0').substring(0, 3));
          out.add(_LyricLine(Duration(minutes: minutes, seconds: seconds, milliseconds: ms), text));
        }
      }
      out.sort((a, b) => a.stamp.compareTo(b.stamp));
      if (!mounted) return;
      setState(() {
        _lines = out;
        _parsed = true;
      });
      _updateActive(AudioService.player.position);
    } catch (_) {
      if (mounted) setState(() => _parsed = true);
    }
  }

  void _updateActive(Duration pos) {
    if (_lines.isEmpty || !mounted) return;
    int lo = 0, hi = _lines.length - 1, res = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_lines[mid].stamp <= pos) {
        res = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (res != _activeIdx) {
      setState(() => _activeIdx = res);
      if (_scroll.hasClients && res >= 0) {
        final target = ((res * _rowHeight) - 200.0).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.themeColor;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          height: 4,
          width: 40,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text("KARAOKE MACHINE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 2, color: themeColor)),
        ),
        Expanded(
          child: !_parsed
              ? Center(child: CircularProgressIndicator(color: themeColor))
              : _lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lyrics, size: 64, color: themeColor.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          const Text(
                            "NO LRC SIDECHAIN FOUND FOR THIS PAYLOAD.\n\nUSE THE FORGE KARAOKE SYNC TO STAMP TIMINGS AND EXPORT AN .LRC FILE.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'VT323', fontSize: 16, color: Colors.white54, height: 1.4),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 200),
                      itemCount: _lines.length,
                      itemBuilder: (context, i) {
                        final active = i == _activeIdx;
                        return SizedBox(
                          height: _rowHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => AudioService.player.seek(_lines[i].stamp),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: Text(
                                  _lines[i].text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: active ? 'ShareTechMono' : 'VT323',
                                    fontSize: active ? 20 : 18,
                                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                    color: active ? themeColor : Colors.white38,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}


class _SeekSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Function(int) onSeek;
  final Color activeColor;

  const _SeekSlider({required this.position, required this.duration, required this.onSeek, this.activeColor = Colors.transparent});

  @override
  State<_SeekSlider> createState() => _SeekSliderState();
}

class _SeekSliderState extends State<_SeekSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds > 0 ? widget.duration.inMilliseconds.toDouble() : 1.0;
    return Slider(
      value: (_dragValue ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, maxMs),
      max: maxMs,
      activeColor: widget.activeColor == Colors.transparent ? null : widget.activeColor,
      onChanged: (val) => setState(() => _dragValue = val),
      onChangeEnd: (val) {
        widget.onSeek(val.toInt());
        setState(() => _dragValue = null);
      },
    );
  }
}
