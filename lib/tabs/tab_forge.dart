// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import '../core/cyber_tap_feedback.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import '../screens/main_shell.dart';
import '../screens/lyric_sync_screen.dart';

class TabForge extends StatefulWidget {
  const TabForge({super.key});

  @override
  State<TabForge> createState() => _TabForgeState();
}

class _TabForgeState extends State<TabForge> {
  static const MethodChannel _acrChannel = MethodChannel('com.sovereign.tagger/acrcloud');
  static const MethodChannel _id3Channel = MethodChannel('com.sovereign.tagger/id3');
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');
  static const MethodChannel _spiderChannel = MethodChannel('com.sovereign.tagger/spider');

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _artistCtrl = TextEditingController();
  final TextEditingController _albumCtrl = TextEditingController();
  final TextEditingController _albumArtistCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  final TextEditingController _genreCtrl = TextEditingController();
  final TextEditingController _discNoCtrl = TextEditingController();
  final TextEditingController _trackNoCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();
  final TextEditingController _composerCtrl = TextEditingController();
  final TextEditingController _producerCtrl = TextEditingController();
  final TextEditingController _lyricsCtrl = TextEditingController();
  final TextEditingController _encoderCtrl = TextEditingController(text: "Sovereign Tagger");
  final TextEditingController _languageCtrl = TextEditingController();

  String _selectedFilePath = "";
  String _statusMessage = "System Idle. Awaiting Audio File For Metadata Injection.";
  bool _isProcessing = false;
  Image? _coverArtImage;
  String _coverArtBase64 = "";

  @override
  void initState() {
    super.initState();
    SovereignState.pendingForgePath.addListener(_onPendingPathChanged);
  }

  @override
  void dispose() {
    SovereignState.pendingForgePath.removeListener(_onPendingPathChanged);
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _albumArtistCtrl.dispose();
    _yearCtrl.dispose();
    _genreCtrl.dispose();
    _discNoCtrl.dispose();
    _trackNoCtrl.dispose();
    _commentCtrl.dispose();
    _composerCtrl.dispose();
    _producerCtrl.dispose();
    _lyricsCtrl.dispose();
    _encoderCtrl.dispose();
    _languageCtrl.dispose();
    super.dispose();
  }

  void _onPendingPathChanged() {
    final path = SovereignState.pendingForgePath.value;
    if (path.isNotEmpty) {
      _loadFile(path);
      SovereignState.pendingForgePath.value = "";
    }
  }

  Future<void> _pickFile() async {
    TapFeedback.machineTap();
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: File Picker Fault: ${e.message}");
      return;
    }
    if (result != null && result.files.single.path != null) {
      final originalPath = result.files.single.path!;
      try {
        final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
        if (!mounted) return;
        final fileName = originalPath.split('/').last;
        final cachePath = "$tempDir/forge_$fileName";
        
        File(originalPath).copySync(cachePath);
        _loadFile(cachePath);
      } catch (e) {
        if (!mounted) return;
        _loadFile(originalPath);
      }
    }
  }

  Future<void> _loadFile(String path) async {
    setState(() {
      _selectedFilePath = path;
      _statusMessage = "File Mounted: ${path.split('/').last}";
      _coverArtImage = null;
      _coverArtBase64 = "";
    });
    _readExistingTags(path);
  }

  Future<void> _ejectMedia() async {
    TapFeedback.machineTap();
    bool hadMedia = false;
    bool purged = false;

    if (_selectedFilePath.isNotEmpty) {
      hadMedia = true;
      bool isCacheCopy = false;
      try {
        final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
        isCacheCopy = tempDir != null && _selectedFilePath.startsWith(tempDir.toString());
      } catch (_) {}

      if (isCacheCopy) {
        try { File(_selectedFilePath).deleteSync(); purged = true; } catch (_) {}
      } else if (File(_selectedFilePath).existsSync()) {
        if (!mounted) return;
        final themeColor = SovereignState.accentColor.value;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: themeColor)),
            title: Text("ORIGINAL FILE MOUNTED", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
            content: const Text(
              "The mounted payload is an ORIGINAL file, not a cache copy.\n\nDELETE IT PERMANENTLY FROM DEVICE STORAGE?",
              style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white70, height: 1.5),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("KEEP FILE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("DELETE ORIGINAL", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try { File(_selectedFilePath).deleteSync(); purged = true; } catch (_) {}
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedFilePath = "";
      _titleCtrl.clear(); _artistCtrl.clear(); _albumCtrl.clear(); _albumArtistCtrl.clear();
      _yearCtrl.clear(); _genreCtrl.clear(); _discNoCtrl.clear(); _trackNoCtrl.clear();
      _commentCtrl.clear(); _composerCtrl.clear(); _producerCtrl.clear(); _lyricsCtrl.clear(); _languageCtrl.clear();
      _encoderCtrl.text = "Sovereign Tagger";
      _coverArtBase64 = "";
      _coverArtImage = null;
      _statusMessage = !hadMedia
          ? "System Idle. Awaiting Audio File For Metadata Injection."
          : (purged ? "Payload Purged From Vault. System Idle." : "Media Ejected. Original Preserved. System Idle.");
      _isProcessing = false;
    });
  }

  Future<void> _pickCoverArt() async {
    TapFeedback.machineTap();
    if (_isProcessing) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: Image Picker Fault: ${e.message}");
      return;
    }
    if (result != null && result.files.single.path != null) {
      try {
        final bytes = await File(result.files.single.path!).readAsBytes();
        if (!mounted) return;
        setState(() {
          _coverArtBase64 = base64Encode(bytes);
          _coverArtImage = Image.memory(bytes, height: 150, width: 150, fit: BoxFit.cover);
          _statusMessage = "Custom Album Art Injected Into Buffer.";
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _statusMessage = "ERR: Cover Read Fault: $e");
      }
    }
  }

  void _clearCoverArt() { 
    setState(() { 
      _coverArtBase64 = ""; 
      _coverArtImage = null; 
      _statusMessage = "Album Art Buffer Cleared."; 
    }); 
  }

  Future<void> _clearAllFields() async {
    TapFeedback.machineTap();
    if (_selectedFilePath.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = "Purging All ID3 Frames From Physical File...";
    });

    try {
      final metadata = {
        'TITLE': '', 'ARTIST': '', 'ALBUM': '', 'ALBUM_ARTIST': '',
        'YEAR': '', 'GENRE': '', 'DISC_NO': '', 'TRACK': '',
        'COMMENT': '', 'COMPOSER': '', 'PRODUCER': '', 'LYRICS': '',
        'ENCODER': '', 'LANGUAGE': '', 'ARTWORK_BASE64': '',
      };

      await _id3Channel.invokeMethod('writeTags', {
        'filePath': _selectedFilePath,
        'metadata': metadata
      });

      setState(() {
        _titleCtrl.clear(); _artistCtrl.clear(); _albumCtrl.clear(); _albumArtistCtrl.clear();
        _yearCtrl.clear(); _genreCtrl.clear(); _discNoCtrl.clear(); _trackNoCtrl.clear();
        _commentCtrl.clear(); _composerCtrl.clear(); _producerCtrl.clear(); _lyricsCtrl.clear(); _languageCtrl.clear();
        _encoderCtrl.text = "Sovereign Tagger";
        _coverArtBase64 = "";
        _coverArtImage = null;
        _statusMessage = "File Completely Purged (Ghost State).";
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Purge Fault: $e";
      });
    }
  }

  Future<void> _clearForPartial() async {
    if (_selectedFilePath.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = "Wiping Non-Essential Metadata (Retaining Core)...";
    });

    try {
      final metadata = {
        'TITLE': _titleCtrl.text, 'ARTIST': _artistCtrl.text, 'ALBUM': '', 'ALBUM_ARTIST': '',
        'YEAR': '', 'GENRE': '', 'DISC_NO': '', 'TRACK': '',
        'COMMENT': '', 'COMPOSER': '', 'PRODUCER': '', 'LYRICS': '',
        'ENCODER': '', 'LANGUAGE': '', 'ARTWORK_BASE64': '',
      };

      await _id3Channel.invokeMethod('writeTags', {
        'filePath': _selectedFilePath,
        'metadata': metadata
      });

      setState(() {
        _albumCtrl.clear(); _albumArtistCtrl.clear();
        _yearCtrl.clear(); _genreCtrl.clear(); _discNoCtrl.clear(); _trackNoCtrl.clear();
        _commentCtrl.clear(); _composerCtrl.clear(); _producerCtrl.clear(); _lyricsCtrl.clear(); _languageCtrl.clear();
        _coverArtBase64 = "";
        _coverArtImage = null;
        _statusMessage = "Reverted To Partial. System Ready For Spider.";
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Wipe Fault: $e";
      });
    }
  }

  Future<void> _readExistingTags(String path) async {
    try {
      final Map<Object?, Object?> rawTags = await _id3Channel.invokeMethod('readTags', {'filePath': path});
      if (!mounted) return;
      final tags = rawTags.map((key, value) => MapEntry(key.toString(), value.toString()));

      if (!mounted) return;
      setState(() {
        _titleCtrl.text = tags["TITLE"] ?? ""; _artistCtrl.text = tags["ARTIST"] ?? "";
        _albumCtrl.text = tags["ALBUM"] ?? ""; _albumArtistCtrl.text = tags["ALBUM_ARTIST"] ?? "";
        _yearCtrl.text = tags["YEAR"] ?? ""; _genreCtrl.text = tags["GENRE"] ?? "";
        _discNoCtrl.text = tags["DISC_NO"] ?? ""; _trackNoCtrl.text = tags["TRACK"] ?? "";
        _commentCtrl.text = tags["COMMENT"] ?? ""; _composerCtrl.text = tags["COMPOSER"] ?? "";
        _producerCtrl.text = tags["PRODUCER"] ?? ""; _lyricsCtrl.text = tags["LYRICS"] ?? ""; _languageCtrl.text = tags["LANGUAGE"] ?? "";
        
        if (tags["ARTWORK_BASE64"] != null && tags["ARTWORK_BASE64"]!.isNotEmpty) {
          _coverArtBase64 = tags["ARTWORK_BASE64"]!;
          _coverArtImage = Image.memory(base64Decode(_coverArtBase64), height: 150, width: 150, fit: BoxFit.cover);
        }
      });
    } catch (e) { debugPrint("Failed to read tags: $e"); }
  }

  Future<void> _spiderAutoTag() async {
    TapFeedback.machineTap();
    if (_titleCtrl.text.isEmpty || _artistCtrl.text.isEmpty) { setState(() => _statusMessage = "ERR: Spider Requires Artist And Title Strings."); return; }
    setState(() { _isProcessing = true; _statusMessage = "Initiating Spider Protocol..."; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final geniusKey = prefs.getString('genius_key') ?? "";
      if (geniusKey.isEmpty) { setState(() { _isProcessing = false; _statusMessage = "ERR: Genius API Key Missing In Kernel Prefs."; }); return; }

      final result = await _spiderChannel.invokeMethod('scrape', {'artist': _artistCtrl.text, 'title': _titleCtrl.text, 'geniusKey': geniusKey});
      final data = jsonDecode(result.toString());

      if (data['status'] == 'success') {
        setState(() {
          if (_titleCtrl.text.isEmpty) _titleCtrl.text = data['title'] ?? "";
          if (_artistCtrl.text.isEmpty) _artistCtrl.text = data['artist'] ?? "";
          if (_albumArtistCtrl.text.isEmpty) _albumArtistCtrl.text = _artistCtrl.text;
          if (_albumCtrl.text.isEmpty) _albumCtrl.text = data['album'] ?? "";
          if (_yearCtrl.text.isEmpty) _yearCtrl.text = data['year'] ?? "";
          if (_genreCtrl.text.isEmpty) _genreCtrl.text = data['genre'] ?? "";
          if (_trackNoCtrl.text.isEmpty) _trackNoCtrl.text = data['track_no'] ?? "";
          if (_discNoCtrl.text.isEmpty) _discNoCtrl.text = data['disc_no'] ?? "";
          if (_lyricsCtrl.text.isEmpty) _lyricsCtrl.text = data['lyrics'] ?? "";
          
          if (data['artwork_base64'] != null && data['artwork_base64'].toString().isNotEmpty) {
            _coverArtBase64 = data['artwork_base64'];
            _coverArtImage = Image.memory(base64Decode(_coverArtBase64), height: 150, width: 150, fit: BoxFit.cover);
          }
          _statusMessage = "Spider Success. Metadata Buffer Populated."; _isProcessing = false;
        });
      } else { setState(() { _statusMessage = "ERR: Spider Kernel Fault: ${data['message']}"; _isProcessing = false; }); }
    } catch (e) { setState(() { _isProcessing = false; _statusMessage = "ERR: Spider Exception: $e"; }); }
  }

  Future<void> _acrIdentify() async {
    TapFeedback.machineTap();
    if (_selectedFilePath.isEmpty) return;
    setState(() { _isProcessing = true; _statusMessage = "Sniping 20s Audio Fragment For Fingerprint..."; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString('acr_host') ?? ""; final key = prefs.getString('acr_key') ?? ""; final secret = prefs.getString('acr_secret') ?? "";
      if (host.isEmpty || key.isEmpty || secret.isEmpty) { setState(() { _isProcessing = false; _statusMessage = "ERR: ACRCloud API Keys Missing In Kernel Prefs."; }); return; }

      await _acrChannel.invokeMethod('initialize', {'host': host, 'accessKey': key, 'accessSecret': secret});
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final tempWavPath = "$tempDir/acr_snippet_${DateTime.now().millisecondsSinceEpoch}.wav";
      
      final session = await FFmpegExecutor.execute('-y -i "$_selectedFilePath" -ss 0 -t 20 -ar 8000 -ac 1 -c:a pcm_s16le "$tempWavPath"');
      if (!ReturnCode.isSuccess(session.getReturnCode())) { setState(() { _isProcessing = false; _statusMessage = "ERR: FFmpeg Snippet Fault."; }); return; }

      setState(() => _statusMessage = "Querying ACRCloud Neural Net...");
      dynamic data;
      try {
        final rawResult = await _acrChannel.invokeMethod('identify', {'filePath': tempWavPath});
        data = jsonDecode(rawResult.toString());
      } finally {
        try { if (File(tempWavPath).existsSync()) File(tempWavPath).deleteSync(); } catch (_) {}
      }

      if (data['status'] != null && data['status']['code'] == 0 && data['metadata'] != null) {
        final music = data['metadata']['music'][0];
        final List<dynamic> artistsArray = music['artists'] ?? [];
        setState(() {
          _titleCtrl.text = music['title'] ?? ""; _artistCtrl.text = artistsArray.isNotEmpty ? artistsArray[0]['name'] : "";
          _statusMessage = "Identity Confirmed. Ready For Spidering."; _isProcessing = false;
        });
      } else { setState(() { _statusMessage = "ERR: No Match Found In ACRCloud DB."; _isProcessing = false; }); }
    } catch (e) { setState(() { _isProcessing = false; _statusMessage = "ERR: ACRCloud Fault: $e"; }); }
  }

  Future<void> _injectTags() async {
    TapFeedback.machineTap();
    if (_selectedFilePath.isEmpty) return;
    setState(() { _isProcessing = true; _statusMessage = "Injecting ID3 Metadata Frames..."; });

    try {
      final metadata = {
        'TITLE': _titleCtrl.text, 'ARTIST': _artistCtrl.text, 'ALBUM': _albumCtrl.text, 'ALBUM_ARTIST': _albumArtistCtrl.text,
        'YEAR': _yearCtrl.text, 'GENRE': _genreCtrl.text, 'DISC_NO': _discNoCtrl.text, 'TRACK': _trackNoCtrl.text,
        'COMMENT': _commentCtrl.text, 'COMPOSER': _composerCtrl.text, 'PRODUCER': _producerCtrl.text, 'LYRICS': _lyricsCtrl.text,
        'ENCODER': _encoderCtrl.text, 'LANGUAGE': _languageCtrl.text, 'ARTWORK_BASE64': _coverArtBase64,
      };

      if (await _id3Channel.invokeMethod('writeTags', {'filePath': _selectedFilePath, 'metadata': metadata})) {
        String verificationNote = "";
        try {
          final Map<Object?, Object?> rawBack = await _id3Channel.invokeMethod('readTags', {'filePath': _selectedFilePath});
          final back = rawBack.map((key, value) => MapEntry(key.toString(), value.toString()));
          final List<String> mismatches = [];
          void verifyField(String key, String wanted) {
            if (wanted.trim().isNotEmpty && (back[key] ?? "") != wanted) mismatches.add(key);
          }
          verifyField('TITLE', _titleCtrl.text);
          verifyField('ARTIST', _artistCtrl.text);
          verifyField('ALBUM', _albumCtrl.text);
          verifyField('TRACK', _trackNoCtrl.text);
          verifyField('YEAR', _yearCtrl.text);
          if (_coverArtBase64.isNotEmpty && (back['ARTWORK_BASE64'] ?? "").isEmpty) mismatches.add('ARTWORK');
          verificationNote = mismatches.isEmpty ? "Round-Trip Verified." : "WARN: Read-Back Fault On ${mismatches.join('/')}.";
        } catch (_) {
          verificationNote = "WARN: Round-Trip Read Fault.";
        }

        String trackStr = _trackNoCtrl.text.trim();
        if (trackStr.isNotEmpty && trackStr.length == 1) trackStr = "0$trackStr";
        String prefix = trackStr.isNotEmpty ? "$trackStr - " : "";
        String artistStr = _artistCtrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
        String titleStr = _titleCtrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
        if (artistStr.isEmpty) artistStr = "Unknown Artist"; if (titleStr.isEmpty) titleStr = "Unknown Title";

        String sourceExt = _selectedFilePath.contains('.')
            ? _selectedFilePath.substring(_selectedFilePath.lastIndexOf('.') + 1).toLowerCase()
            : "";
        if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(sourceExt)) sourceExt = "mp3";
        String newFilePath = "${File(_selectedFilePath).parent.path}/$prefix$artistStr · $titleStr.$sourceExt";
        if (_selectedFilePath != newFilePath) { 
          File(_selectedFilePath).renameSync(newFilePath); 
          _selectedFilePath = newFilePath; 
        }

        setState(() => _statusMessage = "Exporting Master Payload To Public Folder...");
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        try {
          final uriString = await _storageChannel.invokeMethod('addToMediaStore', {
            'filePath': _selectedFilePath,
            'title': titleStr
          });

          String stagingNote = "";
          final isStaging = _selectedFilePath.contains('/Android/data/com.sovereigntagger/') ||
              _selectedFilePath.contains('/cache/');
          if (isStaging) {
            try {
              File(_selectedFilePath).deleteSync();
              stagingNote = "\nStaging Copy Purged. Nothing Left In App Vault.";
              _selectedFilePath = "";
            } catch (_) {}
          }

          if (!mounted) return;
          TapFeedback.machineConfirm();
          setState(() {
            _isProcessing = false;
            _statusMessage = "$verificationNote Master Secured At:\n$uriString$stagingNote";
          });
        } catch (storageErr) {
          setState(() { 
            _isProcessing = false; 
            _statusMessage = "ERR: Tags Written But MediaStore Export Fault: $storageErr"; 
          });
        }
      } else { setState(() { _isProcessing = false; _statusMessage = "ERR: Tag Injection Failed."; }); }
    } catch (e) { setState(() { _isProcessing = false; _statusMessage = "ERR: Injection Kernel Fault: $e"; }); }
  }

  void _launchKaraokeSync() async {
    TapFeedback.machineTap();
    if (_lyricsCtrl.text.isEmpty || _selectedFilePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MOUNT FILE AND PULL LYRICS FIRST.', style: TextStyle(fontFamily: 'ShareTechMono'))));
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LyricSyncScreen(
          filePath: _selectedFilePath,
          title: _titleCtrl.text,
          artist: _artistCtrl.text,
          rawLyrics: _lyricsCtrl.text,
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, Color themeColor, {bool multiLine = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0), 
      child: TextField(
        controller: controller, 
        maxLines: multiLine ? 4 : 1,
        style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
        decoration: InputDecoration(
          labelText: label, 
          labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
          filled: true,
          fillColor: Colors.black,
        ), 
        enabled: !_isProcessing
      )
    );
  }

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
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
                          label: Text("MOUNT MP3 FILE", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: themeColor),
                            backgroundColor: Colors.black,
                          )
                        ),
                      ),
                    ),
                    if (_selectedFilePath.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)), child: IconButton(onPressed: _isProcessing ? null : _ejectMedia, icon: const Icon(Icons.eject, color: Colors.white54), tooltip: "EJECT MEDIA")),
                      const SizedBox(width: 8),
                      Container(decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.amberAccent), borderRadius: BorderRadius.circular(4)), child: IconButton(onPressed: _isProcessing ? null : _clearForPartial, icon: const Icon(Icons.cleaning_services, color: Colors.amberAccent), tooltip: "REVERT TO PARTIAL")),
                      const SizedBox(width: 8),
                      Container(decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(4)), child: IconButton(onPressed: _isProcessing ? null : _clearAllFields, icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), tooltip: "CLEAR WORKSPACE")),
                    ],
                  ],
                ),
                
                if (_selectedFilePath.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(onPressed: _isProcessing ? null : _acrIdentify, icon: const Icon(Icons.hearing, color: Colors.blueAccent), label: const Text("IDENTIFY [ACR]", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.blueAccent, fontWeight: FontWeight.bold)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5)), backgroundColor: Colors.black))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(onPressed: _isProcessing ? null : _spiderAutoTag, icon: const Icon(Icons.auto_awesome, color: Colors.purpleAccent), label: const Text("AUTO-TAG [SPIDER]", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.purpleAccent, fontWeight: FontWeight.bold)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.5)), backgroundColor: Colors.black))),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  Center(
                    child: GestureDetector(
                      onTap: _pickCoverArt, 
                      child: Container(
                        height: 150, width: 150, 
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withValues(alpha: 0.5))), 
                        child: _coverArtImage ?? Icon(Icons.add_photo_alternate, size: 64, color: themeColor.withValues(alpha: 0.3))
                      )
                    )
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(onPressed: _isProcessing ? null : _pickCoverArt, icon: Icon(Icons.image_search, size: 16, color: themeColor), label: Text("BROWSE ART", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor))),
                      TextButton.icon(onPressed: _isProcessing ? null : _clearCoverArt, icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), label: const Text("CLEAR ART", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  _buildField('TITLE', _titleCtrl, themeColor), _buildField('ARTIST', _artistCtrl, themeColor), _buildField('ALBUM', _albumCtrl, themeColor),
                  Row(children: [Expanded(child: _buildField('YEAR', _yearCtrl, themeColor)), const SizedBox(width: 12), Expanded(child: _buildField('GENRE', _genreCtrl, themeColor))]),
                  Row(children: [Expanded(child: _buildField('TRACK NO.', _trackNoCtrl, themeColor)), const SizedBox(width: 12), Expanded(child: _buildField('DISC NO.', _discNoCtrl, themeColor))]),
                  _buildField('ALBUM ARTIST', _albumArtistCtrl, themeColor), _buildField('COMPOSER', _composerCtrl, themeColor), _buildField('PRODUCER', _producerCtrl, themeColor),
                  
                  _buildField('LYRICS', _lyricsCtrl, themeColor, multiLine: true),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _isProcessing ? null : _launchKaraokeSync,
                      icon: const Icon(Icons.mic_external_on, color: Colors.amberAccent),
                      label: const Text("KARAOKE SYLT SYNC", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 12), _buildField('COMMENT', _commentCtrl, themeColor),
                  Row(children: [Expanded(child: _buildField('LANGUAGE', _languageCtrl, themeColor)), const SizedBox(width: 12), Expanded(child: _buildField('ENCODER', _encoderCtrl, themeColor))]),
                  
                  const SizedBox(height: 32),
                  CyberTapFeedback(
                    enableHaptic: false,
                    enableAudio: false,
                    particleColor: themeColor,
                    ringColor: themeColor,
                    particleCount: 16,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _injectTags,
                      icon: const Icon(Icons.save, color: Colors.black),
                      label: const Text("INJECT TAGS & EXPORT", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: themeColor,
                        disabledBackgroundColor: themeColor.withValues(alpha: 0.2),
                      )
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        );
      }
    );
  }
}