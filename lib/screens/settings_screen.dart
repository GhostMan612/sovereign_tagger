// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/cyber_tap_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import '../core/ghost_settings.dart';
import '../core/feedback_settings.dart';
import '../screens/main_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _geniusKeyCtrl = TextEditingController();
  final TextEditingController _acrHostCtrl = TextEditingController();
  final TextEditingController _acrKeyCtrl = TextEditingController();
  final TextEditingController _acrSecretCtrl = TextEditingController();

  bool _isSaving = false;
  bool _isUpdating = false;
  String _cacheStatus = "System Ready.";
  String _updateStatus = "Core Engine Is Ready.";
  bool _isDoctorRunning = false;
  String _doctorReport = "";
  String _fullStackStatus = "Idle.";
  bool _isProbing = false;
  String _probeReport = "";

  bool _isBackingUp = false;
  bool _isRestoring = false;
  String _backupStatus = "System Ready.";

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _geniusKeyCtrl.text = prefs.getString('genius_key') ?? "";
      _acrHostCtrl.text = prefs.getString('acr_host') ?? "";
      _acrKeyCtrl.text = prefs.getString('acr_key') ?? "";
      _acrSecretCtrl.text = prefs.getString('acr_secret') ?? "";
    });
    // Load Ghost Tutorial settings
    GhostSettings.load(prefs);
  }

  Future<void> _saveKeys() async {
    TapFeedback.machineTap();
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('genius_key', _geniusKeyCtrl.text.trim());
    await prefs.setString('acr_host', _acrHostCtrl.text.trim());
    await prefs.setString('acr_key', _acrKeyCtrl.text.trim());
    await prefs.setString('acr_secret', _acrSecretCtrl.text.trim());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('> KEYS SECURELY WRITTEN TO KERNEL PREFS.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: SovereignState.accentColor.value))));
    setState(() => _isSaving = false);
  }

  String _encrypt(String data) {
    final bytes = utf8.encode(data);
    final xorBytes = bytes.map((b) => b ^ 0x53).toList(); 
    return base64Encode(xorBytes);
  }

  String _decrypt(String data) {
    final xorBytes = base64Decode(data);
    final bytes = xorBytes.map((b) => b ^ 0x53).toList();
    return utf8.decode(bytes);
  }

  Future<void> _exportConfig() async {
    TapFeedback.machineTap();
    final config = {
      "genius_key": _geniusKeyCtrl.text.trim(),
      "acr_host": _acrHostCtrl.text.trim(),
      "acr_key": _acrKeyCtrl.text.trim(),
      "acr_secret": _acrSecretCtrl.text.trim()
    };
    final encryptedData = _encrypt(jsonEncode(config));
    
    try {
      final success = await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('exportConfig', {'data': encryptedData});
      if (!mounted) return;
      if (success == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> EXPORTED CONFIG BINARY TO DOWNLOADS FOLDER.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.cyanAccent))));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> ERR: FAILED TO EXPORT CONFIG.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('> ERR: EXPORT FAULT: $e', style: const TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent))));
    }
  }

  Future<void> _importConfig() async {
    TapFeedback.machineTap();
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final encryptedData = await file.readAsString();
        final config = jsonDecode(_decrypt(encryptedData));
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('> CONFIG IMPORTED. INITIATE SAVE PROTOCOL.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: SovereignState.accentColor.value))));
        
        setState(() {
          _geniusKeyCtrl.text = config["genius_key"] ?? "";
          _acrHostCtrl.text = config["acr_host"] ?? "";
          _acrKeyCtrl.text = config["acr_key"] ?? "";
          _acrSecretCtrl.text = config["acr_secret"] ?? "";
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> ERR: INVALID OR CORRUPTED CONFIG BINARY.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent))));
      }
    }
  }

  Future<void> _purgeCache() async {
    TapFeedback.machineTap();
    setState(() => _cacheStatus = "Purging...");
    try {
      int count = 0;
      
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      const storageChannel = MethodChannel('com.sovereign.tagger/storage');
      final cacheDir = Directory((await storageChannel.invokeMethod('getTempDirectory')).toString());
      if (cacheDir.existsSync()) {
        for (var file in cacheDir.listSync(recursive: true)) {
          if (file is File) {
            try {
              file.deleteSync();
              count++;
            } catch (_) {}
          }
        }
      }

      int stagingCount = 0;
      try {
        final extDir = Directory('/storage/emulated/0/Android/data/com.sovereigntagger/files');
        if (extDir.existsSync()) {
          for (var entity in extDir.listSync(recursive: true, followLinks: false)) {
            if (entity is File) {
              try {
                entity.deleteSync();
                stagingCount++;
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      setState(() => _cacheStatus = "Aggressive GC Complete. Purged $count Cache + $stagingCount Staging Files. Python Kernel Untouched.");
    } catch (e) {
      setState(() => _cacheStatus = "ERR: Purge Fault: $e");
    }
  }

  Future<void> _updateYtDlp() async {
    TapFeedback.machineTap();
    setState(() {
      _isUpdating = true;
      _updateStatus = "Initiating Scorched Earth Protocol...";
    });
    try {
      final result = await const MethodChannel('com.sovereign.tagger/ytdlp').invokeMethod('updateCore');
      final data = jsonDecode(result.toString());
      if (data['status'] == 'success') {
        setState(() => _updateStatus = data['message'].toString());
      } else {
        setState(() => _updateStatus = "ERR: Update Failed: ${data['message'].toString()}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateStatus = "ERR: Update Fault: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _updateFullStack() async {
    TapFeedback.machineTap();
    setState(() {
      _isUpdating = true;
      _fullStackStatus = "Full Stack Refresh: yt-dlp + mutagen/lyricsgenius...";
    });
    try {
      final result = await const MethodChannel('com.sovereign.tagger/ytdlp').invokeMethod('updateFullStack');
      final data = jsonDecode(result.toString());
      if (!mounted) return;
      if (data['status'] == 'success') {
        setState(() => _fullStackStatus = data['message'].toString());
      } else {
        setState(() => _fullStackStatus = "ERR: Full Stack Failed: ${data['message']}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _fullStackStatus = "ERR: Full Stack Fault: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _probeFfmpegKernel() async {
    TapFeedback.machineTap();
    setState(() {
      _isProbing = true;
      _probeReport = "Probing FFmpeg Kernel...";
    });
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    try {
      final version = FFmpegKitExtended.getFFmpegVersion();
      final filters = FFmpegKitExtended.getRegisteredFilters();
      final libs = FFmpegKitExtended.getExternalLibraries();
      final buildDate = FFmpegKitExtended.getBuildDate();

      final filterCount = RegExp(r'\S+').allMatches(filters).length;
      final lowerFilters = filters.toLowerCase();
      final lowerLibs = libs.toLowerCase();

      String verdict;
      if (lowerFilters.contains('whisper')) {
        verdict = "WHISPER SURFACE: DETECTED — transcribe op wireable";
      } else if (lowerLibs.contains('whisper')) {
        verdict = "WHISPER: lib linked but NOT exposed as filter — needs plugin route";
      } else {
        verdict = "WHISPER: NOT PRESENT in this build";
      }

      final proLibs = <String>['rubberband', 'soxr', 'x264', 'x265', 'vpx', 'opus', 'chromaprint', 'vidstab']
          .where((l) => lowerLibs.contains(l))
          .toList();

      setState(() => _probeReport = "FFmpeg $version (built $buildDate)\n"
          "Filters registered: $filterCount\n"
          "$verdict\n"
          "Pro libs: ${proLibs.isEmpty ? '(none matched)' : proLibs.join(', ')}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _probeReport = "ERR: Probe Fault: $e");
    } finally {
      if (mounted) setState(() => _isProbing = false);
    }
  }

  Future<void> _whisperDocs() async {
    TapFeedback.machineTap();
    setState(() {
      _isProbing = true;
      _probeReport = "Pulling on-device whisper filter documentation...";
    });
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    try {
      final docsSession = await FFmpegExecutor.execute('-hide_banner -h filter=whisper');
      final docs = docsSession.getOutput() ?? "";
      if (!mounted) return;
      setState(() => _probeReport = docs.isEmpty
          ? "(no docs returned — check logcat for filter errors)"
          : docs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _probeReport = "ERR: Docs Fault: $e");
    } finally {
      if (mounted) setState(() => _isProbing = false);
    }
  }

  Future<void> _backupAll() async {
    TapFeedback.machineTap();
    setState(() { _isBackingUp = true; _backupStatus = "Collecting kernel state..."; });
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final backup = <String, dynamic>{
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'settings': {
          'genius_key': prefs.getString('genius_key') ?? "",
          'acr_host': prefs.getString('acr_host') ?? "",
          'acr_key': prefs.getString('acr_key') ?? "",
          'acr_secret': prefs.getString('acr_secret') ?? "",
          'crossfade_duration': prefs.getDouble('crossfade_duration') ?? 0.0,
          'gapless_enabled': prefs.getBool('gapless_enabled') ?? true,
          'accent_color': prefs.getInt('accent_color') ?? 0xFFFF003C,
        },
        'eq_presets': <String, double>{},
        'playlists': <String, dynamic>{},
      };
      
      // Backup EQ presets
      for (int i = 0; i < 15; i++) {
        final val = prefs.getDouble('eq15_band_$i');
        if (val != null) (backup['eq_presets'] as Map)['band_$i'] = val;
      }
      
      // Backup persisted queue
      final queueJson = prefs.getString('persist_queue');
      if (queueJson != null) {
        backup['playlists']['persist_queue'] = jsonDecode(queueJson);
      }
      
      final encryptedData = _encrypt(jsonEncode(backup));
      
      // Use storage channel to export
      final success = await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('exportConfig', {'data': encryptedData});
      
      if (!mounted) return;
      if (success == true) {
        setState(() => _backupStatus = "BACKUP COMPLETE ✓\nEncrypted binary written to Downloads.");
      } else {
        setState(() => _backupStatus = "ERR: Backup write failed.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupStatus = "ERR: Backup Fault: $e");
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreAll() async {
    TapFeedback.machineTap();
    setState(() { _isRestoring = true; _backupStatus = "Select backup binary..."; });
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) {
        setState(() => _backupStatus = "Restore cancelled.");
        return;
      }
      
      final file = File(result.files.single.path!);
      final encryptedData = await file.readAsString();
      final decrypted = _decrypt(encryptedData);
      final backup = jsonDecode(decrypted) as Map<String, dynamic>;
      
      if (backup['version'] != 1) {
        setState(() => _backupStatus = "ERR: Unsupported backup version.");
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Restore settings
      final settings = backup['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        await prefs.setString('genius_key', settings['genius_key'] ?? "");
        await prefs.setString('acr_host', settings['acr_host'] ?? "");
        await prefs.setString('acr_key', settings['acr_key'] ?? "");
        await prefs.setString('acr_secret', settings['acr_secret'] ?? "");
        await prefs.setDouble('crossfade_duration', settings['crossfade_duration'] ?? 0.0);
        await prefs.setBool('gapless_enabled', settings['gapless_enabled'] ?? true);
        if (settings['accent_color'] != null) {
          await prefs.setInt('accent_color', settings['accent_color']);
          SovereignState.accentColor.value = Color(settings['accent_color']);
        }
      }
      
      // Restore EQ presets
      final eqPresets = backup['eq_presets'] as Map<String, dynamic>?;
      if (eqPresets != null) {
        for (int i = 0; i < 15; i++) {
          final val = eqPresets['band_$i'];
          if (val != null) await prefs.setDouble('eq15_band_$i', val.toDouble());
        }
      }
      
      // Restore playlist
      final playlists = backup['playlists'] as Map<String, dynamic>?;
      if (playlists != null && playlists['persist_queue'] != null) {
        await prefs.setString('persist_queue', jsonEncode(playlists['persist_queue']));
      }
      
      if (!mounted) return;
      _loadKeys(); // Reload UI
      setState(() => _backupStatus = "RESTORE COMPLETE ✓\nSettings + EQ + Queue restored. Restart recommended.");
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupStatus = "ERR: Restore Fault: $e");
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _runDoctor() async {
    TapFeedback.machineTap();
    setState(() {
      _isDoctorRunning = true;
      _doctorReport = "Running on-board python doctor...";
    });
    try {
      const yc = MethodChannel('com.sovereign.tagger/ytdlp');
      final lastErr = _updateStatus.contains("ERR") ? _updateStatus : "";
      final result = await yc.invokeMethod('runDoctor', {'errorLog': lastErr});
      final data = jsonDecode(result.toString());
      if (!mounted) return;
      if (data['status'] == 'success') {
        final hits = (data['hits'] as List).map((h) => "- ${h['patch_id']} (${h['file']}): ${h['hotfix']}").join("\n");
        final inv = (data['inventory'] as List).map((e) => "${e['file']} ${e['bytes']}b").join(", ");
        setState(() => _doctorReport = "yt-dlp ${data['ytdlp_version']}\nRegistry ${data['registry_size']} rules\nHits:\n${hits.isEmpty ? "(none — core likely current)" : hits}\nInventory: $inv\n\nHint: ${data['hint']}");
      } else {
        setState(() => _doctorReport = "ERR: ${data['message']}");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _doctorReport = "ERR: Doctor Fault: $e");
    } finally {
      if (mounted) setState(() => _isDoctorRunning = false);
    }
  }

  void _pickColor(BuildContext context, Color currentColor) {
    Color pickerColor = currentColor;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text("SELECT ACCENT COLOR", style: TextStyle(fontFamily: 'ShareTechMono', color: currentColor)),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (Color color) {
                pickerColor = color;
              },
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
            ),
          ),
          actions: [
            TextButton(
              child: const Text("CANCEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54)),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: currentColor, foregroundColor: Colors.black),
              child: const Text("APPLY TO THE MACHINE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold)),
              onPressed: () {
                SovereignState.accentColor.value = pickerColor;
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setInt('accent_color', pickerColor.toARGB32());
                });
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _geniusKeyCtrl.dispose();
    _acrHostCtrl.dispose();
    _acrKeyCtrl.dispose();
    _acrSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _openRegistration(String url) async {
    TapFeedback.machineTap();
    try {
      await const MethodChannel('com.sovereign.tagger/storage').invokeMethod('openUrl', {'url': url});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> LAUNCHED REGISTRATION PAGE.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.cyanAccent))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ERR: BROWSER FAULT — OPEN MANUALLY.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent))));
    }
  }

  Widget _buildSettingsField(TextEditingController controller, String label, Color accentColor) {
    return TextField(
      controller: controller, 
      style: TextStyle(fontFamily: 'ShareTechMono', color: accentColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: accentColor.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: accentColor)),
        filled: true,
        fillColor: Colors.black,
      )
    );
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
            title: Text("UNIVERSAL KERNEL PREFERENCES", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: themeColor.withValues(alpha: 0.3), height: 1.0),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.file_download, color: Colors.cyanAccent), tooltip: "MANUAL IMPORT .BIN", onPressed: _importConfig),
              IconButton(icon: const Icon(Icons.file_upload, color: Colors.cyanAccent), tooltip: "EXPORT .BIN TO DOWNLOADS", onPressed: _exportConfig),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("> UI PREFERENCES", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: themeColor)),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("SYSTEM ACCENT COLOR", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                  subtitle: const Text("Tap to modify global Machine theme", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 12)),
                  trailing: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                  ),
                  onTap: () => _pickColor(context, themeColor),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: themeColor.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.blur_on, color: themeColor, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text("FEEDBACK MATRIX", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                        ],
                      ),
                      const Text("Global interaction FX. Combinations welcome.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
                      const SizedBox(height: 4),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.sound,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("SOUND FX", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          subtitle: const Text("button clicks + boops", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setSound(x),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.haptics,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("HAPTICS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          subtitle: const Text("vibration on actions + completions", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setHaptics(x),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 16),
                      const Padding(padding: EdgeInsets.only(left: 4), child: Text("VISUAL LAYERS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38))),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.burst,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("PARTICLE BURST", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setBurst(x),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.ring,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("SHOCKWAVE RING", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setRing(x),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.pulse,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("SCALE PULSE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setPulse(x),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                GestureDetector(
                  onTap: () => _openRegistration('https://genius.com/api-clients'),
                  child: const Row(
                    children: [
                      Text("> GENIUS API [LYRICS & ART SPIDER]", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                      SizedBox(width: 8),
                      Icon(Icons.open_in_new, size: 15, color: Colors.amberAccent),
                    ],
                  ),
                ),
                const Text("tap the title to open the Genius registration page", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 12),
                _buildSettingsField(_geniusKeyCtrl, 'CLIENT ACCESS TOKEN', Colors.amberAccent),
                
                const SizedBox(height: 32),
                
                GestureDetector(
                  onTap: () => _openRegistration('https://console.acrcloud.com/'),
                  child: const Row(
                    children: [
                      Text("> ACRCLOUD [AUDIO FINGERPRINTING]", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      SizedBox(width: 8),
                      Icon(Icons.open_in_new, size: 15, color: Colors.blueAccent),
                    ],
                  ),
                ),
                const Text("tap the title to open the ACRCloud console", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 12),
                _buildSettingsField(_acrHostCtrl, 'HOST (E.G. IDENTIFY-EU-WEST-1.ACRCLOUD.COM)', Colors.blueAccent),
                const SizedBox(height: 12),
                _buildSettingsField(_acrKeyCtrl, 'ACCESS KEY', Colors.blueAccent),
                const SizedBox(height: 12),
                _buildSettingsField(_acrSecretCtrl, 'ACCESS SECRET', Colors.blueAccent),

                const SizedBox(height: 32),

                CyberTapFeedback(
                  enableHaptic: false,
                  enableAudio: false,
                  particleColor: themeColor,
                  ringColor: themeColor,
                  particleCount: 16,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveKeys,
                    icon: const Icon(Icons.save, color: Colors.black),
                    label: const Text("WRITE TO KERNEL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: themeColor,
                      disabledBackgroundColor: themeColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),
                
                const Text("> CORE ENGINE MAINTENANCE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                const SizedBox(height: 8),
                const Text("YT-DLP BREAKS WHEN APIS CHANGE. AGGRESSIVELY WIPE AND PULL THE LATEST MASTER BUILD DIRECTLY FROM GITHUB.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isUpdating ? null : _updateYtDlp,
                  icon: _isUpdating 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
                      : const Icon(Icons.security_update_warning, color: Colors.orangeAccent),
                  label: Text(_isUpdating ? "UPDATING CORE ENGINE..." : "CHECK FOR YT-DLP UPDATE", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orangeAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isUpdating ? null : _updateFullStack,
                  icon: _isUpdating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                      : const Icon(Icons.layers, color: Colors.amberAccent),
                  label: const Text("FULL STACK REFRESH (YT-DLP + DEPS)", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
                const SizedBox(height: 8),
                Text("> $_fullStackStatus", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.medical_services, color: Colors.cyanAccent, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(child: Text("ON-BOARD PYTHON DOCTOR", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                            OutlinedButton(
                              onPressed: _isDoctorRunning ? null : _runDoctor,
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: _isDoctorRunning
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                  : const Text("DIAGNOSE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.cyanAccent)),
                            ),
                          ],
                        ),
                      ),
                      if (_doctorReport.isNotEmpty) ...[
                        const Divider(color: Colors.white12, height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(_doctorReport, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70, height: 1.4)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withValues(alpha: 0.5))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.memory, color: themeColor, size: 18),
                            const SizedBox(width: 8),
                            const Expanded(child: Text("FFMPEG KERNEL PROBE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70))),
                            OutlinedButton(
                              onPressed: _isProbing ? null : _probeFfmpegKernel,
                              style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: _isProbing
                                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                                  : Text("PROBE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _isProbing ? null : _whisperDocs,
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.greenAccent), padding: const EdgeInsets.symmetric(horizontal: 12)),
                              child: const Text("DOCS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.greenAccent)),
                            ),
                          ],
                        ),
                      ),
                      if (_probeReport.isNotEmpty) ...[
                        const Divider(color: Colors.white12, height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(_probeReport, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70, height: 1.4)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text("> $_updateStatus", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70)),

                const SizedBox(height: 32),
                
                const Text("> SYSTEM CACHE MAINTENANCE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                const SizedBox(height: 8),
                const Text("ANDROID ISOLATES EDITED FILES IN AN INTERNAL CACHE. PURGE THIS REGULARLY TO FREE UP HARDWARE STORAGE.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _purgeCache,
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  label: const Text("PURGE INTERNAL CACHE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
                const SizedBox(height: 8),
                Text("> $_cacheStatus", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 48),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),

                const Text("> GHOST TUTORIAL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                const SizedBox(height: 8),
                const Text("CYBERPUNK GHOST AVATAR TUTORIAL CHATBOT. CODE-DRAWN GLITCH GHOST WITH CONTEXTUAL HELP.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text("GHOST VISIBLE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                        subtitle: const Text("Show ghost avatar overlay", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                        activeThumbColor: Colors.purpleAccent,
                        activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                        value: GhostSettings.visible.value,
                        onChanged: (val) => GhostSettings.setVisible(val),
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        title: const Text("AUTO EXPAND", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                        subtitle: const Text("Auto-expand on first launch", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                        activeThumbColor: Colors.purpleAccent,
                        activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                        value: GhostSettings.autoExpand.value,
                        onChanged: (val) => GhostSettings.setAutoExpand(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text("REDUCE MOTION (GLOBAL)", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                  subtitle: const Text("Disables ghost glitch/wobble/scanlines — also ambient backdrop / rain effects", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                  activeThumbColor: Colors.redAccent,
                  activeTrackColor: Colors.redAccent.withValues(alpha: 0.3),
                  value: GhostSettings.reduceMotion.value,
                  onChanged: (val) => GhostSettings.setReduceMotion(val),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await GhostSettings.setFirstLaunchComplete();
                    messenger.showSnackBar(const SnackBar(content: Text('> FIRST LAUNCH RESET. GHOST WILL RE-INTRODUCE ON NEXT START.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.purpleAccent))));
                  },
                  icon: const Icon(Icons.refresh, color: Colors.amberAccent),
                  label: const Text("RESET FIRST LAUNCH", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                ),

                const SizedBox(height: 32),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),

                const Text("> BACKUP & RESTORE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                const SizedBox(height: 8),
                const Text("EXPORT/IMPORT SETTINGS + PLAYLISTS + EQ PRESETS AS ENCRYPTED JSON BINARY.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBackingUp ? null : _backupAll,
                        icon: _isBackingUp
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent))
                            : const Icon(Icons.backup, color: Colors.greenAccent),
                        label: const Text("BACKUP ALL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.greenAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isRestoring ? null : _restoreAll,
                        icon: _isRestoring
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                            : const Icon(Icons.restore, color: Colors.amberAccent),
                        label: const Text("RESTORE ALL", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent), backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text("> $_backupStatus", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70)),

                const SizedBox(height: 48),
              ],
            ),
          ),
        );
      }
    );
  }
}