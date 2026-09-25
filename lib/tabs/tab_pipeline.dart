// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import '../screens/main_shell.dart';
import '../core/cyber_tap_feedback.dart';

class MediaItem {
  String originalPath;
  String filename;
  Map<String, String> tags;
  String bucket; 
  String log;
  bool isProcessing;

  MediaItem({
    required this.originalPath,
    required this.filename,
    required this.tags,
    required this.bucket,
    this.log = "Waiting In Queue...",
    this.isProcessing = false,
  });
}

class TabPipeline extends StatefulWidget {
  const TabPipeline({super.key});

  @override
  State<TabPipeline> createState() => _TabPipelineState();
}

class _TabPipelineState extends State<TabPipeline> {
  static const MethodChannel _acrChannel = MethodChannel('com.sovereign.tagger/acrcloud');
  static const MethodChannel _id3Channel = MethodChannel('com.sovereign.tagger/id3');
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');
  static const MethodChannel _spiderChannel = MethodChannel('com.sovereign.tagger/spider');

  final List<MediaItem> _queue = [];
  bool _isBatchRunning = false;
  int _currentIndex = 0;
  String _globalStatus = "System Ready. Awaiting Batch.";

  Future<void> _pickFiles() async {
    TapFeedback.machineTap();
    if (_isBatchRunning) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _globalStatus = "ERR: File Picker Fault: ${e.message}");
      return;
    }
    if (!mounted) return;

    if (result?.files.isNotEmpty ?? false) {
      final pickedFiles = result!.files;
      setState(() {
        _globalStatus = "Scanning ${pickedFiles.length} Files...";
        _queue.clear();
      });

      for (var file in pickedFiles) {
        if (!mounted) break;
        if (file.path == null) continue;
        
        try {
          final Map<Object?, Object?> rawTags = await _id3Channel.invokeMethod('readTags', {'filePath': file.path});
          final tags = rawTags.map((key, value) => MapEntry(key.toString(), value.toString()));
          
          String title = tags["TITLE"]?.trim() ?? "";
          String artist = tags["ARTIST"]?.trim() ?? "";
          String album = tags["ALBUM"]?.trim() ?? "";
          String art = tags["ARTWORK_BASE64"]?.trim() ?? "";
          
          String bucket = "PRISTINE";
          if (title.isEmpty || artist.isEmpty || title.toLowerCase().contains("track") || title.toLowerCase().contains("unknown")) {
            bucket = "GHOST";
          } else if (album.isEmpty || art.isEmpty) {
            bucket = "PARTIAL";
          }

          _queue.add(MediaItem(
            originalPath: file.path!,
            filename: file.name,
            tags: tags,
            bucket: bucket,
            log: bucket == "PRISTINE" ? "Fully Tagged. Will Be Skipped." : "Ready For Processing.",
          ));
        } catch (e) {
          _queue.add(MediaItem(
            originalPath: file.path!,
            filename: file.name,
            tags: {},
            bucket: "GHOST",
            log: "Tag Read ERR. Defaulting To Ghost.",
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _globalStatus = "Queue Built: ${_queue.length} Targets Acquired.";
      });
    }
  }

  void _updateItemLog(int index, String log, {bool? isProcessing, String? newBucket}) {
    if (!mounted) return;
    setState(() {
      _queue[index].log = log;
      if (isProcessing != null) _queue[index].isProcessing = isProcessing;
      if (newBucket != null) _queue[index].bucket = newBucket;
    });
  }

  void _revertToPartial(int index) {
    if (_isBatchRunning) return;
    if (!mounted) return;
    setState(() {
      final item = _queue[index];
      String preservedArtist = item.tags["ARTIST"] ?? "";
      String preservedTitle = item.tags["TITLE"] ?? "";
      
      item.tags.clear();
      if (preservedArtist.isNotEmpty) item.tags["ARTIST"] = preservedArtist;
      if (preservedTitle.isNotEmpty) item.tags["TITLE"] = preservedTitle;
      
      item.bucket = "PARTIAL";
      item.log = "Tags Wiped. Retained Artist & Title.";
    });
  }

  void _revertToGhost(int index) {
    if (_isBatchRunning) return;
    if (!mounted) return;
    setState(() {
      final item = _queue[index];
      item.tags.clear();
      item.bucket = "GHOST";
      item.log = "Completely Purged. Ready For ACR Sniper.";
    });
  }



  Future<void> _executeBatch() async {
    TapFeedback.machineTap();
    if (_queue.isEmpty || _isBatchRunning) return;

    final prefs = await SharedPreferences.getInstance();
    final geniusKey = prefs.getString('genius_key') ?? "";
    final acrHost = prefs.getString('acr_host') ?? "";
    final acrKey = prefs.getString('acr_key') ?? "";
    final acrSecret = prefs.getString('acr_secret') ?? "";

    if (geniusKey.isEmpty || acrHost.isEmpty || acrKey.isEmpty || acrSecret.isEmpty) {
      setState(() => _globalStatus = "ERR: API Keys Missing In Settings.");
      return;
    }

    setState(() {
      _isBatchRunning = true;
      _globalStatus = "Initializing APIs...";
    });

    try {
      await _acrChannel.invokeMethod('initialize', {'host': acrHost, 'accessKey': acrKey, 'accessSecret': acrSecret});
    } catch (e) {
      setState(() { _isBatchRunning = false; _globalStatus = "ERR: ACR Init: $e"; });
      return;
    }

    dynamic tempDir;
    try {
      tempDir = await _storageChannel.invokeMethod('getTempDirectory');
    } catch (e) {
      if (!mounted) return;
      setState(() { _isBatchRunning = false; _globalStatus = "ERR: Temp Vault Fault: $e"; });
      return;
    }

    for (int i = 0; i < _queue.length; i++) {
      if (!mounted || !_isBatchRunning) break;
      _currentIndex = i;
      
      final item = _queue[i];
      if (item.bucket == "PRISTINE" || item.bucket == "PROCESSED" || item.bucket == "FAILED") continue;

      _updateItemLog(i, "Starting Pipeline...", isProcessing: true);
      
      String currentTitle = item.tags["TITLE"] ?? "";
      String currentArtist = item.tags["ARTIST"] ?? "";
      Map<String, String> finalTags = Map.from(item.tags);

      try {
        if (item.bucket == "GHOST") {
          _updateItemLog(i, "Sniping 20s Audio For ACR...");
          final tempWavPath = "$tempDir/acr_batch_${DateTime.now().millisecondsSinceEpoch}.wav";
          final command = '-y -i "${item.originalPath}" -ss 0 -t 20 -ar 8000 -ac 1 -c:a pcm_s16le "$tempWavPath"';
          
          final session = await FFmpegExecutor.execute(command);
          if (ReturnCode.isSuccess(session.getReturnCode())) {
            _updateItemLog(i, "Querying ACR Neural Net...");
            dynamic data;
            try {
              final result = await _acrChannel.invokeMethod('identify', {'filePath': tempWavPath});
              data = jsonDecode(result.toString());
            } finally {
              try { if (File(tempWavPath).existsSync()) File(tempWavPath).deleteSync(); } catch (_) {}
            }

            if (data['status'] != null && data['status']['code'] == 0 && data['metadata'] != null) {
              final music = data['metadata']['music'][0];
              final List<dynamic> artistsArray = music['artists'] ?? [];
              currentTitle = music['title'] ?? "";
              currentArtist = artistsArray.isNotEmpty ? artistsArray[0]['name'] : "";
              finalTags["TITLE"] = currentTitle;
              finalTags["ARTIST"] = currentArtist;
              _updateItemLog(i, "ACR Match: $currentArtist - $currentTitle");
            } else {
              _updateItemLog(i, "ERR: ACR Failed To Identify.", isProcessing: false, newBucket: "FAILED");
              continue; 
            }
          } else {
            _updateItemLog(i, "ERR: FFmpeg Extraction Failed.", isProcessing: false, newBucket: "FAILED");
            continue;
          }
          await Future.delayed(const Duration(milliseconds: 500)); 
        }

        _updateItemLog(i, "Spidering Web For Metadata...");
        final spiderResult = await _spiderChannel.invokeMethod('scrape', {
          'artist': currentArtist,
          'title': currentTitle,
          'geniusKey': geniusKey
        });
        
        final sData = jsonDecode(spiderResult.toString());
        if (sData['status'] == 'success') {
          if (sData['title']?.toString().isNotEmpty ?? false) finalTags["TITLE"] = sData['title'];
          if (sData['artist']?.toString().isNotEmpty ?? false) finalTags["ARTIST"] = sData['artist'];
          finalTags["ALBUM_ARTIST"] = finalTags["ARTIST"] ?? "";
          if (sData['album']?.toString().isNotEmpty ?? false) finalTags["ALBUM"] = sData['album'];
          if (sData['year']?.toString().isNotEmpty ?? false) finalTags["YEAR"] = sData['year'];
          if (sData['genre']?.toString().isNotEmpty ?? false) finalTags["GENRE"] = sData['genre'];
          if (sData['track_no']?.toString().isNotEmpty ?? false) finalTags["TRACK"] = sData['track_no'];
          if (sData['disc_no']?.toString().isNotEmpty ?? false) finalTags["DISC_NO"] = sData['disc_no'];
          if (sData['lyrics']?.toString().isNotEmpty ?? false) finalTags["LYRICS"] = sData['lyrics'];
          if (sData['artwork_base64']?.toString().isNotEmpty ?? false) finalTags["ARTWORK_BASE64"] = sData['artwork_base64'];
        }
        
        finalTags["ENCODER"] = "Sovereign Tagger";

        _updateItemLog(i, "Injecting ID3 Tags...");
        final bool tagSuccess = await _id3Channel.invokeMethod('writeTags', {
          'filePath': item.originalPath,
          'metadata': finalTags
        });

        if (tagSuccess) {
          String trackStr = finalTags['TRACK'] ?? "";
          if (trackStr.isNotEmpty && trackStr.length == 1) trackStr = "0$trackStr";
          String prefix = trackStr.isNotEmpty ? "$trackStr - " : "";
          
          String artistStr = (finalTags['ARTIST'] ?? "Unknown Artist").replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
          String titleStr = (finalTags['TITLE'] ?? "Unknown Title").replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
          final srcParts = item.originalPath.split('.');
          final srcExt = srcParts.length > 1 ? srcParts.last.toLowerCase() : "";
          final ext = ['mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus'].contains(srcExt) ? srcExt : 'mp3';
          String newFileName = "$prefix$artistStr · $titleStr.$ext";
          
          File originalFile = File(item.originalPath);
          String dir = originalFile.parent.path;
          String newFilePath = "$dir/$newFileName";
          
          if (item.originalPath != newFilePath) {
            originalFile.renameSync(newFilePath);
            item.originalPath = newFilePath;
          }

          _updateItemLog(i, "Exporting To MediaStore...");
          await _storageChannel.invokeMethod('addToMediaStore', {
            'filePath': item.originalPath,
            'title': titleStr
          });

          _updateItemLog(i, "Secured: $newFileName", isProcessing: false, newBucket: "PROCESSED");
        } else {
          _updateItemLog(i, "ERR: Failed To Write Tags.", isProcessing: false, newBucket: "FAILED");
        }

      } catch (e) {
        _updateItemLog(i, "ERR: $e", isProcessing: false, newBucket: "FAILED");
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      TapFeedback.machineConfirm();
      setState(() {
        _isBatchRunning = false;
        _globalStatus = "Batch Processing Complete.";
      });
    }
  }

  void _clearQueue() {
    if (_isBatchRunning) return;
    setState(() {
      _queue.clear();
      _globalStatus = "Queue Purged.";
      _currentIndex = 0;
    });
  }

  Future<void> _mixtapeJoin() async {
    TapFeedback.machineTap();
    if (_isBatchRunning) return;
    final mp3Items = _queue.where((item) => item.bucket == "PROCESSED" && item.originalPath.toLowerCase().endsWith('.mp3') && File(item.originalPath).existsSync()).toList();
    if (mp3Items.length < 2) {
      setState(() => _globalStatus = "ERR: Mixtape Join Needs 2+ PROCESSED MP3 Items.");
      return;
    }

    setState(() => _globalStatus = "Mixtape Join: Assembling ${mp3Items.length} Tracks Losslessly...");
    try {
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final listFile = File("$tempDir/mixtape_${DateTime.now().millisecondsSinceEpoch}.txt");
      final buffer = StringBuffer();
      for (final item in mp3Items) {
        final escaped = item.originalPath.replaceAll("'", r"'\''");
        buffer.writeln("file '$escaped'");
      }
      await listFile.writeAsString(buffer.toString());

      final outPath = "$tempDir/sovereign_mixtape_${DateTime.now().millisecondsSinceEpoch}.mp3";
      final session = await FFmpegExecutor.execute('-y -f concat -safe 0 -i "${listFile.path}" -c copy -write_xing 1 "$outPath"');

      if (mounted && ReturnCode.isSuccess(session.getReturnCode())) {
        final uriString = await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': 'Sovereign Mixtape ${DateTime.now().month}/${DateTime.now().day}'});
        try { File(outPath).deleteSync(); } catch (_) {}
        setState(() => _globalStatus = "Mixtape Secured: ${mp3Items.length} Tracks Joined Losslessly.\n$uriString");
      } else {
        if (!mounted) return;
        setState(() => _globalStatus = "ERR: Mixtape Concat Fault. Ensure All Items Are MP3.");
      }
      try { listFile.deleteSync(); } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _globalStatus = "ERR: Mixtape Fault: $e");
    }
  }

  Color _getBucketColor(String bucket, Color themeColor) {
    switch (bucket) {
      case "GHOST": return Colors.redAccent;
      case "PARTIAL": return Colors.amberAccent;
      case "PRISTINE": return themeColor;
      case "PROCESSED": return Colors.cyanAccent;
      case "FAILED": return Colors.deepOrange;
      default: return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Container(
          color: Colors.black,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24.0),
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("AUTONOMOUS BATCH PIPELINE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBatchRunning ? null : _pickFiles,
                            icon: Icon(Icons.folder_copy, color: themeColor),
                            label: Text("LOAD QUEUE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: themeColor),
                              backgroundColor: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(4)),
                          child: IconButton(
                            onPressed: _isBatchRunning ? null : _mixtapeJoin,
                            icon: const Icon(Icons.merge, color: Colors.cyanAccent),
                            tooltip: "MIXTAPE JOIN (lossless concat of PROCESSED mp3s)",
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                          child: IconButton(
                            onPressed: _isBatchRunning ? null : _clearQueue,
                            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                            tooltip: "CLEAR QUEUE",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: CyberTapFeedback(
                            enableHaptic: false,
                            enableAudio: false,
                            particleColor: themeColor,
                            ringColor: themeColor,
                            particleCount: 16,
                            child: ElevatedButton.icon(
                              onPressed: (_queue.isEmpty || _isBatchRunning) ? null : _executeBatch,
                              icon: const Icon(Icons.rocket_launch, color: Colors.black),
                              label: const Text("EXECUTE BATCH", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: themeColor,
                                disabledBackgroundColor: themeColor.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                        if (_isBatchRunning) ...[
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isBatchRunning = false;
                                _globalStatus = "Batch Cancelled By Operator.";
                              });
                            },
                            icon: const Icon(Icons.cancel, color: Colors.redAccent),
                            label: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                              side: const BorderSide(color: Colors.redAccent),
                              backgroundColor: Colors.black,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: _globalStatus.contains("ERR") ? Colors.redAccent : themeColor)
                      ),
                      child: Text(
                        "> $_globalStatus", 
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'VT323',
                          fontSize: 16,
                          color: _globalStatus.contains("ERR") ? Colors.redAccent : themeColor, 
                          height: 1.2
                        ),
                      ),
                    ),
                    if (_isBatchRunning) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _queue.isEmpty ? 0 : (_currentIndex + 1) / _queue.length,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: _queue.length,
                  itemBuilder: (context, index) {
                    final item = _queue[index];
                    return Card(
                      color: Colors.black,
                      margin: const EdgeInsets.only(bottom: 12.0),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: _getBucketColor(item.bucket, themeColor).withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(4)
                      ),
                      child: ListTile(
                        leading: item.isProcessing 
                            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                            : Icon(Icons.music_note, color: _getBucketColor(item.bucket, themeColor)),
                        title: Text(item.filename.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text("> ${item.log}", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', color: _getBucketColor(item.bucket, themeColor), fontSize: 11)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!item.isProcessing && item.bucket == "FAILED")
                              IconButton(
                                icon: const Icon(Icons.replay, color: Colors.cyanAccent, size: 20),
                                tooltip: "RETRY FAILED",
                                onPressed: () {
                                  setState(() {
                                    item.bucket = item.tags["TITLE"]?.isNotEmpty == true ? "PARTIAL" : "GHOST";
                                    item.log = "Retrying...";
                                  });
                                  if (!_isBatchRunning) _executeBatch();
                                },
                              ),
                            if (!item.isProcessing && item.bucket != "PROCESSED" && item.bucket != "GHOST" && item.bucket != "FAILED")
                              IconButton(
                                icon: const Icon(Icons.cleaning_services, color: Colors.amberAccent, size: 20),
                                tooltip: "REVERT TO PARTIAL",
                                onPressed: () => _revertToPartial(index),
                              ),
                            if (!item.isProcessing && item.bucket != "PROCESSED" && item.bucket != "GHOST" && item.bucket != "FAILED")
                              IconButton(
                                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                                tooltip: "PURGE ALL TAGS",
                                onPressed: () => _revertToGhost(index),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getBucketColor(item.bucket, themeColor).withValues(alpha: 0.1),
                                border: Border.all(color: _getBucketColor(item.bucket, themeColor)),
                                borderRadius: BorderRadius.circular(4)
                              ),
                              child: Text(item.bucket, style: TextStyle(fontFamily: 'ShareTechMono', color: _getBucketColor(item.bucket, themeColor), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}