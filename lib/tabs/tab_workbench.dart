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
import '../core/media_forensics.dart';
import '../screens/media_inspector_screen.dart';
import '../core/pcm_recorder.dart';
import '../core/tap_feedback.dart';
import '../core/cyber_tap_feedback.dart';
import '../screens/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/waveform_studio.dart';
import '../core/whisper_model.dart';
import '../core/ghost_commands.dart';
import '../workbench/dsp_builders.dart';
import '../workbench/video_dsp_builders.dart';
import '../workbench/workbench_models.dart';
import '../workbench/workbench_queue.dart';

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
  String _volumeReport = "";
  String _silenceReport = "";
  String _filterFaultReport = "";
  double _duckThresholdDb = -20.0;
  double _duckRatio = 8.0;
  double _duckAttackMs = 200.0;
  double _duckReleaseMs = 500.0;
  double _chorusDepthMs = 2.0;
  double _compandGainDb = 0.0;
  final List<MixTrack> _mixTracks = [];
  int? _waveSelInMs;
  int? _waveSelOutMs;
  double _limitLevel = 0.9;
  double _toneFreq = 440.0;
  double _toneDurSec = 5.0;
  String _toneType = "SINE";
  String _secondFilePath = "";
  int? _wbDurationMs;
  double _splitMinSegmentSec = 2.0;
  String _splitReport = "";
  final List<String> _chainOps = [];
  final TextEditingController _chainNameCtrl = TextEditingController();
  String? _selectedChain;
  Map<String, List<String>> _savedChains = {};
  String _chainAddOp = "Normalize Audio (LUFS -14)";
  final List<String> _batchFiles = [];
  WorkbenchQueue? _activeQueue;
  String _batchReport = "";
  String _videoRotate = "NONE";
  bool _videoFlipH = false;
  bool _videoFlipV = false;
  String _videoScale = "1080p";
  String _videoCropAspect = "16:9";
  String _targetVideoFormat = "mp4";

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

  String _audioCodecArgs(String container) => buildAudioCodecArgs(container, bitDepth: _bitDepth);

  String _resampleFilter() => buildResampleFilter(_sampleRate);

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

  Map<String, String>? _parseLoudnormMeasurements(String output) => parseLoudnormMeasurements(output);

  final List<String> _operations = DspOperation.allOperations;
  final List<String> _formats = DspOperation.audioFormats;
  static const List<String> _chainableOps = DspOperation.chainableOperations;
  static const List<String> _videoFormats = DspOperation.videoFormats;

  bool _isBatchable(String op) => DspOperation.isBatchable(op);
  bool _isVideoOp(String op) => DspOperation.isVideoOp(op);

  Future<void> _scanLufs() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _lufsReport = "Scanning EBU R128 Integrated Loudness..."; });
    try {
      final session = await FFmpegExecutor.execute(buildEbuR128Args(_selectedFilePath));
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
      final session = await FFmpegExecutor.execute(buildEbuR128Args(_selectedFilePath));
      final output = session.getOutput() ?? "";
      

      double? trackGain;
      double? trackPeak;
      double? albumGain;
      double? albumPeak;
      

      final integratedMatch = RegExp(r'I:\s*(-?\d+\.?\d*)\s*LUFS').firstMatch(output);
      if (integratedMatch != null) {
        final integrated = double.tryParse(integratedMatch.group(1) ?? "") ?? 0.0;
        trackGain = -14.0 - integrated;
      }
      

      final truePeakMatch = RegExp(r'TP:\s*(-?\d+\.?\d*)\s*LUFS').firstMatch(output);
      if (truePeakMatch != null) {
        final tp = double.tryParse(truePeakMatch.group(1) ?? "") ?? 0.0;
        trackPeak = pow(10.0, tp / 20.0).toDouble();
      }
      

      albumGain = trackGain;
      albumPeak = trackPeak;

      if (!mounted) return;
      if (trackGain != null && trackPeak != null) {
        final tg = trackGain;
        final tp = trackPeak;
        final ag = albumGain!;
        final ap = albumPeak!;
        _replayGainReport = "Track Gain: ${tg.toStringAsFixed(2)} dB\nTrack Peak: ${tp.toStringAsFixed(6)}\nAlbum Gain: ${ag.toStringAsFixed(2)} dB\nAlbum Peak: ${ap.toStringAsFixed(6)}";


        const id3Channel = MethodChannel('com.sovereign.tagger/id3');
        final metadata = <String, String>{
          'REPLAYGAIN_TRACK_GAIN': '${tg.toStringAsFixed(2)} dB',
          'REPLAYGAIN_TRACK_PEAK': tp.toStringAsFixed(6),
          'REPLAYGAIN_ALBUM_GAIN': '${ag.toStringAsFixed(2)} dB',
          'REPLAYGAIN_ALBUM_PEAK': ap.toStringAsFixed(6),
        };
        
        try {
          await id3Channel.invokeMethod('writeTags', {'filePath': _selectedFilePath, 'metadata': metadata});
          if (!mounted) return;
          setState(() => _replayGainReport = "TAGS WRITTEN ✓\n$_replayGainReport");
        } catch (e) {
          if (!mounted) return;
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

  String? _filterFaultHint(String output) {
    final noSuch = RegExp(r"No such filter:\s*'([^']+)'").firstMatch(output);
    if (noSuch != null) return noSuch.group(1);
    final unknown = RegExp(r"Unknown filter\s*'([^']+)'").firstMatch(output);
    if (unknown != null) return unknown.group(1);
    return null;
  }

  Future<void> _reportFilterFault(String filterName, String output) async {
    String docs = "";
    try {
      final docsSession = await FFmpegExecutor.execute('-hide_banner -h filter=$filterName');
      docs = docsSession.getOutput() ?? "";
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _filterFaultReport = docs.isEmpty
          ? "FILTER '$filterName' NOT IN THIS FFMPEG BUILD. No docs returned — check Settings > FFmpeg filter list on device."
          : docs;
      _statusMessage = "ERR: FILTER '$filterName' UNAVAILABLE IN THIS BUILD. See filter docs below — do not retry blindly.";
    });
  }

  Future<void> _reportEncoderFault(String encoderName, String output) async {
    String docs = "";
    try {
      final docsSession = await FFmpegExecutor.execute('-hide_banner -h encoder=$encoderName');
      docs = docsSession.getOutput() ?? "";
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _filterFaultReport = docs.isEmpty
          ? "ENCODER '$encoderName' NOT IN THIS FFMPEG BUILD. No docs returned — check Settings > FFmpeg encoder list on device."
          : docs;
      _statusMessage = "ERR: ENCODER '$encoderName' UNAVAILABLE IN THIS BUILD. See encoder docs below — do not retry blindly.";
    });
  }

  Future<void> _scanVolume() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _volumeReport = "Scanning Volume (volumedetect)..."; });
    try {
      final session = await FFmpegExecutor.execute(buildVolumeDetectArgs(_selectedFilePath));
      final output = session.getOutput() ?? "";
      final fault = _filterFaultHint(output);
      if (!mounted) return;
      if (fault != null) {
        setState(() => _volumeReport = "ERR: FILTER '$fault' NOT IN THIS FFMPEG BUILD.");
        await _reportFilterFault(fault, output);
        return;
      }
      final mean = RegExp(r'mean_volume:\s*(-?\d+\.?\d*)\s*dB').firstMatch(output);
      final max = RegExp(r'max_volume:\s*(-?\d+\.?\d*)\s*dB').firstMatch(output);
      final samples = RegExp(r'\bn:\s*(\d+)').firstMatch(output);
      if (!mounted) return;
      if (mean != null && max != null) {
        final headroom = -1.0 - (double.tryParse(max.group(1) ?? "") ?? 0.0);
        setState(() => _volumeReport = "Mean Volume: ${mean.group(1)} dB\nMax Volume: ${max.group(1)} dB\nHeadroom To -1 dBTP: ${headroom.toStringAsFixed(1)} dB${samples != null ? '\nSamples: ${samples.group(1)}' : ''}");
      } else {
        setState(() => _volumeReport = "Scan Complete. No Volume Reading Parsed (check source).");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _volumeReport = "ERR: Volume Scan Fault: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _scanSilence() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _silenceReport = "Scanning Silence (silencedetect -45dB / 0.3s)..."; });
    try {
      final session = await FFmpegExecutor.execute(buildSilenceDetectArgs(_selectedFilePath));
      final output = session.getOutput() ?? "";
      final fault = _filterFaultHint(output);
      if (!mounted) return;
      if (fault != null) {
        setState(() => _silenceReport = "ERR: FILTER '$fault' NOT IN THIS FFMPEG BUILD.");
        await _reportFilterFault(fault, output);
        return;
      }
      final starts = RegExp(r'silence_start:\s*([\d.]+)').allMatches(output).map((m) => double.tryParse(m.group(1) ?? "") ?? 0.0).toList();
      final ends = RegExp(r'silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)').allMatches(output).map((m) => (double.tryParse(m.group(1) ?? "") ?? 0.0, double.tryParse(m.group(2) ?? "") ?? 0.0)).toList();
      if (!mounted) return;
      if (starts.isEmpty && ends.isEmpty) {
        setState(() => _silenceReport = "No Silence Found (threshold -45dB, min 0.3s).");
        return;
      }
      double total = 0.0;
      for (final e in ends) { total += e.$2; }
      final lines = <String>[];
      for (int i = 0; i < starts.length && i < 12; i++) {
        if (i < ends.length) {
          lines.add("${starts[i].toStringAsFixed(2)}s -> ${ends[i].$1.toStringAsFixed(2)}s (${ends[i].$2.toStringAsFixed(2)}s)");
        } else {
          lines.add("${starts[i].toStringAsFixed(2)}s -> EOF (open)");
        }
      }
      if (starts.length > 12) lines.add("... +${starts.length - 12} more");
      setState(() => _silenceReport = "Silences: ${starts.length} • Total: ${total.toStringAsFixed(2)}s\n${lines.join('\n')}");
    } catch (e) {
      if (!mounted) return;
      setState(() => _silenceReport = "ERR: Silence Scan Fault: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  List<({double start, double? end})> _parseSilences(String output) => parseSilences(output);

  List<({double start, double end})> _splitSegmentsFromSilence(String output, int? durationMs) =>
      splitSegmentsFromSilence(output, durationMs, minSegmentSec: _splitMinSegmentSec);

  Future<void> _executeSplitOnSilence() async {
    if (_selectedFilePath.isEmpty || _isProcessing) return;
    setState(() { _isProcessing = true; _opProgress = 0.0; _splitReport = ""; _statusMessage = "Scanning Silence For Split Points..."; });
    try {
      final durationMs = await probeDurationMs(_selectedFilePath);
      if (!mounted) return;
      final session = await FFmpegExecutor.execute(buildSilenceDetectArgs(_selectedFilePath));
      final output = session.getOutput() ?? "";
      final fault = _filterFaultHint(output);
      if (!mounted) return;
      if (fault != null) {
        setState(() => _isProcessing = false);
        await _reportFilterFault(fault, output);
        return;
      }
      final silences = _parseSilences(output);
      if (silences.isEmpty) {
        setState(() { _isProcessing = false; _statusMessage = "No Silence Found (threshold -45dB, min 0.3s). Nothing To Split."; });
        return;
      }
      var segments = _splitSegmentsFromSilence(output, durationMs);
      if (segments.isEmpty) {
        setState(() { _isProcessing = false; _statusMessage = "Silence Found, But No Segment Meets The Minimum Length (${_splitMinSegmentSec.toStringAsFixed(1)}s). Lower The Minimum Or Check The Source."; });
        return;
      }
      if (segments.length == 1) {
        setState(() { _isProcessing = false; _statusMessage = "Only One Segment Found — No Splittable Silence. Nothing Written."; });
        return;
      }
      const maxSegments = 200;
      final capped = segments.length > maxSegments;
      if (capped) segments = segments.sublist(0, maxSegments);
      final parts = _selectedFilePath.split('.');
      final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";
      final ext = _preservedContainers.contains(srcExt) ? srcExt : "flac";
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = _baseNameOf(_selectedFilePath);
      final lines = <String>[];
      int ok = 0;
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final outPath = "$tempDir/workbench_split_${timestamp}_$i.$ext";
        final command = '-y -i "$_selectedFilePath" -ss ${seg.start.toStringAsFixed(2)} -to ${seg.end.toStringAsFixed(2)} -vn ${_audioCodecArgs(ext)} "$outPath"';
        if (!mounted) return;
        setState(() { _opProgress = i / segments.length; _statusMessage = "Splitting Segment ${i + 1}/${segments.length} (${seg.start.toStringAsFixed(1)}s - ${seg.end.toStringAsFixed(1)}s)..."; });
        final segSession = await FFmpegExecutor.execute(command);
        if (!ReturnCode.isSuccess(segSession.getReturnCode())) {
          final segOut = segSession.getOutput() ?? "";
          final segTail = segOut.length > 200 ? segOut.substring(segOut.length - 200) : segOut;
          lines.add("FAIL ${i + 1}: rc=${segSession.getReturnCode()} $segTail");
          continue;
        }
        final title = "${baseName}_split_${(i + 1).toString().padLeft(2, '0')}";
        try {
          final uriString = await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': title});
          lines.add("OK ${i + 1}: ${seg.start.toStringAsFixed(1)}s-${seg.end.toStringAsFixed(1)}s -> $uriString");
          File(outPath).delete().ignore();
          ok++;
        } catch (_) {
          lines.add("CACHE ONLY ${i + 1}: $outPath");
          ok++;
        }
      }
      if (!mounted) return;
      TapFeedback.machineConfirm();
      setState(() {
        _isProcessing = false;
        _opProgress = 1.0;
        _splitReport = "Split Done: $ok/${segments.length} OK${capped ? ' (capped at $maxSegments — raise the minimum segment length for long files)' : ''}.\n${lines.join('\n')}";
        _statusMessage = "Split Complete: $ok/${segments.length} Segments Written. See SPLIT report.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isProcessing = false; _statusMessage = "ERR: Split Fault: $e"; });
    }
  }

  List<String> _filtersForOperation(String op, int? durationMs) {
    final filters = <String>[];
    switch (op) {
      case "Apply Fades":
        if (durationMs == null) throw StateError("ERR: Cannot Determine Duration For Fade Out Point.");
        filters.addAll(buildFadeFilter(fadeInSec: _fadeInSec, fadeOutSec: _fadeOutSec, totalDurationSec: durationMs / 1000.0));
        break;
      case "Fold To Mono":
        filters.add(buildMonoFoldFilter());
        break;
      case "Insert Silence":
        filters.add(buildInsertSilenceFilter(silenceSec: _silenceSec, atStart: _silenceAtStart));
        break;
      case "Delete Region": {
        final sMs = _waveSelInMs ?? _parseHmsSafe(_startCtrl.text).inMilliseconds;
        final eMs = _waveSelOutMs ?? _parseHmsSafe(_endCtrl.text).inMilliseconds;
        filters.add(buildDeleteRegionFilter(startSec: sMs / 1000.0, endSec: eMs / 1000.0));
        break;
      }
      case "Click/Pop Repair (adeclick)":
        filters.add(buildDeclickFilter());
        break;
      case "De-Esser":
        filters.add(buildDeEsserFilter(intensity: _deessIntensity));
        break;
      case "Limiter":
        filters.add(buildLimiterFilter(limit: _limitLevel));
        break;
      case "Multiband Compress (mcompand)":
        filters.add(buildMcompandFilter());
        break;
      case "DC/Rumble Fix (highpass)":
        filters.add(buildHighpassFilter());
        break;
      case "Trim Silence":
        filters.add(buildTrimSilenceFilter(precise: false));
        break;
      case "Trim To Silence (Precise)":
        filters.add(buildTrimSilenceFilter(precise: true));
        break;
      case "Chorus (spatial)":
        filters.add(buildChorusFilter(depthMs: _chorusDepthMs));
        break;
      case "Compand (dynamic shaping)":
        filters.add(buildCompandFilter(gainDb: _compandGainDb));
        break;
      case "Firequalizer Curve EQ":
        filters.add(buildFirequalizerCurve(bass: _eqBass, lowMid: _eqLowMid, mid: _eqMid, highMid: _eqHighMid, treble: _eqTreble));
        break;
      case "Granular Audio DSP (Speed/Reverb)":
        filters.addAll(buildGranularSpeedFilter(speed: _audioSpeed, pitchMode: _pitchMode, isReversed: _isReversed, reverbIntensity: _reverbIntensity));
        break;
      case "AI Denoise (afftdn)":
        filters.add(buildDenoiseFilter());
        break;
      case "Parametric EQ":
        filters.addAll(buildEqFilter(bass: _eqBass, lowMid: _eqLowMid, mid: _eqMid, highMid: _eqHighMid, treble: _eqTreble));
        break;
      case "Compress Dynamics":
        filters.add(buildCompressorFilter(ratio: _compRatio));
        break;
      case "15-Band Equalizer (AutoEq)":
        filters.addAll(build15BandEqFilter(_eq15Bands));
        break;
      case "Normalize Audio (LUFS -14)":
        break;
      default:
        throw StateError("ERR: OP '$op' HAS NO FILTER CHAIN.");
    }
    return filters;
  }

  String _baseNameOf(String path) {
    final name = path.split('/').last;
    return name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  }

  String _videoOpSuffix(String op) => buildVideoOpSuffix(op);

  String _buildVideoCommand(String op, String inputPath, String outPath, int? durationMs) {
    return buildVideoCommand(
      op: op,
      inputPath: inputPath,
      outPath: outPath,
      durationMs: durationMs,
      startHms: _startCtrl.text,
      endHms: _endCtrl.text,
      rotate: _videoRotate,
      flipH: _videoFlipH,
      flipV: _videoFlipV,
      scale: _videoScale,
      cropAspect: _videoCropAspect,
      targetVideoFormat: _targetVideoFormat,
      secondFilePath: _secondFilePath,
    );
  }

  Future<String> _injectToMediaStore(String outPath, String title) async {
    try {
      final uriString = await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': title});
      File(outPath).delete().ignore();
      return "Success. Payload Written To:\n$uriString";
    } catch (_) {
      return "Injected To Cache Only (MediaStore Fault):\n$outPath";
    }
  }

  Future<void> _handleRenderFailure(FFmpegSession session) async {
    final output = session.getOutput() ?? "";
    final fault = _filterFaultHint(output);
    if (fault != null) {
      setState(() => _isProcessing = false);
      await _reportFilterFault(fault, output);
      return;
    }
    final encoderFault = RegExp(r"Unknown encoder '([^']+)'").firstMatch(output);
    if (encoderFault != null) {
      setState(() => _isProcessing = false);
      await _reportEncoderFault(encoderFault.group(1)!, output);
      return;
    }
    final tail = output.length > 300 ? output.substring(output.length - 300) : output;
    setState(() { _isProcessing = false; _statusMessage = "ERR: FFmpeg Failed (rc=${session.getReturnCode()}). Last output:\n$tail"; });
  }

  Future<void> _pickMixTrack() async {
    if (_isProcessing || _isRecording) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file != null && file.path != null) {
        final dur = await probeDurationMs(file.path!);
        if (!mounted) return;
        setState(() => _mixTracks.add(MixTrack(path: file.path!, durationMs: dur)));
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: Mix Track Picker Fault: ${e.message}");
    } catch (_) {}
  }

  int _mixTotalDurationMs(List<MixTrack> tracks) {
    int total = _wbDurationMs ?? 0;
    for (final t in tracks) { total += t.durationMs ?? 0; }
    return total;
  }

  String? _mixGuardWarning(List<MixTrack> tracks) {
    final count = 1 + tracks.length;
    final totalMs = _mixTotalDurationMs(tracks);
    if (count > 7) return "MIX CAP IS 7 TRACKS. Remove tracks before executing.";
    if (count > 3 || totalMs > 900000) {
      return "HEAVY MIX — $count tracks / ${_fmtHms(Duration(milliseconds: totalMs))} total. EmbeddingGemma unloads first via the RAM guard; long renders take minutes on low-end hardware.";
    }
    return null;
  }

  static const RecorderSettings _recorderSettings = RecorderSettings(
    androidEncoderSettings: AndroidEncoderSettings(androidEncoder: AndroidEncoder.aacLc),
    iosEncoderSettings: IosEncoderSetting(iosEncoder: IosEncoder.kAudioFormatMPEG4AAC),
    sampleRate: 48000,
    bitRate: 256000,
  );

  @override
  void initState() {
    super.initState();
    _waveController = PlayerController();
    _recorderController = RecorderController();
    GhostCommandBus.pendingWorkbenchCommand.addListener(_onGhostWorkbenchCommand);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onGhostWorkbenchCommand());
    _loadChains();
  }

  @override
  void dispose() {
    _ampSub?.cancel();    _waveController.dispose();
    GhostCommandBus.pendingWorkbenchCommand.removeListener(_onGhostWorkbenchCommand);
    _recorderController.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _chainNameCtrl.dispose();
    super.dispose();
  }

  void _onGhostWorkbenchCommand() {
    final cmd = GhostCommandBus.pendingWorkbenchCommand.value;
    if (cmd == null || !mounted) return;
    GhostCommandBus.pendingWorkbenchCommand.value = null;
    final path = cmd.filePath;
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();
    setState(() {
      if (hasFile) {
        _selectedFilePath = path;
      }
      if (cmd.task == WorkbenchTaskType.transcribeLyricsWhisper) {
        _selectedOperation = "Transcribe (Whisper AI)";
        _statusMessage = hasFile
            ? "Mounted For On-Device Whisper Transcription."
            : "Whisper AI Selected — Mount Track To Transcribe.";
      } else if (cmd.task == WorkbenchTaskType.analyzeReplayGain) {
        _selectedOperation = "Scan ReplayGain (EBU R128)";
        _statusMessage = hasFile
            ? "Mounted For EBU R128 ReplayGain Scan."
            : "ReplayGain Scanner Selected — Mount Track To Scan.";
      } else if (cmd.task == WorkbenchTaskType.openEq) {
        _selectedOperation = "15-Band Equalizer (AutoEq)";
      }
    });
    if (hasFile && cmd.task == WorkbenchTaskType.analyzeReplayGain && !_isProcessing) {
      unawaited(_scanReplayGain());
    }
    if (cmd.onResult != null && !cmd.onResult!.isCompleted) {
      cmd.onResult!.complete(_selectedOperation);
    }
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
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file != null && file.path != null) {
        if (!mounted) return;
        setState(() => _secondFilePath = file.path!);
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
      final cmd = buildToneArgs(toneType: _toneType, freq: _toneFreq, durationSec: _toneDurSec, outPath: outPath);
      await FFmpegExecutor.execute(cmd);
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
      final file = await FilePicker.pickFile(type: FileType.any);

      if (file != null && file.path != null) {
        if (!mounted) return;
        final path = file.path!;
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
          
          await _recorderController.record(path: recordPath, recorderSettings: _recorderSettings);

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
      if (!mounted) return;
      setState(() { _statusMessage = "Whisper: Transcribing (${_whisperLanguage.toUpperCase()}, base.en)..."; _opProgress = 0.0; });
      final durationMs = await probeDurationMs(_selectedFilePath);
      if (!mounted) return;

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
        if (!mounted) return;
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

  Future<void> _executeForensicWorkbenchOp() async {
    setState(() {
      _isProcessing = true;
      _opProgress = 0.0;
      _statusMessage = "Probing Container & Streams...";
    });
    try {
      final report = await MediaForensics.inspect(_selectedFilePath);
      if (!mounted) return;
      if (_selectedOperation == "Lossless Audio Extract (-c:a copy)") {
        setState(() => _statusMessage = "Demuxing Audio Stream (-c:a copy, Zero Re-Encode)...");
        final res = await MediaForensics.extractAudioLossless(report);
        if (!mounted) return;
        if (res.ok) TapFeedback.machineConfirm();
        setState(() {
          _isProcessing = false;
          _statusMessage = res.summary;
        });
      } else if (_selectedOperation == "Split Chapters Losslessly (-c copy)") {
        final res = await MediaForensics.splitChaptersLossless(
          report,
          onProgress: (cur, total, title) {
            if (!mounted) return;
            setState(() {
              _opProgress = total > 0 ? cur / total : 0.0;
              _statusMessage = "Splitting Chapter $cur/$total: $title";
            });
          },
        );
        if (!mounted) return;
        if (res.ok) TapFeedback.machineConfirm();
        setState(() {
          _isProcessing = false;
          _statusMessage = res.summary;
        });
      } else {
        final audit = await MediaForensics.runDeepAudioAudit(
          report,
          onStage: (stage) {
            if (!mounted) return;
            setState(() => _statusMessage = stage);
          },
        );
        if (!mounted) return;
        TapFeedback.machineConfirm();
        final lufs = audit.integratedLufs != null ? "${audit.integratedLufs!.toStringAsFixed(1)} LUFS" : "N/A";
        final tp = audit.truePeakDbtp != null ? "${audit.truePeakDbtp!.toStringAsFixed(1)} dBTP" : "N/A";
        final dr = audit.dynamicRangeDb != null ? "DR${audit.dynamicRangeDb!.round()}" : "N/A";
        setState(() {
          _isProcessing = false;
          _statusMessage = "${audit.verdictLabel}\n${audit.verdictDetail}\nLoudness: $lufs • True Peak: $tp • $dr • Bits: ${audit.effectiveBitDepth}";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = "ERR: Forensic Operation Fault: $e";
      });
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
    if (_selectedOperation == "Scan Volume (volumedetect)") {
      await _scanVolume();
      return;
    }
    if (_selectedOperation == "Scan Silence (silencedetect)") {
      await _scanSilence();
      return;
    }
    if (_selectedOperation == "Split On Silence (silencedetect)") {
      await _executeSplitOnSilence();
      return;
    }
    if (_selectedOperation == "Lossless Audio Extract (-c:a copy)" ||
        _selectedOperation == "Split Chapters Losslessly (-c copy)" ||
        _selectedOperation == "Fake-Lossless & DR Audit") {
      await _executeForensicWorkbenchOp();
      return;
    }
    setState(() { _isProcessing = true; _statusMessage = "Allocating FFmpeg Resources..."; });

    try {
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final durationMs = await probeDurationMs(_selectedFilePath);
      if (!mounted) return;

      final parts = _selectedFilePath.split('.');
      final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";
      final isVideoSrc = ['mp4', 'mkv', 'webm'].contains(srcExt);
      final bool preserveOp = ["Normalize Audio (LUFS -14)", "Granular Audio DSP (Speed/Reverb)", "Apply Fades", "Fold To Mono", "Trim Silence", "Trim To Silence (Precise)", "AI Denoise (afftdn)", "Parametric EQ", "Compress Dynamics", "15-Band Equalizer (AutoEq)", "Insert Silence", "Delete Region", "Click/Pop Repair (adeclick)", "De-Esser", "Limiter", "Multiband Compress (mcompand)", "Chorus (spatial)", "Compand (dynamic shaping)", "Firequalizer Curve EQ", "DC/Rumble Fix (highpass)"].contains(_selectedOperation);

      String ext;
      if (_selectedOperation == "Spectrogram Snapshot") {
        ext = "png";
      } else if (_selectedOperation == "Clip Media (The Scalpel)") {
        ext = srcExt.isEmpty ? "mp4" : srcExt;
      } else if (_selectedOperation == "Convert Format") {
        ext = _targetFormat;
      } else if (_selectedOperation == "Extract Audio (Video to MP3)") {
        ext = "mp3";
      } else if (_selectedOperation == "Extract Audio (Video to M4A)") {
        ext = "m4a";
      } else if (_selectedOperation == "Video Convert (Container)") {
        ext = _targetVideoFormat;
      } else if (_isVideoOp(_selectedOperation)) {
        ext = ['mp4', 'mkv', 'webm'].contains(srcExt) ? srcExt : "mp4";
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
          command = buildClipVideoArgs(
            inputPath: _selectedFilePath,
            outPath: outPath,
            startHms: startText,
            endHms: endText,
          );
        } else {
          command = buildClipAudioArgs(
            inputPath: _selectedFilePath,
            outPath: outPath,
            startHms: startText,
            endHms: endText,
          );
        }
      } else if (_selectedOperation == "Spectrogram Snapshot") {
        command = buildSpectrogramArgs(inputPath: _selectedFilePath, outPath: outPath);
      } else if (_selectedOperation == "Mix With File") {
        final extra = List<MixTrack>.from(_mixTracks);
        if (extra.isEmpty && _secondFilePath.isNotEmpty) {
          extra.add(MixTrack(path: _secondFilePath, durationMs: await probeDurationMs(_secondFilePath)));
        }
        if (extra.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: ADD AT LEAST ONE MIX TRACK FIRST."; });
          return;
        }
        if (1 + extra.length > 7) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MIX CAP IS 7 TRACKS (main + 6). Remove tracks before executing."; });
          return;
        }
        final warn = _mixGuardWarning(extra);
        if (warn != null) setState(() => _statusMessage = "WARN: $warn");
        final inputs = <String>[_selectedFilePath, ...extra.map((t) => t.path)];
        final gains = [1.0, ...extra.map((t) => t.gain)];
        final pans = [0.0, ...extra.map((t) => t.pan)];
        command = buildMultitrackMixArgs(inputPaths: inputs, gains: gains, pans: pans, outPath: outPath, container: ext, bitDepth: _bitDepth);
      } else if (_selectedOperation == "Gapless Join (concat)") {
        if (_secondFilePath.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MOUNT SECOND MEDIA FIRST."; });
          return;
        }
        command = buildGaplessJoinArgs(firstPath: _selectedFilePath, secondPath: _secondFilePath, outPath: outPath, container: ext, bitDepth: _bitDepth);
      } else if (_selectedOperation == "Sidechain Duck (sidechaincompress)") {
        if (_secondFilePath.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MOUNT VOICE MEDIA FIRST (SECOND FILE = SIDECHAIN)."; });
          return;
        }
        command = buildSidechainDuckArgs(mainPath: _selectedFilePath, sidechainPath: _secondFilePath, outPath: outPath, thresholdDb: _duckThresholdDb, ratio: _duckRatio, attackMs: _duckAttackMs, releaseMs: _duckReleaseMs, container: ext, bitDepth: _bitDepth);
      } else if (_selectedOperation == "Crossfade Join") {
        if (_secondFilePath.isEmpty) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: MOUNT SECOND MEDIA FIRST."; });
          return;
        }
        command = buildCrossfadeJoinArgs(firstPath: _selectedFilePath, secondPath: _secondFilePath, outPath: outPath, xfadeSec: _xfadeSec, container: ext, bitDepth: _bitDepth);
      } else if (_selectedOperation == "Extract Audio (Video to MP3)") {
        command = '-y -i "$_selectedFilePath" -vn -c:a libmp3lame -b:a 320k "$outPath"';
      } else if (_selectedOperation == "Convert Format") {
        command = '-y -i "$_selectedFilePath" -vn ${_audioCodecArgs(_targetFormat)} "$outPath"';
      } else if (_isVideoOp(_selectedOperation)) {
        final streams = await probeStreams(_selectedFilePath);
        if (!mounted) return;
        if ((streams['video'] ?? 0) == 0) {
          setState(() { _isProcessing = false; _statusMessage = "ERR: NOT A VIDEO FILE. Mount an MP4, MKV, or WebM first — this op needs a video stream."; });
          return;
        }
        try {
          command = _buildVideoCommand(_selectedOperation, _selectedFilePath, outPath, durationMs);
        } on StateError catch (e) {
          setState(() { _isProcessing = false; _statusMessage = e.message; });
          return;
        }
      } else if (preserveOp) {
        List<String> filters;
        try {
          filters = _filtersForOperation(_selectedOperation, durationMs);
        } on StateError catch (e) {
          setState(() { _isProcessing = false; _statusMessage = e.message; });
          return;
        }
        final resampleFilter = _resampleFilter();
        if (resampleFilter.isNotEmpty) filters.insert(0, resampleFilter);

        String? loudnormFilter;
        if (_selectedOperation == "Normalize Audio (LUFS -14)") {
          if (_normMode == "DYNAMIC (dynaudnorm)") {
            loudnormFilter = buildLoudnormFilter(mode: _normMode);
          } else {
            loudnormFilter = buildLoudnormFilter(mode: _normMode);
            if (_twoPassLoudnorm) {
              setState(() => _statusMessage = "LOUDNORM PASS 1/2: ANALYZING...");
              final analysisCmd = buildLoudnormFirstPassArgs(_selectedFilePath);
              final pass1 = await FFmpegExecutor.execute(analysisCmd);
              if (!mounted) return;
              final measured = _parseLoudnormMeasurements(pass1.getOutput() ?? "");
              if (measured != null) {
                loudnormFilter = buildLoudnormFilter(mode: _normMode, measured: measured);
              } else {
                setState(() => _statusMessage = "WARN: Pass-1 Analysis Unreadable. Falling Back To Single-Pass.");
              }
            }
          }
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
        if (!mounted) return;
        if (_isVideoOp(_selectedOperation)) {
          final outStreams = await probeStreams(outPath);
          if (!mounted) return;
          if ((outStreams['video'] ?? 0) == 0) {
            setState(() { _isProcessing = false; _statusMessage = "ERR: RENDER PRODUCED NO VIDEO STREAM. The codec or filter dropped the video — check the encoder docs below."; });
            return;
          }
        }
        setState(() => _statusMessage = "Process Complete. Injecting To MediaStore...");
        final originalName = _selectedFilePath.split('/').last;
        final baseName = originalName.contains('.') ? originalName.substring(0, originalName.lastIndexOf('.')) : originalName;
        final outSuffix = _isVideoOp(_selectedOperation) ? _videoOpSuffix(_selectedOperation) : "_mod";
        final payloadNote = await _injectToMediaStore(outPath, "$baseName$outSuffix");
        if (!mounted) return;
        TapFeedback.machineConfirm();
        setState(() { _isProcessing = false; _statusMessage = payloadNote; });
      } else {
        if (!mounted) return;
        await _handleRenderFailure(session);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isProcessing = false; _statusMessage = "Critical ERR: $e"; });
    }
  }

  static const String _chainsPrefsKey = 'workbench_chains';

  Future<void> _loadChains() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chainsPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final loaded = <String, List<String>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            loaded[k] = v.map((e) => e.toString()).where((e) => _chainableOps.contains(e)).toList();
          }
        });
        if (!mounted) return;
        setState(() => _savedChains = loaded);
      }
    } catch (_) {}
  }

  Future<void> _persistChains() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chainsPrefsKey, jsonEncode(_savedChains));
    } catch (_) {}
  }

  void _saveChain() {
    final name = _chainNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _statusMessage = "ERR: NAME THE CHAIN FIRST.");
      return;
    }
    if (_chainOps.isEmpty) {
      setState(() => _statusMessage = "ERR: CHAIN IS EMPTY. Add at least one op first.");
      return;
    }
    setState(() {
      _savedChains[name] = List<String>.from(_chainOps);
      _selectedChain = name;
      _statusMessage = "Chain Saved: $name (${_chainOps.length} ops).";
    });
    _persistChains();
  }

  void _deleteChain(String name) {
    setState(() {
      _savedChains.remove(name);
      if (_selectedChain == name) _selectedChain = null;
      _statusMessage = "Chain Deleted: $name.";
    });
    _persistChains();
  }

  List<String> _chainFilters(List<String> ops, int? durationMs) {
    final out = <String>[];
    for (final op in ops) {
      final sub = _filtersForOperation(op, durationMs);
      if (op == "Normalize Audio (LUFS -14)") {
        sub.insert(0, buildLoudnormFilter(mode: _normMode));
      }
      out.addAll(sub);
    }
    final resample = _resampleFilter();
    if (resample.isNotEmpty) {
      final at = out.isNotEmpty && (out.first.startsWith('loudnorm=') || out.first.startsWith('dynaudnorm=')) ? 1 : 0;
      out.insert(at, resample);
    }
    return out;
  }

  Future<void> _executeChain() async {
    if (_selectedFilePath.isEmpty || _isProcessing || _isRecording) return;
    if (_chainOps.isEmpty) {
      setState(() => _statusMessage = "ERR: CHAIN IS EMPTY. Add at least one op first.");
      return;
    }
    setState(() { _isProcessing = true; _opProgress = 0.0; _statusMessage = "Running Chain (${_chainOps.length} ops) In One Pass..."; });
    try {
      final tempDir = await _storageChannel.invokeMethod('getTempDirectory');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final durationMs = await probeDurationMs(_selectedFilePath);
      if (!mounted) return;
      final parts = _selectedFilePath.split('.');
      final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";
      final ext = _preservedContainers.contains(srcExt) ? srcExt : "flac";
      final outPath = "$tempDir/workbench_chain_$timestamp.$ext";
      List<String> filters;
      try {
        filters = _chainFilters(_chainOps, durationMs);
      } on StateError catch (e) {
        if (!mounted) return;
        setState(() { _isProcessing = false; _statusMessage = e.message; });
        return;
      }
      if (filters.isEmpty) {
        setState(() { _isProcessing = false; _statusMessage = "ERR: CHAIN BUILT NO FILTERS. Check op settings (all EQ at zero, no speed/reverb change)."; });
        return;
      }
      final command = '-y -i "$_selectedFilePath" -af "${filters.join(',')}" -vn ${_audioCodecArgs(ext)} "$outPath"';
      setState(() => _statusMessage = "Executing Chain: ${_chainOps.join(' > ').toUpperCase()}");
      final session = await FFmpegExecutor.execute(command, onStatistics: (stats) {
        if (durationMs == null || durationMs <= 0 || !mounted) return;
        setState(() => _opProgress = (stats.time / durationMs).clamp(0.0, 1.0));
      });
      if (ReturnCode.isSuccess(session.getReturnCode())) {
        if (!mounted) return;
        setState(() => _statusMessage = "Chain Complete. Injecting To MediaStore...");
        final payloadNote = await _injectToMediaStore(outPath, "${_baseNameOf(_selectedFilePath)}_chain");
        if (!mounted) return;
        TapFeedback.machineConfirm();
        setState(() { _isProcessing = false; _statusMessage = "Chain Ran: ${_chainOps.join(' > ')}.\n$payloadNote"; });
      } else {
        if (!mounted) return;
        await _handleRenderFailure(session);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isProcessing = false; _statusMessage = "Critical ERR: $e"; });
    }
  }

  String _outputExtFor(String inputPath, String op) => DspOperation.outputExtension(
    inputPath,
    op,
    targetAudioFormat: _targetFormat,
    targetVideoFormat: _targetVideoFormat,
  );

  String _buildTransformCommand(String op, String inputPath, String outPath, int? durationMs) {
    if (_isVideoOp(op)) return _buildVideoCommand(op, inputPath, outPath, durationMs);
    if (op == "Convert Format") return '-y -i "$inputPath" -vn ${_audioCodecArgs(_targetFormat)} "$outPath"';
    if (op == "Extract Audio (Video to MP3)") return '-y -i "$inputPath" -vn -c:a libmp3lame -b:a 320k "$outPath"';
    if (!_chainableOps.contains(op)) throw StateError("ERR: OP '$op' IS NOT BATCHABLE.");
    final filters = _filtersForOperation(op, durationMs);
    final resample = _resampleFilter();
    if (resample.isNotEmpty) filters.insert(0, resample);
    if (op == "Normalize Audio (LUFS -14)") {
      filters.insert(0, buildLoudnormFilter(mode: _normMode));
    }
    final chain = filters.isNotEmpty ? '-af "${filters.join(',')}"' : "";
    return '-y -i "$inputPath" $chain -vn ${_audioCodecArgs(_outputExtFor(inputPath, op))} "$outPath"';
  }

  Future<void> _pickBatchFiles() async {
    if (_isProcessing) return;
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: _isVideoOp(_selectedOperation) ? FileType.video : FileType.audio);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = "ERR: File Picker Fault: ${e.message}");
      return;
    }
    if (picked.isEmpty) return;
    if (!mounted) return;
    setState(() {
      for (final f in picked) {
        if (f.path != null && f.path!.isNotEmpty && !_batchFiles.contains(f.path)) _batchFiles.add(f.path!);
      }
    });
  }

  Future<void> _executeBatch() async {
    if (_isProcessing || _batchFiles.isEmpty) return;
    if (!_isBatchable(_selectedOperation)) {
      setState(() => _statusMessage = "ERR: BATCH ONLY RUNS SINGLE-FILE TRANSFORMS. Select a DSP op, Convert Format, Extract Audio, or a video op first — Mix, Join, Duck, Mux, scans, Split, and Whisper do not batch.");
      return;
    }
    setState(() { _isProcessing = true; _opProgress = 0.0; _batchReport = "Batch Running: $_selectedOperation over ${_batchFiles.length} file(s)..."; });

    final queue = WorkbenchQueue();
    queue.addJobs(_batchFiles, _selectedOperation);
    _activeQueue = queue;

    try {
      final summary = await queue.execute(
        commandBuilder: (op, inputPath, outPath, durationMs) async =>
            _buildTransformCommand(op, inputPath, outPath, durationMs),
        getTempDirectory: () async => await _storageChannel.invokeMethod('getTempDirectory'),
        mediaStoreInjector: (outPath, title) async =>
            await _storageChannel.invokeMethod('addToMediaStore', {'filePath': outPath, 'title': title}),
        durationProbe: (path) => probeDurationMs(path),
        streamProbe: (path) => probeStreams(path),
        targetAudioFormat: _targetFormat,
        targetVideoFormat: _targetVideoFormat,
        onJobStarted: (job, idx, total) {
          if (!mounted) return;
          setState(() {
            _opProgress = (idx - 1) / total;
            _statusMessage = "Batch $idx/$total: ${job.fileName}";
          });
        },
        onJobProgress: (job, jobProgress, overallProgress) {
          if (!mounted) return;
          setState(() => _opProgress = overallProgress);
        },
        onJobCompleted: (job, idx, total) {
          if (!mounted) return;
          setState(() => _opProgress = idx / total);
        },
      );

      if (!mounted) return;
      TapFeedback.machineConfirm();
      setState(() {
        _isProcessing = false;
        _activeQueue = null;
        _opProgress = 1.0;
        _batchReport = summary;
        final okCount = queue.jobs.where((j) => j.isSuccess).length;
        _statusMessage = "Batch Complete: $okCount/${_batchFiles.length} OK. See BATCH QUEUE report.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _activeQueue = null;
        _statusMessage = "ERR: Batch Fault: $e";
      });
    } finally {
      if (mounted) {
        setState(() => _activeQueue = null);
      }
    }
  }

  void _showWorkbenchManual() {
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
                      const Expanded(child: Text('WORKBENCH FIELD MANUAL', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  _wmh('MOUNT'),
                  _wmb('Mount a file with MOUNT MEDIA, or record into a file. All DSP ops use FFmpeg and write the result only after EXECUTE ON THE MACHINE.'),
                  _wmh('QUALITY'),
                  _wmb('Master status: 48k/16-bit WAV via STUDIO REC, or AAC fallback. Use COPY MODE for same-format passthrough. Fold to mono produces a WAV master by default. No re-encodes unless the operation needs one.'),
                  _wmh('COMMON OPS'),
                  _wmb('EXTRACT AUDIO, CLIP, CONVERT FORMAT, NORMALIZE LOUDNORM, GRANULAR DSP, FADE IN/OUT, FOLD TO MONO, TRIM SILENCE, and WHISPER. Each op has its own duration/start/end fields as shown below. EXECUTE writes only into temp paths or a new file.'),
                  _wmh('READOUTS'),
                  _wmb('SCAN VOLUME (volumedetect) reports mean/max volume and headroom to -1 dBTP. SCAN SILENCE (silencedetect) lists every silence at -45dB / 0.3s with start, end, and duration. Both are read-only.'),
                  _wmh('NEW DSP'),
                  _wmb('SIDECHAIN DUCK: main file is the music to duck, second file is the voice sidechain — threshold/ratio/attack/release. CHORUS: spatial depth in ms. COMPAND: gentle dynamic curve with makeup gain. FIREQUALIZER: smooth curve EQ driven by the 5 Parametric EQ sliders. TRIM TO SILENCE (PRECISE): 50ms windows at -50dB, tighter than TRIM SILENCE.'),
                  _wmh('SPLIT ON SILENCE'),
                  _wmb('Cuts the mounted file at every detected silence (-45dB, min 0.3s) into numbered tracks (<name>_split_01, _split_02...). Segments shorter than the minimum length are dropped. Same container, re-encoded for sample-accurate cuts. If no splittable silence is found, nothing is written.'),
                  _wmh('VIDEO OPS'),
                  _wmb('VIDEO TRIM re-encodes between START/END for frame-accurate cuts (Clip is -c copy, keyframe boundaries only). ROTATE/FLIP uses transpose/hflip/vflip — the same orientation map as the photo editor. SCALE keeps aspect (even widths via -2). CROP center-crops to 16:9 / 4:3 / 1:1 / 9:16. MUTE drops the audio stream with -c:v copy. EXTRACT AUDIO (M4A) pulls AAC 256k; MP3 extract already existed. VIDEO CONVERT re-encodes per container (libx264+aac for mp4/mkv, libvpx-vp9+opus for webm). MUX VIDEO + AUDIO lays a second audio file over the video with explicit -map 0:v:0 -map 1:a:0, video copied, audio re-encoded. Every video render is verified with probeStreams — an output with no video stream is reported, never injected silently. Video ops batch like audio ops (Mux does not — it needs a second file). Video ops do not chain — chains are audio filter chains only.'),
                  _wmh('OP CHAINS'),
                  _wmb('Build an ordered chain from the 20 single-file DSP ops and save it by name. RUN CHAIN applies every op in ONE ffmpeg pass (filters concatenated) and writes one file. Normalize inside a chain is single-pass loudnorm — the two-pass analysis only runs when Normalize is executed directly. Mix/Join/Duck/Clip/Convert cannot be chained — they need a second file or a different shape.'),
                  _wmh('BATCH QUEUE'),
                  _wmb('Runs the currently selected operation over every file in the queue, one at a time, with the current slider and settings values. Each file gets its own OK/FAIL line in the report. Only single-file transforms batch — Mix, Join, Duck, scans, Split, and Whisper do not.'),
                  _wmh('MULTITRACK MIX'),
                  _wmb('MIX WITH FILE layers the main file with up to 6 extra tracks, each with gain and pan. Tracks resample to 48k stereo (soxr) and mix through amix with a 0.95 limiter. Over 3 tracks or 15 minutes total is flagged HEAVY — the RAM guard unloads EmbeddingGemma first. GAPLESS JOIN butt-joins two files with no crossfade and no gap.'),
                  _wmh('WAVE SELECTION'),
                  _wmb('Drag on WAVEFORM STUDIO to select a region — DELETE REGION removes exactly that selection to the millisecond. Typing bounds by hand clears the exact selection and uses the typed HH:MM:SS instead.'),
                  _wmh('FILTER FAULTS'),
                  _wmb('If a filter is missing from this FFmpeg build (sidechaincompress, chorus, compand, firequalizer, volumedetect, silencedetect are all unverified on device), the op fails loudly with the filter name and its real docs — never a silent no-op. Missing encoders (libx264, libvpx-vp9) fail the same loud way with their real -h docs.'),
                  _wmh('WHISPER'),
                  _wmb('Transcribe produces a plain text block and writes a sidecar .srt. First run extracts the bundled 141MB model. Cancel stops the FFmpeg session and discards the partial output.'),
                  _wmh('RECORDER'),
                  _wmb('REC captures 48k mono PCM WAV by default. HALT auto-exports the recording to cache. STOP finishes the file. AAC is thefallback mode.'),
                  _wmh('MEDIAINFO & FORENSICS'),
                  _wmb('Tap the analytics icon in the header (or choose Lossless Audio Extract / Split Chapters / Fake-Lossless Audit) to inspect containers, streams, FastStart atoms, EBU R128 + DR crest, 16/19.5 kHz MP3 brickwall shelves, and split chapters with -c copy.'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wmh(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(t, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)));

  Widget _wmb(String t) => Text(t, style: const TextStyle(fontFamily: 'VT323', fontSize: 15, color: Colors.white70, height: 1.35));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: SovereignState.accentColor,
      builder: (context, themeColor, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "THE SCALPEL & STUDIO",
                        style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 22, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 1.2)
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.analytics_outlined, color: Colors.cyanAccent),
                      tooltip: "MEDIAINFO & FORENSICS",
                      onPressed: _isProcessing
                          ? null
                          : () {
                              TapFeedback.machineTap();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MediaInspectorScreen(
                                    initialPath: _selectedFilePath.isEmpty ? null : _selectedFilePath,
                                  ),
                                ),
                              );
                            },
                    ),
                    IconButton(
                      icon: Icon(Icons.help_outline, color: themeColor),
                      tooltip: "FIELD MANUAL",
                      onPressed: _showWorkbenchManual,
                    ),
                  ],
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
                          fxColor: Colors.redAccent,
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
                        _waveSelInMs = selIn.inMilliseconds;
                        _waveSelOutMs = selOut.inMilliseconds;
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
                                    if (!mounted) return;
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
                            onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; },
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
                            onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; },
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

                  if (_selectedOperation == "Video Trim (Re-Encode)") ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startCtrl,
                            onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; },
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
                            onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; },
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
                    const SizedBox(height: 8),
                    const Text("Re-encodes for frame-accurate cuts. Clip is -c copy (keyframe boundaries only).", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                  ],

                  if (_selectedOperation == "Video Rotate / Flip") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text("ROTATE:", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.white54)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _videoRotate,
                                    isExpanded: true,
                                    dropdownColor: Colors.black,
                                    icon: Icon(Icons.arrow_drop_down, color: themeColor),
                                    items: const ["NONE", "90 CW", "180", "90 CCW"].map((r) => DropdownMenuItem<String>(
                                      value: r,
                                      child: Text(r, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 13, color: Colors.white)),
                                    )).toList(),
                                    onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _videoRotate = v); },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            title: const Text("FLIP HORIZONTAL", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                            activeThumbColor: themeColor,
                            activeTrackColor: themeColor.withAlpha(76),
                            value: _videoFlipH,
                            onChanged: _isProcessing ? null : (val) => setState(() => _videoFlipH = val),
                          ),
                          SwitchListTile(
                            title: const Text("FLIP VERTICAL", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.white70)),
                            activeThumbColor: themeColor,
                            activeTrackColor: themeColor.withAlpha(76),
                            value: _videoFlipV,
                            onChanged: _isProcessing ? null : (val) => setState(() => _videoFlipV = val),
                          ),
                          const Text("Rotation runs first (transpose), then flips. Audio is copied untouched.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Video Scale / Resize") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _videoScale,
                          isExpanded: true,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: const ["1080p", "720p", "480p"].map((s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text("SCALE TO $s (aspect preserved)", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                          )).toList(),
                          onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _videoScale = v); },
                        ),
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Video Crop (Center)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _videoCropAspect,
                          isExpanded: true,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: const ["16:9", "4:3", "1:1", "9:16"].map((a) => DropdownMenuItem<String>(
                            value: a,
                            child: Text("CENTER CROP $a", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                          )).toList(),
                          onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _videoCropAspect = v); },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("Center crop — the frame is cut equally from both sides.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                  ],

                  if (_selectedOperation == "Video Convert (Container)") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _targetVideoFormat,
                          isExpanded: true,
                          dropdownColor: Colors.black,
                          icon: Icon(Icons.arrow_drop_down, color: themeColor),
                          items: _videoFormats.map((fmt) => DropdownMenuItem<String>(
                            value: fmt,
                            child: Text("TARGET CONTAINER: .$fmt", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                          )).toList(),
                          onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _targetVideoFormat = v); },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text("libx264 + aac for mp4/mkv, libvpx-vp9 + opus for webm. A missing encoder fails loudly with its real docs.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
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

            if (_selectedOperation == "Scan Volume (volumedetect)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.cyanAccent.withAlpha(127)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("VOLUME SCANNER (VOLUMEDETECT)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                    const SizedBox(height: 6),
                    const Text("Reports mean volume, max volume, and headroom to -1 dBTP. Read-only — writes nothing.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _scanVolume,
                      icon: const Icon(Icons.volume_up, color: Colors.cyanAccent, size: 18),
                      label: const Text("SCAN VOLUME", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                    if (_volumeReport.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.cyanAccent.withAlpha(76))),
                        child: Text("> $_volumeReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.3)),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Scan Silence (silencedetect)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.amberAccent.withAlpha(127)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("SILENCE SCANNER (SILENCEDETECT)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                    const SizedBox(height: 6),
                    const Text("Lists every silence (threshold -45dB, min 0.3s) with start, end, and duration. Read-only — writes nothing.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _scanSilence,
                      icon: const Icon(Icons.graphic_eq, color: Colors.amberAccent, size: 18),
                      label: const Text("SCAN SILENCE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                    if (_silenceReport.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.amberAccent.withAlpha(76))),
                        child: Text("> $_silenceReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.3)),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Split On Silence (silencedetect)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.amberAccent.withAlpha(127)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("SPLIT ON SILENCE (SILENCEDETECT)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                    const SizedBox(height: 6),
                    const Text("Cuts the file at every silence (threshold -45dB, min 0.3s) into numbered tracks. Segments shorter than the minimum are dropped. Same container, re-encoded for sample-accurate cuts.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("MIN SEGMENT", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        Text("${_splitMinSegmentSec.toStringAsFixed(1)}s", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _splitMinSegmentSec, min: 0.5, max: 10, divisions: 19,
                      activeColor: Colors.amberAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _splitMinSegmentSec = val),
                    ),
                    if (_splitReport.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.amberAccent.withAlpha(76))),
                        child: Text("> $_splitReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.3)),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Sidechain Duck (sidechaincompress)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SIDECHAIN DUCKING — VOICE DUCKS MUSIC", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("THRESHOLD", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                        Text("${_duckThresholdDb.toStringAsFixed(0)} dB", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _duckThresholdDb, min: -40, max: -1, divisions: 39,
                      activeColor: Colors.cyanAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _duckThresholdDb = val),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("RATIO", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                        Text("${_duckRatio.toStringAsFixed(1)}:1", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _duckRatio, min: 2, max: 20, divisions: 36,
                      activeColor: Colors.tealAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _duckRatio = val),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("ATTACK", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                        Text("${_duckAttackMs.toStringAsFixed(0)} ms", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _duckAttackMs, min: 10, max: 1000, divisions: 33,
                      activeColor: Colors.amberAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _duckAttackMs = val),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("RELEASE", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                        Text("${_duckReleaseMs.toStringAsFixed(0)} ms", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _duckReleaseMs, min: 50, max: 2000, divisions: 39,
                      activeColor: Colors.purpleAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _duckReleaseMs = val),
                    ),
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Chorus (spatial)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("CHORUS DEPTH", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                        Text("${_chorusDepthMs.toStringAsFixed(1)} ms", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _chorusDepthMs, min: 0.5, max: 5, divisions: 18,
                      activeColor: Colors.cyanAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _chorusDepthMs = val),
                    ),
                    const Text("in 0.7 / out 0.9 • delay 55ms • decay 0.4 • speed 0.25Hz", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Compand (dynamic shaping)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("MAKEUP GAIN", style: TextStyle(fontFamily: 'ShareTechMono', fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                        Text("${_compandGainDb >= 0 ? '+' : ''}${_compandGainDb.toStringAsFixed(1)} dB", style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white)),
                      ],
                    ),
                    Slider(
                      value: _compandGainDb, min: -12, max: 12, divisions: 24,
                      activeColor: Colors.tealAccent, inactiveColor: Colors.white24,
                      onChanged: _isProcessing ? null : (val) => setState(() => _compandGainDb = val),
                    ),
                    const Text("Gentle curve: -80/-80 • -60/-50 • -30/-25 • -10/-8 • 0/0 • attack 50ms • release 300ms", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ),
            ],

            if (_selectedOperation == "Trim To Silence (Precise)") ...[
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(76))),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("PRECISE TRIM — 50ms WINDOWS AT -50dB", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                    SizedBox(height: 4),
                    Text("Tighter than TRIM SILENCE (0.3s/0.8s windows at -45dB). Cuts leading and trailing silence to the frame.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
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

                  if (_selectedOperation == "Parametric EQ" || _selectedOperation == "Firequalizer Curve EQ") ...[
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
                          const Text("Drag a selection on the WAVEFORM STUDIO above — it deletes to the exact millisecond — or type bounds below.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: TextField(controller: _startCtrl, onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; }, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.greenAccent), decoration: const InputDecoration(labelText: "IN", labelStyle: TextStyle(color: Colors.white38), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("→", style: TextStyle(color: Colors.white24))),
                              Expanded(child: TextField(controller: _endCtrl, onChanged: (_) { _waveSelInMs = null; _waveSelOutMs = null; }, style: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.redAccent), decoration: const InputDecoration(labelText: "OUT", labelStyle: TextStyle(color: Colors.white38), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _isProcessing || _isRecording ? null : _executeOperation,
                            icon: const Icon(Icons.content_cut, color: Colors.redAccent, size: 18),
                            label: const Text("DELETE WAVE SELECTION NOW", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Mix With File") ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text("MULTITRACK MIX (MAIN + UP TO 6)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70))),
                              OutlinedButton.icon(
                                onPressed: _isProcessing ? null : _pickMixTrack,
                                icon: const Icon(Icons.library_add, size: 16),
                                label: const Text("ADD TRACK", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11)),
                                style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text("MAIN: ${_selectedFilePath.split('/').last} (gain 1.00 / center)", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                          if (_mixTracks.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text("No extra tracks yet — ADD TRACK to layer audio over the main file.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                            ),
                          for (int i = 0; i < _mixTracks.length; i++) ...[
                            const Divider(color: Colors.white12, height: 20),
                            Row(
                              children: [
                                Expanded(child: Text("TRACK ${i + 1}: ${_mixTracks[i].path.split('/').last}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white70))),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                  tooltip: "REMOVE TRACK",
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  padding: EdgeInsets.zero,
                                  onPressed: _isProcessing ? null : () => setState(() => _mixTracks.removeAt(i)),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("GAIN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white70)),
                                Expanded(
                                  child: Slider(
                                    value: _mixTracks[i].gain, min: 0, max: 2, divisions: 40,
                                    activeColor: themeColor, inactiveColor: Colors.white24,
                                    onChanged: _isProcessing ? null : (v) => setState(() => _mixTracks[i].gain = v),
                                  ),
                                ),
                                Text("${_mixTracks[i].gain.toStringAsFixed(2)}x", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text("PAN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white70)),
                                Expanded(
                                  child: Slider(
                                    value: _mixTracks[i].pan, min: -1, max: 1, divisions: 20,
                                    activeColor: themeColor, inactiveColor: Colors.white24,
                                    onChanged: _isProcessing ? null : (v) => setState(() => _mixTracks[i].pan = v),
                                  ),
                                ),
                                Text(_mixTracks[i].pan == 0 ? "C" : (_mixTracks[i].pan < 0 ? "L${(-_mixTracks[i].pan * 100).round()}%" : "R${(_mixTracks[i].pan * 100).round()}%"), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white)),
                              ],
                            ),
                          ],
                          if (_mixGuardWarning(_mixTracks) != null) ...[
                            const SizedBox(height: 8),
                            Text("> ${_mixGuardWarning(_mixTracks)!}", style: const TextStyle(fontFamily: 'VT323', fontSize: 13, color: Colors.amberAccent)),
                          ],
                          const SizedBox(height: 4),
                          const Text("All tracks resampled to 48k stereo (soxr), mixed with amix, peak-limited at 0.95.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white38)),
                        ],
                      ),
                    ),
                  ],

                  if (_selectedOperation == "Crossfade Join" || _selectedOperation == "Sidechain Duck (sidechaincompress)" || _selectedOperation == "Gapless Join (concat)" || _selectedOperation == "Mux Video + Audio") ...[
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
                          if (_selectedOperation == "Sidechain Duck (sidechaincompress)") ...[
                            const SizedBox(height: 8),
                            const Text("MAIN = MUSIC TO DUCK • SECOND = VOICE / SIDECHAIN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                          ],
                          if (_selectedOperation == "Gapless Join (concat)") ...[
                            const SizedBox(height: 8),
                            const Text("Butt-join, no crossfade, no gap. Both files resampled to 48k stereo first.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                          ],
                          if (_selectedOperation == "Mux Video + Audio") ...[
                            const SizedBox(height: 8),
                            const Text("MAIN = VIDEO • SECOND = AUDIO TRACK. Video is copied, audio re-encoded (aac / opus for webm).", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
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

                  if (_selectedOperation != "Clip Media (The Scalpel)" && _selectedOperation != "Extract Audio (Video to MP3)" && !_isVideoOp(_selectedOperation)) ...[
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

                  if (_filterFaultReport.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.orangeAccent.withAlpha(127)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(_filterFaultReport, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70, height: 1.3)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  CyberTapFeedback(
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
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("OP CHAINS (SAVED PRESETS)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                        const SizedBox(height: 4),
                        const Text("Stack the 20 single-file DSP ops in order and run them in ONE ffmpeg pass. Normalize inside a chain is single-pass loudnorm. Mix/Join/Duck/Clip/Convert cannot chain.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                        const SizedBox(height: 12),
                        if (_chainOps.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text("Chain is empty — pick an op below and ADD TO CHAIN.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                          ),
                        for (int i = 0; i < _chainOps.length; i++) ...[
                          Row(
                            children: [
                              Text("${i + 1}. ", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
                              Expanded(child: Text(_chainOps[i].toUpperCase(), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70))),
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 16),
                                tooltip: "MOVE UP",
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                onPressed: _isProcessing || i == 0 ? null : () => setState(() { final op = _chainOps.removeAt(i); _chainOps.insert(i - 1, op); }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, size: 16),
                                tooltip: "MOVE DOWN",
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                onPressed: _isProcessing || i == _chainOps.length - 1 ? null : () => setState(() { final op = _chainOps.removeAt(i); _chainOps.insert(i + 1, op); }),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                tooltip: "REMOVE",
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                onPressed: _isProcessing ? null : () => setState(() => _chainOps.removeAt(i)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(76))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _chainAddOp,
                                    isExpanded: true,
                                    dropdownColor: Colors.black,
                                    icon: Icon(Icons.arrow_drop_down, color: themeColor),
                                    items: _chainableOps.map((op) => DropdownMenuItem<String>(value: op, child: Text(op.toUpperCase(), style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)))).toList(),
                                    onChanged: _isProcessing ? null : (v) { if (v != null) setState(() => _chainAddOp = v); },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _isProcessing ? null : () => setState(() => _chainOps.add(_chainAddOp)),
                              style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                              child: Text("ADD", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _chainNameCtrl,
                                style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor),
                                decoration: InputDecoration(
                                  labelText: 'CHAIN NAME',
                                  labelStyle: const TextStyle(fontFamily: 'ShareTechMono', color: Colors.white54),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor.withAlpha(76))),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: themeColor)),
                                  filled: true,
                                  fillColor: Colors.black,
                                ),
                                enabled: !_isProcessing,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _isProcessing ? null : _saveChain,
                              style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                              child: Text("SAVE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(76))),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedChain,
                                    isExpanded: true,
                                    dropdownColor: Colors.black,
                                    hint: const Text("SAVED CHAINS", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white38)),
                                    icon: Icon(Icons.arrow_drop_down, color: themeColor),
                                    items: _savedChains.keys.map((name) => DropdownMenuItem<String>(value: name, child: Text("$name (${_savedChains[name]!.length} OPS)", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white)))).toList(),
                                    onChanged: _isProcessing ? null : (v) {
                                      if (v != null) setState(() { _selectedChain = v; _chainOps.clear(); _chainOps.addAll(_savedChains[v]!); });
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: "DELETE SAVED CHAIN",
                              onPressed: _isProcessing || _selectedChain == null ? null : () => _deleteChain(_selectedChain!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isProcessing || _chainOps.isEmpty ? null : _executeChain,
                          icon: Icon(Icons.playlist_play, color: themeColor, size: 18),
                          label: Text("RUN CHAIN (${_chainOps.length} OPS)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(127))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("BATCH QUEUE", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                        const SizedBox(height: 4),
                        const Text("Runs the currently selected operation over every file below, one at a time, with the current slider and settings values. Each file gets its own OK/FAIL line.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white54)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isProcessing ? null : _pickBatchFiles,
                                icon: Icon(Icons.library_add, color: themeColor, size: 18),
                                label: Text("ADD FILES", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(vertical: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _isProcessing || _batchFiles.isEmpty ? null : () => setState(() { _batchFiles.clear(); _batchReport = ""; }),
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                              child: const Text("CLEAR", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        if (_batchFiles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text("Queue is empty — ADD FILES to batch the selected operation.", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38)),
                          ),
                        for (int i = 0; i < _batchFiles.length; i++) ...[
                          Row(
                            children: [
                              Expanded(child: Text("${i + 1}. ${_batchFiles[i].split('/').last}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70))),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                tooltip: "REMOVE",
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                onPressed: _isProcessing ? null : () => setState(() => _batchFiles.removeAt(i)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_isProcessing && _activeQueue != null)
                          OutlinedButton.icon(
                            onPressed: () {
                              _activeQueue?.cancel();
                              setState(() => _statusMessage = "Cancelling Batch Queue...");
                            },
                            icon: const Icon(Icons.stop, color: Colors.redAccent, size: 18),
                            label: const Text("CANCEL BATCH", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _isProcessing || _batchFiles.isEmpty ? null : _executeBatch,
                            icon: Icon(Icons.play_arrow, color: themeColor, size: 18),
                            label: Text("RUN BATCH (${_batchFiles.length} FILES)", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 12, color: themeColor, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(side: BorderSide(color: themeColor), padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        if (_batchReport.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.black, border: Border.all(color: themeColor.withAlpha(76))),
                            child: Text("> $_batchReport", style: const TextStyle(fontFamily: 'VT323', fontSize: 14, color: Colors.white70, height: 1.3)),
                          ),
                        ],
                      ],
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
