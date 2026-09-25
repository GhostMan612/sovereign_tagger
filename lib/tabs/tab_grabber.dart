// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import '../core/cyber_tap_feedback.dart';
import 'package:video_player/video_player.dart';
import '../core/media_probe.dart';
import '../screens/main_shell.dart';

class TabGrabber extends StatefulWidget {
  const TabGrabber({super.key});
  @override
  State<TabGrabber> createState() => _TabGrabberState();
}

class _TabGrabberState extends State<TabGrabber> {
  static const MethodChannel _ytChannel = MethodChannel('com.sovereign.tagger/ytdlp');
  static const EventChannel _eventChannel = EventChannel('com.sovereign.tagger/ytdlp_events');
  static const MethodChannel _id3Channel = MethodChannel('com.sovereign.tagger/id3');
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');

  VideoPlayerController? _videoController;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _trackNoController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = "System Idle. Ready For Target URL.";
  String _lastDownloadedFile = "";
  
  bool _isFetchingFormats = false;
  String _fetchedMediaTitle = "";
  bool _isCurrentJobVideo = false;

  String _searchSource = "youtube";
  String _quickVideoRes = "1080";
  String _audioExportMode = "MP3 320K";
  String _activeDownloadUrl = "";
  String? _companionPendingVideo;
  int _selfHealAttempts = 0;

  String _newJobId() => "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(900000) + 100000}";

  @override
  void initState() {
    super.initState();
    _listenToDownloadEvents();
  }

  @override
  void dispose() {
    _urlController.dispose(); _trackNoController.dispose(); _artistController.dispose(); _titleController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _listenToDownloadEvents() {
    _eventChannel.receiveBroadcastStream().listen((event) {
      if (!mounted) return;
      try {
        final data = jsonDecode(event.toString());
        final status = data['status'];
        if (status == 'downloading') {
          setState(() {
            _progress = (data['percent'] as num).toDouble();
            final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
            final file = data['current_file'] ?? "";
            if (file.isNotEmpty) {
              _statusMessage = "Fetching: $file\n[ ${(speed / 1024 / 1024).toStringAsFixed(2)} MB/s ]";
            } else {
              _statusMessage = "Fetching Media... [ ${(speed / 1024 / 1024).toStringAsFixed(2)} MB/s ]";
            }
          });
        } else if (status == 'finished') {
          final isPlaylist = data['isPlaylist'] ?? false;
          if (!isPlaylist && _companionPendingVideo != null && data['audioPath'] == null) {
            final videoPath = _companionPendingVideo!;
            _companionPendingVideo = null;
            _mergeSelfHealed(videoPath, data['filePath']);
          } else if (isPlaylist) {
             _processPlaylistPipeline(data['filePath']);
          } else {
             _processMediaPipeline(data['filePath'], isSplit: data['isSplit'] ?? false, audioPath: data['audioPath']);
          }
        }
      } catch (_) {
      }
    }, onError: (error) {
      if (!mounted) return;
      setState(() { _isProcessing = false; _statusMessage = "ERR: Download Failed: $error"; });
    });
  }

  Future<void> _executeHunterKiller() async {
    TapFeedback.machineTap();
    final query = "${_artistController.text.trim()} ${_titleController.text.trim()}".trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ENTER ARTIST AND TITLE TO SEARCH.', style: TextStyle(fontFamily: 'ShareTechMono'))));
      return;
    }
    setState(() { _isProcessing = true; _statusMessage = "Hunting On ${_searchSource.toUpperCase()}..."; });

    try {
      final result = await _ytChannel.invokeMethod('searchMedia', {'query': query, 'source': _searchSource});
      final data = jsonDecode(result.toString());

      if (data['status'] == 'success') {
        final results = data['results'] as List<dynamic>;
        setState(() { _isProcessing = false; _statusMessage = "Targets Acquired."; });
        if (!mounted) return;
        _showSearchResults(results);
      } else {
        setState(() { _isProcessing = false; _statusMessage = "ERR: Search Failed: ${data['message']}"; });
      }
    } catch (e) {
      setState(() { _isProcessing = false; _statusMessage = "ERR: Hunter Kernel Fault: $e"; });
    }
  }

  void _showSearchResults(List<dynamic> results) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.black,
      builder: (context) {
        return ValueListenableBuilder<Color>(
          valueListenable: SovereignState.accentColor,
          builder: (context, themeColor, child) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.5, expand: false,
              builder: (context, scrollController) {
                return Material(
                    color: Colors.black,
                    shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
                    child: Column(
                    children: [
                      Padding(padding: const EdgeInsets.all(16.0), child: Text("SELECT TARGET SOURCE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 18, fontWeight: FontWeight.bold, color: themeColor))),
                      Divider(color: themeColor.withValues(alpha: 0.3)),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController, itemCount: results.length,
                          itemBuilder: (context, index) {
                            final r = results[index];
                            final duration = r['duration'] ?? 0;
                            final min = duration ~/ 60;
                            final sec = (duration % 60).toString().padLeft(2, '0');

                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: Icon(Icons.track_changes, color: themeColor, size: 32),
                                title: Text(r['title'] ?? 'UNKNOWN', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                                subtitle: Text("${r['uploader']} • $min:$sec", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
                                onTap: () {
                                  Navigator.pop(context);
                                  setState(() => _urlController.text = r['url']);
                                  _fetchAvailableFormats();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        );
      },
    );
  }

  Future<void> _quickAudio() async {
    TapFeedback.machineTap();
    final url = _urlController.text.trim();
    if (url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PROVIDE VALID TARGET URL.', style: TextStyle(fontFamily: 'ShareTechMono')))); return; }
    _startDownload(url, 'bestaudio/best', false);
  }

  Future<void> _quickVideo() async {
    TapFeedback.machineTap();
    final url = _urlController.text.trim();
    if (url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PROVIDE VALID TARGET URL.', style: TextStyle(fontFamily: 'ShareTechMono')))); return; }
    _startDownload(url, "bestvideo[height<=$_quickVideoRes]+bestaudio/best", true);
  }

  Future<void> _fetchAvailableFormats() async {
    TapFeedback.machineTap();
    final url = _urlController.text.trim();
    if (url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PROVIDE VALID TARGET URL.', style: TextStyle(fontFamily: 'ShareTechMono')))); return; }
    setState(() { _isFetchingFormats = true; _statusMessage = "Analyzing Target Multiplex..."; });

    try {
      final result = await _ytChannel.invokeMethod('getFormats', {'url': url});
      final data = jsonDecode(result.toString());

      if (data['status'] == 'error') { if (!mounted) return; setState(() { _isFetchingFormats = false; _statusMessage = "ERR: ${data['message']}"; }); return; }

      if (data['is_playlist'] == true) {
         if (!mounted) return;
         setState(() {
           _isFetchingFormats = false;
           _fetchedMediaTitle = data['title'];
           _statusMessage = "Playlist Detected: ${data['track_count']} Tracks.";
         });
         _showPlaylistDialog(url, data['title'], data['track_count']);
         return;
      }

      final List<dynamic> rawFormats = data['formats'] ?? [];
      final String mediaTitle = data['title'] ?? 'UNKNOWN MEDIA';
      
      setState(() { _fetchedMediaTitle = mediaTitle; if (_titleController.text.isEmpty) _titleController.text = mediaTitle; _isFetchingFormats = false; _statusMessage = "Formats Decrypted."; });

      final List<Map<String, dynamic>> cleanFormats = [];
      for (var f in rawFormats) {
         final resolution = f['resolution']?.toString() ?? '';
         final ext = f['ext']?.toString() ?? '';
         if (resolution == 'unknown' || ext == 'mhtml') continue;
         cleanFormats.add(f as Map<String, dynamic>);
      }
      if (!mounted) return;
      _showFormatPicker(cleanFormats, url);
    } on PlatformException catch (e) { if (!mounted) return; setState(() { _isFetchingFormats = false; _statusMessage = "ERR: Channel Fault: ${e.message}"; }); }
  }

  void _showPlaylistDialog(String url, String title, int count) {
    showDialog(
      context: context,
      builder: (context) {
        return ValueListenableBuilder<Color>(
          valueListenable: SovereignState.accentColor,
          builder: (context, themeColor, child) {
            return AlertDialog(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(side: BorderSide(color: themeColor), borderRadius: BorderRadius.circular(8)),
              title: Text("DOWNLOAD PLAYLIST?", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
              content: Text("TARGET: $title\nTRACKS: $count\n\nWARNING: HARVESTING FULL PLAYLISTS REQUIRES MASSIVE BANDWIDTH. AUDIO WILL BE CONVERTED TO CBR 320KBPS MP3 AND ROUTED TO PIPELINE.", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ABORT", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
                  onPressed: () {
                    Navigator.pop(context);
                    _startDownload(url, 'bestaudio/best', false);
                  },
                  child: const Text("HARVEST PLAYLIST", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _showFormatPicker(List<Map<String, dynamic>> formats, String url) {
    final audioFormats = formats.where((f) => f['resolution'] == 'audio only').toList();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.black,
      builder: (context) {
        return ValueListenableBuilder<Color>(
          valueListenable: SovereignState.accentColor,
          builder: (context, themeColor, child) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.5, expand: false,
              builder: (context, scrollController) {
                return Material(
                    color: Colors.black,
                    shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
                    child: Column(
                    children: [
                      Padding(padding: const EdgeInsets.all(16.0), child: Text("SELECT STREAM FORMAT: $_fetchedMediaTitle", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      Divider(color: themeColor.withValues(alpha: 0.3)),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController, itemCount: formats.length,
                          itemBuilder: (context, index) {
                            final f = formats[index];
                            final isAudioOnly = f['resolution'] == 'audio only';
                            List<String> details = ["SIZE: ${f['filesize'] != null ? (f['filesize'] / 1024 / 1024).toStringAsFixed(1) + " MB" : "UNKNOWN"}"];
                            if (isAudioOnly && f['abr'] != null) details.add("${f['abr'].toStringAsFixed(0)}KBPS");
                            if (!isAudioOnly && f['vbr'] != null) details.add("${f['vbr'].toStringAsFixed(0)}KBPS");

                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: Icon(isAudioOnly ? Icons.audiotrack : Icons.video_library, color: isAudioOnly ? themeColor : Colors.cyanAccent, size: 32),
                                title: Text(isAudioOnly ? "AUDIO ONLY (${f['ext']})" : "VIDEO (${f['resolution']})", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                                subtitle: Text(details.join(" • "), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)), trailing: Text(f['format_id'].toString(), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.grey, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(context);
                                  if (isAudioOnly) {
                                    _startDownload(url, f['format_id'].toString(), false);
                                  } else if (audioFormats.isNotEmpty) {
                                    _showAudioPickerForMerge(audioFormats, url, f['format_id'].toString(), themeColor);
                                  } else {
                                    _startDownload(url, f['format_id'].toString(), true);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        );
      },
    );
  }

  void _showAudioPickerForMerge(List<Map<String, dynamic>> audioFormats, String url, String videoFormatId, Color themeColor) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.black,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.5, expand: false,
          builder: (context, scrollController) {
            return Material(
                color: Colors.black,
                shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
                child: Column(
                children: [
                  Padding(padding: const EdgeInsets.all(16.0), child: Text("SELECT AUDIO STREAM FOR MULTIPLEX MERGE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor))),
                  Divider(color: themeColor.withValues(alpha: 0.3)),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController, itemCount: audioFormats.length,
                      itemBuilder: (context, index) {
                        final f = audioFormats[index];
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            leading: Icon(Icons.audiotrack, color: themeColor, size: 32),
                            title: Text("AUDIO (${f['ext']})", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            subtitle: Text("SIZE: ${f['filesize'] != null ? (f['filesize'] / 1024 / 1024).toStringAsFixed(1) + " MB" : "UNKNOWN"} • ${f['abr'] != null ? f['abr'].toStringAsFixed(0) : '?'}KBPS", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
                            trailing: Text(f['format_id'].toString(), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.grey, fontSize: 12)),
                            onTap: () { Navigator.pop(context); _startDownload(url, "$videoFormatId+${f['format_id']}", true); },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startDownload(String url, String formatId, bool isVideoFormat) async {
    TapFeedback.machineTap();
    AudioService.player.stop();
    _videoController?.dispose(); _videoController = null;
    final jobId = _newJobId();
    setState(() { _isProcessing = true; _progress = 0.0; _statusMessage = "Mounting Python Engine..."; _lastDownloadedFile = ""; _isCurrentJobVideo = isVideoFormat; _activeDownloadUrl = url; _companionPendingVideo = null; _selfHealAttempts = 0; });

    try {
      final resultData = jsonDecode((await _ytChannel.invokeMethod('downloadMedia', {'url': url, 'formatId': formatId, 'jobId': jobId, 'optionsJson': jsonEncode({'formatId': formatId})})).toString());
      if (resultData['status'] == 'error') { if (!mounted) return; setState(() { _isProcessing = false; _statusMessage = "ERR: ${resultData['message']}"; }); }
    } on PlatformException catch (e) { if (!mounted) return; setState(() { _isProcessing = false; _statusMessage = "ERR: Channel Fault: ${e.message}"; }); }
  }

  Future<void> _processPlaylistPipeline(String dirPath) async {
    TapFeedback.machineTap();
    if (!mounted) return;
    setState(() => _statusMessage = "Playlist Acquired. Routing To Transcoder...");
    
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      setState(() { _isProcessing = false; _statusMessage = "ERR: Playlist Cache Corrupt."; });
      return;
    }

    try {
      int count = 0;
      for (var file in dir.listSync()) {
        if (file is File && !file.path.endsWith('.mp3')) {
          final mp3Path = "${file.path}.mp3";
          final durationMs = await probeDurationMs(file.path);
          final session = await FFmpegExecutor.execute("-y -i \"${file.path}\" -vn -c:a libmp3lame -b:a 320k \"$mp3Path\"", onStatistics: (stats) {
            if (durationMs == null || durationMs <= 0 || !mounted) return;
            final pct = (stats.time / durationMs).clamp(0.0, 1.0);
            setState(() => _statusMessage = "Transcoding: ${(pct * 100).toStringAsFixed(0)}%");
          });
          final returnCode = session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            final fileName = file.path.split('/').last;
            await _storageChannel.invokeMethod('addToMediaStore', {'filePath': mp3Path, 'title': fileName});
            try { File(mp3Path).deleteSync(); } catch (_) {}
            count++;
          }
          try { file.deleteSync(); } catch (_) {}
        }
      }
      
      TapFeedback.machineConfirm();
      setState(() { _statusMessage = "Success. $count Tracks Exported. Open Pipeline To Batch Tag."; _isProcessing = false; });
    } catch (e) {
      setState(() { _isProcessing = false; _statusMessage = "ERR: Playlist Transcode Fault: $e"; });
    }
  }

  Future<Map<String, int>> _probeStreams(String path) => probeStreams(path);

  Future<String?> _mergeWithLadder(String videoPath, String audioPath, String outDir) async {
    TapFeedback.machineTap();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tempVid = "$outDir/temp_v_$stamp.tmp";
    final tempAud = "$outDir/temp_a_$stamp.tmp";
    final tempAudAac = "$outDir/temp_aa_$stamp.m4a";
    final tempOut = "$outDir/temp_o_$stamp.mkv";

    try { File(videoPath).renameSync(tempVid); } catch (_) { return null; }
    try { File(audioPath).renameSync(tempAud); } catch (_) { try { File(tempVid).deleteSync(); } catch (_) {} return null; }

    Future<bool> verifyOutput() async {
      var probe = await _probeStreams(tempOut);
      if (probe.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
        probe = await _probeStreams(tempOut);
      }
      // Empty probe = ffprobe could not read (resource/timing) — trust the
      // successful return code rather than failing the rung. Explicit audio==0
      // is the only hard rejection.
      final audioCount = probe['audio'];
      return audioCount == null || audioCount > 0;
    }

    void cleanupSuccess() {
      try { File(tempAudAac).deleteSync(); File(tempVid).deleteSync(); File(tempAud).deleteSync(); } catch (_) {}
    }

    void cleanupFailure() {
      try { File(tempOut).deleteSync(); File(tempAudAac).deleteSync(); File(tempVid).deleteSync(); File(tempAud).deleteSync(); } catch (_) {}
    }

    setState(() => _statusMessage = "Multiplex Rung 1/3 (Stream Copy + Explicit Maps)...");
    final session1 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAud\" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 \"$tempOut\"");
    if (ReturnCode.isSuccess(session1.getReturnCode()) && await verifyOutput()) {
      cleanupSuccess();
      return tempOut;
    }
    try { File(tempOut).deleteSync(); } catch (_) {}

    setState(() => _statusMessage = "Rung 1 Fault. Rung 2/3: AAC Companion Remux...");
    final remux = await FFmpegExecutor.execute("-y -i \"$tempAud\" -vn -c:a aac -b:a 256k \"$tempAudAac\"");
    if (ReturnCode.isSuccess(remux.getReturnCode())) {
      final session2 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAudAac\" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 \"$tempOut\"");
      if (ReturnCode.isSuccess(session2.getReturnCode()) && await verifyOutput()) {
        cleanupSuccess();
        return tempOut;
      }
      try { File(tempOut).deleteSync(); } catch (_) {}
    }

    setState(() => _statusMessage = "Rung 2 Fault. Rung 3/3: Default Stream Selection...");
    final session3 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAud\" -c:v copy -c:a copy \"$tempOut\"");
    if (ReturnCode.isSuccess(session3.getReturnCode()) && await verifyOutput()) {
      cleanupSuccess();
      return tempOut;
    }

    cleanupFailure();
    final panicLog = session3.getOutput() ?? "";
    final logTail = panicLog.length > 300 ? panicLog.substring(panicLog.length - 300) : panicLog;
    _lastMergeDiagnostics = logTail.replaceAll('\n', ' | ');
    return null;
  }

  String _lastMergeDiagnostics = "";

  Future<void> _mergeSelfHealed(String videoPath, String audioPath) async {
    if (!mounted) return;
    setState(() => _statusMessage = "COMPANION AUDIO ACQUIRED. RESUMING MULTIPLEX...");
    await _processMediaPipeline(videoPath, isSplit: true, audioPath: audioPath);
  }

  Future<void> _processMediaPipeline(String rawFilePath, {bool isSplit = false, String? audioPath}) async {
    if (!mounted) return;
    setState(() { _progress = 1.0; _statusMessage = "Processing Media Payload..."; });

    final title = _titleController.text.isNotEmpty ? _titleController.text : "UNKNOWN TITLE";
    final artist = _artistController.text.isNotEmpty ? _artistController.text : "UNKNOWN ARTIST";
    String paddedTrack = _trackNoController.text.trim();
    if (paddedTrack.isNotEmpty && paddedTrack.length == 1) paddedTrack = "0$paddedTrack";
    final cleanTrack = paddedTrack.isNotEmpty ? "$paddedTrack - " : "";
    
    final cleanTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final cleanArtist = artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final String outDir = rawFilePath.substring(0, rawFilePath.lastIndexOf('/'));
    String finalPathForStorage = rawFilePath;

    if (_isCurrentJobVideo && isSplit && audioPath != null) {
        finalPathForStorage = "$outDir/$cleanTrack$cleanArtist · $cleanTitle.mkv";
        setState(() => _statusMessage = "Merging Lossless MKV (FFmpeg)...");

        final mergedPath = await _mergeWithLadder(rawFilePath, audioPath, outDir);
        if (mergedPath == null) {
            if (!mounted) return;
            setState(() { _isProcessing = false; _statusMessage = "ERR: FFmpeg Video Merge Kernel Panic. All 3 Rungs Failed.\nDIAG: $_lastMergeDiagnostics"; });
            try { File(rawFilePath).deleteSync(); File(audioPath).deleteSync(); } catch (_) {}
            return;
        }

        try { File(mergedPath).renameSync(finalPathForStorage); } catch (_) {}

    } else {
        if (_isCurrentJobVideo) {
            final probe = await _probeStreams(rawFilePath);
            if (!mounted) return;
            if (probe['audio'] == 0 && probe.isNotEmpty) {
                if (_selfHealAttempts >= 1) {
                  setState(() { _isProcessing = false; _statusMessage = "ERR: Silent Payload Self-Heal Already Attempted. Try ADVANCED FORMAT FETCH With Progressive Stream."; });
                  return;
                }
                _selfHealAttempts++;
                if (_activeDownloadUrl.isNotEmpty && _companionPendingVideo == null) {
                    setState(() => _statusMessage = "PAYLOAD IS SILENT (0 AUDIO STREAMS). SELF-HEALING: FETCHING COMPANION AUDIO STREAM...");
                    _companionPendingVideo = rawFilePath;
                    try {
                      final companionJob = _newJobId();
                      final companionResult = jsonDecode((await _ytChannel.invokeMethod('downloadMedia', {'url': _activeDownloadUrl, 'formatId': 'bestaudio/best', 'jobId': companionJob, 'optionsJson': jsonEncode({'formatId': 'bestaudio/best'})})).toString());
                      if (_companionPendingVideo == null) return;
                      if (companionResult['status'] == 'error') throw Exception(companionResult['message']);
                    } catch (e) {
                      _companionPendingVideo = null;
                      if (!mounted) return;
                      setState(() { _isProcessing = false; _statusMessage = "ERR: Self-Heal Companion Fetch Failed: $e"; });
                    }
                    return;
                }
                setState(() { _isProcessing = false; _statusMessage = "ERR: Silent Payload. No Companion Available. Use ADVANCED FORMAT FETCH And Pick A Progressive Stream."; });
                return;
            }
            finalPathForStorage = "$outDir/$cleanTrack$cleanArtist · $cleanTitle.${rawFilePath.split('.').last}";
            try { File(rawFilePath).renameSync(finalPathForStorage); } catch (_) {}
        } else {
            final rawExt = rawFilePath.split('.').last.toLowerCase();
            if (_audioExportMode == "SOURCE COPY" && ['webm', 'opus', 'm4a', 'mp4'].contains(rawExt)) {
                final copyExt = rawExt == 'webm' ? 'webm' : rawExt;
                finalPathForStorage = "$outDir/$cleanTrack$cleanArtist · $cleanTitle.$copyExt";
                setState(() => _statusMessage = "SOURCE COPY: Preserving Original Codec Stream (No Transcode)...");
                try { File(rawFilePath).renameSync(finalPathForStorage); } catch (_) {}
            } else {
            finalPathForStorage = "$outDir/$cleanTrack$cleanArtist · $cleanTitle.mp3";
            setState(() => _statusMessage = "Audio Transcoding (FFmpeg)...");
            
            final tempIn = "$outDir/temp_i_${DateTime.now().millisecondsSinceEpoch}.tmp";
            final tempOut = "$outDir/temp_o_${DateTime.now().millisecondsSinceEpoch}.mp3";

            try { File(rawFilePath).renameSync(tempIn); } catch (_) {}

            final durationMs = await probeDurationMs(tempIn);
            final session = await FFmpegExecutor.execute("-y -i \"$tempIn\" -vn -c:a libmp3lame -b:a 320k \"$tempOut\"", onStatistics: (stats) {
              if (durationMs == null || durationMs <= 0 || !mounted) return;
              final pct = (stats.time / durationMs).clamp(0.0, 1.0);
              setState(() => _statusMessage = "Audio Transcoding: ${(pct * 100).toStringAsFixed(0)}%");
            });
            final returnCode = session.getReturnCode();
            
            if (ReturnCode.isSuccess(returnCode)) {
                try { File(tempOut).renameSync(finalPathForStorage); } catch (_) {}
                try { File(tempIn).deleteSync(); } catch (_) {}
            } else {
                setState(() { _isProcessing = false; _statusMessage = "ERR: FFmpeg Transcode Fault."; });
                try { File(tempIn).deleteSync(); } catch (_) {}
                return;
            }
            if (!mounted) return;
            setState(() => _statusMessage = "Injecting ID3 Metadata...");
            try { 
              await _id3Channel.invokeMethod('writeTags', {'filePath': finalPathForStorage, 'metadata': {'TITLE': title, 'ARTIST': artist, if (paddedTrack.isNotEmpty) 'TRACK': paddedTrack}}); 
            } catch (_) {
            }

            setState(() => _statusMessage = "Verifying Container Integrity...");
            final expectedMs = durationMs;
            final actualMs = await probeDurationMs(finalPathForStorage);
            if (expectedMs != null && actualMs != null) {
              final drift = (expectedMs - actualMs).abs();
              if (drift > 2000) {
                setState(() => _statusMessage = "Xing Header Fault Detected (drift ${(drift / 1000).toStringAsFixed(1)}s). Lossless Repair...");
                final repairPath = "$outDir/temp_r_${DateTime.now().millisecondsSinceEpoch}.mp3";
                final repair = await FFmpegExecutor.execute("-y -i \"$finalPathForStorage\" -c copy -write_xing 1 -id3v2_version 3 \"$repairPath\"");
                if (ReturnCode.isSuccess(repair.getReturnCode())) {
                  final repairedMs = await probeDurationMs(repairPath);
                  if (repairedMs != null && (expectedMs - repairedMs).abs() <= 2000) {
                    try {
                      File(finalPathForStorage).deleteSync();
                      File(repairPath).renameSync(finalPathForStorage);
                      setState(() => _statusMessage = "Container Repaired. Xing Header Regenerated.");
                    } catch (_) {
                      try { File(repairPath).deleteSync(); } catch (_) {}
                    }
                  } else {
                    try { File(repairPath).deleteSync(); } catch (_) {}
                  }
                } else {
                  try { File(repairPath).deleteSync(); } catch (_) {}
                }
              }
            }
            }
        }
    }

    if (!mounted) return;
    
    if (_isCurrentJobVideo) {
      setState(() => _statusMessage = "Exporting Video To Public Vault...");
      try {
        final finalUri = (await _storageChannel.invokeMethod('addToMediaStore', {'filePath': finalPathForStorage, 'title': title}))?.toString() ?? finalPathForStorage;

        TapFeedback.machineConfirm();
        setState(() { _statusMessage = "Success. Secured In Movies Folder."; _lastDownloadedFile = finalUri; _isProcessing = false; });

        _videoController = VideoPlayerController.networkUrl(Uri.parse(finalUri));
        await _videoController!.initialize();
        setState(() {}); 

        try {
          if (File(finalPathForStorage).existsSync()) File(finalPathForStorage).deleteSync();
        } catch (_) {}

      } catch (e) {
        if (!mounted) return;
        setState(() { _isProcessing = false; _statusMessage = "ERR: Storage Mount Fault: $e"; });
      }
    } else {
      setState(() => _statusMessage = "Routing Raw Audio To The Forge...");
      TapFeedback.machineConfirm();
      setState(() {
        _statusMessage = "Success. Track Isolated In System Cache."; 
        _lastDownloadedFile = finalPathForStorage; 
        _isProcessing = false; 
      });
      
      SovereignState.pendingForgePath.value = finalPathForStorage;
      SovereignState.currentTab.value = 1;
    }
  }

  Widget _buildField(String label, TextEditingController controller, Color themeColor, {bool isNumber = false}) {
    return TextField(
      controller: controller, 
      style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, 
        labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
        filled: true,
        fillColor: Colors.black,
      ), 
      enabled: !_isProcessing && !_isFetchingFormats
    );
  }

  void _showYtDlpHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: Colors.cyanAccent),
        ),
        child: SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.help_outline, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      const Expanded(child: Text("YT-DLP FIELD MANUAL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  _h("WHAT THIS ENGINE IS"),
                  _b("yt-dlp is the same downloader engine the desktop pros use — 1000+ supported sites. This tab drives it natively through bundled Python; no shell, no cloud."),
                  _h("SITES THAT WORK WELL"),
                  _b("YouTube • SoundCloud • Bandcamp • Vimeo • Twitter/X • Reddit • direct media URLs. Facebook works too — silent videos auto-heal with a bestaudio companion fetch."),
                  _h("THREE WAYS TO GRAB"),
                  _b("1. QUICK AUDIO — bestaudio/best, fastest path to Forge.\n2. QUICK VIDEO — best video up to your chosen height + best audio, auto-merged losslessly.\n3. ADVANCED — fetch every format the site exposes and hand-pick exact streams."),
                  _h("EXPORT AS"),
                  _b("MP3 320K (default): decoded + re-encoded at max quality with full ID3 tagging.\nSOURCE COPY: zero transcode passthrough (webm/opus/m4a) — bit-perfect, skips ID3 for webm."),
                  _h("TIPS THE PROS USE"),
                  _b("- Paste a DIRECT LINK to skip search entirely (DIRECT LINK OVERRIDE).\n- If YouTube throws bot-walls: SETTINGS > CHECK FOR YT-DLP UPDATE (scorched-earth pulls latest master from GitHub).\n- Still broken? RUN ON-BOARD PYTHON DOCTOR, then FULL STACK REFRESH.\n- Playlists: paste a playlist URL and confirm the batch dialog when prompted.\n- Age/region-locked media may need an advanced format pick instead of quick modes."),
                  _h("KNOWN LIMITS"),
                  _b("- DRM streams (Netflix/Spotify) are unsupported by design.\n- Private/login-only content needs cookies this build does not carry.\n- Live streams grab as best available segment snapshot."),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _h(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(t, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
  );

  Widget _b(String t) => Text(t, style: const TextStyle(fontFamily: 'VT323', fontSize: 15, color: Colors.white70, height: 1.35));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Container(
          color: Colors.black,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("MEDIA ASSEMBLY PIPELINE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2)),
                    ),
                    IconButton(
                      icon: Icon(Icons.help_outline, color: themeColor),
                      tooltip: "YT-DLP FIELD MANUAL",
                      onPressed: _showYtDlpHelp,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_isProcessing || _progress > 0)
                  LinearProgressIndicator(value: _progress, minHeight: 3, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
                if (_isProcessing || _progress > 0) const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: _statusMessage.contains("ERR") ? Colors.redAccent : themeColor)
                  ),
                  child: Text(
                    "> $_statusMessage",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'VT323',
                      fontSize: 14,
                      color: _statusMessage.contains("ERR") ? Colors.redAccent : themeColor,
                      height: 1.2
                    )
                  ),
                ),
                const SizedBox(height: 14),

                const Text("> DIRECT LINK OVERRIDE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 12),
                _buildField('TARGET URL [OPTIONAL]', _urlController, themeColor),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: (_isProcessing || _isFetchingFormats) ? null : _fetchAvailableFormats, 
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white24), backgroundColor: Colors.black), 
                  child: Text(_isFetchingFormats ? 'ANALYZING FORMATS...' : (_isProcessing ? 'PROCESSING...' : 'ADVANCED: FETCH ALL FORMATS'), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, color: Colors.white70))
                ),
                
                const SizedBox(height: 24),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),
                
                const Text("> DATABASE QUERY ENGINE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 12),
                Row(children: [Expanded(flex: 2, child: _buildField('TRACK NO.', _trackNoController, themeColor, isNumber: true)), const SizedBox(width: 12), Expanded(flex: 5, child: _buildField('ARTIST', _artistController, themeColor))]),
                const SizedBox(height: 12), _buildField('SONG TITLE', _titleController, themeColor),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _searchSource,
                            isExpanded: true,
                            dropdownColor: Colors.black,
                            icon: Icon(Icons.arrow_drop_down, color: themeColor),
                            items: const [
                              DropdownMenuItem<String>(value: "youtube", child: Text("YOUTUBE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold))),
                              DropdownMenuItem<String>(value: "soundcloud", child: Text("SOUNDCLOUD", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold))),
                              DropdownMenuItem<String>(value: "bandcamp", child: Text("BANDCAMP", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold))),
                            ],
                            onChanged: _isProcessing ? null : (String? newValue) {
                              if (newValue != null) setState(() => _searchSource = newValue);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: CyberTapFeedback(
                        enableHaptic: false,
                        enableAudio: false,
                        particleColor: themeColor,
                        ringColor: themeColor,
                        child: OutlinedButton.icon(
                          onPressed: (_isProcessing || _isFetchingFormats) ? null : _executeHunterKiller,
                          icon: Icon(Icons.radar, color: themeColor),
                          label: Text("MEDIA HUNTER", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: themeColor),
                            backgroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),

                const Text("> AUDIOPHILE QUICK-GRAB ENGINE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _audioExportMode,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: const [
                            DropdownMenuItem<String>(value: "MP3 320K", child: Text("MP3 320K", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontWeight: FontWeight.bold))),
                            DropdownMenuItem<String>(value: "SOURCE COPY", child: Text("SOURCE COPY", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
                          ],
                          onChanged: _isProcessing ? null : (String? newValue) {
                            if (newValue != null) setState(() => _audioExportMode = newValue);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isProcessing || _isFetchingFormats) ? null : _quickAudio, 
                        icon: Icon(Icons.graphic_eq, color: themeColor), 
                        label: Text(_audioExportMode == "MP3 320K" ? "MAX AUDIO [MP3]" : "MAX AUDIO [SOURCE]", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)), 
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: themeColor.withValues(alpha: 0.5)), backgroundColor: Colors.black)
                      )
                    ),
                  ]
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _quickVideoRes,
                          dropdownColor: Colors.black,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                          items: const [
                            DropdownMenuItem<String>(value: "2160", child: Text("4K", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
                            DropdownMenuItem<String>(value: "1440", child: Text("2K", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
                            DropdownMenuItem<String>(value: "1080", child: Text("1080P", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
                            DropdownMenuItem<String>(value: "720", child: Text("720P", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
                          ],
                          onChanged: _isProcessing ? null : (String? newValue) {
                            if (newValue != null) setState(() => _quickVideoRes = newValue);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isProcessing || _isFetchingFormats) ? null : _quickVideo, 
                        icon: const Icon(Icons.movie_filter, color: Colors.cyanAccent), 
                        label: const Text("QUICK VIDEO [MKV]", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)), 
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5)), backgroundColor: Colors.black)
                      )
                    ),
                  ]
                ),
                
                const SizedBox(height: 24),

                if (_lastDownloadedFile.isNotEmpty && !_isProcessing) ...[
                  const SizedBox(height: 16),
                  if (_isCurrentJobVideo && _videoController != null && _videoController!.value.isInitialized)
                    Container(
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                      child: Column(
                        children: [
                          AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: VideoPlayer(_videoController!))),
                          IconButton(icon: Icon(_videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: themeColor, size: 32), onPressed: () => setState(() => _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play()))
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12), 
                    decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withValues(alpha: 0.3))), 
                    child: Text("> FINAL PIPELINE DESTINATION:\n> $_lastDownloadedFile", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70, height: 1.5))
                  ),
                ],
              ],
            ),
          ),
        );
      }
    );
  }
}