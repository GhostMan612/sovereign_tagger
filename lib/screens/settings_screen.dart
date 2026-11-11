// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
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
import '../core/embedding_model.dart';
import '../core/embedding_service.dart';
import '../core/ffmpeg_executor.dart';
import '../core/ghost_settings.dart';
import '../core/feedback_settings.dart';
import '../core/model_lifecycle.dart';
import '../core/storage_client.dart';
import '../screens/main_shell.dart';
import '../services/ghost_brain.dart';
import '../services/ghost_vector_index.dart';
import '../tabs/tab_library.dart';
import '../widgets/cyber_backdrop.dart';
import '../widgets/machine_rain.dart';

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
  final TextEditingController _hfTokenCtrl = TextEditingController();

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
    ModelLifecycle.instance.ensureInitialized();
    unawaited(GhostVectorIndex.instance.loadFromDiskIfNeeded());
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _geniusKeyCtrl.text = prefs.getString('genius_key') ?? "";
      _acrHostCtrl.text = prefs.getString('acr_host') ?? "";
      _acrKeyCtrl.text = prefs.getString('acr_key') ?? "";
      _acrSecretCtrl.text = prefs.getString('acr_secret') ?? "";
      _hfTokenCtrl.text = prefs.getString('hf_token') ?? "";
    });

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
    await prefs.setString('hf_token', _hfTokenCtrl.text.trim());

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
      "acr_secret": _acrSecretCtrl.text.trim(),
      "hf_token": _hfTokenCtrl.text.trim(),
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
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked != null && picked.path != null) {
      try {
        final file = File(picked.path!);
        final encryptedData = await file.readAsString();
        final config = jsonDecode(_decrypt(encryptedData));
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('> CONFIG IMPORTED. INITIATE SAVE PROTOCOL.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: SovereignState.accentColor.value))));
        
        setState(() {
          _geniusKeyCtrl.text = config["genius_key"] ?? "";
          _acrHostCtrl.text = config["acr_host"] ?? "";
          _acrKeyCtrl.text = config["acr_key"] ?? "";
          _acrSecretCtrl.text = config["acr_secret"] ?? "";
          _hfTokenCtrl.text = config["hf_token"] ?? "";
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
        await FilePicker.clearTemporaryFiles();
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

      if (!mounted) return;
      setState(() => _cacheStatus = "Aggressive GC Complete. Purged $count Cache + $stagingCount Staging Files. Python Kernel Untouched.");
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
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
          'hf_token': prefs.getString('hf_token') ?? "",
          'crossfade_duration': prefs.getDouble('crossfade_duration') ?? 0.0,
          'gapless_enabled': prefs.getBool('gapless_enabled') ?? true,
          'accent_color': prefs.getInt('accent_color') ?? 0xFFFF003C,
          'fx_backdrop_enabled': prefs.getBool('fx_backdrop_enabled') ?? true,
          'fx_backdrop_intensity': prefs.getDouble('fx_backdrop_intensity') ?? 0.90,
        },
        'eq_presets': <String, double>{},
        'playlists': <String, dynamic>{},
      };
      

      for (int i = 0; i < 15; i++) {
        final val = prefs.getDouble('eq15_band_$i');
        if (val != null) (backup['eq_presets'] as Map)['band_$i'] = val;
      }
      

      final queueJson = prefs.getString('persist_queue');
      if (queueJson != null) {
        final queue = Map<String, dynamic>.from(jsonDecode(queueJson) as Map);
        final posJson = prefs.getString('persist_queue_pos');
        if (posJson != null) queue.addAll(Map<String, dynamic>.from(jsonDecode(posJson) as Map));
        backup['playlists']['persist_queue'] = queue;
      }
      
      final encryptedData = _encrypt(jsonEncode(backup));
      

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
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null || picked.path == null) {
        if (!mounted) return;
        setState(() => _backupStatus = "Restore canceled.");
        return;
      }
      
      final file = File(picked.path!);
      final encryptedData = await file.readAsString();
      final decrypted = _decrypt(encryptedData);
      final backup = jsonDecode(decrypted) as Map<String, dynamic>;
      
      if (backup['version'] != 1) {
        if (!mounted) return;
        setState(() => _backupStatus = "ERR: Unsupported backup version.");
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      

      final settings = backup['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        await prefs.setString('genius_key', settings['genius_key'] ?? "");
        await prefs.setString('acr_host', settings['acr_host'] ?? "");
        await prefs.setString('acr_key', settings['acr_key'] ?? "");
        await prefs.setString('acr_secret', settings['acr_secret'] ?? "");
        if (settings['hf_token'] != null) {
          await prefs.setString('hf_token', settings['hf_token'].toString());
        }
        await prefs.setDouble('crossfade_duration', settings['crossfade_duration'] ?? 0.0);
        await prefs.setBool('gapless_enabled', settings['gapless_enabled'] ?? true);
        if (settings['accent_color'] != null) {
          await prefs.setInt('accent_color', settings['accent_color']);
          SovereignState.accentColor.value = Color(settings['accent_color']);
        }
        if (settings['fx_backdrop_enabled'] != null) {
          await FeedbackSettings.setBackdrop(settings['fx_backdrop_enabled'] == true);
        }
        if (settings['fx_backdrop_intensity'] is num) {
          await FeedbackSettings.setBackdropIntensity((settings['fx_backdrop_intensity'] as num).toDouble());
        }
      }
      

      final eqPresets = backup['eq_presets'] as Map<String, dynamic>?;
      if (eqPresets != null) {
        for (int i = 0; i < 15; i++) {
          final val = eqPresets['band_$i'];
          if (val != null) await prefs.setDouble('eq15_band_$i', val.toDouble());
        }
      }
      

      final playlists = backup['playlists'] as Map<String, dynamic>?;
      if (playlists != null && playlists['persist_queue'] != null) {
        final queue = Map<String, dynamic>.from(playlists['persist_queue'] as Map);
        await prefs.setString('persist_queue', jsonEncode({'paths': queue['paths'] ?? []}));
        await prefs.setString('persist_queue_pos', jsonEncode({'index': queue['index'] ?? 0, 'positionMs': queue['positionMs'] ?? 0}));
      }
      
      if (!mounted) return;
      _loadKeys();
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
      if (!mounted) return;
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
    _hfTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _downloadEmbeddingGemma() async {
    TapFeedback.machineTap();
    final token = _hfTokenCtrl.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hf_token', token);
    if (!mounted) return;
    final ok = ModelLifecycle.instance.state.value.filesReady
        ? !(await ModelLifecycle.instance.verifyLiveInference()).startsWith('ERR')
        : await ModelLifecycle.instance.downloadAndActivate(hfToken: token);
    if (!mounted) return;
    final statusMsg = ModelLifecycle.instance.state.value.statusText;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('> $statusMsg', style: const TextStyle(fontFamily: 'ShareTechMono')),
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ok ? Colors.greenAccent : Colors.redAccent),
        ),
      ),
    );
  }

  Future<void> _importEmbeddingFile({required bool isTokenizer}) async {
    TapFeedback.machineTap();
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (!mounted || picked == null || picked.path == null) return;
    await ModelLifecycle.instance.importLocalFile(
      path: picked.path!,
      isTokenizer: isTokenizer,
    );
  }

  Future<void> _rebuildVectorIndex() async {
    TapFeedback.machineTap();
    if (GhostVectorIndex.instance.state.value.isIndexing) {
      GhostVectorIndex.instance.cancelIndexing();
      return;
    }
    try {
      final rows = await StorageClient.queryAudio();
      if (!mounted) return;
      final tracks = rows
          .map(LibTrack.fromMap)
          .where((t) => t.path.isNotEmpty)
          .map(
            (t) => GhostTrack(
              path: t.path,
              title: t.title,
              artist: t.artist,
              album: t.album,
              trackNo: t.track,
              discNo: t.disc,
            ),
          )
          .toList();
      await GhostVectorIndex.instance.ensureIndexed(
        tracks,
        forceRebuild: true,
        readEmbeddedLyrics: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> ERR: VECTOR INDEX FAULT: $e', style: const TextStyle(fontFamily: 'ShareTechMono')),
          backgroundColor: Colors.black,
          shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.redAccent)),
        ),
      );
    }
  }

  Widget _buildEmbeddingGemmaCard(Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openRegistration(EmbeddingModel.repoUrl),
          child: const Row(
            children: [
              Expanded(
                child: Text(
                  "> GHOSTBRAIN EMBEDDINGGEMMA [256-D AI]",
                  style: TextStyle(
                    fontFamily: 'ShareTechMono',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.open_in_new, size: 15, color: Colors.cyanAccent),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "GOOGLE AI EDGE LITERT 256-D MATRYOSHKA SEMANTIC ROUTER + OFFLINE LIBRARY & LRC LYRIC VECTOR SEARCH. WEIGHTS LIVE OUTSIDE APK (0 MB BLOAT) AND AUTO-UNLOAD ON IDLE/LOW RAM.",
          style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<EmbeddingRuntimeState>(
                valueListenable: ModelLifecycle.instance.state,
                builder: (context, rt, _) {
                  final badgeColor = rt.loaded
                      ? Colors.greenAccent
                      : (rt.filesReady ? Colors.cyanAccent : Colors.amberAccent);
                  final badgeLabel = rt.loaded
                      ? "LITE-RT ACTIVE"
                      : (rt.filesReady ? "STANDBY" : "FALLBACK 256-D");
                  final isErr = rt.statusText.startsWith('ERR') ||
                      rt.statusText.contains('HTTP') ||
                      rt.statusText.contains('failed');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.psychology, color: Colors.cyanAccent, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "EMBEDDINGGEMMA-300M KERNEL",
                              style: TextStyle(
                                fontFamily: 'ShareTechMono',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.14),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.7)),
                            ),
                            child: Text(
                              badgeLabel,
                              style: TextStyle(
                                fontFamily: 'ShareTechMono',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (rt.totalRamMb > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          "DEVICE RAM: ${rt.availRamMb} MB FREE / ${rt.totalRamMb} MB TOTAL${rt.lowMemory ? ' [LOW MEMORY GUARD]' : ''}",
                          style: TextStyle(
                            fontFamily: 'ShareTechMono',
                            fontSize: 10,
                            color: rt.lowMemory ? Colors.redAccent : Colors.white38,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        "> ${rt.statusText}",
                        style: TextStyle(
                          fontFamily: 'VT323',
                          fontSize: 14,
                          color: isErr ? Colors.redAccent : Colors.white70,
                        ),
                      ),
                      if (rt.isDownloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: rt.progress > 0 ? rt.progress : null,
                          minHeight: 4,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hfTokenCtrl,
                        obscureText: true,
                        style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.cyanAccent, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'HF READ TOKEN (OPTIONAL — AUTO-MIRROR WORKS WITHOUT TOKEN)',
                          labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 10),
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.cyanAccent),
                          ),
                          filled: true,
                          fillColor: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openRegistration(EmbeddingModel.repoUrl),
                              child: const Text(
                                "[1. ACCEPT HF GEMMA LICENSE ↗]",
                                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.cyanAccent),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _openRegistration(EmbeddingModel.hfTokensUrl),
                            child: const Text(
                              "[2. GET HF READ TOKEN ↗]",
                              style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.cyanAccent),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: rt.isDownloading
                            ? () => ModelLifecycle.instance.cancelDownload()
                            : (rt.isBusy ? null : _downloadEmbeddingGemma),
                        icon: rt.isDownloading
                            ? const Icon(Icons.close, color: Colors.redAccent, size: 16)
                            : (rt.isBusy
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                  )
                                : const Icon(Icons.cloud_download, color: Colors.cyanAccent, size: 16)),
                        label: Text(
                          rt.isDownloading
                              ? "CANCEL DOWNLOAD"
                              : (rt.filesReady ? "VERIFY / ACTIVATE GEMMA" : "DOWNLOAD GEMMA-300M (~184 MB)"),
                          style: TextStyle(
                            fontFamily: 'ShareTechMono',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: rt.isDownloading ? Colors.redAccent : Colors.cyanAccent,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: rt.isDownloading ? Colors.redAccent : Colors.cyanAccent),
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: rt.isBusy ? null : () => _importEmbeddingFile(isTokenizer: false),
                              icon: const Icon(Icons.folder_open, color: Colors.amberAccent, size: 15),
                              label: const Text(
                                "IMPORT .TFLITE",
                                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.amberAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.7)),
                                backgroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: rt.isBusy ? null : () => _importEmbeddingFile(isTokenizer: true),
                              icon: const Icon(Icons.translate, color: Colors.amberAccent, size: 15),
                              label: const Text(
                                "IMPORT TOKENIZER",
                                style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.amberAccent),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.7)),
                                backgroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (rt.filesReady) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: rt.isBusy ? null : _downloadEmbeddingGemma,
                            icon: const Icon(Icons.verified_outlined, color: Colors.cyanAccent, size: 15),
                            label: const Text(
                              "TEST LIVE 256-D INFERENCE",
                              style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.cyanAccent),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.7)),
                              backgroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: rt.isBusy
                                    ? null
                                    : () => rt.loaded
                                        ? ModelLifecycle.instance.unloadFromRam()
                                        : ModelLifecycle.instance.loadIntoRam(),
                                icon: Icon(
                                  rt.loaded ? Icons.memory : Icons.bolt,
                                  color: rt.loaded ? Colors.orangeAccent : Colors.greenAccent,
                                  size: 15,
                                ),
                                label: Text(
                                  rt.loaded ? "UNLOAD RAM" : "LOAD IN RAM",
                                  style: TextStyle(
                                    fontFamily: 'ShareTechMono',
                                    fontSize: 11,
                                    color: rt.loaded ? Colors.orangeAccent : Colors.greenAccent,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: rt.loaded ? Colors.orangeAccent : Colors.greenAccent),
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: rt.isBusy ? null : () => ModelLifecycle.instance.deleteWeights(),
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 15),
                                label: const Text(
                                  "DELETE WEIGHTS",
                                  style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.redAccent),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.7)),
                                  backgroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
              const Divider(color: Colors.white24, height: 24),
              ValueListenableBuilder<GhostVectorIndexState>(
                valueListenable: GhostVectorIndex.instance.state,
                builder: (context, idx, _) {
                  final isGemmaIdx = idx.engineId == EmbeddingGemmaService.nativeEngineId;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.hub, color: themeColor, size: 17),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "LIBRARY + LRC VECTOR INDEX",
                              style: TextStyle(
                                fontFamily: 'ShareTechMono',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            isGemmaIdx ? "GEMMA 256-D" : "N-GRAM 256-D",
                            style: TextStyle(
                              fontFamily: 'ShareTechMono',
                              fontSize: 10,
                              color: isGemmaIdx ? Colors.cyanAccent : Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "> ${idx.statusText}",
                        style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70),
                      ),
                      if (idx.isIndexing) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: idx.progress > 0 ? idx.progress : null,
                          minHeight: 4,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                        ),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _rebuildVectorIndex,
                        icon: Icon(
                          idx.isIndexing ? Icons.close : Icons.radar,
                          color: idx.isIndexing ? Colors.redAccent : themeColor,
                          size: 16,
                        ),
                        label: Text(
                          idx.isIndexing ? "CANCEL VECTOR INDEXING" : "INDEX LIBRARY + LRC LYRICS",
                          style: TextStyle(
                            fontFamily: 'ShareTechMono',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: idx.isIndexing ? Colors.redAccent : themeColor,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: idx.isIndexing ? Colors.redAccent : themeColor),
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: CyberBackdrop(
                  accentColor: themeColor,
                  variant: BackdropVariant.generic,
                  intensity: 0.80,
                ),
              ),
              SingleChildScrollView(
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
                    color: Colors.black.withValues(alpha: 0.82),
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
                      const Divider(color: Colors.white12, height: 16),
                      ValueListenableBuilder<bool>(
                        valueListenable: FeedbackSettings.backdrop,
                        builder: (context, v, _) => SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text("ANIMATED CYBER BACKDROP", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                          subtitle: const Text("themed cyberpunk scene art + live GPU shader", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                          value: v,
                          activeThumbColor: themeColor,
                          onChanged: (x) => FeedbackSettings.setBackdrop(x),
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: FeedbackSettings.backdropIntensity,
                        builder: (context, intensity, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("BACKDROP INTENSITY", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                                Text("${(intensity * 100).round()}%", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
                              ],
                            ),
                            Slider(
                              value: intensity.clamp(0.20, 1.50),
                              min: 0.20,
                              max: 1.50,
                              divisions: 26,
                              activeColor: themeColor,
                              inactiveColor: Colors.white24,
                              onChanged: (val) => FeedbackSettings.setBackdropIntensity(val, persist: false),
                              onChangeEnd: (val) => FeedbackSettings.setBackdropIntensity(val, persist: true),
                            ),
                          ],
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

                _buildEmbeddingGemmaCard(themeColor),

                const SizedBox(height: 40),
                const Divider(color: Colors.white24),
                const SizedBox(height: 24),

                const Text("> GHOST TUTORIAL", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                const SizedBox(height: 8),
                const Text("CYBERPUNK GHOST AVATAR TUTORIAL CHATBOT. CODE-DRAWN GLITCH GHOST WITH CONTEXTUAL HELP.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: GhostSettings.visible,
                        builder: (context, v, _) => SwitchListTile(
                          title: const Text("GHOST VISIBLE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                          subtitle: const Text("Show ghost avatar overlay", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                          activeThumbColor: Colors.purpleAccent,
                          activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                          value: v,
                          onChanged: (val) => GhostSettings.setVisible(val),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: GhostSettings.autoExpand,
                        builder: (context, v, _) => SwitchListTile(
                          title: const Text("AUTO EXPAND", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                          subtitle: const Text("Auto-expand on first launch", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                          activeThumbColor: Colors.purpleAccent,
                          activeTrackColor: Colors.purpleAccent.withValues(alpha: 0.3),
                          value: v,
                          onChanged: (val) => GhostSettings.setAutoExpand(val),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: GhostSettings.reduceMotion,
                  builder: (context, v, _) => SwitchListTile(
                    title: const Text("REDUCE MOTION (GLOBAL)", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                    subtitle: const Text("Disables ghost glitch/wobble/scanlines — also ambient backdrop / rain effects", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                    activeThumbColor: Colors.redAccent,
                    activeTrackColor: Colors.redAccent.withValues(alpha: 0.3),
                    value: v,
                    onChanged: (val) => GhostSettings.setReduceMotion(val),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await GhostSettings.clearFirstLaunchComplete();
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
            ],
          ),
        );
      }
    );
  }
}