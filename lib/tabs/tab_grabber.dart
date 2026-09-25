// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/tap_feedback.dart';
import '../core/ffmpeg_executor.dart';
import '../core/cyber_tap_feedback.dart';
import '../core/forge_request.dart';
import '../core/media_probe.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../core/title_cleaner.dart';
import '../screens/main_shell.dart';

enum _ExportMode { m4a, mp3, original }

class _GrabJob {
  final String id;
  final String url;
  final bool isVideo;
  final bool isPlaylist;
  final _ExportMode mode;
  String label;
  String stage = "Starting yt-dlp...";
  double progress = 0;
  double speed = 0;
  String? error;
  String? companionForVideo;
  int selfHealAttempts = 0;

  _GrabJob({required this.id, required this.url, required this.isVideo, required this.isPlaylist, required this.mode, required this.label});
}

class _GrabCard {
  final String id;
  String path;
  final bool isVideo;
  final Map<String, dynamic> info;
  final TextEditingController title;
  final TextEditingController artist;
  final TextEditingController album;
  final TextEditingController track;
  final TextEditingController fileName;
  String artBase64 = "";
  bool useArt = true;
  bool busy = false;
  bool fileNameTouched = false;
  String status = "";
  String? savedUri;
  String? savedPath;

  _GrabCard({required this.id, required this.path, required this.isVideo, required this.info, required String t, required String a, required String al, required String tr, required String name})
      : title = TextEditingController(text: t),
        artist = TextEditingController(text: a),
        album = TextEditingController(text: al),
        track = TextEditingController(text: tr),
        fileName = TextEditingController(text: name);

  bool get saved => savedUri != null;
  String get ext => TitleCleaner.extensionOf(path);

  void dispose() {
    title.dispose();
    artist.dispose();
    album.dispose();
    track.dispose();
    fileName.dispose();
  }

  Map<String, String> tags() => {
        'TITLE': title.text.trim(),
        'ARTIST': artist.text.trim(),
        'ALBUM': album.text.trim(),
        'TRACK': track.text.trim(),
        if ((info['release_year'] ?? '').toString().isNotEmpty) 'YEAR': info['release_year'].toString(),
        if ((info['genre'] ?? '').toString().isNotEmpty) 'GENRE': info['genre'].toString(),
        if (useArt && artBase64.isNotEmpty) 'ARTWORK_BASE64': artBase64,
      };
}

class TabGrabber extends StatefulWidget {
  const TabGrabber({super.key});
  @override
  State<TabGrabber> createState() => _TabGrabberState();
}

class _TabGrabberState extends State<TabGrabber> {
  static const MethodChannel _ytChannel = MethodChannel('com.sovereign.tagger/ytdlp');
  static const EventChannel _eventChannel = EventChannel('com.sovereign.tagger/ytdlp_events');

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  final Map<String, _GrabJob> _jobs = {};
  final List<_GrabCard> _cards = [];
  StreamSubscription? _eventSub;

  bool _isBusy = false;
  String _statusMessage = "System Idle. Paste A Link, Share One From Another App, Or Hunt By Artist + Title.";
  String _searchSource = "youtube";
  String _quickVideoRes = "1080";
  _ExportMode _exportMode = _ExportMode.m4a;
  String _lastMergeDiagnostics = "";

  String _newJobId() => "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(900000) + 100000}";

  @override
  void initState() {
    super.initState();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    SovereignState.pendingGrabberUrl.addListener(_onSharedUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedUrl());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    SovereignState.pendingGrabberUrl.removeListener(_onSharedUrl);
    _urlController.dispose();
    _artistController.dispose();
    _titleController.dispose();
    for (final c in _cards) {
      c.dispose();
    }
    super.dispose();
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
  }

  void _onSharedUrl() {
    final url = SovereignState.pendingGrabberUrl.value;
    if (url == null || url.isEmpty) return;
    SovereignState.pendingGrabberUrl.value = null;
    setState(() {
      _urlController.text = url;
      _statusMessage = "Link Received. Choose MAX AUDIO, QUICK VIDEO Or FETCH ALL FORMATS.";
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'ShareTechMono'))));
  }

  String? _requireUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _toast('PASTE OR SHARE A LINK FIRST.');
      return null;
    }
    return url;
  }

  String _audioFormatFor(_ExportMode mode) => mode == _ExportMode.m4a ? 'bestaudio[ext=m4a]/bestaudio/best' : 'bestaudio/best';

  void _onEvent(dynamic event) {
    if (!mounted) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(event.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final jobId = data['jobId']?.toString() ?? '';
    final job = _jobs[jobId] ?? _jobs.values.where((j) => j.companionForVideo != null && jobId.startsWith(j.id)).firstOrNull;
    if (job == null) return;
    final status = data['status'];
    if (status == 'downloading') {
      setState(() {
        job.progress = (data['percent'] as num?)?.toDouble() ?? 0;
        job.speed = (data['speed'] as num?)?.toDouble() ?? 0;
        final idx = (data['playlist_index'] as num?)?.toInt() ?? 0;
        final count = (data['playlist_count'] as num?)?.toInt() ?? 0;
        final name = data['current_file']?.toString() ?? '';
        if (name.isNotEmpty && !job.isPlaylist) job.label = name;
        job.stage = "${data['stage'] == 'video' ? 'VIDEO' : data['stage'] == 'audio' ? 'AUDIO' : 'FETCH'}${count > 0 ? ' $idx/$count' : ''} • ${(job.speed / 1024 / 1024).toStringAsFixed(2)} MB/s${count > 0 && name.isNotEmpty ? '\n$name' : ''}";
      });
    } else if (status == 'finished') {
      _onFinished(job, jobId, data);
    }
  }

  Future<void> _startDownload(String url, String formatId, {required bool isVideo, bool playlist = false, String? label}) async {
    TapFeedback.machineTap();
    final jobId = _newJobId();
    final job = _GrabJob(id: jobId, url: url, isVideo: isVideo, isPlaylist: playlist, mode: _exportMode, label: label ?? url);
    setState(() {
      _jobs[jobId] = job;
      _statusMessage = "Download Started. You Can Keep Browsing — Results Appear Below.";
    });
    try {
      final raw = await _ytChannel.invokeMethod('downloadMedia', {'url': url, 'formatId': formatId, 'jobId': jobId, 'optionsJson': jsonEncode({'formatId': formatId, 'playlist': playlist})});
      final result = jsonDecode(raw.toString()) as Map<String, dynamic>;
      if (!mounted) return;
      if (result['status'] == 'cancelled') {
        setState(() => _jobs.remove(jobId));
        _setStatus("Download Cancelled.");
      } else if (result['status'] == 'error') {
        setState(() {
          job.error = result['message']?.toString() ?? 'Unknown yt-dlp error';
          job.stage = "FAILED";
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        job.error = e.message ?? 'Channel fault';
        job.stage = "FAILED";
      });
    }
  }

  Future<void> _cancelJob(_GrabJob job) async {
    TapFeedback.machineTap();
    setState(() => job.stage = "Cancelling...");
    try {
      await _ytChannel.invokeMethod('cancelDownload', {'jobId': job.id});
    } catch (_) {}
  }

  void _dismissJob(_GrabJob job) => setState(() => _jobs.remove(job.id));

  Future<void> _onFinished(_GrabJob job, String eventJobId, Map<String, dynamic> data) async {
    final info = (data['info'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    try {
      if (job.companionForVideo != null && eventJobId != job.id) {
        final videoPath = job.companionForVideo!;
        job.companionForVideo = null;
        setState(() => job.stage = "Companion Audio Acquired. Merging...");
        await _finishVideo(job, videoPath, data['filePath']?.toString(), info, isSplit: true);
        return;
      }
      if (data['isPlaylist'] == true) {
        final items = ((data['items'] as List?) ?? const []).whereType<Map>().toList();
        for (var i = 0; i < items.length; i++) {
          if (!mounted) return;
          setState(() {
            job.stage = "Processing ${i + 1}/${items.length}...";
            job.progress = (i + 1) / items.length;
          });
          final item = items[i].cast<String, dynamic>();
          await _processAudio(job, item['filePath'].toString(), (item['info'] as Map?)?.cast<String, dynamic>() ?? {});
        }
        _finishJob(job, "${items.length} Tracks Ready Below. Nothing Is Saved Until You Say So.");
        return;
      }
      final path = data['filePath']?.toString() ?? '';
      if (job.isVideo) {
        await _finishVideo(job, path, data['audioPath']?.toString(), info, isSplit: data['isSplit'] == true);
      } else {
        await _processAudio(job, path, info);
        _finishJob(job, "Track Ready Below. Edit Tags, Then SAVE, SEND TO FORGE Or PLAY.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        job.error = "Processing fault: $e";
        job.stage = "FAILED";
      });
    }
  }

  void _finishJob(_GrabJob job, String message) {
    if (!mounted) return;
    TapFeedback.machineConfirm();
    setState(() {
      _jobs.remove(job.id);
      _statusMessage = message;
    });
  }

  Future<String> _convertAudio(_GrabJob job, String rawPath) async {
    final dir = rawPath.substring(0, rawPath.lastIndexOf('/'));
    final base = rawPath.split('/').last.split('.').first;
    final rawExt = TitleCleaner.extensionOf(rawPath);
    Future<String> run(String args, String outExt, String label) async {
      final out = "$dir/${base}_x.$outExt";
      final durationMs = await probeDurationMs(rawPath);
      final session = await FFmpegExecutor.execute('-y -i "$rawPath" $args "$out"', onStatistics: (stats) {
        if (durationMs == null || durationMs <= 0 || !mounted) return;
        setState(() => job.stage = "$label ${((stats.time / durationMs).clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%");
      });
      if (!ReturnCode.isSuccess(session.getReturnCode())) {
        try {
          File(out).deleteSync();
        } catch (_) {}
        throw Exception("FFmpeg $label failed");
      }
      try {
        File(rawPath).deleteSync();
      } catch (_) {}
      return out;
    }

    switch (job.mode) {
      case _ExportMode.original:
        return rawPath;
      case _ExportMode.mp3:
        if (rawExt == 'mp3') return rawPath;
        final out = await run('-vn -c:a libmp3lame -b:a 320k -id3v2_version 3', 'mp3', 'MP3 320K');
        return _repairXing(out);
      case _ExportMode.m4a:
        if (rawExt == 'mp3' || rawExt == 'flac') return rawPath;
        final codec = await probeAudioCodec(rawPath);
        if (codec == 'aac' || codec == 'alac') {
          if (rawExt == 'm4a') return rawPath;
          return run('-vn -c:a copy -movflags +faststart', 'm4a', 'REMUX');
        }
        return run('-vn -c:a aac -b:a 256k -movflags +faststart', 'm4a', 'AAC 256K');
    }
  }

  Future<String> _repairXing(String path) async {
    final expected = await probeDurationMs(path);
    if (expected == null) return path;
    final dir = path.substring(0, path.lastIndexOf('/'));
    final repairPath = "$dir/xing_${DateTime.now().millisecondsSinceEpoch}.mp3";
    final repair = await FFmpegExecutor.execute('-y -i "$path" -c copy -write_xing 1 -id3v2_version 3 "$repairPath"');
    if (ReturnCode.isSuccess(repair.getReturnCode())) {
      final repaired = await probeDurationMs(repairPath);
      if (repaired != null && (expected - repaired).abs() <= 2000) {
        try {
          File(path).deleteSync();
          File(repairPath).renameSync(path);
          return path;
        } catch (_) {}
      }
    }
    try {
      File(repairPath).deleteSync();
    } catch (_) {}
    return path;
  }

  Future<String> _thumbnailArt(String url, String workDir) async {
    if (url.isEmpty) return "";
    final raw = "$workDir/thumb_${DateTime.now().microsecondsSinceEpoch}";
    final out = "$raw.jpg";
    try {
      final res = jsonDecode((await _ytChannel.invokeMethod('fetchThumbnail', {'url': url, 'outPath': raw})).toString()) as Map<String, dynamic>;
      if (res['status'] != 'success') return "";
      final session = await FFmpegExecutor.execute('-y -i "$raw" -vf crop=ih:ih -q:v 3 "$out"');
      final ok = ReturnCode.isSuccess(session.getReturnCode()) && File(out).existsSync();
      final bytes = await File(ok ? out : raw).readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return "";
    } finally {
      for (final p in [raw, out]) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }
  }

  ({String artist, String title, String track}) _guess(Map<String, dynamic> info) {
    final track = (info['track'] ?? '').toString();
    final artist = (info['artist'] ?? '').toString();
    if (track.isNotEmpty && artist.isNotEmpty) {
      return (artist: artist.split(',').first.trim(), title: track, track: (info['track_number'] ?? '').toString());
    }
    final channel = (info['channel'] ?? info['uploader'] ?? '').toString();
    final split = TitleCleaner.splitArtistTitle(artist.isNotEmpty ? artist : channel, (info['title'] ?? '').toString());
    return (artist: split.artist, title: split.title, track: split.trackNo);
  }

  Future<void> _processAudio(_GrabJob job, String rawPath, Map<String, dynamic> info) async {
    if (rawPath.isEmpty || !File(rawPath).existsSync()) throw Exception("Downloaded file missing");
    setState(() => job.stage = "Preparing Audio...");
    final path = await _convertAudio(job, rawPath);
    final g = _guess(info);
    final ext = TitleCleaner.extensionOf(path);
    final card = _GrabCard(
      id: _newJobId(),
      path: path,
      isVideo: false,
      info: info,
      t: g.title,
      a: g.artist,
      al: (info['album'] ?? '').toString(),
      tr: g.track,
      name: TitleCleaner.buildFileName(artist: g.artist, title: g.title, trackNo: g.track, ext: ext),
    );
    if (!mounted) return;
    setState(() {
      job.stage = "Fetching Cover Art...";
      _cards.insert(0, card);
    });
    final art = await _thumbnailArt((info['thumbnail'] ?? '').toString(), path.substring(0, path.lastIndexOf('/')));
    if (!mounted) return;
    setState(() {
      card.artBase64 = art;
      card.status = TagIO.canWrite(path) ? "" : "NOTE: .${ext.toUpperCase()} can't hold tags. Pick M4A or MP3 mode to tag it.";
    });
  }

  Future<void> _finishVideo(_GrabJob job, String videoPath, String? audioPath, Map<String, dynamic> info, {required bool isSplit}) async {
    final outDir = videoPath.substring(0, videoPath.lastIndexOf('/'));
    String finalPath = videoPath;
    if (isSplit && audioPath != null) {
      final merged = await _mergeWithLadder(job, videoPath, audioPath, outDir);
      if (merged == null) {
        if (!mounted) return;
        setState(() {
          job.error = "All 3 merge rungs failed.\nDIAG: $_lastMergeDiagnostics";
          job.stage = "FAILED";
        });
        try {
          File(videoPath).deleteSync();
          File(audioPath).deleteSync();
        } catch (_) {}
        return;
      }
      finalPath = merged;
    } else {
      final probe = await probeStreams(videoPath);
      if (probe['audio'] == 0 && probe.isNotEmpty) {
        if (job.selfHealAttempts >= 1) {
          setState(() {
            job.error = "Video has no audio and self-heal was already tried. Use FETCH ALL FORMATS and pick a stream with audio.";
            job.stage = "FAILED";
          });
          return;
        }
        job.selfHealAttempts++;
        job.companionForVideo = videoPath;
        setState(() => job.stage = "Video Is Silent. Fetching Companion Audio...");
        final companionId = "${job.id}_c";
        final raw = await _ytChannel.invokeMethod('downloadMedia', {'url': job.url, 'formatId': 'bestaudio/best', 'jobId': companionId, 'optionsJson': jsonEncode({'formatId': 'bestaudio/best'})});
        final res = jsonDecode(raw.toString()) as Map<String, dynamic>;
        if (res['status'] != 'success' && mounted) {
          setState(() {
            job.companionForVideo = null;
            job.error = "Companion audio fetch failed: ${res['message'] ?? res['status']}";
            job.stage = "FAILED";
          });
        }
        return;
      }
    }
    final g = _guess(info);
    final ext = TitleCleaner.extensionOf(finalPath);
    final card = _GrabCard(
      id: _newJobId(),
      path: finalPath,
      isVideo: true,
      info: info,
      t: g.title,
      a: g.artist,
      al: '',
      tr: '',
      name: TitleCleaner.buildFileName(artist: g.artist, title: g.title, ext: ext),
    );
    if (!mounted) return;
    setState(() => _cards.insert(0, card));
    _finishJob(job, "Video Ready Below. SAVE TO MOVIES When Happy.");
  }

  Future<String?> _mergeWithLadder(_GrabJob job, String videoPath, String audioPath, String outDir) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tempVid = "$outDir/temp_v_$stamp.tmp";
    final tempAud = "$outDir/temp_a_$stamp.tmp";
    final tempAudAac = "$outDir/temp_aa_$stamp.m4a";
    final tempOut = "$outDir/${job.id}_merged.mkv";

    try {
      File(videoPath).renameSync(tempVid);
    } catch (_) {
      return null;
    }
    try {
      File(audioPath).renameSync(tempAud);
    } catch (_) {
      try {
        File(tempVid).deleteSync();
      } catch (_) {}
      return null;
    }

    Future<bool> verifyOutput() async {
      var probe = await probeStreams(tempOut);
      if (probe.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
        probe = await probeStreams(tempOut);
      }
      final audioCount = probe['audio'];
      return audioCount == null || audioCount > 0;
    }

    void cleanup({required bool keepOut}) {
      for (final p in [tempAudAac, tempVid, tempAud, if (!keepOut) tempOut]) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }

    void stage(String s) {
      if (mounted) setState(() => job.stage = s);
    }

    stage("Merge 1/3: Stream Copy");
    final session1 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAud\" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 \"$tempOut\"");
    if (ReturnCode.isSuccess(session1.getReturnCode()) && await verifyOutput()) {
      cleanup(keepOut: true);
      return tempOut;
    }
    try {
      File(tempOut).deleteSync();
    } catch (_) {}

    stage("Merge 2/3: AAC Companion Remux");
    final remux = await FFmpegExecutor.execute("-y -i \"$tempAud\" -vn -c:a aac -b:a 256k \"$tempAudAac\"");
    if (ReturnCode.isSuccess(remux.getReturnCode())) {
      final session2 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAudAac\" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 \"$tempOut\"");
      if (ReturnCode.isSuccess(session2.getReturnCode()) && await verifyOutput()) {
        cleanup(keepOut: true);
        return tempOut;
      }
      try {
        File(tempOut).deleteSync();
      } catch (_) {}
    }

    stage("Merge 3/3: Default Stream Selection");
    final session3 = await FFmpegExecutor.execute("-y -i \"$tempVid\" -i \"$tempAud\" -c:v copy -c:a copy \"$tempOut\"");
    if (ReturnCode.isSuccess(session3.getReturnCode()) && await verifyOutput()) {
      cleanup(keepOut: true);
      return tempOut;
    }
    cleanup(keepOut: false);
    final panicLog = session3.getOutput() ?? "";
    final logTail = panicLog.length > 300 ? panicLog.substring(panicLog.length - 300) : panicLog;
    _lastMergeDiagnostics = logTail.replaceAll('\n', ' | ');
    return null;
  }

  Future<void> _saveCard(_GrabCard card, {bool silent = false}) async {
    if (card.busy || card.saved) return;
    TapFeedback.machineTap();
    setState(() {
      card.busy = true;
      card.status = card.isVideo ? "Saving To Movies..." : "Writing Tags...";
    });
    try {
      if (!card.isVideo && TagIO.canWrite(card.path)) {
        final ok = await TagIO.write(card.path, card.tags());
        if (!ok) throw Exception("Tag write failed");
      }
      final temp = await StorageClient.tempDir();
      final dir = Directory('$temp/export_${DateTime.now().microsecondsSinceEpoch}');
      dir.createSync(recursive: true);
      final name = TitleCleaner.withExtension(card.fileName.text.trim().isEmpty ? 'Untitled' : card.fileName.text.trim(), card.ext);
      final staged = '${dir.path}/$name';
      SaveResult result;
      try {
        await File(card.path).copy(staged);
        result = await StorageClient.exportToLibrary(staged, card.title.text.trim().isEmpty ? name : card.title.text.trim());
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
      await AudioService.replacePathInQueue(card.path, result.path);
      try {
        if (File(card.path).existsSync()) File(card.path).deleteSync();
      } catch (_) {}
      if (!mounted) return;
      if (!silent) TapFeedback.machineConfirm();
      setState(() {
        card.busy = false;
        card.savedUri = result.uri;
        card.savedPath = result.path;
        card.status = "SAVED ✓ ${card.isVideo ? 'Movies' : 'Music'}/${result.displayName.isNotEmpty ? result.displayName : name}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        card.busy = false;
        card.status = "ERR: Save failed: $e";
      });
    }
  }

  Future<void> _saveAll() async {
    for (final c in _cards.where((c) => !c.saved && !c.busy && !c.isVideo).toList()) {
      await _saveCard(c, silent: true);
    }
    TapFeedback.machineConfirm();
    _setStatus("All Pending Tracks Saved To Music.");
  }

  void _sendCardToForge(_GrabCard card) {
    TapFeedback.machineTap();
    if (card.saved && card.savedPath != null && card.savedPath!.isNotEmpty) {
      SovereignState.sendToForge(ForgeRequest(path: card.savedPath!, origin: ForgeOrigin.library, originUri: card.savedUri));
    } else {
      final prefill = card.tags();
      SovereignState.sendToForge(ForgeRequest(path: card.path, origin: ForgeOrigin.grabber, prefill: prefill, suggestedFileName: TitleCleaner.withExtension(card.fileName.text.trim(), card.ext)));
    }
    setState(() {
      _cards.remove(card);
      card.dispose();
    });
  }

  Future<void> _playCard(_GrabCard card) async {
    TapFeedback.machineTap();
    final path = card.saved && (card.savedPath ?? '').isNotEmpty ? card.savedPath! : card.path;
    if (!File(path).existsSync()) {
      _toast('FILE NO LONGER AVAILABLE.');
      return;
    }
    AudioService.registerInfo(path, TrackInfo(title: card.title.text.trim().isEmpty ? card.fileName.text : card.title.text.trim(), artist: card.artist.text.trim(), album: card.album.text.trim(), uri: card.savedUri));
    await AudioService.playNow(File(path));
    _toast('▶ PLAYING IN THE MACHINE. TAP THE MINI-PLAYER FOR FULL SCREEN.');
  }

  Future<void> _discardCard(_GrabCard card) async {
    TapFeedback.machineTap();
    if (!card.saved) {
      await AudioService.removePathsFromQueue({card.path});
      try {
        final f = File(card.path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _cards.remove(card);
      card.dispose();
    });
  }

  Future<void> _executeHunterKiller() async {
    TapFeedback.machineTap();
    final query = "${_artistController.text.trim()} ${_titleController.text.trim()}".trim();
    if (query.isEmpty) {
      _toast('ENTER ARTIST AND/OR TITLE TO SEARCH.');
      return;
    }
    setState(() {
      _isBusy = true;
      _statusMessage = "Hunting On ${_searchSource.toUpperCase()}...";
    });
    try {
      final result = await _ytChannel.invokeMethod('searchMedia', {'query': query, 'source': _searchSource});
      final data = jsonDecode(result.toString());
      if (!mounted) return;
      if (data['status'] == 'success') {
        final results = data['results'] as List<dynamic>;
        setState(() {
          _isBusy = false;
          _statusMessage = results.isEmpty ? "No Targets Found." : "${results.length} Targets Acquired.";
        });
        if (results.isNotEmpty) _showSearchResults(results);
      } else {
        setState(() {
          _isBusy = false;
          _statusMessage = "ERR: Search Failed: ${data['message']}";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = "ERR: Hunter Kernel Fault: $e";
      });
    }
  }

  void _showSearchResults(List<dynamic> results) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) {
        final themeColor = SovereignState.accentColor.value;
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Material(
              color: Colors.black,
              shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
              child: Column(
                children: [
                  Padding(padding: const EdgeInsets.all(16.0), child: Text("SELECT TARGET", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 18, fontWeight: FontWeight.bold, color: themeColor))),
                  Divider(color: themeColor.withValues(alpha: 0.3), height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final r = results[index] as Map;
                        final duration = (r['duration'] as num?)?.toInt() ?? 0;
                        final thumb = r['thumbnail']?.toString() ?? '';
                        return ListTile(
                          leading: SizedBox(
                            width: 64,
                            height: 40,
                            child: thumb.isEmpty
                                ? Icon(Icons.track_changes, color: themeColor)
                                : Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.track_changes, color: themeColor)),
                          ),
                          title: Text(r['title']?.toString() ?? 'UNKNOWN', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13)),
                          subtitle: Text("${r['uploader']} • ${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                          trailing: IconButton(
                            icon: Icon(Icons.graphic_eq, color: themeColor),
                            tooltip: "GRAB AUDIO NOW",
                            onPressed: () {
                              Navigator.pop(context);
                              _urlController.text = r['url'].toString();
                              _startDownload(r['url'].toString(), _audioFormatFor(_exportMode), isVideo: false, label: r['title']?.toString());
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _urlController.text = r['url'].toString());
                            _fetchAvailableFormats();
                          },
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

  void _quickAudio() {
    final url = _requireUrl();
    if (url == null) return;
    _startDownload(url, _audioFormatFor(_exportMode), isVideo: false);
  }

  void _quickVideo() {
    final url = _requireUrl();
    if (url == null) return;
    _startDownload(url, "bestvideo[height<=$_quickVideoRes]+bestaudio/best[height<=$_quickVideoRes]/best", isVideo: true);
  }

  Future<void> _fetchAvailableFormats() async {
    TapFeedback.machineTap();
    final url = _requireUrl();
    if (url == null) return;
    setState(() {
      _isBusy = true;
      _statusMessage = "Analyzing Target Multiplex...";
    });
    try {
      final result = await _ytChannel.invokeMethod('getFormats', {'url': url});
      final data = jsonDecode(result.toString());
      if (!mounted) return;
      if (data['status'] == 'error') {
        setState(() {
          _isBusy = false;
          _statusMessage = "ERR: ${data['message']}";
        });
        return;
      }
      if (data['is_playlist'] == true) {
        setState(() {
          _isBusy = false;
          _statusMessage = "Playlist Detected: ${data['track_count']} Tracks.";
        });
        _showPlaylistDialog(url, data['title'].toString(), (data['track_count'] as num).toInt());
        return;
      }
      final title = data['title']?.toString() ?? 'UNKNOWN MEDIA';
      final formats = <Map<String, dynamic>>[];
      for (final f in (data['formats'] as List? ?? const [])) {
        final m = (f as Map).cast<String, dynamic>();
        if (m['resolution'] == 'unknown' || m['ext'] == 'mhtml') continue;
        formats.add(m);
      }
      setState(() {
        _isBusy = false;
        _statusMessage = "Formats Decrypted: $title";
      });
      _showFormatPicker(formats, url, title);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = "ERR: Channel Fault: ${e.message}";
      });
    }
  }

  void _showPlaylistDialog(String url, String title, int count) {
    final themeColor = SovereignState.accentColor.value;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(side: BorderSide(color: themeColor), borderRadius: BorderRadius.circular(8)),
        title: Text("DOWNLOAD PLAYLIST?", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor)),
        content: Text("TARGET: $title\nTRACKS: $count\n\nEvery track downloads as audio (${_modeLabel(_exportMode)}) and appears below as its own card. Nothing is saved to Music until you tap SAVE or SAVE ALL.", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ABORT", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(context);
              _startDownload(url, _audioFormatFor(_exportMode), isVideo: false, playlist: true, label: title);
            },
            child: const Text("HARVEST PLAYLIST", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _sizeLabel(Map<String, dynamic> f) {
    final size = f['filesize'];
    return size is num ? "${(size / 1024 / 1024).toStringAsFixed(1)} MB" : "? MB";
  }

  void _showFormatPicker(List<Map<String, dynamic>> formats, String url, String title) {
    final audioFormats = formats.where((f) => f['resolution'] == 'audio only').toList();
    final themeColor = SovereignState.accentColor.value;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Material(
          color: Colors.black,
          shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.all(16.0), child: Text("SELECT STREAM: $title", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Divider(color: themeColor.withValues(alpha: 0.3), height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: formats.length,
                  itemBuilder: (context, index) {
                    final f = formats[index];
                    final isAudioOnly = f['resolution'] == 'audio only';
                    final details = <String>[_sizeLabel(f)];
                    if (isAudioOnly && f['abr'] is num) details.add("${(f['abr'] as num).toStringAsFixed(0)} KBPS");
                    if (!isAudioOnly && f['vbr'] is num) details.add("${(f['vbr'] as num).toStringAsFixed(0)} KBPS");
                    if ((f['acodec'] ?? 'none') != 'none' && !isAudioOnly) details.add("HAS AUDIO");
                    return ListTile(
                      leading: Icon(isAudioOnly ? Icons.audiotrack : Icons.video_library, color: isAudioOnly ? themeColor : Colors.cyanAccent, size: 30),
                      title: Text(isAudioOnly ? "AUDIO ONLY (${f['ext']} • ${f['acodec'] ?? '?'})" : "VIDEO (${f['resolution']} • ${f['ext']})", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13)),
                      subtitle: Text(details.join(" • "), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                      trailing: Text(f['format_id'].toString(), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        if (isAudioOnly) {
                          _startDownload(url, f['format_id'].toString(), isVideo: false, label: title);
                        } else if ((f['acodec'] ?? 'none') == 'none' && audioFormats.isNotEmpty) {
                          _showAudioPickerForMerge(audioFormats, url, f['format_id'].toString(), title);
                        } else {
                          _startDownload(url, f['format_id'].toString(), isVideo: true, label: title);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioPickerForMerge(List<Map<String, dynamic>> audioFormats, String url, String videoFormatId, String title) {
    final themeColor = SovereignState.accentColor.value;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Material(
          color: Colors.black,
          shape: Border.all(color: themeColor.withValues(alpha: 0.5)),
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.all(16.0), child: Text("PICK AUDIO TO MERGE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor))),
              Divider(color: themeColor.withValues(alpha: 0.3), height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: audioFormats.length,
                  itemBuilder: (context, index) {
                    final f = audioFormats[index];
                    return ListTile(
                      leading: Icon(Icons.audiotrack, color: themeColor, size: 30),
                      title: Text("AUDIO (${f['ext']} • ${f['acodec'] ?? '?'})", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      subtitle: Text("${_sizeLabel(f)} • ${f['abr'] is num ? (f['abr'] as num).toStringAsFixed(0) : '?'} KBPS", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
                      trailing: Text(f['format_id'].toString(), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        _startDownload(url, "$videoFormatId+${f['format_id']}", isVideo: true, label: title);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(_ExportMode m) => switch (m) {
        _ExportMode.m4a => "M4A ORIGINAL",
        _ExportMode.mp3 => "MP3 320K",
        _ExportMode.original => "AS-IS",
      };

  void _showYtDlpHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: Colors.cyanAccent)),
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
                      const Expanded(child: Text("GRABBER FIELD MANUAL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  _h("HOW IT FLOWS"),
                  _b("1. Paste a link, SHARE one from YouTube/SoundCloud/any app into Sovereign Tagger, or hunt by artist + title.\n2. Downloads run in the background — you can start several.\n3. Each finished track becomes a card. Nothing is saved yet.\n4. Fix the title/artist/file name on the card, then choose: PLAY it, SAVE to Music, SEND to the Forge for a full tag job, or DISCARD."),
                  _h("AUDIO MODES"),
                  _b("M4A ORIGINAL (default): grabs the AAC stream the site already serves — no re-encode, no quality loss, fully taggable.\nMP3 320K: re-encodes for old car stereos. Bigger file, not better sound (sources are ~128-160 kbps).\nAS-IS: keeps whatever the site served (often .webm/.opus). Can't hold tags in this app."),
                  _h("COVER ART"),
                  _b("The video thumbnail is centre-cropped to a square and offered as cover art. Untick it on the card if you'd rather use the Forge's catalog art."),
                  _h("SITES"),
                  _b("YouTube • SoundCloud • Bandcamp • Vimeo • X • Reddit • Facebook (silent videos auto-heal) • direct media links — 1000+ sites via yt-dlp."),
                  _h("WHEN IT BREAKS"),
                  _b("- Bot-walls/403s: SETTINGS > CHECK FOR YT-DLP UPDATE.\n- Still broken: ON-BOARD PYTHON DOCTOR, then FULL STACK REFRESH.\n- DRM (Spotify/Netflix) and login-only content are not supported."),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _h(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(t, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)));

  Widget _b(String t) => Text(t, style: const TextStyle(fontFamily: 'VT323', fontSize: 15, color: Colors.white70, height: 1.35));

  Widget _field(String label, TextEditingController controller, Color themeColor, {bool isNumber = false, bool enabled = true, ValueChanged<String>? onChanged, bool dense = false}) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontSize: dense ? 13 : 15),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        isDense: dense,
        labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
        filled: true,
        fillColor: Colors.black,
      ),
      enabled: enabled,
    );
  }

  Widget _jobTile(_GrabJob job, Color themeColor) {
    final failed = job.error != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: failed ? Colors.redAccent : themeColor.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(job.isVideo ? Icons.movie_filter : (job.isPlaylist ? Icons.playlist_play : Icons.graphic_eq), color: failed ? Colors.redAccent : themeColor, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(job.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 12))),
              if (failed)
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, color: Colors.white54, size: 18), onPressed: () => _dismissJob(job))
              else
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 18), tooltip: "CANCEL", onPressed: () => _cancelJob(job)),
            ],
          ),
          if (!failed) LinearProgressIndicator(value: job.progress > 0 && job.progress <= 1 ? job.progress : null, minHeight: 3, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
          const SizedBox(height: 4),
          Text(failed ? "ERR: ${job.error}" : job.stage, style: TextStyle(fontFamily: 'VT323', fontSize: 14, color: failed ? Colors.redAccent : Colors.white60)),
        ],
      ),
    );
  }

  Widget _cardTile(_GrabCard card, Color themeColor) {
    final c = card.isVideo ? Colors.cyanAccent : themeColor;
    final locked = card.busy || card.saved;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: card.saved ? Colors.greenAccent.withValues(alpha: 0.6) : c.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: card.isVideo || card.artBase64.isEmpty || locked ? null : () => setState(() => card.useArt = !card.useArt),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(border: Border.all(color: c.withValues(alpha: 0.4))),
                  child: card.isVideo
                      ? Icon(Icons.movie, color: c, size: 36)
                      : card.artBase64.isEmpty
                          ? Icon(Icons.music_note, color: c.withValues(alpha: 0.4), size: 36)
                          : Opacity(opacity: card.useArt ? 1 : 0.25, child: Image.memory(base64Decode(card.artBase64), fit: BoxFit.cover, gaplessPlayback: true)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((card.info['title'] ?? card.fileName.text).toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 4),
                    Text("${card.ext.toUpperCase()}${card.isVideo ? ' VIDEO' : ''}${!card.isVideo && card.artBase64.isNotEmpty ? (card.useArt ? ' • THUMBNAIL AS COVER' : ' • NO COVER (TAP ART)') : ''}", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: c)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!card.isVideo) ...[
            _field('TITLE', card.title, themeColor, enabled: !locked, dense: true, onChanged: (_) => _autoCardName(card)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 3, child: _field('ARTIST', card.artist, themeColor, enabled: !locked, dense: true, onChanged: (_) => _autoCardName(card))),
              const SizedBox(width: 8),
              Expanded(child: _field('TRACK', card.track, themeColor, isNumber: true, enabled: !locked, dense: true, onChanged: (_) => _autoCardName(card))),
            ]),
            const SizedBox(height: 8),
            _field('ALBUM', card.album, themeColor, enabled: !locked, dense: true),
            const SizedBox(height: 8),
          ],
          _field('FILE NAME', card.fileName, themeColor, enabled: !locked, dense: true, onChanged: (_) => card.fileNameTouched = true),
          if (card.status.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(card.status, style: TextStyle(fontFamily: 'VT323', fontSize: 14, color: card.status.startsWith('ERR') ? Colors.redAccent : (card.saved ? Colors.greenAccent : Colors.amberAccent))),
          ],
          const SizedBox(height: 8),
          if (card.busy) LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(c)),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _cardButton(Icons.play_arrow, "PLAY", Colors.greenAccent, card.busy ? null : () => _playCard(card)),
              if (!card.saved) _cardButton(Icons.save_alt, card.isVideo ? "SAVE TO MOVIES" : "SAVE TO MUSIC", c, card.busy ? null : () => _saveCard(card)),
              if (!card.isVideo) _cardButton(Icons.edit_note, card.saved ? "EDIT IN FORGE" : "SEND TO FORGE", Colors.purpleAccent, card.busy ? null : () => _sendCardToForge(card)),
              _cardButton(card.saved ? Icons.check : Icons.delete_outline, card.saved ? "DONE" : "DISCARD", card.saved ? Colors.white54 : Colors.redAccent, card.busy ? null : () => _discardCard(card)),
            ],
          ),
        ],
      ),
    );
  }

  void _autoCardName(_GrabCard card) {
    if (card.fileNameTouched) return;
    card.fileName.text = TitleCleaner.buildFileName(artist: card.artist.text.trim(), title: card.title.text.trim(), trackNo: card.track.text.trim(), ext: card.ext);
  }

  Widget _cardButton(IconData icon, String label, Color color, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: color.withValues(alpha: 0.5)), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), visualDensity: VisualDensity.compact),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        final isErr = _statusMessage.startsWith("ERR");
        final pendingAudio = _cards.where((c) => !c.saved && !c.isVideo).length;
        return Container(
          color: Colors.black,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text("THE GRABBER", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2))),
                    IconButton(icon: Icon(Icons.help_outline, color: themeColor), tooltip: "FIELD MANUAL", onPressed: _showYtDlpHelp),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isBusy) LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black, border: Border.all(color: isErr ? Colors.redAccent : themeColor)),
                  child: Text("> $_statusMessage", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'VT323', fontSize: 14, color: isErr ? Colors.redAccent : themeColor, height: 1.2)),
                ),
                const SizedBox(height: 14),
                _field('LINK (PASTE OR SHARE INTO APP)', _urlController, themeColor),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_ExportMode>(
                          value: _exportMode,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: [
                            for (final m in _ExportMode.values)
                              DropdownMenuItem(value: m, child: Text(_modeLabel(m), style: TextStyle(fontFamily: 'ShareTechMono', color: m == _ExportMode.m4a ? Colors.white : Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _exportMode = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CyberTapFeedback(
                        enableHaptic: false,
                        enableAudio: false,
                        particleColor: themeColor,
                        ringColor: themeColor,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _quickAudio,
                          icon: Icon(Icons.graphic_eq, color: themeColor),
                          label: const Text("MAX AUDIO", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: themeColor.withValues(alpha: 0.6)), backgroundColor: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                          onChanged: (v) {
                            if (v != null) setState(() => _quickVideoRes = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _quickVideo,
                        icon: const Icon(Icons.movie_filter, color: Colors.cyanAccent),
                        label: const Text("QUICK VIDEO", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5)), backgroundColor: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _isBusy ? null : _fetchAvailableFormats,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Colors.white24), backgroundColor: Colors.black),
                  child: Text(_isBusy ? 'WORKING...' : 'ADVANCED: FETCH ALL FORMATS / PLAYLIST', style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.white70)),
                ),
                if (_jobs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text("> ACTIVE DOWNLOADS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, fontWeight: FontWeight.bold, color: themeColor)),
                  const SizedBox(height: 8),
                  for (final job in _jobs.values.toList().reversed) _jobTile(job, themeColor),
                ],
                if (_cards.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Text("> READY (${_cards.length})", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, fontWeight: FontWeight.bold, color: themeColor))),
                      if (pendingAudio >= 2)
                        TextButton.icon(onPressed: _saveAll, icon: Icon(Icons.done_all, size: 16, color: themeColor), label: Text("SAVE ALL ($pendingAudio)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final card in _cards) _cardTile(card, themeColor),
                ],
                const SizedBox(height: 18),
                const Divider(color: Colors.white24),
                const SizedBox(height: 12),
                const Text("> MEDIA HUNTER", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 10),
                _field('ARTIST', _artistController, themeColor),
                const SizedBox(height: 10),
                _field('SONG TITLE', _titleController, themeColor),
                const SizedBox(height: 10),
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
                            ],
                            onChanged: _isBusy ? null : (v) {
                              if (v != null) setState(() => _searchSource = v);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _executeHunterKiller,
                        icon: Icon(Icons.radar, color: themeColor),
                        label: Text("HUNT", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: themeColor), backgroundColor: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
