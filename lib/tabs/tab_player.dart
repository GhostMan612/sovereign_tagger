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
import '../core/forge_request.dart';
import '../core/lrc.dart';
import '../core/metadata_sources.dart';
import '../core/playlists.dart';
import '../screens/main_shell.dart';
import '../screens/playback_engine_screen.dart';
import '../screens/eq_presets_screen.dart';
import '../widgets/playlist_picker.dart';

class TheaterScreen extends StatelessWidget {
  const TheaterScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours > 0 ? '${d.inHours}:' : '';
    return '$hours$minutes:$seconds';
  }

  void _seekBy(int seconds) {
    if (AudioService.isVideo.value && AudioService.videoController.value != null) {
      final c = AudioService.videoController.value!;
      c.seekTo(c.value.position + Duration(seconds: seconds));
    } else {
      var target = AudioService.player.position + Duration(seconds: seconds);
      if (target.isNegative) target = Duration.zero;
      AudioService.player.seek(target);
    }
  }

  void _sendToForge(BuildContext context, String path) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    SovereignState.sendToForge(ForgeRequest(path: path, origin: ForgeOrigin.player, originUri: AudioService.infoFor(path)?.uri));
  }

  void _showTrackMenu(BuildContext context, File file, int index, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: themeColor.withValues(alpha: 0.5)),
      ),
      builder: (sheetContext) {
        final isFav = PlaylistStore.isFavorite(file.path);
        Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? themeColor),
              title: Text(title, style: TextStyle(fontFamily: 'ShareTechMono', color: color ?? Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle, style: TextStyle(fontFamily: 'ShareTechMono', color: (color ?? themeColor).withValues(alpha: 0.7), fontSize: 12)),
              onTap: onTap,
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(margin: const EdgeInsets.symmetric(vertical: 12), height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              tile(Icons.low_priority, "PLAY NEXT", "Queue immediately after the current track", () {
                AudioService.moveAfterCurrent(index);
                Navigator.pop(sheetContext);
              }),
              tile(isFav ? Icons.favorite : Icons.favorite_border, isFav ? "REMOVE FROM FAVORITES" : "ADD TO FAVORITES", "Heart this track", () {
                PlaylistStore.toggleFavorite(file.path);
                Navigator.pop(sheetContext);
              }, color: Colors.pinkAccent),
              tile(Icons.playlist_add, "ADD TO PLAYLIST", "Pick or create a playlist", () async {
                Navigator.pop(sheetContext);
                await showPlaylistPicker(context, [file.path], themeColor);
              }),
              tile(Icons.edit_note, "EDIT IN FORGE", "Fix tags, art, lyrics and file name", () {
                Navigator.pop(sheetContext);
                _sendToForge(context, file.path);
              }),
              tile(Icons.delete_sweep, "REMOVE FROM QUEUE", "The file itself is not deleted", () {
                AudioService.removeFromPlaylist(index);
                Navigator.pop(sheetContext);
              }, color: Colors.redAccent),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showQueueSheet(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.97),
            border: Border(top: BorderSide(color: themeColor.withValues(alpha: 0.5))),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Container(margin: const EdgeInsets.symmetric(vertical: 12), height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: AudioService.pickAndEnqueue,
                          icon: Icon(Icons.playlist_add, color: themeColor, size: 18),
                          label: Text("ADD FILES", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontSize: 12)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor.withValues(alpha: 0.5))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final paths = AudioService.playlist.value.map((f) => f.path).toList();
                            if (paths.isEmpty) return;
                            await showPlaylistPicker(sheetContext, paths, themeColor, createOnly: true);
                          },
                          icon: const Icon(Icons.save_alt, color: Colors.cyanAccent, size: 18),
                          label: const Text("SAVE AS PLAYLIST", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontSize: 12)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.6))),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 20.0, right: 8.0, top: 8.0),
                  child: Row(
                    children: [
                      ValueListenableBuilder<List<File>>(
                        valueListenable: AudioService.playlist,
                        builder: (context, list, _) => Text("> UP NEXT • ${list.length} TRACKS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: themeColor)),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                        onPressed: () {
                          AudioService.clearPlaylist();
                          Navigator.pop(sheetContext);
                        },
                        tooltip: "CLEAR QUEUE",
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 20, bottom: 4),
                  child: Align(alignment: Alignment.centerLeft, child: Text("DRAG ≡ TO REORDER • SWIPE TO REMOVE • HOLD FOR OPTIONS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38))),
                ),
                Expanded(
                  child: ValueListenableBuilder<List<File>>(
                    valueListenable: AudioService.playlist,
                    builder: (context, playlist, child) {
                      if (playlist.isEmpty) {
                        return const Center(child: Text("> Queue Empty. Open The LIBRARY To Pick Music.", style: TextStyle(fontFamily: 'VT323', fontSize: 16, color: Colors.white54)));
                      }
                      return ValueListenableBuilder<int>(
                        valueListenable: AudioService.infoRevision,
                        builder: (context, _, __) => ValueListenableBuilder<int>(
                          valueListenable: AudioService.currentIndex,
                          builder: (context, currentIndex, child) {
                            return ReorderableListView.builder(
                              buildDefaultDragHandles: false,
                              itemCount: playlist.length,
                              onReorderItem: (oldIndex, newIndex) => AudioService.reorderPlaylist(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
                              itemBuilder: (context, index) {
                                final file = playlist[index];
                                final isCurrent = index == currentIndex;
                                final isVidExt = AudioService.videoExtensions.contains(file.path.split('.').last.toLowerCase());
                                final itemColor = isVidExt ? Colors.cyanAccent : themeColor;
                                final info = AudioService.infoFor(file.path);
                                if (info == null) AudioService.ensureInfo(file.path);
                                final title = info?.title ?? file.path.split('/').last;
                                final artist = info?.artist ?? '';
                                return Dismissible(
                                  key: ValueKey('q_${index}_${file.path}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(color: Colors.redAccent.withValues(alpha: 0.25), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.remove_circle_outline, color: Colors.redAccent)),
                                  confirmDismiss: (_) async {
                                    await AudioService.removeFromPlaylist(index);
                                    return false;
                                  },
                                  child: Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      dense: true,
                                      tileColor: isCurrent ? itemColor.withValues(alpha: 0.1) : Colors.transparent,
                                      leading: Icon(isCurrent ? Icons.graphic_eq : (isVidExt ? Icons.movie : Icons.audiotrack), color: isCurrent ? itemColor : Colors.white54),
                                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', color: isCurrent ? itemColor : Colors.white, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                                      subtitle: artist.isEmpty ? null : Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                                      trailing: ReorderableDragStartListener(index: index, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, color: Colors.white38))),
                                      onTap: () => AudioService.playIndex(index),
                                      onLongPress: () => _showTrackMenu(context, file, index, themeColor),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            title: Text("NOW PLAYING", style: TextStyle(fontFamily: 'ShareTechMono', color: accentColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.purpleAccent),
                tooltip: "EQUALIZER",
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
                            onLeft: () => _seekBy(-10),
                            onRight: () => _seekBy(10),
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
                                            child: Hero(
                                              tag: 'now-playing-art',
                                              child: Image(
                                                image: image.image,
                                                fit: BoxFit.contain,
                                                filterQuality: FilterQuality.high,
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      return Center(child: Icon(Icons.music_note, size: 160, color: themeColor.withValues(alpha: 0.12)));
                                    },
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
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
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Column(
                              children: [
                                ValueListenableBuilder<String>(
                                  valueListenable: AudioService.currentTitle,
                                  builder: (context, title, child) => AutoScrollText(
                                    text: title.toUpperCase(),
                                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ValueListenableBuilder<String>(
                                  valueListenable: AudioService.currentArtist,
                                  builder: (context, artist, child) => AutoScrollText(
                                    text: artist.toUpperCase(),
                                    style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 15, color: themeColor),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _FavoriteButton(themeColor: themeColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                              isVideoMode: true,
                              controller: controller,
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
                              isVideoMode: false,
                              controller: null,
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
    required bool isVideoMode,
    required VideoPlayerController? controller,
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
            child: _SeekSlider(position: position, duration: duration, onSeek: onSeek),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
              Text("-${_formatDuration(duration > position ? duration - position : Duration.zero)}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
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
                onPressed: AudioService.togglePlayPause,
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
          padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 24.0, top: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const IconButton(
                icon: Icon(Icons.stop, size: 26, color: Colors.redAccent),
                onPressed: AudioService.stopPlayer,
                tooltip: "STOP",
              ),
              ValueListenableBuilder<int>(
                valueListenable: AudioService.sleepTimerMinutes,
                builder: (context, mins, child) => ValueListenableBuilder<bool>(
                  valueListenable: AudioService.sleepAtEndOfTrack,
                  builder: (context, endOfTrack, _) => IconButton(
                    icon: Icon(Icons.bedtime, size: 26, color: (mins > 0 || endOfTrack) ? themeColor : Colors.white70),
                    onPressed: () => _showSleepSheet(context, themeColor),
                    tooltip: endOfTrack ? "SLEEP: END OF TRACK" : (mins > 0 ? "SLEEP TIMER: $mins MIN" : "SLEEP TIMER"),
                  ),
                ),
              ),
              if (!isVideoMode)
                IconButton(
                  icon: const Icon(Icons.lyrics, size: 26, color: Colors.white70),
                  onPressed: () => _showLyricsSheet(context, themeColor),
                  tooltip: "LYRICS",
                )
              else if (controller != null)
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
                icon: const Icon(Icons.more_horiz, size: 26, color: Colors.white70),
                tooltip: "TRACK OPTIONS",
                onPressed: () {
                  final idx = AudioService.currentIndex.value;
                  if (idx < 0 || idx >= AudioService.playlist.value.length) return;
                  _showTrackMenu(context, AudioService.playlist.value[idx], idx, themeColor);
                },
              ),
              IconButton(
                icon: const Icon(Icons.queue_music, size: 28, color: Colors.white70),
                onPressed: () => _showQueueSheet(context, themeColor),
                tooltip: "QUEUE",
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
          builder: (context, current, child) => ValueListenableBuilder<bool>(
            valueListenable: AudioService.sleepAtEndOfTrack,
            builder: (context, endOfTrack, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("SLEEP TIMER", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 16, color: themeColor)),
                  const SizedBox(height: 4),
                  Text(
                    endOfTrack ? "ACTIVE: STOP AFTER THIS TRACK" : (current > 0 ? "ACTIVE: FADE OUT IN ~$current MIN" : "INACTIVE"),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'VT323', fontSize: 15, color: (current > 0 || endOfTrack) ? themeColor : Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final m in [5, 15, 30, 45, 60, 90])
                        OutlinedButton(
                          onPressed: () { AudioService.setSleepTimer(m); Navigator.pop(sheetContext); },
                          style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor.withValues(alpha: 0.6))),
                          child: Text("$m MIN", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
                        ),
                      OutlinedButton(
                        onPressed: () { AudioService.setSleepAtEndOfTrack(true); Navigator.pop(sheetContext); },
                        style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)),
                        child: Text("END OF TRACK", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
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
        child: _LyricsSheet(themeColor: themeColor, onSendToForge: (path, lyrics) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          SovereignState.sendToForge(ForgeRequest(path: path, origin: ForgeOrigin.player, originUri: AudioService.infoFor(path)?.uri, prefill: {'LYRICS': lyrics}));
        }),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final Color themeColor;
  const _FavoriteButton({required this.themeColor});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AudioService.currentIndex,
      builder: (context, idx, _) => ValueListenableBuilder<Set<String>>(
        valueListenable: PlaylistStore.favorites,
        builder: (context, favs, _) {
          if (idx < 0 || idx >= AudioService.playlist.value.length) return const SizedBox(width: 48);
          final path = AudioService.playlist.value[idx].path;
          final fav = favs.contains(path);
          return IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.pinkAccent : Colors.white54),
            tooltip: fav ? "UNFAVORITE" : "FAVORITE",
            onPressed: () => PlaylistStore.toggleFavorite(path),
          );
        },
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

class _LyricsSheet extends StatefulWidget {
  final Color themeColor;
  final void Function(String path, String lyrics) onSendToForge;
  const _LyricsSheet({required this.themeColor, required this.onSendToForge});

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  static const double _rowHeight = 42.0;
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Duration>? _posSub;
  List<LrcLine> _lines = [];
  String _plain = "";
  String _source = "";
  String _raw = "";
  bool _parsed = false;
  bool _searching = false;
  int _activeIdx = -1;
  String _path = "";

  @override
  void initState() {
    super.initState();
    AudioService.currentIndex.addListener(_reload);
    AudioService.currentLyrics.addListener(_reload);
    _reload();
    _posSub = AudioService.player.positionStream.listen(_updateActive);
  }

  @override
  void dispose() {
    AudioService.currentIndex.removeListener(_reload);
    AudioService.currentLyrics.removeListener(_reload);
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _apply(String raw, String source) {
    _raw = raw;
    if (Lrc.isSynced(raw)) {
      _lines = Lrc.parse(raw).where((l) => l.text.isNotEmpty).toList();
      _plain = "";
    } else {
      _lines = [];
      _plain = raw.trim();
    }
    _source = raw.trim().isEmpty ? "" : source;
    _activeIdx = -1;
  }

  Future<void> _reload() async {
    final idx = AudioService.currentIndex.value;
    if (idx < 0 || idx >= AudioService.playlist.value.length) {
      if (mounted) setState(() { _apply("", ""); _parsed = true; _path = ""; });
      return;
    }
    final path = AudioService.playlist.value[idx].path;
    var raw = AudioService.currentLyrics.value;
    var source = "EMBEDDED TAG";
    if (!Lrc.isSynced(raw)) {
      final dot = path.lastIndexOf('.');
      final lrc = File(dot > 0 ? "${path.substring(0, dot)}.lrc" : "$path.lrc");
      try {
        if (lrc.existsSync()) {
          final side = await lrc.readAsString();
          if (Lrc.isSynced(side)) {
            raw = side;
            source = "SIDECAR .LRC";
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _path = path;
      _apply(raw, source);
      _parsed = true;
    });
    _updateActive(AudioService.player.position);
  }

  Future<void> _searchOnline() async {
    final idx = AudioService.currentIndex.value;
    if (idx < 0 || idx >= AudioService.playlist.value.length) return;
    final info = AudioService.infoFor(AudioService.playlist.value[idx].path);
    final title = info?.title ?? AudioService.currentTitle.value;
    final artist = info?.artist ?? "";
    setState(() => _searching = true);
    try {
      final r = await MetadataSources.fetchLyrics(artist: artist, title: title, album: info?.album ?? "", durationMs: AudioService.player.duration?.inMilliseconds ?? info?.durationMs ?? 0);
      if (!mounted) return;
      setState(() {
        _searching = false;
        final found = r.synced.isNotEmpty ? r.synced : r.plain;
        if (found.isNotEmpty) _apply(found, "LRCLIB (NOT SAVED)");
      });
      if (r.synced.isEmpty && r.plain.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> NO LYRICS FOUND ONLINE FOR THIS TRACK.', style: TextStyle(fontFamily: 'ShareTechMono'))));
      }
      _updateActive(AudioService.player.position);
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _updateActive(Duration pos) {
    if (_lines.isEmpty || !mounted) return;
    final res = Lrc.activeIndex(_lines, pos);
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
    final unsavedOnline = _source.startsWith("LRCLIB");
    return Column(
      children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 12), height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text(_lines.isNotEmpty ? "KARAOKE MACHINE" : "LYRICS", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 2, color: themeColor))),
              if (_source.isNotEmpty) Text(_source, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
            ],
          ),
        ),
        if (unsavedOnline && _path.isNotEmpty)
          TextButton.icon(
            onPressed: () => widget.onSendToForge(_path, _raw),
            icon: const Icon(Icons.save_alt, size: 16, color: Colors.amberAccent),
            label: const Text("EMBED INTO FILE VIA FORGE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.amberAccent)),
          ),
        Expanded(
          child: !_parsed
              ? Center(child: CircularProgressIndicator(color: themeColor))
              : _lines.isNotEmpty
                  ? ListView.builder(
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
                    )
                  : _plain.isNotEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
                          child: Text(_plain, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 19, color: Colors.white70, height: 1.4)),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lyrics, size: 64, color: themeColor.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              const Text(
                                "NO LYRICS IN THIS FILE.",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'VT323', fontSize: 16, color: Colors.white54, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _searching ? null : _searchOnline,
                                icon: _searching ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor)) : Icon(Icons.travel_explore, color: themeColor),
                                label: Text("FIND LYRICS ONLINE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
                                style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor)),
                              ),
                            ],
                          ),
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
