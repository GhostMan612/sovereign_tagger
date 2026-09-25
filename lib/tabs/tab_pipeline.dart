// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/tap_feedback.dart';
import '../core/ffmpeg_executor.dart';
import '../core/cyber_tap_feedback.dart';
import '../core/forge_request.dart';
import '../core/metadata_sources.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../core/title_cleaner.dart';
import '../screens/main_shell.dart';
import 'tab_library.dart';

class BatchItem {
  String path;
  String? uri;
  String filename;
  Map<String, String> tags;
  String bucket;
  String log;
  bool isProcessing;

  BatchItem({required this.path, required this.filename, required this.tags, required this.bucket, this.uri, this.log = "Waiting In Queue...", this.isProcessing = false});
}

class TabPipeline extends StatefulWidget {
  const TabPipeline({super.key});

  @override
  State<TabPipeline> createState() => _TabPipelineState();
}

class _TabPipelineState extends State<TabPipeline> {
  static const double _autoApplyThreshold = 0.8;

  final List<BatchItem> _queue = [];
  bool _isBatchRunning = false;
  bool _cancelRequested = false;
  bool _renameFiles = false;
  bool _includePristine = false;
  int _currentIndex = 0;
  String _globalStatus = "Load Tracks From The Library Or Files, Then EXECUTE BATCH.\nConfident Matches Are Fixed In Place; Unsure Ones Go To REVIEW.";

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _globalStatus = s);
  }

  String _classify(Map<String, String> tags) {
    final title = (tags["TITLE"] ?? "").trim();
    final artist = (tags["ARTIST"] ?? "").trim();
    final lower = title.toLowerCase();
    if (title.isEmpty || artist.isEmpty || RegExp(r'^track\s*\d+$').hasMatch(lower) || lower.contains("unknown") || artist.toLowerCase().contains("unknown")) return "GHOST";
    if ((tags["ALBUM"] ?? "").trim().isEmpty || (tags["ARTWORK_BASE64"] ?? "").isEmpty || (tags["YEAR"] ?? "").trim().isEmpty) return "PARTIAL";
    return "PRISTINE";
  }

  Future<void> _addItems(List<({String path, String? uri, String name})> entries) async {
    setState(() => _globalStatus = "Reading Tags On ${entries.length} Files...");
    var added = 0;
    for (final e in entries) {
      if (!mounted) return;
      if (_queue.any((q) => q.path == e.path)) continue;
      final tags = await TagIO.read(e.path);
      final bucket = tags.isEmpty ? "GHOST" : _classify(tags);
      _queue.add(BatchItem(
        path: e.path,
        uri: e.uri,
        filename: e.name,
        tags: tags,
        bucket: bucket,
        log: !TagIO.canWrite(e.path) ? "Format Can't Hold Tags — Will Be Skipped." : (bucket == "PRISTINE" ? "Fully Tagged. Skipped Unless INCLUDE PRISTINE Is On." : "Ready."),
      ));
      added++;
      if (added % 10 == 0) setState(() {});
    }
    if (!mounted) return;
    setState(() => _globalStatus = "Queue: ${_queue.length} Tracks (${_count('GHOST')} GHOST • ${_count('PARTIAL')} PARTIAL • ${_count('PRISTINE')} PRISTINE).");
  }

  int _count(String bucket) => _queue.where((i) => i.bucket == bucket).length;

  Future<void> _pickFiles() async {
    TapFeedback.machineTap();
    if (_isBatchRunning) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    } on PlatformException catch (e) {
      _setStatus("ERR: File Picker Fault: ${e.message}");
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final entries = <({String path, String? uri, String name})>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final uri = f.identifier == null ? null : await StorageClient.resolveMediaUri(identifier: f.identifier);
      entries.add((path: f.path!, uri: uri, name: f.name));
    }
    await _addItems(entries);
    final unresolved = _queue.where((i) => i.uri == null).length;
    if (unresolved > 0) _setStatus("$_globalStatus\nNOTE: $unresolved Picked File(s) Have No Library Link — Fixed Copies Will Be Added To Music Instead.");
  }

  Future<void> _pickFromLibrary() async {
    TapFeedback.machineTap();
    if (_isBatchRunning) return;
    List<LibTrack> tracks;
    try {
      tracks = (await StorageClient.queryAudio()).map(LibTrack.fromMap).where((t) => t.path.isNotEmpty).toList();
    } catch (e) {
      _setStatus("ERR: Library Read Fault: $e (Open The LIBRARY Tab Once To Grant Permission)");
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<List<LibTrack>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LibraryPickerSheet(tracks: tracks, themeColor: SovereignState.accentColor.value),
    );
    if (picked == null || picked.isEmpty) return;
    await _addItems([for (final t in picked) (path: t.path, uri: t.uri, name: t.displayName.isEmpty ? t.path.split('/').last : t.displayName)]);
  }

  void _updateItem(BatchItem item, String log, {bool? isProcessing, String? newBucket}) {
    if (!mounted) return;
    setState(() {
      item.log = log;
      if (isProcessing != null) item.isProcessing = isProcessing;
      if (newBucket != null) item.bucket = newBucket;
    });
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final c = SovereignState.accentColor.value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(side: BorderSide(color: c), borderRadius: BorderRadius.circular(6)),
        title: Text(title, style: TextStyle(fontFamily: 'ShareTechMono', color: c, fontWeight: FontWeight.bold)),
        content: Text(body, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.black), onPressed: () => Navigator.pop(d, true), child: Text(yes, style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _executeBatch() async {
    TapFeedback.machineTap();
    if (_queue.isEmpty || _isBatchRunning) return;
    final targets = _queue.where((i) => TagIO.canWrite(i.path) && (i.bucket == "GHOST" || i.bucket == "PARTIAL" || i.bucket == "REVIEW" || (_includePristine && i.bucket == "PRISTINE"))).toList();
    if (targets.isEmpty) {
      _setStatus("Nothing To Do. All Tracks Are PRISTINE, PROCESSED Or Untaggable.");
      return;
    }

    final useAcr = await MetadataSources.acrConfigured();
    final uris = targets.map((i) => i.uri).whereType<String>().toList();
    var fixInPlace = true;
    if (uris.isNotEmpty) {
      _setStatus("Requesting Permission To Modify ${uris.length} File(s)...");
      final granted = await StorageClient.requestWriteAccess(uris);
      if (!mounted) return;
      if (!granted) {
        final copies = await _confirm("PERMISSION DENIED", "Android did not allow modifying the originals.\n\nContinue and add fixed COPIES to Music instead?", "USE COPIES");
        if (!copies) {
          _setStatus("Batch Cancelled. Nothing Was Changed.");
          return;
        }
        fixInPlace = false;
      }
    }

    setState(() {
      _isBatchRunning = true;
      _cancelRequested = false;
      _globalStatus = "Batch Running On ${targets.length} Tracks${useAcr ? '' : ' (ACRCloud keys not set — GHOST tracks are matched from their file names)'}...";
    });

    var fixed = 0, review = 0, failed = 0;
    for (var n = 0; n < targets.length; n++) {
      if (!mounted || _cancelRequested) break;
      final item = targets[n];
      setState(() => _currentIndex = n);
      String? working;
      try {
        _updateItem(item, "Staging Working Copy...", isProcessing: true);
        working = await StorageClient.copyToStaging(item.path, prefix: 'batch');
        final durationMs = int.tryParse(item.tags['DURATION_MS'] ?? '') ?? 0;

        var artist = (item.tags['ARTIST'] ?? '').trim();
        var title = (item.tags['TITLE'] ?? '').trim();
        if (item.bucket == "GHOST") {
          MetaCandidate? hit;
          if (useAcr) {
            _updateItem(item, "Fingerprinting (ACRCloud)...");
            try {
              hit = await MetadataSources.acrIdentify(working);
            } catch (_) {}
          }
          if (hit != null) {
            artist = hit.artist;
            title = hit.title;
          } else {
            final base = item.filename.contains('.') ? item.filename.substring(0, item.filename.lastIndexOf('.')) : item.filename;
            final guess = TitleCleaner.splitArtistTitle(artist, title.isNotEmpty ? title : base);
            artist = guess.artist;
            title = guess.title;
          }
        }
        if (title.isEmpty) throw Exception("No title to search with");

        _updateItem(item, "Searching Catalogs For \"$artist - $title\"...");
        final res = await MetadataSources.search(artist: artist, title: title, album: item.tags['ALBUM'] ?? '', durationMs: durationMs);
        final best = res.best;
        if (best == null || res.confidence < _autoApplyThreshold) {
          review++;
          _updateItem(item, best == null ? "No Catalog Match. Tap To Fix In The Forge." : "Unsure (${(res.confidence * 100).round()}%): ${best.artist} - ${best.title}. Tap To Review In Forge.", isProcessing: false, newBucket: "REVIEW");
          continue;
        }

        final merged = Map<String, String>.from(item.tags)..remove('DURATION_MS');
        best.toTags().forEach((k, v) {
          if (v.trim().isNotEmpty) merged[k] = v.trim();
        });
        final currentLyrics = (item.tags['LYRICS'] ?? '').trim();
        if (currentLyrics.isEmpty) {
          final lyr = res.lyricsSynced.isNotEmpty ? res.lyricsSynced : res.lyricsPlain;
          if (lyr.isNotEmpty) merged['LYRICS'] = lyr;
        }
        if ((item.tags['ARTWORK_BASE64'] ?? '').isEmpty && best.artworkUrl.isNotEmpty) {
          _updateItem(item, "Fetching Artwork...");
          final art = await MetadataSources.fetchArtworkBase64(best.artworkUrl);
          if (art != null) merged['ARTWORK_BASE64'] = art;
        }

        _updateItem(item, "Writing Tags...");
        if (!await TagIO.write(working, merged)) throw Exception("Tag write failed");
        final mismatch = TagIO.verify(merged, await TagIO.read(working));
        if (mismatch.isNotEmpty) throw Exception("Read-back mismatch on ${mismatch.join('/')}");

        final ext = TitleCleaner.extensionOf(item.path);
        final newName = _renameFiles ? TitleCleaner.buildFileName(artist: merged['ARTIST'] ?? '', title: merged['TITLE'] ?? '', trackNo: merged['TRACK'] ?? '', ext: ext) : null;
        SaveResult result;
        if (fixInPlace && item.uri != null) {
          _updateItem(item, "Fixing Original In Place...");
          result = await StorageClient.overwriteOriginal(uri: item.uri!, workingPath: working, displayName: newName);
        } else {
          _updateItem(item, "Adding Fixed Copy To Music...");
          final temp = await StorageClient.tempDir();
          final dir = Directory('$temp/export_${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
          final staged = '${dir.path}/${newName ?? item.filename}';
          await File(working).copy(staged);
          try {
            result = await StorageClient.exportToLibrary(staged, merged['TITLE'] ?? item.filename);
          } finally {
            try {
              dir.deleteSync(recursive: true);
            } catch (_) {}
          }
        }
        if (result.path.isNotEmpty && result.path != item.path) {
          await AudioService.replacePathInQueue(item.path, result.path);
          item.path = result.path;
        }
        if (result.uri.isNotEmpty) item.uri = result.uri;
        if (result.displayName.isNotEmpty) item.filename = result.displayName;
        item.tags = merged;
        fixed++;
        _updateItem(item, "${result.overwroteOriginal ? 'Fixed In Place' : 'Copy Saved'}: ${merged['ARTIST']} - ${merged['TITLE']} (${(res.confidence * 100).round()}%)", isProcessing: false, newBucket: "PROCESSED");
      } catch (e) {
        failed++;
        _updateItem(item, "ERR: $e", isProcessing: false, newBucket: "FAILED");
      } finally {
        if (working != null) {
          try {
            File(working).deleteSync();
          } catch (_) {}
        }
      }
    }

    await AudioService.refreshNowPlaying();
    StorageClient.bumpLibrary();
    if (!mounted) return;
    TapFeedback.machineConfirm();
    setState(() {
      _isBatchRunning = false;
      _globalStatus = "${_cancelRequested ? 'Batch Cancelled' : 'Batch Complete'}: $fixed Fixed • $review Need Review • $failed Failed.";
    });
  }

  void _openInForge(BatchItem item) {
    if (_isBatchRunning) return;
    SovereignState.sendToForge(ForgeRequest(path: item.path, origin: ForgeOrigin.library, originUri: item.uri));
  }

  void _itemMenu(BatchItem item, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.97),
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: themeColor.withValues(alpha: 0.5))),
      builder: (sheet) {
        Widget tile(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? themeColor),
              title: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', color: color ?? Colors.white, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(sheet);
                onTap();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(Icons.edit_note, "OPEN IN FORGE", () => _openInForge(item), color: Colors.purpleAccent),
              tile(Icons.hearing, "RE-IDENTIFY FROM SCRATCH (GHOST)", () => setState(() {
                    item.bucket = "GHOST";
                    item.log = "Will Be Re-Identified Ignoring Current Title/Artist.";
                  })),
              tile(Icons.cleaning_services, "RETAG KEEPING TITLE + ARTIST", () => setState(() {
                    item.bucket = "PARTIAL";
                    item.log = "Will Be Retagged Using Its Current Title/Artist.";
                  }), color: Colors.amberAccent),
              tile(Icons.remove_circle_outline, "REMOVE FROM BATCH", () => setState(() => _queue.remove(item)), color: Colors.redAccent),
            ],
          ),
        );
      },
    );
  }

  void _clearQueue() {
    if (_isBatchRunning) return;
    setState(() {
      _queue.clear();
      _globalStatus = "Queue Cleared.";
      _currentIndex = 0;
    });
  }

  Future<void> _mixtapeJoin() async {
    TapFeedback.machineTap();
    if (_isBatchRunning) return;
    final mp3Items = _queue.where((item) => item.bucket == "PROCESSED" && item.path.toLowerCase().endsWith('.mp3') && File(item.path).existsSync()).toList();
    if (mp3Items.length < 2) {
      _setStatus("ERR: Mixtape Join Needs 2+ PROCESSED MP3 Tracks.");
      return;
    }
    _setStatus("Mixtape Join: Assembling ${mp3Items.length} Tracks Losslessly...");
    try {
      final tempDir = await StorageClient.tempDir();
      final listFile = File("$tempDir/mixtape_${DateTime.now().millisecondsSinceEpoch}.txt");
      final buffer = StringBuffer();
      for (final item in mp3Items) {
        buffer.writeln("file '${item.path.replaceAll("'", r"'\''")}'");
      }
      await listFile.writeAsString(buffer.toString());
      final outPath = "$tempDir/Sovereign Mixtape ${DateTime.now().month}-${DateTime.now().day}.mp3";
      final session = await FFmpegExecutor.execute('-y -f concat -safe 0 -i "${listFile.path}" -map 0:a -c copy -write_xing 1 "$outPath"');
      try {
        listFile.deleteSync();
      } catch (_) {}
      if (!ReturnCode.isSuccess(session.getReturnCode())) {
        _setStatus("ERR: Mixtape Concat Fault. Tracks Must Share Sample Rate And Channels.");
        return;
      }
      final result = await StorageClient.exportToLibrary(outPath, 'Sovereign Mixtape ${DateTime.now().month}/${DateTime.now().day}');
      try {
        File(outPath).deleteSync();
      } catch (_) {}
      _setStatus("Mixtape Saved: ${result.displayName} (${mp3Items.length} Tracks).");
    } catch (e) {
      _setStatus("ERR: Mixtape Fault: $e");
    }
  }

  Color _getBucketColor(String bucket, Color themeColor) {
    switch (bucket) {
      case "GHOST":
        return Colors.redAccent;
      case "PARTIAL":
        return Colors.amberAccent;
      case "PRISTINE":
        return themeColor;
      case "PROCESSED":
        return Colors.cyanAccent;
      case "REVIEW":
        return Colors.purpleAccent;
      case "FAILED":
        return Colors.deepOrange;
      default:
        return Colors.white54;
    }
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged, Color themeColor) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: value ? Colors.black : Colors.white70)),
      selected: value,
      selectedColor: themeColor,
      backgroundColor: Colors.black,
      side: BorderSide(color: value ? themeColor : Colors.white24),
      showCheckmark: false,
      onSelected: _isBatchRunning ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        final isErr = _globalStatus.startsWith("ERR");
        return Container(
          color: Colors.black,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("BATCH TAGGER", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBatchRunning ? null : _pickFromLibrary,
                            icon: Icon(Icons.library_music, color: themeColor, size: 18),
                            label: Text("FROM LIBRARY", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: themeColor), backgroundColor: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBatchRunning ? null : _pickFiles,
                            icon: Icon(Icons.folder_copy, color: themeColor, size: 18),
                            label: Text("FILES", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: themeColor.withValues(alpha: 0.6)), backgroundColor: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(4)),
                          child: IconButton(onPressed: _isBatchRunning ? null : _mixtapeJoin, icon: const Icon(Icons.merge, color: Colors.cyanAccent), tooltip: "MIXTAPE JOIN (PROCESSED MP3s)"),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)),
                          child: IconButton(onPressed: _isBatchRunning ? null : _clearQueue, icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), tooltip: "CLEAR QUEUE"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _toggle("RENAME FILES TO ARTIST - TITLE", _renameFiles, (v) => setState(() => _renameFiles = v), themeColor),
                        _toggle("INCLUDE PRISTINE", _includePristine, (v) => setState(() => _includePristine = v), themeColor),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CyberTapFeedback(
                            child: ElevatedButton.icon(
                              onPressed: (_queue.isEmpty || _isBatchRunning) ? null : _executeBatch,
                              icon: const Icon(Icons.rocket_launch, color: Colors.black),
                              label: const Text("EXECUTE BATCH", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: themeColor, disabledBackgroundColor: themeColor.withValues(alpha: 0.2)),
                            ),
                          ),
                        ),
                        if (_isBatchRunning) ...[
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _cancelRequested ? null : () => setState(() {
                              _cancelRequested = true;
                              _globalStatus = "Cancelling After The Current Track...";
                            }),
                            icon: const Icon(Icons.cancel, color: Colors.redAccent),
                            label: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16), side: const BorderSide(color: Colors.redAccent), backgroundColor: Colors.black),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: isErr ? Colors.redAccent : themeColor)),
                      child: Text("> $_globalStatus", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'VT323', fontSize: 15, color: isErr ? Colors.redAccent : themeColor, height: 1.2)),
                    ),
                    if (_isBatchRunning) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _queue.isEmpty ? 0 : (_currentIndex + 1) / _queue.length, minHeight: 4, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
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
                    final c = _getBucketColor(item.bucket, themeColor);
                    return Card(
                      color: Colors.black,
                      margin: const EdgeInsets.only(bottom: 10.0),
                      shape: RoundedRectangleBorder(side: BorderSide(color: c.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(4)),
                      child: ListTile(
                        onTap: item.bucket == "REVIEW" || item.bucket == "FAILED" ? () => _openInForge(item) : null,
                        onLongPress: _isBatchRunning ? null : () => _itemMenu(item, themeColor),
                        leading: item.isProcessing ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor)) : Icon(item.uri == null ? Icons.music_note_outlined : Icons.music_note, color: c),
                        title: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                        subtitle: Text("> ${item.log}", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'ShareTechMono', color: c, fontSize: 11)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), border: Border.all(color: c), borderRadius: BorderRadius.circular(4)),
                          child: Text(item.bucket, style: TextStyle(fontFamily: 'ShareTechMono', color: c, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
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
}

class _LibraryPickerSheet extends StatefulWidget {
  final List<LibTrack> tracks;
  final Color themeColor;
  const _LibraryPickerSheet({required this.tracks, required this.themeColor});

  @override
  State<_LibraryPickerSheet> createState() => _LibraryPickerSheetState();
}

class _LibraryPickerSheetState extends State<_LibraryPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibTrack> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = widget.tracks.where((t) => q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q) || t.folder.toLowerCase().contains(q)).toList();
    list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()) != 0 ? a.artist.toLowerCase().compareTo(b.artist.toLowerCase()) : a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.themeColor;
    final visible = _visible;
    final allVisibleSelected = visible.isNotEmpty && visible.every((t) => _selected.contains(t.path));
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: c.withValues(alpha: 0.6))), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text("PICK TRACKS (${_selected.length})", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, fontSize: 16, color: c))),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allVisibleSelected) {
                        _selected.removeAll(visible.map((t) => t.path));
                      } else {
                        _selected.addAll(visible.map((t) => t.path));
                      }
                    }),
                    child: Text(allVisibleSelected ? "NONE" : "ALL SHOWN", style: TextStyle(fontFamily: 'ShareTechMono', color: c)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                style: TextStyle(fontFamily: 'ShareTechMono', color: c),
                decoration: InputDecoration(
                  hintText: "FILTER BY TITLE, ARTIST, ALBUM OR FOLDER",
                  hintStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 12),
                  prefixIcon: Icon(Icons.search, color: c),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: c.withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: c)),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final t = visible[i];
                  final on = _selected.contains(t.path);
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    activeColor: c,
                    onChanged: (v) => setState(() => v == true ? _selected.add(t.path) : _selected.remove(t.path)),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13)),
                    subtitle: Text("${t.artist} • ${t.album}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, widget.tracks.where((t) => _selected.contains(t.path)).toList()),
                    style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text("ADD ${_selected.length} TO BATCH", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
