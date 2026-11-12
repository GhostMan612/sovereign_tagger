// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dsp_builders.dart';

class MixTrack {
  final String path;
  final int? durationMs;
  double gain;
  double pan;

  MixTrack({
    required this.path,
    this.durationMs,
    this.gain = 1.0,
    this.pan = 0.0,
  }) {
    validateMediaPath(path, name: 'mix track path');
    if (!gain.isFinite || gain < 0) {
      throw ArgumentError('ERR: Track gain must be non-negative.');
    }
    if (!pan.isFinite || pan < -1.0 || pan > 1.0) {
      throw ArgumentError('ERR: Track pan must be between -1.0 (left) and +1.0 (right).');
    }
  }

  MixTrack copyWith({
    String? path,
    int? durationMs,
    double? gain,
    double? pan,
  }) {
    return MixTrack(
      path: path ?? this.path,
      durationMs: durationMs ?? this.durationMs,
      gain: gain ?? this.gain,
      pan: pan ?? this.pan,
    );
  }
}

class DspOperation {
  static const List<String> allOperations = [
    "Extract Audio (Video to MP3)",
    "Lossless Audio Extract (-c:a copy)",
    "Split Chapters Losslessly (-c copy)",
    "Fake-Lossless & DR Audit",
    "Clip Media (The Scalpel)",
    "Convert Format",
    "Normalize Audio (LUFS -14)",
    "Granular Audio DSP (Speed/Reverb)",
    "Apply Fades",
    "Fold To Mono",
    "Trim Silence",
    "Trim To Silence (Precise)",
    "AI Denoise (afftdn)",
    "Parametric EQ",
    "Compress Dynamics",
    "15-Band Equalizer (AutoEq)",
    "Scan ReplayGain (EBU R128)",
    "Scan Volume (volumedetect)",
    "Scan Silence (silencedetect)",
    "Split On Silence (silencedetect)",
    "Transcribe (Whisper AI)",
    "Insert Silence",
    "Delete Region",
    "Mix With File",
    "Crossfade Join",
    "Gapless Join (concat)",
    "Sidechain Duck (sidechaincompress)",
    "Click/Pop Repair (adeclick)",
    "De-Esser",
    "Limiter",
    "Multiband Compress (mcompand)",
    "Chorus (spatial)",
    "Compand (dynamic shaping)",
    "Firequalizer Curve EQ",
    "DC/Rumble Fix (highpass)",
    "Tone Generator (Test Signals)",
    "Spectrogram Snapshot",
    "Video Trim (Re-Encode)",
    "Video Rotate / Flip",
    "Video Scale / Resize",
    "Video Crop (Center)",
    "Mute Video (Drop Audio)",
    "Extract Audio (Video to M4A)",
    "Video Convert (Container)",
    "Mux Video + Audio"
  ];

  static const List<String> chainableOperations = [
    "Normalize Audio (LUFS -14)",
    "Granular Audio DSP (Speed/Reverb)",
    "Apply Fades",
    "Fold To Mono",
    "Trim Silence",
    "Trim To Silence (Precise)",
    "AI Denoise (afftdn)",
    "Parametric EQ",
    "Compress Dynamics",
    "15-Band Equalizer (AutoEq)",
    "Insert Silence",
    "Delete Region",
    "Click/Pop Repair (adeclick)",
    "De-Esser",
    "Limiter",
    "Multiband Compress (mcompand)",
    "Chorus (spatial)",
    "Compand (dynamic shaping)",
    "Firequalizer Curve EQ",
    "DC/Rumble Fix (highpass)",
  ];

  static const List<String> videoOperations = [
    "Video Trim (Re-Encode)",
    "Video Rotate / Flip",
    "Video Scale / Resize",
    "Video Crop (Center)",
    "Mute Video (Drop Audio)",
    "Extract Audio (Video to M4A)",
    "Video Convert (Container)",
    "Mux Video + Audio",
  ];

  static const List<String> videoFormats = ["mp4", "mkv", "webm"];
  static const List<String> audioFormats = ["mp3", "wav", "flac", "ogg", "m4a"];

  static const List<String> forensicOperations = [
    "Lossless Audio Extract (-c:a copy)",
    "Split Chapters Losslessly (-c copy)",
    "Fake-Lossless & DR Audit",
  ];

  static const List<String> preserveOperations = [
    "Normalize Audio (LUFS -14)",
    "Granular Audio DSP (Speed/Reverb)",
    "Apply Fades",
    "Fold To Mono",
    "Trim Silence",
    "Trim To Silence (Precise)",
    "AI Denoise (afftdn)",
    "Parametric EQ",
    "Compress Dynamics",
    "15-Band Equalizer (AutoEq)",
    "Insert Silence",
    "Delete Region",
    "Click/Pop Repair (adeclick)",
    "De-Esser",
    "Limiter",
    "Multiband Compress (mcompand)",
    "Chorus (spatial)",
    "Compand (dynamic shaping)",
    "Firequalizer Curve EQ",
    "DC/Rumble Fix (highpass)"
  ];

  static bool isBatchable(String op) {
    return chainableOperations.contains(op) ||
        op == "Convert Format" ||
        op == "Extract Audio (Video to MP3)" ||
        (videoOperations.contains(op) && op != "Mux Video + Audio");
  }

  static bool isVideoOp(String op) => videoOperations.contains(op);

  static bool requiresVideoInput(String op) => videoOperations.contains(op);

  static bool producesVideoOutput(String op) =>
      videoOperations.contains(op) && op != "Extract Audio (Video to M4A)";

  static bool producesAudioOutput(String op) => !producesVideoOutput(op);

  static bool isForensicOp(String op) => forensicOperations.contains(op);

  static bool isPreserveOp(String op) => preserveOperations.contains(op);

  static String outputExtension(
    String inputPath,
    String op, {
    String targetAudioFormat = 'mp3',
    String targetVideoFormat = 'mp4',
  }) {
    if (op == "Convert Format") return targetAudioFormat;
    if (op == "Extract Audio (Video to MP3)") return "mp3";
    if (op == "Extract Audio (Video to M4A)") return "m4a";
    if (op == "Video Convert (Container)") return targetVideoFormat;

    final parts = inputPath.split('.');
    final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";

    if (isVideoOp(op)) {
      return videoFormats.contains(srcExt) ? srcExt : "mp4";
    }
    return preservedAudioContainers.contains(srcExt) ? srcExt : "flac";
  }
}

enum BatchJobStatus {
  pending,
  running,
  completed,
  failed,
  skipped,
}

class BatchJob {
  final String id;
  final String inputPath;
  final String operation;
  BatchJobStatus status;
  double progress;
  String? outputUri;
  String? errorMessage;
  DateTime? startedAt;
  DateTime? completedAt;

  BatchJob({
    required this.id,
    required this.inputPath,
    required this.operation,
    this.status = BatchJobStatus.pending,
    this.progress = 0.0,
    this.outputUri,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  String get fileName => inputPath.split('/').last;

  String get baseName {
    final n = fileName;
    return n.contains('.') ? n.substring(0, n.lastIndexOf('.')) : n;
  }

  bool get isFinished =>
      status == BatchJobStatus.completed ||
      status == BatchJobStatus.failed ||
      status == BatchJobStatus.skipped;

  bool get isSuccess => status == BatchJobStatus.completed;

  String get summary {
    switch (status) {
      case BatchJobStatus.pending:
        return "PENDING";
      case BatchJobStatus.running:
        return "RUNNING (${(progress * 100).toInt()}%)";
      case BatchJobStatus.completed:
        return outputUri != null ? "OK -> $outputUri" : "OK";
      case BatchJobStatus.failed:
        return "FAIL: ${errorMessage ?? 'Unknown error'}";
      case BatchJobStatus.skipped:
        return "SKIP: ${errorMessage ?? 'Skipped'}";
    }
  }
}

class MasteringTarget {
  final double targetLufs;
  final double maxTruePeakDbtp;
  final double maxLoudnessRangeLu;
  final String mode;

  const MasteringTarget({
    required this.targetLufs,
    required this.maxTruePeakDbtp,
    required this.maxLoudnessRangeLu,
    required this.mode,
  });

  const MasteringTarget.streaming()
      : targetLufs = -14.0,
        maxTruePeakDbtp = -1.0,
        maxLoudnessRangeLu = 11.0,
        mode = "TWO-PASS LOUDNORM";

  const MasteringTarget.broadcast()
      : targetLufs = -23.0,
        maxTruePeakDbtp = -1.0,
        maxLoudnessRangeLu = 7.0,
        mode = "TWO-PASS LOUDNORM";

  const MasteringTarget.podcast()
      : targetLufs = -16.0,
        maxTruePeakDbtp = -1.0,
        maxLoudnessRangeLu = 9.0,
        mode = "TWO-PASS LOUDNORM";

  const MasteringTarget.dynamicCompression()
      : targetLufs = -14.0,
        maxTruePeakDbtp = -1.0,
        maxLoudnessRangeLu = 14.0,
        mode = "DYNAMIC (dynaudnorm)";
}

class AudioInspectResult {
  final double? meanVolumeDb;
  final double? maxVolumeDb;
  final double? headroomDb;
  final int? samples;
  final double? integratedLufs;
  final double? truePeakDbtp;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final List<({double start, double? end})> silences;
  final double totalSilenceSec;

  const AudioInspectResult({
    this.meanVolumeDb,
    this.maxVolumeDb,
    this.headroomDb,
    this.samples,
    this.integratedLufs,
    this.truePeakDbtp,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.silences = const [],
    this.totalSilenceSec = 0.0,
  });
}
