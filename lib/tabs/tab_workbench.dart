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
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import '../core/ffmpeg_executor.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import '../core/media_probe.dart';
import '../core/pcm_recorder.dart';
import '../core/tap_feedback.dart';
import '../core/cyber_tap_feedback.dart';
import '../screens/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/waveform_studio.dart';
import '../core/whisper_model.dart';

class TabWorkbench extends StatefulWidget {
  const TabWorkbench({super.key});

  @override
  State<TabWorkbench> createState() => _TabWorkbenchState();
}

class _TabWorkbenchState extends State<TabWorkbench> {
  static const MethodChannel _storageChannel = MethodChannel('com.sovereign.tagger/storage');
  
  late final PlayerController _waveController;
  late final RecorderController _recorderController;

  String _selectedFilePath = "";
  String _statusMessage = "System Idle. Awaiting Media Or Mic Input.";
  bool _isProcessing = false;
  double _opProgress = 0.0;
  bool _isRecording = false;
  StreamSubscription<int>? _ampSub;
  final List<double> _wavePeaks = [];

  String _selectedOperation = "Extract Audio (Video to MP3)";
  String _targetFormat = "mp3";

  final TextEditingController _startCtrl = TextEditingController(text: "00:00:00");
  final TextEditingController _endCtrl = TextEditingController(text: "00:00:15");

  double _audioSpeed = 1.00;
  double _reverbIntensity = 0.0;
  bool _isReversed = false;

  String _sampleRate = "Source";
  int _bitDepth = 16;
  bool _twoPassLoudnorm = false;
  double _fadeInSec = 0.0;
  double _fadeOutSec = 0.0;
  bool _pcmLossless = true;
  bool _silenceAtStart = false;
  double _silenceSec = 2.0;
  double _xfadeSec = 3.0;
  double _deessIntensity = 0.5;
  double _limitLevel = 0.9;
  double _toneFreq = 440.0;
  double _toneDurSec = 5.0;
  String _toneType = "SINE";
  String _secondFilePath = "";
  int? _wbDurationMs;

  String _pitchMode = "VARISPEED (pitch+tempo)";
  String _normMode = "TWO-PASS LOUDNORM";
  double _eqBass = 0.0;
  double _eqLowMid = 0.0;
  double _eqMid = 0.0;
  double _eqHighMid = 0.0;
  double _eqTreble = 0.0;
  double _compRatio = 4.0;
  String _lufsReport = "";
  String _whisperReport = "";
  String _whisperLanguage = "en";
  String _replayGainReport = "";
  final List<double> _eq15Bands = List.filled(15, 0.0);
  static const List<int> _eq15Freqs = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

  static const List<String> _preservedContainers = ['mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus'];

  String _audioCodecArgs(String container) {
    switch (container) {
      case 'flac':
        return _bitDepth == 24 ? '-c:a flac -sample_fmt s32' : '-c:a flac';
      case 'wav':
        return _bitDepth == 24 ? '-c:a pcm_s24le' : '-c:a pcm_s16le';
      case 'm4a':
        return '-c:a aac -b:a 256k';
      case 'ogg':
        return '-c:a libvorbis -q:a 6';
      case 'opus':
        return '-c:a libopus -b:a 256k';
      default:
        return '-c:a libmp3lame -b:a 320k';
    }
  }

  String _resampleFilter() {
    if (_sampleRate == "Source") return "";
    return "aresample=$_sampleRate:resampler=soxr";
  }

  String _fmtHms(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }

  Widget _eqRow(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            Text("${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
          ],
        ),
        Slider(
          value: value, min: -12, max: 12, divisions: 24,
          activeColor: color, inactiveColor: Colors.white24,
          onChanged: _isProcessing ? null : onChanged,
        ),
      ],
    );
  }

  Map<String, String>? _parseLoudnormMeasurements(String output) {
    try {
      final matches = RegExp(r'\{[^{}]*"input_i"[^{}]*\}').allMatches(output);
      if (matches.isEmpty) return null;
      final last = matches.last.group(0)!;
      final decoded = jsonDecode(last);
      if (decoded is Map<String, dynamic> && decoded.containsKey('input_i')) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ""));
      }
    } catch (_) {
      try {
        final start = output.lastIndexOf('{');
        final end = output.lastIndexOf('}');
        if (start >= 0 && end > start) {
          final decoded = jsonDecode(output.substring(start, end + 1));
          if (decoded is Map<String, dynamic> && decoded.containsKey('input_i')) {
            return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ""));
          }
        }
      } catch (_) {}
    }
    return null;
  }

  final List<String> _operations = [
    "Extract Audio (Video to MP3)",
    "Clip Media (The Scalpel)",
    "Convert Format",
    "Normalize Audio (LUFS -14)",
    "Granular Audio DSP (Speed/Reverb)",
    "Apply Fades",
    "Fold To Mono",
    "Trim Silence",
    "AI Denoise (afftdn)",
    "Parametric EQ",
    "Compress Dynamics",
    "15-Band Equalizer (AutoEq)",
    "Scan ReplayGain (EBU R128)",
    "Transcribe (Whisper AI)",
    "Insert Silence",
    "Delete Region",
    "Mix With File",
    "Crossfade Join",
    "Click/Pop Repair (adeclick)",
    "De-Esser",
    "Limiter",
    "Multiband Compress (mcompand)",
    "DC/Rumble Fix (highpass)",
    "Tone Generator (Test Signals)",
    "Spectrogram Snapshot"
  ];

  final List<String> _formats = ["mp3", "wav", "flac", "ogg", "m4a"];

  Future<void> _scanLufs() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _lufsReport = "Scanning EBU R128 Integrated Loudness..."; });
    try {
      final session = await FFmpegExecutor.execute('-y -i "$_selectedFilePath" -af ebur128 -f null -');
      final output = session.getOutput() ?? "";
      final match = RegExp(r'I:\s*(-?\d+\.?\d*)\s*LUFS').firstMatch(output);
      if (!mounted) return;
      if (match != null) {
        final lufs = match.group(1);
        final delta = (-14.0 - (double.tryParse(lufs ?? "") ?? 0.0));
        setState(() => _lufsReport = "Integrated: $lufs LUFS • Suggested Gain To -14: ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} dB");
      } else {
        setState(() => _lufsReport = "Scan Complete. No Integrated Reading Parsed (check source).");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lufsReport = "ERR: LUFS Scan Fault: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _scanReplayGain() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _replayGainReport = "Scanning ReplayGain (EBU R128)..."; });
    try {
      final session = await FFmpegExecutor.execute('-y -i "$_selectedFilePath" -af ebur128 -f null -');
      final output = session.getOutput() ?? "";
      
      // Parse EBU R128 output for ReplayGain values
      double? trackGain;
      double? trackPeak;
      double? albumGain;
      double? albumPeak;
      
      // Look for integrated loudness (used for track gain calculation)
      final integratedMatch = RegExp(r'I:\s*(-?\d+\.?\d*)\s*LUFS').firstMatch(output);
      if (integratedMatch != null) {
        final integrated = double.tryParse(integratedMatch.group(1) ?? "") ?? 0.0;
        trackGain = -14.0 - integrated; // Target -14 LUFS
      }
      
      // Look for true peak
      final truePeakMatch = RegExp(r'TP:\s*(-?\d+\.?\d*)\s*LUFS').firstMatch(output);
      if (truePeakMatch != null) {
        final tp = double.tryParse(truePeakMatch.group(1) ?? "") ?? 0.0;
        trackPeak = pow(10.0, tp / 20.0).toDouble(); // Convert dBTP to linear
      }
      
      // For album gain/peak, we'd need multiple files - use track values as fallback
      albumGain = trackGain;
      albumPeak = trackPeak;

      if (!mounted) return;
      if (trackGain != null && trackPeak != null) {
        final tg = trackGain;
        final tp = trackPeak;
        final ag = albumGain!;
        final ap = albumPeak!;
        _replayGainReport = "Track Gain: ${tg.toStringAsFixed(2)} dB\nTrack Peak: ${tp.toStringAsFixed(6)}\nAlbum Gain: ${ag.toStringAsFixed(2)} dB\nAlbum Peak: ${ap.toStringAsFixed(6)}";

        // Write tags via id3 channel
        const id3Channel = MethodChannel('com.sovereign.tagger/id3');
        final metadata = <String, String>{
          'REPLAYGAIN_TRACK_GAIN': '${tg.toStringAsFixed(2)} dB',
          'REPLAYGAIN_TRACK_PEAK': tp.toStringAsFixed(6),
          'REPLAYGAIN_ALBUM_GAIN': '${ag.toStringAsFixed(2)} dB',
          'REPLAYGAIN_ALBUM_PEAK': ap.toStringAsFixed(6),
        };
        
        try {
          await id3Channel.invokeMethod('writeTags', {'filePath': _selectedFilePath, 'metadata': metadata});
          setState(() => _replayGainReport = "TAGS WRITTEN ✓\n$_replayGainReport");
        } catch (e) {
          setState(() => _replayGainReport = "Scan Complete (Tag Write Failed: $e)\n$_replayGainReport");
        }
      } else {
        setState(() => _replayGainReport = "Scan Complete. No ReplayGain Values Parsed.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _replayGainReport = "ERR: ReplayGain Scan Fault: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _waveController = PlayerController();
    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 48000
      ..bitRate = 256000
      ..updateFrequency = const Duration(milliseconds: 50);
  }

  @override
  void dispose() {
    _ampSub?.cancel();    _waveController.dispose();
    _recorderController.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _startAmpStream() {
    _ampSub?.cancel();
    _wavePeaks.clear();
    _ampSub = PcmRecorder.amplitudes().listen((peak) {
      if (!mounted) return;
      setState(() {
        _wavePeaks.add(peak / 32767.0);
        if (_wavePeaks.length > 48) _wavePeaks.removeAt(0);
      });
    });
  }

  void _stopAmpStream() {
    _ampSub?.cancel();
    _ampSub = null;
    if (mounted) setState(() => _wavePeaks.clear());
  }

  Duration _parseHmsSafe(String s, {bool fallbackFull = false}) {
    final p = s.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    if (fallbackFull && p[0] == 0 && p[1] == 0 && p[2] == 0) {
      return Duration(milliseconds: _wbDurationMs ?? 0);
    }
    return Duration(hours: p[0], minutes: p[1], seconds: p[2]);
  }

  Future<void> _pickSecondFile() async {
    if (_isProcessing || _isRecording) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        if (!mounted) return;
        setState(() => _secondFilePath = result.files.single.path!);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: Second Picker Fault: ${e.message}");
    } catch (_) {}
  }

  Future<void> _generateTone() async {
    setState(() { _isProcessing = true; _statusMessage = "Synthesizing Test Signal..."; });
    try {
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final outPath = "$tempDir/tone_${DateTime.now().millisecondsSinceEpoch}.wav";
      final d = _toneDurSec.toStringAsFixed(2);
      final input = _toneType == "SINE"
          ? "sine=frequency=${_toneFreq.round()}:duration=$d:sample_rate=48000"
          : "anoisesrc=color=${_toneType == 'WHITE NOISE' ? 'white' : 'pink'}:duration=$d:sample_rate=48000:amplitude=0.6";
      await FFmpegExecutor.execute('-y -f lavfi -i "$input" -c:a pcm_s16le "$outPath"');
      String note = "Tone Generated + Mounted For DSP.";
      try {
        await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': 'Machine Tone ${_toneFreq.round()}Hz'});
        note = "Test Signal Injected To Music Vault + Mounted.";
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _statusMessage = note;
        _selectedFilePath = outPath;
        _wbDurationMs = (_toneDurSec * 1000).round();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: Tone Fault: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickFile() async {
    if (_isProcessing || _isRecording) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);

      if (result != null && result.files.single.path != null) {
        if (!mounted) return;
        final path = result.files.single.path!;
        final dur = await probeDurationMs(path);
        if (!mounted) return;
        setState(() {
          _selectedFilePath = path;
          _wbDurationMs = dur;
          _statusMessage = "Media Mounted: ${path.split('/').last}";
        });
        if (_selectedOperation == "Clip Media (The Scalpel)" && !_selectedFilePath.endsWith('mp4')) {
          await _waveController.preparePlayer(path: _selectedFilePath);
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: File Picker Fault: ${e.message}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: Picker Fault: $e");
    }
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;

    if (_pcmLossless) {
      if (_isRecording) {
        _stopAmpStream();
        final path = await PcmRecorder.stop();
        if (path != null) {
          String exportedNote = "";
          try {
            await _storageChannel.invokeMethod('addToMediaStore', {'filePath': path, 'title': "Sovereign Recording ${DateTime.now().month}-${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute}"});
            exportedNote = "Exported To Music Vault.";
          } catch (_) {
            exportedNote = "MediaStore Export Fault — Copy Retained In Cache.";
          }
          if (!mounted) return;
          final recDur = await probeDurationMs(path);
          if (!mounted) return;
          setState(() {
            _isRecording = false;
            _selectedFilePath = path;
            _wbDurationMs = recDur;
            _statusMessage = "Lossless PCM Secured (48k/16-bit WAV). $exportedNote Mounted For DSP.";
          });
          if (_selectedOperation == "Clip Media (The Scalpel)") {
            try { await _waveController.preparePlayer(path: _selectedFilePath); } catch (_) {}
          }
        } else {
          if (!mounted) return;
          setState(() {
            _isRecording = false;
            _statusMessage = "ERR: PCM Stop Fault.";
          });
        }
      } else {
        try {
          bool hasPerm = await PcmRecorder.hasPermission();
          if (!hasPerm) {
            hasPerm = await _recorderController.checkPermission();
          }
          if (!hasPerm) {
            if (!mounted) return;
            setState(() => _statusMessage = "ERR: Microphone Access Denied.");
            return;
          }
          final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
          final recordPath = "$tempDir/studio_lossless_${DateTime.now().millisecondsSinceEpoch}.wav";
          final ok = await PcmRecorder.start(path: recordPath, sampleRate: 48000, channels: 1);
          if (!mounted) return;
          if (ok) {
            setState(() {
              _isRecording = true;
              _statusMessage = "PCM ARMED — 48k/16-bit LOSSLESS. Capturing...";
            });
            _startAmpStream();
          } else {
            setState(() => _statusMessage = "ERR: PCM Engine Failed To Arm.");
          }
        } catch (e) {
          if (!mounted) return;
          setState(() => _statusMessage = "ERR: PCM Fault: $e");
        }
      }
      return;
    }

    if (_isRecording) {
      final path = await _recorderController.stop();
      if (path != null) {
        String exportedNote = "";
        try {
          await _storageChannel.invokeMethod('addToMediaStore', {'filePath': path, 'title': "Sovereign Recording ${DateTime.now().month}-${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute}"});
          exportedNote = "Exported To Music Vault.";
        } catch (_) {
          exportedNote = "MediaStore Export Fault — Copy Retained In Cache.";
        }
        if (!mounted) return;
        final recDur = await probeDurationMs(path);
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _selectedFilePath = path;
          _wbDurationMs = recDur;
          _statusMessage = "Recording Secured. $exportedNote Mounted For DSP.";
        });
        if (_selectedOperation == "Clip Media (The Scalpel)") {
          await _waveController.preparePlayer(path: _selectedFilePath);
        }
      }
    } else {
      try {
        final hasPermission = await _recorderController.checkPermission();
        if (hasPermission) {
          final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
          final recordPath = "$tempDir/studio_record_${DateTime.now().millisecondsSinceEpoch}.m4a";
          
          await _recorderController.record(path: recordPath);

          if (!mounted) return;
          setState(() {
            _isRecording = true;
            _statusMessage = "Mic Active. Injecting Audio Stream...";
          });
        } else {
          if (!mounted) return;
          setState(() => _statusMessage = "ERR: Microphone Access Denied.");
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _statusMessage = "ERR: Recorder Fault: $e");
      }
    }
  }

  Future<void> _executeWhisper() async {
    try {
      setState(() { _isProcessing = true; _statusMessage = "Whisper: Locating Model Payload..."; _opProgress = 0.0; });

      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      File modelFile;
      try {
        modelFile = await WhisperModel.ensure(onProgress: (stage, p) {
          if (!mounted) return;
          setState(() {
            _opProgress = p;
            _statusMessage = "Whisper: $stage (141MB, first run only) ${(p * 100).toStringAsFixed(0)}%...";
          });
        });
      } catch (e) {
        if (!mounted) return;
        setState(() { _isProcessing = false; _statusMessage = "ERR: Whisper Model Unavailable: $e\n\nConnect to the internet and run Transcribe again — the model downloads once (141MB) from huggingface.co."; });
        return;
      }

      final srtPath = "$tempDir/whisper_${DateTime.now().millisecondsSinceEpoch}.srt";
      setState(() { _statusMessage = "Whisper: Transcribing (${_whisperLanguage.toUpperCase()}, base.en)..."; _opProgress = 0.0; });
      final durationMs = await probeDurationMs(_selectedFilePath);

      final session = await FFmpegExecutor.execute(
        '-y -i "$_selectedFilePath" -vn -af "whisper=model=${modelFile.path}:language=$_whisperLanguage:destination=$srtPath:format=srt" -f null -',
        onStatistics: (stats) {
          if (durationMs == null || durationMs <= 0 || !mounted) return;
          setState(() => _opProgress = (stats.time / durationMs).clamp(0.0, 1.0));
        },
      );

      if (ReturnCode.isSuccess(session.getReturnCode()) && File(srtPath).existsSync()) {
        final srtText = await File(srtPath).readAsString();
        final preview = srtText.length > 220 ? "${srtText.substring(0, 220)}..." : srtText;

        final srcParts = _selectedFilePath.split('/');
        final srcName = srcParts.last;
        final dot = srcName.lastIndexOf('.');
        final baseName = dot > 0 ? srcName.substring(0, dot) : srcName;
        final sidecarPath = "${_selectedFilePath.substring(0, _selectedFilePath.lastIndexOf('/'))}/$baseName.srt";
        try { File(srtPath).copySync(sidecarPath); } catch (_) {}

        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _statusMessage = "Transcription Secured:\n$sidecarPath\n\nPREVIEW:\n$preview";
        });
      } else {
        setState(() => _statusMessage = "Whisper Fault. Pulling On-Device Filter Documentation...");
        final docsSession = await FFmpegExecutor.execute('-hide_banner -h filter=whisper');
        final docs = docsSession.getOutput() ?? "";
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _whisperReport = docs.isEmpty ? "(no docs returned — filter may take different name)" : docs;
          _statusMessage = "ERR: Whisper Command Failed. Real Filter Syntax Captured Below.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isProcessing = false; _statusMessage = "ERR: Whisper Fault: $e"; });
    }
  }

  Future<void> _executeOperation() async {
    if (_selectedOperation == "Tone Generator (Test Signals)") {
      await _generateTone();
      return;
    }
    if (_selectedFilePath.isEmpty || _isRecording) return;
    if (_selectedOperation == "Transcribe (Whisper AI)") {
      await _executeWhisper();
      return;
    }
    if (_selectedOperation == "Scan ReplayGain (EBU R128)") {
      await _scanReplayGain();
      return;
    }
    setState(() { _isProcessing = true; _statusMessage = "Allocating FFmpeg Resources..."; });

    try {
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final durationMs = await probeDurationMs(_selectedFilePath);

      final parts = _selectedFilePath.split('.');
      final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";
      final isVideoSrc = ['mp4', 'mkv', 'webm'].contains(srcExt);
      final bool preserveOp = ["Normalize Audio (LUFS -14)", "Granular Audio DSP (Speed/Reverb)", "Apply Fades", "Fold To Mono", "Trim Silence", "AI Denoise (afftdn)", "Parametric EQ", "Compress Dynamics", "15-Band Equalizer (AutoEq)", "Insert Silence", "Delete Region", "Click/Pop Repair (adeclick)", "De-Esser", "Limiter", "Multiband Compress (mcompand)", "DC/Rumble Fix (highpass)"].contains(_selectedOperation);

      String ext;
      if (_selectedOperation == "Spectrogram Snapshot") {
        ext = "png";
      } else if (_selectedOperation == "Clip Media (The Scalpel)") {
        ext = srcExt.isEmpty ? "mp4" : srcExt;
      } else if (_selectedOperation == "Convert Format") {
        ext = _targetFormat;
      } else if (_selectedOperation == "Extract Audio (Video to MP3)") {
        ext = "mp3";
      } else {
        ext = _preservedContainers.contains(srcExt) ? srcExt : "flac";
      }

      final outPath = "$tempDir/workbench_$timestamp.$ext";
      String command = "";

      if (_selectedOperation == "Clip Media (The Scalpel)") {
        final timeFmt = RegExp(r'^\d{1,2}:\d{2}:\d{2}$');
        final startText = _startCtrl.text.trim();
        final endText = _endCtrl.text.trim();
        if (!timeFmt.hasMatch(startText) || !timeFmt.hasMatch(endText)) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: Clip Bounds Must Be HH:MM:SS."; });
          return;
        }
        Duration parseHms(String s) {
          final p = s.split(':').map((e) => int.parse(e)).toList();
          return Duration(hours: p[0], minutes: p[1], seconds: p[2]);
        }
        final start = parseHms(startText);
        final end = parseHms(endText);
        if (end <= start) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: END Must Exceed START."; });
          return;
        }
        if (durationMs != null && end.inMilliseconds > durationMs + 500) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: END Exceeds Source Duration (${_fmtHms(Duration(milliseconds: durationMs))})."; });
          return;
        }
        if (isVideoSrc) {
          if (start > Duration.zero) {
            command = '-y -ss $startText -i "$_selectedFilePath" -t ${_fmtHms(end - start)} -c copy -avoid_negative_ts make_zero "$outPath"';
          } else {
            command = '-y -i "$_selectedFilePath" -to $endText -c copy -avoid_negative_ts make_zero "$outPath"';
          }
        } else {
          command = '-y -i "$_selectedFilePath" -ss $startText -to $endText -c copy "$outPath"';
        }
      } else if (_selectedOperation == "Spectrogram Snapshot") {
        command = '-y -i "$_selectedFilePath" -lavfi "showspectrogrampic=s=1280x720:legend=1" -frames:v 1 "$outPath"';
      } else if (_selectedOperation == "Mix With File") {
        if (_secondFilePath.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MOUNT SECOND MEDIA FIRST."; });
          return;
        }
        command = '-y -i "$_selectedFilePath" -i "$_secondFilePath" -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:normalize=0" ${_audioCodecArgs(ext)} "$outPath"';
      } else if (_selectedOperation == "Crossfade Join") {
        if (_secondFilePath.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MOUNT SECOND MEDIA FIRST."; });
          return;
        }
        command = '-y -i "$_selectedFilePath" -i "$_secondFilePath" -filter_complex "[0:a][1:a]acrossfade=d=${_xfadeSec.toStringAsFixed(2)}:c1=tri:c2=tri" ${_audioCodecArgs(ext)} "$outPath"';
      } else if (_selectedOperation == "Extract Audio (Video to MP3)") {
        command = '-y -i "$_selectedFilePath" -vn -c:a libmp3lame -b:a 320k "$outPath"';
      } else if (_selectedOperation == "Convert Format") {
        command = '-y -i "$_selectedFilePath" -vn ${_audioCodecArgs(_targetFormat)} "$outPath"';
      } else if (preserveOp) {
        List<String> filters = [];
        final resampleFilter = _resampleFilter();
        if (resampleFilter.isNotEmpty) filters.add(resampleFilter);

        String? loudnormFilter;
        if (_selectedOperation == "Normalize Audio (LUFS -14)") {
          if (_normMode == "DYNAMIC (dynaudnorm)") {
            loudnormFilter = 'dynaudnorm=p=0.9:m=12';
          } else {
            loudnormFilter = 'loudnorm=I=-14:LRA=11:TP=-1.5';
            if (_twoPassLoudnorm) {
              setState(() => _statusMessage = "LOUDNORM PASS 1/2: ANALYZING...");
              final analysisCmd = '-y -i "$_selectedFilePath" -af "loudnorm=I=-14:LRA=11:TP=-1.5:print_format=json" -f null -';
              final pass1 = await FFmpegExecutor.execute(analysisCmd);
              final measured = _parseLoudnormMeasurements(pass1.getOutput() ?? "");
              if (measured != null) {
                loudnormFilter = 'loudnorm=I=-14:LRA=11:TP=-1.5:measured_I=${measured['input_i']}:measured_LRA=${measured['input_lra']}:measured_TP=${measured['input_tp']}:measured_thresh=${measured['input_thresh']}:offset=${measured['target_offset']}:linear=true';
              } else {
                setState(() => _statusMessage = "WARN: Pass-1 Analysis Unreadable. Falling Back To Single-Pass.");
              }
            }
          }
        }

        switch (_selectedOperation) {
          case "Apply Fades":
            if (durationMs == null) {
              setState(() { _isProcessing = false; _statusMessage = "ERR: Cannot Determine Duration For Fade Out Point."; });
              return;
            }
            final totalSec = durationMs / 1000.0;
            if (_fadeInSec > 0) filters.add("afade=t=in:st=0:d=${_fadeInSec.toStringAsFixed(2)}");
            if (_fadeOutSec > 0) {
              final outStart = (totalSec - _fadeOutSec).clamp(0.0, totalSec).toStringAsFixed(2);
              filters.add("afade=t=out:st=$outStart:d=${_fadeOutSec.toStringAsFixed(2)}");
            }
            break;
          case "Fold To Mono":
            filters.add("pan=mono|c0=0.5*c0+0.5*c1");
            break;
          case "Insert Silence": {
            final ms = (_silenceSec * 1000).round();
            filters.add(_silenceAtStart ? "adelay=$ms:all=1" : "apad=pad_dur=${_silenceSec.toStringAsFixed(2)}");
            break;
          }
          case "Delete Region": {
            final sSec = _parseHmsSafe(_startCtrl.text).inMilliseconds / 1000.0;
            final eSec = _parseHmsSafe(_endCtrl.text).inMilliseconds / 1000.0;
            if (eSec <= sSec) {
              setState(() { _isProcessing = false; _statusMessage = "ERR: END Must Exceed START (use wave selection)."; });
              return;
            }
            filters.add("aselect='not(between(t,$sSec,$eSec))',asetpts=N/SR/TB");
            break;
          }
          case "Click/Pop Repair (adeclick)":
            filters.add("adeclick");
            break;
          case "De-Esser":
            filters.add("deesser=i=${_deessIntensity.toStringAsFixed(2)}:m=0.5:f=0.5");
            break;
          case "Limiter":
            filters.add("alimiter=limit=${_limitLevel.toStringAsFixed(2)}:attack=5:release=50");
            break;
          case "Multiband Compress (mcompand)":
            filters.add("mcompand");
            break;
          case "DC/Rumble Fix (highpass)":
            filters.add("highpass=f=10");
            break;
          case "Trim Silence":
            filters.add("silenceremove=start_periods=1:start_duration=0.3:start_threshold=-45dB:stop_periods=-1:stop_duration=0.8:stop_threshold=-45dB");
            break;
          case "Granular Audio DSP (Speed/Reverb)":
            if (_isReversed) filters.add("areverse");
            if (_audioSpeed != 1.0) {
              final s = _audioSpeed.toStringAsFixed(2);
              switch (_pitchMode) {
                case "RUBBERBAND (pitch only)":
                  filters.add("rubberband=pitch=$s");
                  break;
                case "ATEMPO (tempo only)":
                  filters.add("atempo=${_audioSpeed.clamp(0.5, 2.0).toStringAsFixed(2)}");
                  break;
                default:
                  filters.add("asetrate=44100*$s,aresample=44100");
              }
            }
            if (_reverbIntensity > 0) {
              final delay = 60 + (_reverbIntensity * 40);
              final decay = 0.2 + (_reverbIntensity * 0.4);
              filters.add("aecho=0.8:0.88:$delay:$decay");
            }
            break;
          case "AI Denoise (afftdn)":
            filters.add("afftdn=nf=-25");
            break;
          case "Parametric EQ":
            if (_eqBass != 0) filters.add("bass=g=${_eqBass.toStringAsFixed(1)}:f=100");
            if (_eqLowMid != 0) filters.add("equalizer=f=320:t=q:w=1.2:g=${_eqLowMid.toStringAsFixed(1)}");
            if (_eqMid != 0) filters.add("equalizer=f=1000:t=q:w=1.2:g=${_eqMid.toStringAsFixed(1)}");
            if (_eqHighMid != 0) filters.add("equalizer=f=3500:t=q:w=1.2:g=${_eqHighMid.toStringAsFixed(1)}");
            if (_eqTreble != 0) filters.add("treble=g=${_eqTreble.toStringAsFixed(1)}:f=8000");
            if (filters.length <= (resampleFilter.isNotEmpty ? 1 : 0)) {
              setState(() { _isProcessing = false; _statusMessage = "ERR: All EQ Bands At Zero. Nothing To Apply."; });
              return;
            }
            break;
          case "Compress Dynamics":
            filters.add("acompressor=threshold=0.1:ratio=${_compRatio.toStringAsFixed(1)}:attack=50:release=500");
            break;
          case "15-Band Equalizer (AutoEq)":
            for (int i = 0; i < 15; i++) {
              if (_eq15Bands[i] != 0) {
                final freq = _eq15Freqs[i];
                filters.add("equalizer=f=$freq:t=q:w=1.2:g=${_eq15Bands[i].toStringAsFixed(1)}");
              }
            }
            if (filters.length <= (resampleFilter.isNotEmpty ? 1 : 0)) {
              setState(() { _isProcessing = false; _statusMessage = "ERR: All EQ Bands At Zero. Nothing To Apply."; });
              return;
            }
            break;
        }

        if (loudnormFilter != null) filters.insert(0, loudnormFilter);

        final filterChain = filters.isNotEmpty ? '-af "${filters.join(',')}"' : "";
        command = '-y -i "$_selectedFilePath" $filterChain -vn ${_audioCodecArgs(ext)} "$outPath"';
      }

      if (command.isEmpty) {
        setState(() { _isProcessing = false; _statusMessage = "ERR: NOTHING LOADED INTO THE MACHINE."; });
        return;
      }

      setState(() { _statusMessage = "Executing In The Machine: ${_selectedOperation.toUpperCase()}"; _opProgress = 0.0; });
      final session = await FFmpegExecutor.execute(command, onStatistics: (stats) {
        if (durationMs == null || durationMs <= 0 || !mounted) return;
        setState(() => _opProgress = (stats.time / durationMs).clamp(0.0, 1.0));
      });

      if (ReturnCode.isSuccess(session.getReturnCode())) {
        setState(() => _statusMessage = "Process Complete. Injecting To MediaStore...");
        final originalName = _selectedFilePath.split('/').last;
        final baseName = originalName.contains('.') ? originalName.substring(0, originalName.lastIndexOf('.')) : originalName;
        String payloadNote;
        try {
          final uriString = await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': "${baseName}_mod"});
          payloadNote = "Success. Payload Written To:\n$uriString";
          File(outPath).delete().ignore();
        } catch (_) {
          payloadNote = "Injected To Cache Only (MediaStore Fault):\n$outPath";
        }
        if (!mounted) return;
        TapFeedback.machineConfirm();
        setState(() { _isProcessing = false; _statusMessage = payloadNote; });
      } else {
        setState(() { _isProcessing = false; _statusMessage = "ERR: Kernel Panic. FFmpeg Segfault."; });
      }
    } catch (e) {
      setState(() { _isProcessing = false; _statusMessage = "Critical ERR: $e"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "THE SCALPEL & STUDIO",
                  style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2)
                ),
                const SizedBox(height: 8),
                const Text(
                  "DIRECT FFMPEG INJECTION // DSP MANIPULATION",
                  style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54, fontSize: 12)
                ),
                const SizedBox(height: 10),
                if (_isProcessing)
                  LinearProgressIndicator(
                    value: _opProgress > 0 ? _opProgress : null,
                    backgroundColor: Colors.black,
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                    minHeight: 3,
                  ),
                if (_isProcessing) const SizedBox(height: 8),
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
                const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: CyberTapFeedback(
                          enableHaptic: false,
                          enableAudio: false,
                          particleColor: themeColor,
                          ringColor: themeColor,
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing || _isRecording ? null : _pickFile,
                            icon: Icon(Icons.folder_open, color: themeColor),
                            label: Text("MOUNT MEDIA", style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: themeColor),
                              backgroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CyberTapFeedback(
                          enableHaptic: false,
                          enableAudio: false,
                          particleColor: Colors.redAccent,
                          ringColor: Colors.redAccent,
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _toggleRecording,
                            icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic, color: _isRecording ? Colors.redAccent : Colors.redAccent),
                            label: Text(_isRecording ? "HALT" : "REC", style: TextStyle(fontFamily: 'ShareTechMono', color: _isRecording ? Colors.redAccent : Colors.white70, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: _isRecording ? Colors.redAccent : Colors.white24),
                              backgroundColor: _isRecording ? Colors.redAccent.withAlpha(25) : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(color: Colors.black, border: Border.all(color: _pcmLossless ? themeColor.withAlpha(127) : Colors.white24)),
                    child: Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        title: Text("LOSSLESS PCM (48K WAV)", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: _pcmLossless ? themeColor : Colors.white70)),
                        subtitle: const Text("True 16-bit AudioRecord — highest quality, bypasses aac", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                        activeThumbColor: themeColor,
                        activeTrackColor: themeColor.withAlpha(76),
                        value: _pcmLossless,
                        onChanged: _isRecording ? null : (v) => setState(() => _pcmLossless = v),
                      ),
                    ),
                  ),
                
                  if (_isRecording) ...[
                    const SizedBox(height: 16),
                    if (_pcmLossless)
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.redAccent.withAlpha(127)),
                          boxShadow: [BoxShadow(color: Colors.redAccent.withAlpha(25), blurRadius: 8, spreadRadius: 2)],
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: CustomPaint(
                                size: Size(MediaQuery.of(context).size.width - 52, 88),
                                painter: _PcmWavePainter(_wavePeaks),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)),
                                  const SizedBox(width: 10),
                                  Text("PCM CAPTURING — 48k/16-bit LOSSLESS", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent.withValues(alpha: 0.9), fontWeight: FontWeight.bold, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.redAccent.withAlpha(127)),
                          boxShadow: [BoxShadow(color: Colors.redAccent.withAlpha(25), blurRadius: 8, spreadRadius: 2)],
                        ),
                        child: AudioWaveforms(
                          size: Size(MediaQuery.of(context).size.width, 100.0),
                          recorderController: _recorderController,
                          enableGesture: false,
                          waveStyle: const WaveStyle(
                            waveColor: Colors.redAccent,
                            extendWaveform: true,
                            showMiddleLine: true,
                            middleLineColor: Colors.redAccent,
                          ),
                        ),
                      ),
                  ],

                if (_selectedFilePath.isNotEmpty && !_isRecording) ...[
                  const SizedBox(height: 24),
                  WaveformStudio(
                    key: ValueKey(_selectedFilePath),
                    filePath: _selectedFilePath,
                    durationMs: _wbDurationMs ?? 0,
                    initialIn: _parseHmsSafe(_startCtrl.text),
                    initialOut: _parseHmsSafe(_endCtrl.text, fallbackFull: true),
                    onSelection: (selIn, selOut) {
                      setState(() {
                        _startCtrl.text = _fmtHms(selIn);
                        _endCtrl.text = _fmtHms(selOut);
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black, 
                      border: Border.all(color: themeColor.withAlpha(127))
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedOperation,
                        isExpanded: true,
                        dropdownColor: Colors.black,
                        icon: Icon(Icons.arrow_drop_down, color: themeColor),
                        items: _operations.map((String op) => DropdownMenuItem<String>(
                          value: op, 
                          child: Text(op.toUpperCase(), style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white))
                        )).toList(),
                        onChanged: _isProcessing || _isRecording ? null : (String? newValue) async {
                          if (newValue != null) {
                            setState(() => _selectedOperation = newValue);
                            if (newValue == "Clip Media (The Scalpel)" && !_selectedFilePath.endsWith('mp4')) {
                              await _waveController.preparePlayer(path: _selectedFilePath);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_selectedOperation == "Clip Media (The Scalpel)") ...[
                    if (!_selectedFilePath.endsWith('mp4'))
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black, 
                          border: Border.all(color: themeColor.withAlpha(76))
                        ),
                        child: Column(
                          children: [
                            AudioFileWaveforms(
                              size: Size(MediaQuery.of(context).size.width, 100.0),
                              playerController: _waveController,
                              enableSeekGesture: true,
                              waveformType: WaveformType.long,
                              playerWaveStyle: PlayerWaveStyle(
                                fixedWaveColor: Colors.white24,
                                liveWaveColor: themeColor,
                                spacing: 4,
                              ),
                            ),
                            StreamBuilder<PlayerState>(
                              stream: _waveController.onPlayerStateChanged,
                              builder: (context, snapshot) {
                                final isPlaying = snapshot.data == PlayerState.playing;
                                return IconButton(
                                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: themeColor, size: 36),
                                  onPressed: () async {
                                    isPlaying ? await _waveController.pausePlayer() : await _waveController.startPlayer();
                                    setState((){});
                                  },
                                );
                              }
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startCtrl, 
                            style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
                            decoration: InputDecoration(
                              labelText: 'START [HH:MM:SS]', 
                              labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withAlpha(76))),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                              filled: true,
                              fillColor: Colors.black,
                            ), 
                            enabled: !_isProcessing
                          )
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _endCtrl, 
                            style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
                            decoration: InputDecoration(
                              labelText: 'END [HH:MM:SS]', 
                              labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withAlpha(76))),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                              filled: true,
                              fillColor: Colors.black,
                            ), 
                            enabled: !_isProcessing
                          )
                        ),
                      ],
                    ),
                  ],

                  if (_selectedOperation == "Convert Format") ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black, 
                        border: Border.all(color: themeColor.withAlpha(127))
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _targetFormat,
                          isExpanded: true,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: _formats.map((String fmt) => DropdownMenuItem<String>(
                            value: fmt, 
                            child: Text("TARGET FORMAT: .$fmt", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white))
                          )).toList(),
                          onChanged: _isProcessing ? null : (String? newValue) {
                            if (newValue != null) setState(() => _targetFormat = newValue);
                          },
                        ),
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Normalize Audio (LUFS -14)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: themeColor.withAlpha(76)),
                      ),
                      child: Row(
                        children: [
                          const Text("MODE:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _normMode,
                                isExpanded: true,
                                dropdownColor: Colors.black,
                                icon: Icon(Icons.arrow_drop_down, color: themeColor),
                                items: const [
                                  DropdownMenuItem<String>(value: "TWO-PASS LOUDNORM", child: Text("TWO-PASS LOUDNORM (broadcast)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white))),
                                  DropdownMenuItem<String>(value: "DYNAMIC (dynaudnorm)", child: Text("DYNAMIC (dynaudnorm, windowed)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white))),
                                ],
                                onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _normMode = v); },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_normMode == "TWO-PASS LOUDNORM")
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: themeColor.withAlpha(76)),
                        ),
                        child: SwitchListTile(
                          title: const Text("TWO-PASS LOUDNORM", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                          subtitle: const Text("Analyze First. Maximum Precision.", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.white38, fontSize: 11)),
                          activeThumbColor: themeColor,
                          activeTrackColor: themeColor.withAlpha(76),
                          value: _twoPassLoudnorm,
                          onChanged: _isProcessing ? null : (val) => setState(() => _twoPassLoudnorm = val),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.cyanAccent.withAlpha(76)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _scanLufs,
                            icon: _isProcessing
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                : const Icon(Icons.graphic_eq, color: Colors.cyanAccent, size: 18),
                            label: const Text("SCAN LUFS (EBUR128)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                          if (_lufsReport.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text("> $_lufsReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70)),
],
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Scan ReplayGain (EBU R128)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.greenAccent.withAlpha(127)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("REPLAYGAIN SCANNER (EBU R128)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    const SizedBox(height: 6),
                    const Text("Analyzes integrated loudness and true peak per EBU R128. Writes REPLAYGAIN_* tags to file (TXXX frames). Target: -14 LUFS.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _scanReplayGain,
                      icon: _isProcessing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent))
                          : const Icon(Icons.volume_up, color: Colors.greenAccent, size: 18),
                      label: const Text("SCAN REPLAYGAIN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.greenAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                    if (_replayGainReport.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.greenAccent.withAlpha(76)),
                        ),
                        child: Text("> $_replayGainReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.3)),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Apply Fades") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: themeColor.withAlpha(127)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("FADE IN", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                              Text("${_fadeInSec.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            ],
                          ),
                          Slider(
                            value: _fadeInSec, min: 0, max: 10, divisions: 20,
                            activeColor: Colors.cyanAccent, inactiveColor: Colors.white24,
                            onChanged: _isProcessing ? null : (val) => setState(() => _fadeInSec = val),
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("FADE OUT", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                              Text("${_fadeOutSec.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            ],
                          ),
                          Slider(
                            value: _fadeOutSec, min: 0, max: 10, divisions: 20,
                            activeColor: Colors.purpleAccent, inactiveColor: Colors.white24,
                            onChanged: _isProcessing ? null : (val) => setState(() => _fadeOutSec = val),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Parametric EQ") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: themeColor.withAlpha(127)),
                      ),
                      child: Column(
                        children: [
                          _eqRow("BASS 100Hz", _eqBass, Colors.redAccent, (v) => setState(() => _eqBass = v)),
                          _eqRow("LOW-MID 320Hz", _eqLowMid, Colors.orangeAccent, (v) => setState(() => _eqLowMid = v)),
                          _eqRow("MID 1kHz", _eqMid, Colors.amberAccent, (v) => setState(() => _eqMid = v)),
                          _eqRow("HIGH-MID 3.5kHz", _eqHighMid, Colors.cyanAccent, (v) => setState(() => _eqHighMid = v)),
                          _eqRow("TREBLE 8kHz", _eqTreble, Colors.purpleAccent, (v) => setState(() => _eqTreble = v)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Compress Dynamics") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: themeColor.withAlpha(127)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("RATIO", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                              Text("${_compRatio.toStringAsFixed(1)}:1", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            ],
                          ),
                          Slider(
                            value: _compRatio, min: 1, max: 12, divisions: 22,
                            activeColor: Colors.tealAccent, inactiveColor: Colors.white24,
                            onChanged: _isProcessing ? null : (val) => setState(() => _compRatio = val),
                          ),
                          const Text("threshold -20dB • attack 50ms • release 500ms", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "15-Band Equalizer (AutoEq)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.purpleAccent.withAlpha(127)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("15-BAND PARAMETRIC EQ (AUTOEQ COMPATIBLE)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                          const SizedBox(height: 4),
                          const Text("Frequencies: 25, 40, 63, 100, 160, 250, 400, 630, 1k, 1.6k, 2.5k, 4k, 6.3k, 10k, 16k Hz. Q=1.2. SAVE PRESET syncs with the PLAYER tune-icon screen.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white54)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(15, (i) {
                              final freq = _eq15Freqs[i];
                              final label = freq >= 1000 ? "${(freq / 1000).toStringAsFixed(1)}k" : "$freq";
                              return SizedBox(
                                width: 70,
                                child: Column(
                                  children: [
                                    Text(label, style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: themeColor)),
                                    Slider(
                                      value: _eq15Bands[i], min: -12, max: 12, divisions: 24,
                                      activeColor: themeColor, inactiveColor: Colors.white24,
                                      onChanged: _isProcessing ? null : (val) => setState(() => _eq15Bands[i] = val),
                                    ),
                                    Text("${_eq15Bands[i] >= 0 ? '+' : ''}${_eq15Bands[i].toStringAsFixed(1)}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white)),
                                  ],
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _isProcessing ? null : () {
                                  SharedPreferences.getInstance().then((p) {
                                    for (int i = 0; i < 15; i++) {
                                      p.setDouble('eq15_band_$i', _eq15Bands[i]);
                                    }
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('> 15-BAND EQ PRESET SAVED TO KERNEL.', style: TextStyle(fontFamily: 'ShareTechMono')), backgroundColor: Colors.black, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.purpleAccent))));
                                },
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.purpleAccent), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                                child: const Text("SAVE PRESET", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _isProcessing ? null : () {
                                  setState(() {
                                    for (int i = 0; i < 15; i++) {
                                      _eq15Bands[i] = 0.0;
                                    }
                                  });
                                },
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                                child: const Text("FLAT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Insert Silence") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("INSERT AT START", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                            subtitle: const Text("off = append silence at end", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                            value: _silenceAtStart,
                            activeThumbColor: themeColor,
                            onChanged: _isProcessing ? null : (v) => setState(() => _silenceAtStart = v),
                          ),
                          Row(
                            children: [
                              const Text("LENGTH", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                              Expanded(
                                child: Slider(
                                  value: _silenceSec, min: 0.5, max: 30, divisions: 59,
                                  activeColor: themeColor,
                                  label: "${_silenceSec.toStringAsFixed(1)}s",
                                  onChanged: _isProcessing ? null : (v) => setState(() => _silenceSec = v),
                                ),
                              ),
                              Text("${_silenceSec.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Delete Region") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.redAccent.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("REGION TO ERASE (HH:MM:SS)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                          const SizedBox(height: 4),
                          const Text("Drag a selection on the WAVEFORM STUDIO above, or type bounds below.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: TextField(controller: _startCtrl, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.greenAccent), decoration: const InputDecoration(labelText: "IN", labelStyle: TextStyle(color: Colors.white38), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("→", style: TextStyle(color: Colors.white24))),
                              Expanded(child: TextField(controller: _endCtrl, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent), decoration: const InputDecoration(labelText: "OUT", labelStyle: TextStyle(color: Colors.white38), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Mix With File" || _selectedOperation == "Crossfade Join") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _pickSecondFile,
                            icon: const Icon(Icons.library_add, size: 18),
                            label: Text(_secondFilePath.isEmpty ? "MOUNT SECOND MEDIA" : "SECOND: ${_secondFilePath.split('/').last}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
                            style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(vertical: 10)),
                          ),
                          if (_selectedOperation == "Crossfade Join") ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text("XFADE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                                Expanded(
                                  child: Slider(
                                    value: _xfadeSec, min: 0.5, max: 15, divisions: 29,
                                    activeColor: themeColor,
                                    label: "${_xfadeSec.toStringAsFixed(1)}s",
                                    onChanged: _isProcessing ? null : (v) => setState(() => _xfadeSec = v),
                                  ),
                                ),
                                Text("${_xfadeSec.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "De-Esser") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Row(
                        children: [
                          const Text("INTENSITY", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                          Expanded(
                            child: Slider(
                              value: _deessIntensity, min: 0.1, max: 1.0, divisions: 18,
                              activeColor: themeColor,
                              label: "${(_deessIntensity * 100).round()}%",
                              onChanged: _isProcessing ? null : (v) => setState(() => _deessIntensity = v),
                            ),
                          ),
                          Text("${(_deessIntensity * 100).round()}%", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Limiter") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Row(
                        children: [
                          const Text("CEILING", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                          Expanded(
                            child: Slider(
                              value: _limitLevel, min: 0.2, max: 1.0, divisions: 16,
                              activeColor: themeColor,
                              label: _limitLevel.toStringAsFixed(2),
                              onChanged: _isProcessing ? null : (v) => setState(() => _limitLevel = v),
                            ),
                          ),
                          Text(_limitLevel.toStringAsFixed(2), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Tone Generator (Test Signals)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: "SINE", label: Text("SINE")),
                              ButtonSegment(value: "WHITE NOISE", label: Text("WHITE")),
                              ButtonSegment(value: "PINK NOISE", label: Text("PINK")),
                            ],
                            selected: {_toneType},
                            onSelectionChanged: _isProcessing ? null : (s) => setState(() => _toneType = s.first),
                            style: const ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.black)),
                          ),
                          const SizedBox(height: 8),
                          if (_toneType == "SINE")
                            Row(
                              children: [
                                const Text("FREQ", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                                Expanded(
                                  child: Slider(
                                    value: _toneFreq.clamp(20.0, 8000.0), min: 20, max: 8000, divisions: 159,
                                    activeColor: themeColor,
                                    label: "${_toneFreq.round()}Hz",
                                    onChanged: _isProcessing ? null : (v) => setState(() => _toneFreq = v),
                                  ),
                                ),
                                Text("${_toneFreq.round()}Hz", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          Row(
                            children: [
                              const Text("DURATION", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
                              Expanded(
                                child: Slider(
                                  value: _toneDurSec, min: 1, max: 30, divisions: 29,
                                  activeColor: themeColor,
                                  label: "${_toneDurSec.round()}s",
                                  onChanged: _isProcessing ? null : (v) => setState(() => _toneDurSec = v),
                                ),
                              ),
                              Text("${_toneDurSec.round()}s", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Transcribe (Whisper AI)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.greenAccent.withAlpha(127)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Text("LANGUAGE:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _whisperLanguage,
                                    isExpanded: true,
                                    dropdownColor: Colors.black,
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.greenAccent),
                                    items: const [
                                      DropdownMenuItem<String>(value: "en", child: Text("EN — English (base.en model)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white))),
                                      DropdownMenuItem<String>(value: "auto", child: Text("AUTO — detect (may need multilingual model)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white))),
                                    ],
                                    onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _whisperLanguage = v); },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text("Output: .srt sidecar next to source + text preview. First run extracts 141MB model to cache. CPU-heavy — expect ~real-time duration.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    ),
                    if (_whisperReport.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.orangeAccent.withAlpha(127)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(_whisperReport, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70, height: 1.3)),
                        ),
                      ),
                  ],

                  if (_selectedOperation != "Clip Media (The Scalpel)" && _selectedOperation != "Extract Audio (Video to MP3)") ...[
                    Builder(builder: (context) {
                      final pathParts = _selectedFilePath.split('.');
                      final srcE = pathParts.length > 1 ? pathParts.last.toLowerCase() : "";
                      final effExt = _selectedOperation == "Convert Format"
                          ? _targetFormat
                          : (_preservedContainers.contains(srcE) ? srcE : "flac");
                      final losslessOut = ['wav', 'flac'].contains(effExt);
                      return Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.amberAccent.withAlpha(76)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("MASTERING QUALITY", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text("RESAMPLE:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _sampleRate,
                                      isExpanded: true,
                                      dropdownColor: Colors.black,
                                      icon: const Icon(Icons.arrow_drop_down, color: Colors.amberAccent),
                                      items: ["Source", "44100", "48000", "96000"].map((r) => DropdownMenuItem<String>(
                                        value: r,
                                        child: Text(r == "Source" ? "SOURCE RATE (soxr off)" : "$r Hz (soxr)", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.white)),
                                      )).toList(),
                                      onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _sampleRate = v); },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (losslessOut) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text("BIT DEPTH:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _isProcessing ? null : () => setState(() => _bitDepth = 16),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: _bitDepth == 16 ? Colors.amberAccent : Colors.white24),
                                              backgroundColor: _bitDepth == 16 ? Colors.amberAccent.withValues(alpha: 0.15) : Colors.transparent,
                                            ),
                                            child: const Text("16-BIT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _isProcessing ? null : () => setState(() => _bitDepth = 24),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: _bitDepth == 24 ? Colors.amberAccent : Colors.white24),
                                              backgroundColor: _bitDepth == 24 ? Colors.amberAccent.withValues(alpha: 0.15) : Colors.transparent,
                                            ),
                                            child: const Text("24-BIT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white70)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],

                  if (_selectedOperation == "Granular Audio DSP (Speed/Reverb)") ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.purpleAccent.withAlpha(127)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("TEMPO / PITCH WARP", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                              Text("${_audioSpeed.toStringAsFixed(2)}x", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            ],
                          ),
                          Slider(
                            value: _audioSpeed, min: 0.5, max: 2.0, divisions: 30,
                            activeColor: Colors.purpleAccent, inactiveColor: Colors.white24,
                            onChanged: _isProcessing ? null : (val) => setState(() => _audioSpeed = val),
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            children: [
                              const Text("MODE:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _pitchMode,
                                    isExpanded: true,
                                    dropdownColor: Colors.black,
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.purpleAccent),
                                    items: const [
                                      DropdownMenuItem<String>(value: "VARISPEED (pitch+tempo)", child: Text("VARISPEED — asetrate (pitch+tempo)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white))),
                                      DropdownMenuItem<String>(value: "RUBBERBAND (pitch only)", child: Text("RUBBERBAND — pitch only, formant-safe", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white))),
                                      DropdownMenuItem<String>(value: "ATEMPO (tempo only)", child: Text("ATEMPO — tempo only, pitch-safe", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white))),
                                    ],
                                    onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _pitchMode = v); },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("SPATIAL REVERB", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                              Text("${(_reverbIntensity * 100).toInt()}%", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                            ],
                          ),
                          Slider(
                            value: _reverbIntensity, min: 0.0, max: 1.0, divisions: 20,
                            activeColor: Colors.cyanAccent, inactiveColor: Colors.white24,
                            onChanged: _isProcessing ? null : (val) => setState(() => _reverbIntensity = val),
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          SwitchListTile(
                            title: const Text("INVERT WAVEFORM (REVERSE)", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.redAccent)),
                            activeThumbColor: Colors.redAccent,
                            activeTrackColor: Colors.redAccent.withAlpha(76),
                            inactiveThumbColor: Colors.white54,
                            inactiveTrackColor: Colors.white12,
                            value: _isReversed,
                            onChanged: _isProcessing ? null : (val) => setState(() => _isReversed = val),
                          )
                        ],
                      ),
                    )
                  ],

                  const SizedBox(height: 32),
                  CyberTapFeedback(
                    enableHaptic: false,
                    enableAudio: false,
                    particleColor: themeColor,
                    ringColor: themeColor,
                    particleCount: 16,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing || _isRecording ? null : _executeOperation,
                      icon: const Icon(Icons.bolt, color: Colors.black),
                      label: const Text("EXECUTE ON THE MACHINE", style: TextStyle(fontFamily: 'ShareTechMono', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: themeColor,
                        disabledBackgroundColor: themeColor.withAlpha(51),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        );
      }
    );
  }
}
class _PcmWavePainter extends CustomPainter {
  final List<double> peaks;
  _PcmWavePainter(this.peaks);

  static const int _maxBars = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final live = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    final idle = Paint()..color = Colors.redAccent.withValues(alpha: 0.15);
    final mid = size.height / 2;
    final barW = size.width / _maxBars;
    for (int i = 0; i < _maxBars; i++) {
      final hasData = i < peaks.length;
      final p = hasData ? peaks[i].clamp(0.02, 1.0) : 0.03;
      final h = (p * (size.height - 10)).clamp(3.0, size.height - 10);
      final rect = Rect.fromLTWH(i * barW + barW * 0.22, mid - h / 2, barW * 0.56, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), hasData ? live : idle);
    }
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = Colors.redAccent.withValues(alpha: 0.25)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_PcmWavePainter oldDelegate) => true;
}
