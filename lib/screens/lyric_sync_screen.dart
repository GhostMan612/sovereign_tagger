// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'main_shell.dart';

class LyricSyncScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String artist;
  final String rawLyrics;

  const LyricSyncScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.artist,
    required this.rawLyrics,
  });

  @override
  State<LyricSyncScreen> createState() => _LyricSyncScreenState();
}

class _LyricSyncScreenState extends State<LyricSyncScreen> {
  final AudioPlayer _player = AudioPlayer();
  List<String> _lines = [];
  List<String> _syncedLines = [];
  int _currentIndex = 0;
  double _playbackSpeed = 1.0;
  bool _isFinished = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _lines = widget.rawLyrics.split('\n').where((line) => line.trim().isNotEmpty).toList();
    _syncedLines = List.filled(_lines.length, "");
    _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      await _player.setFilePath(widget.filePath);
      await _player.setSpeed(_playbackSpeed);
      if (mounted) _player.play();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatTimestamp(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    String twoDigitMilliseconds = (duration.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, "0");
    return "[$twoDigitMinutes:$twoDigitSeconds.$twoDigitMilliseconds]";
  }

  void _syncCurrentLine() {
    if (_currentIndex < _lines.length) {
      final position = _player.position;
      setState(() {
        _syncedLines[_currentIndex] = "${_formatTimestamp(position)}${_lines[_currentIndex]}";
        _currentIndex++;
        if (_currentIndex >= _lines.length) _isFinished = true;
      });
    }
  }

  void _undoLastSync() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _syncedLines[_currentIndex] = "";
        _isFinished = false;
      });
    }
  }

  Future<void> _exportLrc() async {
    try {
      final originalFile = File(widget.filePath);
      final dir = originalFile.parent.path;
      final fileName = originalFile.path.split('/').last;
      final dot = fileName.lastIndexOf('.');
      final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
      final lrcPath = "$dir/$baseName.lrc";

      String lrcContent = "[ti:${widget.title}]\n[ar:${widget.artist}]\n";
      for (String line in _syncedLines) {
        if (line.isNotEmpty) lrcContent += "$line\n";
      }

      final lrcFile = File(lrcPath);
      await lrcFile.writeAsString(lrcContent);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('> SUCCESS. .LRC INJECTED NEXT TO AUDIO FILE.', style: TextStyle(fontFamily: 'ShareTechMono', color: SovereignState.accentColor.value)),
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(side: BorderSide(color: SovereignState.accentColor.value))
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('> ERR: EXPORT FAULT: $e', style: const TextStyle(fontFamily: 'ShareTechMono')),
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent))
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(icon: Icon(Icons.arrow_back, color: themeColor), onPressed: () => Navigator.pop(context)),
            title: Text("KARAOKE SYNCHRONIZER", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: themeColor.withValues(alpha: 0.3), height: 1.0),
            ),
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(bottom: BorderSide(color: Colors.white24))
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("> PLAYBACK TEMPO WARP", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        Text("${_playbackSpeed}x", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.amberAccent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.amberAccent,
                        trackHeight: 4.0,
                      ),
                      child: Slider(
                        value: _playbackSpeed, min: 0.5, max: 1.0, divisions: 5,
                        onChanged: (val) {
                          setState(() => _playbackSpeed = val);
                          _player.setSpeed(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: _loadFailed
                    ? const Text("> AUDIO PAYLOAD FAILED TO MOUNT.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent))
                    : StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, stateSnap) {
                          final playing = stateSnap.data?.playing ?? false;
                          return Row(
                            children: [
                              IconButton(
                                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 40, color: themeColor),
                                onPressed: () => playing ? _player.pause() : _player.play(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.replay, size: 28, color: Colors.white70),
                                tooltip: "RESTART TRACK",
                                onPressed: () => _player.seek(Duration.zero),
                              ),
                              Expanded(
                                child: StreamBuilder<Duration>(
                                  stream: _player.positionStream,
                                  builder: (context, posSnap) {
                                    final pos = posSnap.data ?? Duration.zero;
                                    return Text(
                                      "${pos.inMinutes.toString().padLeft(2, '0')}:${pos.inSeconds.remainder(60).toString().padLeft(2, '0')}",
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontFamily: 'VT323', fontSize: 18, color: Colors.white70),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentIndex;
                    final isSynced = index < _currentIndex;
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isCurrent ? themeColor : (isSynced ? Colors.white24 : Colors.transparent)),
                        boxShadow: isCurrent ? [BoxShadow(color: themeColor.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: -2)] : null,
                      ),
                      child: Text(
                        isSynced ? _syncedLines[index] : _lines[index],
                        style: TextStyle(
                          fontFamily: 'ShareTechMono',
                          fontSize: 16,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? themeColor : (isSynced ? Colors.white54 : Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black, 
                  border: Border(top: BorderSide(color: themeColor))
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                      child: IconButton(
                        onPressed: _undoLastSync,
                        icon: const Icon(Icons.undo, color: Colors.redAccent, size: 32),
                        tooltip: "REVERT LINE",
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _isFinished
                        ? ElevatedButton.icon(
                            onPressed: _exportLrc,
                            icon: const Icon(Icons.save, color: Colors.black),
                            label: const Text("EXPORT .LRC TARGET", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, padding: const EdgeInsets.symmetric(vertical: 20)),
                          )
                        : ElevatedButton.icon(
                            onPressed: _syncCurrentLine,
                            icon: const Icon(Icons.touch_app, color: Colors.black),
                            label: const Text("SYNC LINE STAMP", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: themeColor, padding: const EdgeInsets.symmetric(vertical: 20)),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}