// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/tap_feedback.dart';
import '../core/cyber_tap_feedback.dart';
import '../core/forge_request.dart';
import '../core/lrc.dart';
import '../core/metadata_sources.dart';
import '../core/storage_client.dart';
import '../core/tag_io.dart';
import '../core/title_cleaner.dart';
import '../screens/main_shell.dart';
import '../screens/lyric_sync_screen.dart';
import '../widgets/metadata_review_sheet.dart';
import 'tab_player.dart';

class TabForge extends StatefulWidget {
  const TabForge({super.key});

  @override
  State<TabForge> createState() => _TabForgeState();
}

class _TabForgeState extends State<TabForge> {
  static const List<(String, String)> _fieldSpec = [
    ('TITLE', 'TITLE'),
    ('ARTIST', 'ARTIST'),
    ('ALBUM', 'ALBUM'),
    ('ALBUM_ARTIST', 'ALBUM ARTIST'),
    ('YEAR', 'YEAR'),
    ('GENRE', 'GENRE'),
    ('TRACK', 'TRACK NO.'),
    ('TRACK_TOTAL', 'OF'),
    ('DISC_NO', 'DISC NO.'),
    ('DISC_TOTAL', 'OF'),
    ('COMPOSER', 'COMPOSER'),
    ('PRODUCER', 'PRODUCER'),
    ('LYRICS', 'LYRICS'),
    ('COMMENT', 'COMMENT'),
    ('LANGUAGE', 'LANGUAGE'),
    ('ENCODER', 'ENCODER'),
  ];

  final Map<String, TextEditingController> _ctrl = {for (final (k, _) in _fieldSpec) k: TextEditingController()};
  final TextEditingController _fileNameCtrl = TextEditingController();

  String _workingPath = "";
  bool _ownsWorkingCopy = false;
  String? _originUri;
  String _originalPath = "";
  String _originalDisplayName = "";
  ForgeOrigin? _origin;
  int _durationMs = 0;
  Map<String, String> _loadedTags = {};

  String _statusMessage = "System Idle. Mount Any Audio File, Or Send One Here From Grabber, Library Or Player.";
  bool _isProcessing = false;
  bool _dirty = false;
  bool _suppressDirty = false;
  bool _fileNameTouched = false;
  String _coverArtBase64 = "";
  Uint8List? _coverBytes;

  @override
  void initState() {
    super.initState();
    for (final c in _ctrl.values) {
      c.addListener(_markDirty);
    }
    SovereignState.pendingForge.addListener(_onPendingRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingRequest());
  }

  @override
  void dispose() {
    SovereignState.pendingForge.removeListener(_onPendingRequest);
    for (final c in _ctrl.values) {
      c.dispose();
    }
    _fileNameCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_suppressDirty || _workingPath.isEmpty || _dirty) return;
    setState(() => _dirty = true);
  }

  String _v(String key) => _ctrl[key]!.text.trim();

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
  }

  void _onPendingRequest() {
    final req = SovereignState.pendingForge.value;
    if (req == null) return;
    SovereignState.pendingForge.value = null;
    _mount(req);
  }

  Future<bool> _confirm(String title, String body, String yes, {Color? yesColor}) async {
    final themeColor = SovereignState.accentColor.value;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: themeColor)),
        title: Text(title, style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
        content: Text(body, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: yesColor ?? themeColor, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(d, true),
            child: Text(yes, style: const TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _discardWorkingCopy() async {
    if (_workingPath.isNotEmpty && _ownsWorkingCopy) {
      try {
        final f = File(_workingPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _mount(ForgeRequest req) async {
    if (_isProcessing) return;
    if (_dirty && _workingPath.isNotEmpty) {
      final discard = await _confirm("UNSAVED CHANGES", "The mounted file has edits that were not saved.\n\nDiscard them and mount the new file?", "DISCARD");
      if (!discard) return;
    }
    if (!File(req.path).existsSync()) {
      _setStatus("ERR: File Not Found: ${req.path.split('/').last}");
      return;
    }
    setState(() {
      _isProcessing = true;
      _statusMessage = "Mounting ${req.path.split('/').last}...";
    });
    try {
      await _discardWorkingCopy();
      final staging = await StorageClient.isAppStaging(req.path);
      String working;
      bool owns;
      if (staging) {
        working = req.path;
        owns = req.origin == ForgeOrigin.grabber || req.origin == ForgeOrigin.picked;
      } else {
        working = await StorageClient.copyToStaging(req.path);
        owns = true;
      }
      String? originUri = req.originUri;
      if (originUri == null && req.origin != ForgeOrigin.grabber && !staging) {
        originUri = await StorageClient.resolveMediaUri(path: req.path);
      }
      final tags = await TagIO.read(working);
      if (!mounted) return;
      _suppressDirty = true;
      setState(() {
        _workingPath = working;
        _ownsWorkingCopy = owns;
        _originUri = originUri;
        _origin = req.origin;
        _originalPath = staging ? "" : req.path;
        _originalDisplayName = req.path.split('/').last;
        _durationMs = int.tryParse(tags['DURATION_MS'] ?? '') ?? 0;
        _loadedTags = tags;
        for (final (k, _) in _fieldSpec) {
          _ctrl[k]!.text = tags[k] ?? "";
        }
        _setCover(tags['ARTWORK_BASE64'] ?? "");
        for (final e in req.prefill.entries) {
          if (e.key == 'ARTWORK_BASE64') {
            _setCover(e.value);
          } else if (_ctrl.containsKey(e.key)) {
            _ctrl[e.key]!.text = e.value;
          }
        }
        _fileNameCtrl.text = req.suggestedFileName ?? _originalDisplayName;
        _fileNameTouched = req.suggestedFileName != null;
        _dirty = req.prefill.isNotEmpty;
        _isProcessing = false;
        _statusMessage = "Mounted: $_originalDisplayName\n${_originLabel()} • ${TitleCleaner.extensionOf(working).toUpperCase()}${TagIO.canWrite(working) ? '' : ' • TAGS NOT SUPPORTED FOR THIS FORMAT'}";
      });
      _suppressDirty = false;
    } catch (e) {
      _suppressDirty = false;
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Mount Fault: $e";
      });
    }
  }

  String _originLabel() {
    switch (_origin) {
      case ForgeOrigin.library:
      case ForgeOrigin.player:
        return _originUri != null ? "LIBRARY ORIGINAL (SAVE FIXES IT IN PLACE)" : "DEVICE FILE (SAVE ADDS A COPY TO MUSIC)";
      case ForgeOrigin.picked:
        return _originUri != null ? "PICKED ORIGINAL (SAVE FIXES IT IN PLACE)" : "PICKED FILE (SAVE ADDS A COPY TO MUSIC)";
      case ForgeOrigin.grabber:
        return "GRABBER DOWNLOAD (SAVE ADDS IT TO MUSIC)";
      case null:
        return "";
    }
  }

  void _setCover(String b64) {
    _coverArtBase64 = b64;
    try {
      _coverBytes = b64.isEmpty ? null : base64Decode(b64);
    } catch (_) {
      _coverArtBase64 = "";
      _coverBytes = null;
    }
  }

  Future<void> _pickFile() async {
    TapFeedback.machineTap();
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
    } on PlatformException catch (e) {
      _setStatus("ERR: File Picker Fault: ${e.message}");
      return;
    }
    if (result == null || result.files.single.path == null) return;
    final file = result.files.single;
    String? originUri;
    if (file.identifier != null) {
      originUri = await StorageClient.resolveMediaUri(identifier: file.identifier);
    }
    await _mount(ForgeRequest(path: file.path!, origin: ForgeOrigin.picked, originUri: originUri));
    if (mounted && originUri == null && _workingPath.isNotEmpty) {
      _setStatus("$_statusMessage\nNOTE: Original location unknown to Android — SAVE will add a fixed copy to Music. Use LIBRARY > EDIT IN FORGE to fix in place.");
    }
  }

  Future<void> _eject() async {
    TapFeedback.machineTap();
    if (_dirty) {
      final ok = await _confirm("EJECT WITHOUT SAVING?", "Unsaved edits will be lost. The original file is never touched by EJECT.", "EJECT");
      if (!ok) return;
    }
    await _discardWorkingCopy();
    if (!mounted) return;
    _suppressDirty = true;
    setState(() {
      _workingPath = "";
      _ownsWorkingCopy = false;
      _originUri = null;
      _originalPath = "";
      _originalDisplayName = "";
      _origin = null;
      _loadedTags = {};
      for (final c in _ctrl.values) {
        c.clear();
      }
      _fileNameCtrl.clear();
      _setCover("");
      _dirty = false;
      _statusMessage = "Media Ejected. Working Copy Purged. Original Untouched.";
    });
    _suppressDirty = false;
  }

  void _resetForm() {
    _suppressDirty = true;
    setState(() {
      for (final (k, _) in _fieldSpec) {
        _ctrl[k]!.text = _loadedTags[k] ?? "";
      }
      _setCover(_loadedTags['ARTWORK_BASE64'] ?? "");
      _dirty = false;
      _statusMessage = "Form Reset To The Tags Currently In The File.";
    });
    _suppressDirty = false;
  }

  Future<void> _stripToCore() async {
    final ok = await _confirm("STRIP TO CORE", "Clear every field except TITLE and ARTIST in the form?\n\nNothing is written until you press SAVE.", "STRIP");
    if (!ok || !mounted) return;
    setState(() {
      for (final (k, _) in _fieldSpec) {
        if (k != 'TITLE' && k != 'ARTIST') _ctrl[k]!.clear();
      }
      _setCover("");
      _dirty = true;
      _statusMessage = "Form Stripped To Title + Artist. Run SEARCH METADATA, Then SAVE.";
    });
  }

  Future<void> _clearForm() async {
    final ok = await _confirm("CLEAR ALL FIELDS", "Blank every field and the artwork in the form?\n\nSAVE afterwards would remove these tags from the file.", "CLEAR", yesColor: Colors.redAccent);
    if (!ok || !mounted) return;
    setState(() {
      for (final c in _ctrl.values) {
        c.clear();
      }
      _setCover("");
      _dirty = true;
      _statusMessage = "Form Cleared. Nothing Written Yet.";
    });
  }

  Future<void> _pickCoverArt() async {
    TapFeedback.machineTap();
    if (_isProcessing || _workingPath.isEmpty) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    } on PlatformException catch (e) {
      _setStatus("ERR: Image Picker Fault: ${e.message}");
      return;
    }
    if (result == null || result.files.single.path == null) return;
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      if (!mounted) return;
      setState(() {
        _coverArtBase64 = base64Encode(bytes);
        _coverBytes = bytes;
        _dirty = true;
        _statusMessage = "Artwork Loaded Into Form. SAVE To Embed It.";
      });
    } catch (e) {
      _setStatus("ERR: Cover Read Fault: $e");
    }
  }

  void _clearCoverArt() {
    setState(() {
      _setCover("");
      _dirty = true;
      _statusMessage = "Artwork Removed From Form. SAVE To Strip It From The File.";
    });
  }

  Map<String, String> _formMetadata() {
    final out = <String, String>{};
    for (final (k, _) in _fieldSpec) {
      out[k] = k == 'LYRICS' ? _ctrl[k]!.text.trim() : _v(k);
    }
    out['ARTWORK_BASE64'] = _coverArtBase64;
    return out;
  }

  void _applyToForm(Map<String, String> fields) {
    setState(() {
      for (final e in fields.entries) {
        if (e.key == 'ARTWORK_BASE64') {
          _setCover(e.value);
        } else if (_ctrl.containsKey(e.key)) {
          _ctrl[e.key]!.text = e.value;
        }
      }
      if (!_fileNameTouched && _origin == ForgeOrigin.grabber) _autoName(silent: true);
      _dirty = true;
      _statusMessage = "${fields.length} Field(s) Applied To Form. Review, Then SAVE.";
    });
  }

  void _autoName({bool silent = false}) {
    final ext = TitleCleaner.extensionOf(_workingPath);
    final name = TitleCleaner.buildFileName(artist: _v('ARTIST'), title: _v('TITLE'), trackNo: _v('TRACK'), ext: ext);
    _fileNameCtrl.text = name;
    _fileNameTouched = !silent;
    if (!silent) setState(() => _dirty = true);
  }

  Future<void> _searchMetadata() async {
    TapFeedback.machineTap();
    if (_workingPath.isEmpty) return;
    var artist = _v('ARTIST');
    var title = _v('TITLE');
    if (title.isEmpty) {
      final base = _originalDisplayName.contains('.') ? _originalDisplayName.substring(0, _originalDisplayName.lastIndexOf('.')) : _originalDisplayName;
      title = base;
    }
    setState(() {
      _isProcessing = true;
      _statusMessage = "Searching iTunes • Deezer • MusicBrainz • LRCLIB For \"${artist.isEmpty ? '' : '$artist - '}$title\"...";
    });
    try {
      final res = await MetadataSources.search(artist: artist, title: title, album: _v('ALBUM'), durationMs: _durationMs);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      await _review(res.candidates, res, res.confidence);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Search Fault: $e";
      });
    }
  }

  Future<void> _acrIdentify() async {
    TapFeedback.machineTap();
    if (_workingPath.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = "Fingerprinting 15s Of Audio Via ACRCloud...";
    });
    try {
      final hit = await MetadataSources.acrIdentify(_workingPath);
      if (!mounted) return;
      if (hit == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "No Fingerprint Match. Try SEARCH METADATA With Artist + Title.";
        });
        return;
      }
      setState(() => _statusMessage = "Fingerprint: ${hit.artist} - ${hit.title}. Enriching Via Catalog Search...");
      SpiderResult? res;
      try {
        res = await MetadataSources.search(artist: hit.artist, title: hit.title, album: hit.album, durationMs: _durationMs > 0 ? _durationMs : hit.durationMs);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final candidates = [...(res?.candidates ?? const <MetaCandidate>[]), hit];
      final confidence = res != null && res.confidence > 0 ? res.confidence : hit.score.clamp(0.0, 1.0);
      await _review(candidates, res, confidence, heading: "ACR MATCH: ${hit.artist} - ${hit.title}");
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: ACRCloud Fault: $e";
      });
    }
  }

  Future<void> _review(List<MetaCandidate> candidates, SpiderResult? res, double confidence, {String heading = 'REVIEW MATCH'}) async {
    if (candidates.isEmpty && (res == null || (res.lyricsPlain.isEmpty && res.lyricsSynced.isEmpty))) {
      _setStatus("No Match Found. Edit ARTIST / TITLE To Something Cleaner And Search Again.");
      return;
    }
    final picked = await showMetadataReview(
      context: context,
      current: _formMetadata(),
      candidates: candidates,
      themeColor: SovereignState.accentColor.value,
      lyricsPlain: res?.lyricsPlain ?? '',
      lyricsSynced: res?.lyricsSynced ?? '',
      confidence: confidence,
      heading: heading,
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      _setStatus("Review Closed. Form Unchanged.");
      return;
    }
    _applyToForm(picked);
  }

  Future<void> _findLyrics() async {
    TapFeedback.machineTap();
    if (_workingPath.isEmpty) return;
    if (_v('TITLE').isEmpty) {
      _setStatus("ERR: Lyrics Search Needs A TITLE.");
      return;
    }
    setState(() {
      _isProcessing = true;
      _statusMessage = "Searching LRCLIB For Lyrics...";
    });
    try {
      final r = await MetadataSources.fetchLyrics(artist: _v('ARTIST'), title: _v('TITLE'), album: _v('ALBUM'), durationMs: _durationMs);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (r.plain.isEmpty && r.synced.isEmpty) {
        _setStatus("No Lyrics Found On LRCLIB For This Artist/Title/Duration.");
        return;
      }
      final picked = await showMetadataReview(
        context: context,
        current: _formMetadata(),
        candidates: const [],
        themeColor: SovereignState.accentColor.value,
        lyricsPlain: r.plain,
        lyricsSynced: r.synced,
        heading: 'LYRICS FOUND',
      );
      if (!mounted || picked == null || picked.isEmpty) return;
      _applyToForm(picked);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Lyrics Fault: $e";
      });
    }
  }

  Future<void> _launchKaraokeSync() async {
    TapFeedback.machineTap();
    final raw = _ctrl['LYRICS']!.text;
    if (raw.trim().isEmpty || _workingPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MOUNT A FILE AND LOAD LYRICS FIRST.', style: TextStyle(fontFamily: 'ShareTechMono'))));
      return;
    }
    final plain = Lrc.isSynced(raw) ? Lrc.stripTimestamps(raw) : raw;
    final lrc = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LyricSyncScreen(filePath: _workingPath, title: _v('TITLE'), artist: _v('ARTIST'), rawLyrics: plain),
      ),
    );
    if (!mounted || lrc == null || lrc.isEmpty) return;
    setState(() {
      _ctrl['LYRICS']!.text = lrc;
      _dirty = true;
      _statusMessage = "Synced Lyrics Loaded Into Form. SAVE To Embed Them (Player Karaoke Reads Them).";
    });
  }

  Future<void> _playInPlayer() async {
    TapFeedback.machineTap();
    if (_workingPath.isEmpty) return;
    await AudioService.playNow(File(_workingPath));
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TheaterScreen()));
  }

  Future<String> _stageForExport(String name) async {
    final temp = await StorageClient.tempDir();
    final dir = Directory('$temp/export_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    final target = '${dir.path}/$name';
    await File(_workingPath).copy(target);
    return target;
  }

  Future<void> _save({bool asCopy = false}) async {
    TapFeedback.machineTap();
    if (_workingPath.isEmpty || _isProcessing) return;
    final ext = TitleCleaner.extensionOf(_workingPath);
    if (!TagIO.canWrite(_workingPath)) {
      _setStatus("ERR: .${ext.toUpperCase()} Files Can't Hold Tags Here.\nRe-Grab As M4A, Or Convert In WORKBENCH First.");
      return;
    }
    final meta = _formMetadata();
    final title = _v('TITLE');
    final desiredName = TitleCleaner.withExtension(
      _fileNameCtrl.text.trim().isEmpty ? TitleCleaner.buildFileName(artist: _v('ARTIST'), title: title, trackNo: _v('TRACK'), ext: ext) : _fileNameCtrl.text.trim(),
      ext,
    );

    setState(() {
      _isProcessing = true;
      _statusMessage = "Writing Tags To Working Copy...";
    });

    try {
      if (!await TagIO.write(_workingPath, meta)) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _statusMessage = "ERR: Tag Write Failed. Nothing Was Saved.";
        });
        return;
      }
      final mismatches = TagIO.verify(meta, await TagIO.read(_workingPath));
      if (!mounted) return;
      if (mismatches.isNotEmpty) {
        final go = await _confirm("READ-BACK MISMATCH", "After writing, these fields did not read back as entered: ${mismatches.join(', ')}.\n\nSave anyway?", "SAVE ANYWAY");
        if (!go || !mounted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = "Save Aborted. Read-Back Mismatch On ${mismatches.join('/')}.";
          });
          return;
        }
      }

      final previousWorking = _workingPath;
      final previousOriginal = _originalPath;
      SaveResult result;
      var fixOriginal = _originUri != null && !asCopy;
      if (fixOriginal) {
        setState(() => _statusMessage = "Requesting Permission To Modify The Original...");
        final granted = await StorageClient.requestWriteAccess([_originUri!]);
        if (!mounted) return;
        if (!granted) {
          final fallback = await _confirm("PERMISSION DENIED", "Android did not allow changing the original file.\n\nSave the fixed song as a new copy in Music instead?", "SAVE COPY");
          if (!fallback || !mounted) {
            setState(() {
              _isProcessing = false;
              _statusMessage = "Save Cancelled. Tags Are Still In The Working Copy — Nothing Lost.";
            });
            return;
          }
          fixOriginal = false;
        }
      }

      if (fixOriginal) {
        setState(() => _statusMessage = "Writing Fixed File Over The Original...");
        result = await StorageClient.overwriteOriginal(
          uri: _originUri!,
          workingPath: _workingPath,
          displayName: desiredName == _originalDisplayName ? null : desiredName,
        );
      } else {
        setState(() => _statusMessage = "Adding Fixed File To Music...");
        final exportPath = await _stageForExport(desiredName);
        try {
          result = await StorageClient.exportToLibrary(exportPath, title.isEmpty ? desiredName : title);
        } finally {
          try {
            File(exportPath).parent.deleteSync(recursive: true);
          } catch (_) {}
        }
      }

      var finalNote = "";
      if (result.path.isNotEmpty && File(result.path).existsSync()) {
        final finalBack = await TagIO.read(result.path);
        final finalMismatch = TagIO.verify(meta, finalBack);
        finalNote = finalMismatch.isEmpty ? "Round-Trip Verified On Final File." : "WARN: Final File Read-Back Differs On ${finalMismatch.join('/')}.";
      }

      if (result.path.isNotEmpty) {
        await AudioService.replacePathInQueue(previousWorking, result.path);
        if (previousOriginal.isNotEmpty && previousOriginal != result.path) {
          await AudioService.replacePathInQueue(previousOriginal, result.path);
        }
        await AudioService.refreshNowPlaying();
      }

      if (_ownsWorkingCopy) {
        try {
          File(previousWorking).deleteSync();
        } catch (_) {}
      }

      String newWorking = "";
      var owns = false;
      if (result.path.isNotEmpty && File(result.path).existsSync()) {
        try {
          newWorking = await StorageClient.copyToStaging(result.path);
          owns = true;
        } catch (_) {}
      }
      final back = newWorking.isEmpty ? <String, String>{} : await TagIO.read(newWorking);
      if (!mounted) return;
      TapFeedback.machineConfirm();
      final where = result.displayName.isNotEmpty ? result.displayName : desiredName;
      setState(() {
        _workingPath = newWorking;
        _ownsWorkingCopy = owns;
        _originUri = result.uri.isNotEmpty ? result.uri : _originUri;
        _originalPath = result.path;
        _originalDisplayName = where;
        _origin = ForgeOrigin.library;
        _loadedTags = back.isEmpty ? meta : back;
        _fileNameCtrl.text = where;
        _fileNameTouched = false;
        _dirty = false;
        _isProcessing = false;
        _statusMessage = "${fixOriginal ? 'ORIGINAL FIXED' : 'SAVED TO MUSIC'} ✓ $where\n$finalNote${newWorking.isEmpty ? '\nFile Released From Forge.' : ''}";
      });
      StorageClient.bumpLibrary();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Save Fault: $e\nTags Remain In The Working Copy — Nothing Lost.";
      });
    }
  }

  Widget _buildField(String key, String label, Color themeColor, {bool multiLine = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: _ctrl[key],
        maxLines: multiLine ? 6 : 1,
        minLines: 1,
        keyboardType: keyboard,
        style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontSize: multiLine ? 13 : 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
          filled: true,
          fillColor: Colors.black,
          isDense: true,
        ),
        enabled: !_isProcessing,
      ),
    );
  }

  Widget _toolButton({required IconData icon, required String label, required Color color, required VoidCallback? onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 18),
      label: Text(label, style: TextStyle(fontFamily: 'ShareTechMono', color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: color.withValues(alpha: 0.5)), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        final mountedFile = _workingPath.isNotEmpty;
        final isErr = _statusMessage.startsWith("ERR");
        final canFix = _originUri != null;
        return Container(
          color: Colors.black,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text("THE FORGE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2))),
                    if (_dirty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(border: Border.all(color: Colors.amberAccent), borderRadius: BorderRadius.circular(4)),
                        child: const Text("UNSAVED", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.amberAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_isProcessing) LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(themeColor)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.black, border: Border.all(color: isErr ? Colors.redAccent : themeColor)),
                  child: Text("> $_statusMessage", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'VT323', fontSize: 14, color: isErr ? Colors.redAccent : themeColor, height: 1.2)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CyberTapFeedback(
                        enableHaptic: false,
                        enableAudio: false,
                        particleColor: themeColor,
                        ringColor: themeColor,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _pickFile,
                          icon: Icon(Icons.folder_open, color: themeColor),
                          label: Text("MOUNT AUDIO FILE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: themeColor), backgroundColor: Colors.black),
                        ),
                      ),
                    ),
                    if (mountedFile) ...[
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)),
                        child: IconButton(onPressed: _isProcessing ? null : _eject, icon: const Icon(Icons.eject, color: Colors.white54), tooltip: "EJECT (ORIGINAL UNTOUCHED)"),
                      ),
                    ],
                  ],
                ),
                if (mountedFile) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fileNameCtrl,
                    enabled: !_isProcessing,
                    onChanged: (_) {
                      _fileNameTouched = true;
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: "FILE NAME ON SAVE",
                      labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: "AUTO NAME FROM TAGS",
                        icon: Icon(Icons.auto_fix_high, color: themeColor),
                        onPressed: _isProcessing ? null : () => _autoName(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _toolButton(icon: Icons.play_circle_fill, label: "PLAY IN PLAYER", color: Colors.greenAccent, onPressed: _isProcessing ? null : _playInPlayer)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _toolButton(icon: Icons.hearing, label: "IDENTIFY [ACR]", color: Colors.blueAccent, onPressed: _isProcessing ? null : _acrIdentify)),
                      const SizedBox(width: 8),
                      Expanded(child: _toolButton(icon: Icons.travel_explore, label: "SEARCH METADATA", color: Colors.purpleAccent, onPressed: _isProcessing ? null : _searchMetadata)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: _isProcessing ? null : _pickCoverArt,
                      child: Container(
                        height: 160,
                        width: 160,
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                        child: _coverBytes != null
                            ? Image.memory(_coverBytes!, fit: BoxFit.cover, gaplessPlayback: true)
                            : Icon(Icons.add_photo_alternate, size: 64, color: themeColor.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(onPressed: _isProcessing ? null : _pickCoverArt, icon: Icon(Icons.image_search, size: 16, color: themeColor), label: Text("BROWSE ART", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor))),
                      TextButton.icon(onPressed: _isProcessing || _coverBytes == null ? null : _clearCoverArt, icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), label: const Text("CLEAR ART", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildField('TITLE', 'TITLE', themeColor),
                  _buildField('ARTIST', 'ARTIST', themeColor),
                  _buildField('ALBUM', 'ALBUM', themeColor),
                  _buildField('ALBUM_ARTIST', 'ALBUM ARTIST', themeColor),
                  Row(children: [
                    Expanded(child: _buildField('YEAR', 'YEAR', themeColor, keyboard: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _buildField('GENRE', 'GENRE', themeColor)),
                  ]),
                  Row(children: [
                    Expanded(child: _buildField('TRACK', 'TRACK', themeColor, keyboard: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('TRACK_TOTAL', 'OF', themeColor, keyboard: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildField('DISC_NO', 'DISC', themeColor, keyboard: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('DISC_TOTAL', 'OF', themeColor, keyboard: TextInputType.number)),
                  ]),
                  _buildField('COMPOSER', 'COMPOSER', themeColor),
                  _buildField('PRODUCER', 'PRODUCER', themeColor),
                  Row(
                    children: [
                      Text("LYRICS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor)),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _ctrl['LYRICS']!,
                        builder: (context, value, _) {
                          if (value.text.trim().isEmpty) return const SizedBox.shrink();
                          final synced = Lrc.isSynced(value.text);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(border: Border.all(color: synced ? Colors.cyanAccent : Colors.white24), borderRadius: BorderRadius.circular(3)),
                            child: Text(synced ? "SYNCED" : "PLAIN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: synced ? Colors.cyanAccent : Colors.white54)),
                          );
                        },
                      ),
                      const Spacer(),
                      TextButton.icon(onPressed: _isProcessing ? null : _findLyrics, icon: const Icon(Icons.lyrics, size: 16, color: Colors.cyanAccent), label: const Text("FIND", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontSize: 12))),
                      TextButton.icon(onPressed: _isProcessing ? null : _launchKaraokeSync, icon: const Icon(Icons.mic_external_on, size: 16, color: Colors.amberAccent), label: const Text("SYNC", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontSize: 12))),
                    ],
                  ),
                  _buildField('LYRICS', 'LYRICS (PLAIN OR [MM:SS.xx] LRC)', themeColor, multiLine: true),
                  _buildField('COMMENT', 'COMMENT', themeColor),
                  Row(children: [
                    Expanded(child: _buildField('LANGUAGE', 'LANGUAGE', themeColor)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildField('ENCODER', 'ENCODER', themeColor)),
                  ]),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: _toolButton(icon: Icons.undo, label: "RESET", color: Colors.white70, onPressed: _isProcessing || !_dirty ? null : _resetForm)),
                      const SizedBox(width: 8),
                      Expanded(child: _toolButton(icon: Icons.cleaning_services, label: "STRIP", color: Colors.amberAccent, onPressed: _isProcessing ? null : _stripToCore)),
                      const SizedBox(width: 8),
                      Expanded(child: _toolButton(icon: Icons.delete_sweep, label: "CLEAR", color: Colors.redAccent, onPressed: _isProcessing ? null : _clearForm)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  CyberTapFeedback(
                    enableHaptic: false,
                    enableAudio: false,
                    particleColor: themeColor,
                    ringColor: themeColor,
                    particleCount: 16,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _save(),
                      icon: Icon(canFix ? Icons.build_circle : Icons.save_alt, color: Colors.black),
                      label: Text(canFix ? "SAVE & FIX ORIGINAL" : "SAVE TO MUSIC", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), backgroundColor: themeColor, disabledBackgroundColor: themeColor.withValues(alpha: 0.2)),
                    ),
                  ),
                  if (canFix) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isProcessing ? null : () => _save(asCopy: true),
                      child: const Text("SAVE AS A NEW COPY INSTEAD", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 12)),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
