// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:math';

const List<String> preservedAudioContainers = ['mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus'];

const List<int> equalizer15Frequencies = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

void validateMediaPath(String path, {String name = 'media path'}) {
  if (path.trim().isEmpty) {
    throw ArgumentError('ERR: $name cannot be empty.');
  }
  if (path.contains('\u0000') || path.contains('\n') || path.contains('\r')) {
    throw ArgumentError('ERR: $name contains illegal control characters.');
  }
}

void validateTimeHms(String hms, {String name = 'time code'}) {
  final trimmed = hms.trim();
  final timeFmt = RegExp(r'^\d{1,2}:\d{2}:\d{2}$');
  if (!timeFmt.hasMatch(trimmed)) {
    throw ArgumentError('ERR: $name must be formatted as HH:MM:SS.');
  }
}

String buildAudioCodecArgs(String container, {int bitDepth = 16}) {
  switch (container.toLowerCase()) {
    case 'flac':
      return bitDepth == 24 ? '-c:a flac -sample_fmt s32' : '-c:a flac';
    case 'wav':
      return bitDepth == 24 ? '-c:a pcm_s24le' : '-c:a pcm_s16le';
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

String buildResampleFilter(String sampleRate) {
  if (sampleRate == "Source" || sampleRate.isEmpty) return "";
  final rate = int.tryParse(sampleRate);
  if (rate != null && (rate < 8000 || rate > 384000)) {
    throw ArgumentError('ERR: Invalid sample rate $sampleRate.');
  }
  return "aresample=$sampleRate:resampler=soxr";
}

String buildVolumeDetectArgs(String path) {
  validateMediaPath(path, name: 'input path');
  return '-y -i "$path" -af volumedetect -f null -';
}

String buildSilenceDetectArgs(String path, {double noiseDb = -45.0, double minDurationSec = 0.3}) {
  validateMediaPath(path, name: 'input path');
  if (!noiseDb.isFinite || noiseDb > 0) {
    throw ArgumentError('ERR: Noise threshold must be <= 0 dB.');
  }
  if (!minDurationSec.isFinite || minDurationSec <= 0) {
    throw ArgumentError('ERR: Minimum silence duration must be > 0 seconds.');
  }
  return '-y -i "$path" -af silencedetect=noise=${noiseDb.toStringAsFixed(0)}dB:d=${minDurationSec.toStringAsFixed(1)} -f null -';
}

String buildEbuR128Args(String path) {
  validateMediaPath(path, name: 'input path');
  return '-y -i "$path" -af ebur128 -f null -';
}

String buildLoudnormFirstPassArgs(String path, {double targetI = -14.0, double targetLra = 11.0, double targetTp = -1.5}) {
  validateMediaPath(path, name: 'input path');
  if (!targetI.isFinite || !targetLra.isFinite || !targetTp.isFinite) {
    throw ArgumentError('ERR: Loudnorm targets must be finite.');
  }
  return '-y -i "$path" -af "loudnorm=I=${targetI.toStringAsFixed(0)}:LRA=${targetLra.toStringAsFixed(0)}:TP=${targetTp.toStringAsFixed(1)}:print_format=json" -f null -';
}

String buildLoudnormFilter({
  String mode = "TWO-PASS LOUDNORM",
  double targetI = -14.0,
  double targetLra = 11.0,
  double targetTp = -1.5,
  Map<String, String>? measured,
}) {
  if (mode == "DYNAMIC (dynaudnorm)") {
    return 'dynaudnorm=p=0.9:m=12';
  }
  if (!targetI.isFinite || !targetLra.isFinite || !targetTp.isFinite) {
    throw ArgumentError('ERR: Loudnorm targets must be finite.');
  }
  if (measured != null && measured.containsKey('input_i') && measured['input_i']!.isNotEmpty) {
    final mi = measured['input_i'] ?? '-14.0';
    final mlra = measured['input_lra'] ?? '11.0';
    final mtp = measured['input_tp'] ?? '-1.5';
    final mthresh = measured['input_thresh'] ?? '-24.0';
    final offset = measured['target_offset'] ?? '0.0';
    return 'loudnorm=I=${targetI.toStringAsFixed(0)}:LRA=${targetLra.toStringAsFixed(0)}:TP=${targetTp.toStringAsFixed(1)}:measured_I=$mi:measured_LRA=$mlra:measured_TP=$mtp:measured_thresh=$mthresh:offset=$offset:linear=true';
  }
  return 'loudnorm=I=${targetI.toStringAsFixed(0)}:LRA=${targetLra.toStringAsFixed(0)}:TP=${targetTp.toStringAsFixed(1)}';
}

Map<String, String>? parseLoudnormMeasurements(String output) {
  Map<String, String>? parseMap(dynamic decoded) {
    if (decoded is Map<String, dynamic> && decoded.containsKey('input_i')) {
      final inputI = decoded['input_i']?.toString() ?? '';
      if (inputI.isEmpty) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return null;
  }
  try {
    final matches = RegExp(r'\{[^{}]*"input_i"[^{}]*\}').allMatches(output);
    if (matches.isNotEmpty) {
      final last = matches.last.group(0)!;
      final parsed = parseMap(jsonDecode(last));
      if (parsed != null) return parsed;
    }
  } catch (_) {}
  try {
    final start = output.lastIndexOf('{');
    final end = output.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = parseMap(jsonDecode(output.substring(start, end + 1)));
      if (parsed != null) return parsed;
    }
  } catch (_) {}
  return null;
}

List<({double start, double? end})> parseSilences(String output) {
  final regex = RegExp(r'silence_start:\s*([\d.]+)|silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)');
  final matches = regex.allMatches(output);
  final out = <({double start, double? end})>[];
  double? currentStart;
  for (final m in matches) {
    final startStr = m.group(1);
    final endStr = m.group(2);
    if (startStr != null) {
      if (currentStart != null) {
        out.add((start: currentStart, end: null));
      }
      currentStart = double.tryParse(startStr);
    } else if (endStr != null && currentStart != null) {
      final endVal = double.tryParse(endStr);
      out.add((start: currentStart, end: endVal));
      currentStart = null;
    }
  }
  if (currentStart != null) {
    out.add((start: currentStart, end: null));
  }
  return out;
}

List<({double start, double end})> splitSegmentsFromSilence(String output, int? durationMs, {double minSegmentSec = 2.0}) {
  if (minSegmentSec <= 0 || !minSegmentSec.isFinite) {
    throw ArgumentError('ERR: Minimum segment length must be positive.');
  }
  final silences = parseSilences(output);
  double? totalSec;
  if (durationMs != null && durationMs > 0) {
    totalSec = durationMs / 1000.0;
  } else if (silences.isNotEmpty && silences.last.end != null) {
    totalSec = silences.last.end;
  } else if (silences.isNotEmpty) {
    totalSec = silences.last.start;
  }
  if (totalSec == null || totalSec <= 0) return [];
  final segments = <({double start, double end})>[];
  double cursor = 0.0;
  for (final s in silences) {
    if (s.start - cursor >= minSegmentSec) {
      segments.add((start: cursor, end: s.start));
    }
    if (s.end == null) return segments;
    cursor = s.end!;
  }
  if (totalSec - cursor >= minSegmentSec) {
    segments.add((start: cursor, end: totalSec));
  }
  return segments;
}

List<String> buildFadeFilter({double fadeInSec = 0.0, double fadeOutSec = 0.0, required double totalDurationSec}) {
  if (!fadeInSec.isFinite || fadeInSec < 0 || !fadeOutSec.isFinite || fadeOutSec < 0 || !totalDurationSec.isFinite || totalDurationSec < 0) {
    throw ArgumentError('ERR: Fade parameters must be non-negative finite values.');
  }
  final filters = <String>[];
  if (fadeInSec > 0) {
    filters.add("afade=t=in:st=0:d=${fadeInSec.toStringAsFixed(2)}");
  }
  if (fadeOutSec > 0) {
    final outStart = (totalDurationSec - fadeOutSec).clamp(0.0, totalDurationSec).toStringAsFixed(2);
    filters.add("afade=t=out:st=$outStart:d=${fadeOutSec.toStringAsFixed(2)}");
  }
  return filters;
}

List<String> buildGranularSpeedFilter({
  required double speed,
  required String pitchMode,
  bool isReversed = false,
  double reverbIntensity = 0.0,
}) {
  if (!speed.isFinite || speed <= 0) {
    throw ArgumentError('ERR: Audio speed must be a positive finite value.');
  }
  if (!reverbIntensity.isFinite || reverbIntensity < 0 || reverbIntensity > 1.0) {
    throw ArgumentError('ERR: Reverb intensity must be between 0.0 and 1.0.');
  }
  final filters = <String>[];
  if (isReversed) filters.add("areverse");
  if (speed != 1.0) {
    final s = speed.toStringAsFixed(2);
    switch (pitchMode) {
      case "RUBBERBAND (pitch only)":
        filters.add("rubberband=pitch=$s");
        break;
      case "ATEMPO (tempo only)":
        filters.add("atempo=${speed.clamp(0.5, 2.0).toStringAsFixed(2)}");
        break;
      default:
        filters.add("asetrate=44100*$s,aresample=44100");
    }
  }
  if (reverbIntensity > 0) {
    final delay = 60 + (reverbIntensity * 40);
    final decay = 0.2 + (reverbIntensity * 0.4);
    filters.add("aecho=0.8:0.88:$delay:$decay");
  }
  return filters;
}

List<String> buildEqFilter({
  double bass = 0.0,
  double lowMid = 0.0,
  double mid = 0.0,
  double highMid = 0.0,
  double treble = 0.0,
}) {
  if (!bass.isFinite || !lowMid.isFinite || !mid.isFinite || !highMid.isFinite || !treble.isFinite) {
    throw ArgumentError('ERR: EQ band values must be finite.');
  }
  final filters = <String>[];
  if (bass != 0) filters.add("bass=g=${bass.toStringAsFixed(1)}:f=100");
  if (lowMid != 0) filters.add("equalizer=f=320:t=q:w=1.2:g=${lowMid.toStringAsFixed(1)}");
  if (mid != 0) filters.add("equalizer=f=1000:t=q:w=1.2:g=${mid.toStringAsFixed(1)}");
  if (highMid != 0) filters.add("equalizer=f=3500:t=q:w=1.2:g=${highMid.toStringAsFixed(1)}");
  if (treble != 0) filters.add("treble=g=${treble.toStringAsFixed(1)}:f=8000");
  if (filters.isEmpty) throw StateError("ERR: All EQ Bands At Zero. Nothing To Apply.");
  return filters;
}

List<String> build15BandEqFilter(List<double> bands) {
  final filters = <String>[];
  final count = min(bands.length, equalizer15Frequencies.length);
  for (int i = 0; i < count; i++) {
    final b = bands[i];
    if (!b.isFinite) throw ArgumentError('ERR: EQ band value must be finite.');
    if (b != 0) {
      final freq = equalizer15Frequencies[i];
      filters.add("equalizer=f=$freq:t=q:w=1.2:g=${b.toStringAsFixed(1)}");
    }
  }
  if (filters.isEmpty) throw StateError("ERR: All EQ Bands At Zero. Nothing To Apply.");
  return filters;
}

String buildFirequalizerCurve({
  double bass = 0.0,
  double lowMid = 0.0,
  double mid = 0.0,
  double highMid = 0.0,
  double treble = 0.0,
}) {
  if (!bass.isFinite || !lowMid.isFinite || !mid.isFinite || !highMid.isFinite || !treble.isFinite) {
    throw ArgumentError('ERR: Firequalizer values must be finite.');
  }
  if (bass == 0 && lowMid == 0 && mid == 0 && highMid == 0 && treble == 0) {
    throw StateError("ERR: All EQ Bands At Zero. Nothing To Apply.");
  }
  return "firequalizer=gain_entry='entry(100,${bass.toStringAsFixed(1)});entry(320,${lowMid.toStringAsFixed(1)});entry(1000,${mid.toStringAsFixed(1)});entry(3500,${highMid.toStringAsFixed(1)});entry(8000,${treble.toStringAsFixed(1)})'";
}

String buildDeleteRegionFilter({required double startSec, required double endSec}) {
  if (!startSec.isFinite || !endSec.isFinite) {
    throw ArgumentError('ERR: Region timestamps must be finite.');
  }
  if (startSec < 0 || endSec < 0) {
    throw ArgumentError('ERR: Region timestamps must be non-negative.');
  }
  if (endSec <= startSec) {
    throw StateError("ERR: END Must Exceed START (use wave selection).");
  }
  return "aselect='not(between(t,$startSec,$endSec))',asetpts=N/SR/TB";
}

String buildMonoFoldFilter() {
  return "pan=mono|c0=0.5*c0+0.5*c1";
}

String buildInsertSilenceFilter({required double silenceSec, bool atStart = false}) {
  if (!silenceSec.isFinite || silenceSec <= 0) {
    throw ArgumentError('ERR: Silence duration must be positive and finite.');
  }
  final ms = (silenceSec * 1000).round();
  return atStart ? "adelay=$ms:all=1" : "apad=pad_dur=${silenceSec.toStringAsFixed(2)}";
}

String buildDeclickFilter() {
  return "adeclick";
}

String buildDeEsserFilter({double intensity = 0.5}) {
  if (!intensity.isFinite || intensity < 0.0 || intensity > 1.0) {
    throw ArgumentError('ERR: De-esser intensity must be between 0.0 and 1.0.');
  }
  return "deesser=i=${intensity.toStringAsFixed(2)}:m=0.5:f=0.5";
}

String buildLimiterFilter({double limit = 0.9, double attackMs = 5.0, double releaseMs = 50.0}) {
  if (!limit.isFinite || limit <= 0.0 || limit > 1.0) {
    throw ArgumentError('ERR: Limiter level must be between 0.0 (exclusive) and 1.0 (inclusive).');
  }
  if (!attackMs.isFinite || attackMs <= 0 || !releaseMs.isFinite || releaseMs <= 0) {
    throw ArgumentError('ERR: Attack and release times must be positive.');
  }
  return "alimiter=limit=${limit.toStringAsFixed(2)}:attack=${attackMs.toInt()}:release=${releaseMs.toInt()}";
}

String buildMcompandFilter() {
  return "mcompand";
}

String buildHighpassFilter({double freq = 10.0}) {
  if (!freq.isFinite || freq <= 0) {
    throw ArgumentError('ERR: Highpass frequency must be positive.');
  }
  return "highpass=f=${freq.toStringAsFixed(0)}";
}

String buildTrimSilenceFilter({bool precise = false}) {
  if (precise) {
    return "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05:stop_periods=-1:stop_threshold=-50dB:stop_silence=0.05";
  }
  return "silenceremove=start_periods=1:start_duration=0.3:start_threshold=-45dB:stop_periods=-1:stop_duration=0.8:stop_threshold=-45dB";
}

String buildChorusFilter({double depthMs = 2.0}) {
  if (!depthMs.isFinite || depthMs < 0.0) {
    throw ArgumentError('ERR: Chorus depth must be non-negative.');
  }
  return "chorus=0.7:0.9:55:0.4:0.25:${depthMs.toStringAsFixed(1)}";
}

String buildCompandFilter({double gainDb = 0.0}) {
  if (!gainDb.isFinite) {
    throw ArgumentError('ERR: Compand gain must be finite.');
  }
  return "compand=attacks=0.05:decays=0.3:points=-80/-80|-60/-50|-30/-25|-10/-8|0/0:gain=${gainDb.toStringAsFixed(1)}";
}

String buildDenoiseFilter({double noiseFloorDb = -25.0}) {
  if (!noiseFloorDb.isFinite || noiseFloorDb > 0) {
    throw ArgumentError('ERR: Denoise noise floor must be non-positive dB.');
  }
  return "afftdn=nf=${noiseFloorDb.toStringAsFixed(0)}";
}

String buildCompressorFilter({double threshold = 0.1, double ratio = 4.0, double attackMs = 50.0, double releaseMs = 500.0}) {
  if (!threshold.isFinite || threshold <= 0.0 || threshold > 1.0) {
    throw ArgumentError('ERR: Compressor threshold must be between 0.0 (exclusive) and 1.0 (inclusive).');
  }
  if (!ratio.isFinite || ratio < 1.0) {
    throw ArgumentError('ERR: Compressor ratio must be >= 1.0.');
  }
  if (!attackMs.isFinite || attackMs <= 0 || !releaseMs.isFinite || releaseMs <= 0) {
    throw ArgumentError('ERR: Compressor attack and release times must be positive.');
  }
  return "acompressor=threshold=${threshold.toStringAsFixed(1)}:ratio=${ratio.toStringAsFixed(1)}:attack=${attackMs.toInt()}:release=${releaseMs.toInt()}";
}

String buildSidechainDuckArgs({
  required String mainPath,
  required String sidechainPath,
  required String outPath,
  double thresholdDb = -20.0,
  double ratio = 8.0,
  double attackMs = 200.0,
  double releaseMs = 500.0,
  required String container,
  int bitDepth = 16,
}) {
  validateMediaPath(mainPath, name: 'main music path');
  validateMediaPath(sidechainPath, name: 'sidechain voice path');
  validateMediaPath(outPath, name: 'output path');
  if (!thresholdDb.isFinite || thresholdDb > 0) {
    throw ArgumentError('ERR: Ducking threshold must be <= 0 dB.');
  }
  if (!ratio.isFinite || ratio < 1.0) {
    throw ArgumentError('ERR: Ducking ratio must be >= 1.0.');
  }
  final thresh = pow(10.0, thresholdDb / 20.0).clamp(0.015625, 1.0).toDouble();
  final codec = buildAudioCodecArgs(container, bitDepth: bitDepth);
  return '-y -i "$mainPath" -i "$sidechainPath" -filter_complex "[0:a][1:a]sidechaincompress=threshold=${thresh.toStringAsFixed(4)}:ratio=${ratio.toStringAsFixed(1)}:attack=${attackMs.toStringAsFixed(0)}:release=${releaseMs.toStringAsFixed(0)}[out]" -map "[out]" -vn $codec "$outPath"';
}

String buildCrossfadeJoinArgs({
  required String firstPath,
  required String secondPath,
  required String outPath,
  double xfadeSec = 3.0,
  required String container,
  int bitDepth = 16,
}) {
  validateMediaPath(firstPath, name: 'first input path');
  validateMediaPath(secondPath, name: 'second input path');
  validateMediaPath(outPath, name: 'output path');
  if (!xfadeSec.isFinite || xfadeSec < 0) {
    throw ArgumentError('ERR: Crossfade duration must be non-negative.');
  }
  final codec = buildAudioCodecArgs(container, bitDepth: bitDepth);
  return '-y -i "$firstPath" -i "$secondPath" -filter_complex "[0:a][1:a]acrossfade=d=${xfadeSec.toStringAsFixed(2)}:c1=tri:c2=tri" $codec "$outPath"';
}

String buildGaplessJoinArgs({
  required String firstPath,
  required String secondPath,
  required String outPath,
  required String container,
  int bitDepth = 16,
}) {
  validateMediaPath(firstPath, name: 'first input path');
  validateMediaPath(secondPath, name: 'second input path');
  validateMediaPath(outPath, name: 'output path');
  final codec = buildAudioCodecArgs(container, bitDepth: bitDepth);
  return '-y -i "$firstPath" -i "$secondPath" -filter_complex "[0:a]aresample=48000:ocl=stereo:resampler=soxr[a0];[1:a]aresample=48000:ocl=stereo:resampler=soxr[a1];[a0][a1]concat=n=2:v=0:a=1[out]" -map "[out]" $codec "$outPath"';
}

String buildToneArgs({
  required String toneType,
  required double freq,
  required double durationSec,
  required String outPath,
}) {
  validateMediaPath(outPath, name: 'output path');
  if (!durationSec.isFinite || durationSec <= 0) {
    throw ArgumentError('ERR: Tone duration must be positive.');
  }
  if (!freq.isFinite || freq <= 0) {
    throw ArgumentError('ERR: Tone frequency must be positive.');
  }
  final d = durationSec.toStringAsFixed(2);
  final input = toneType == "SINE"
      ? "sine=frequency=${freq.round()}:duration=$d:sample_rate=48000"
      : "anoisesrc=color=${toneType == 'WHITE NOISE' ? 'white' : 'pink'}:duration=$d:sample_rate=48000:amplitude=0.6";
  return '-y -f lavfi -i "$input" -c:a pcm_s16le "$outPath"';
}

String buildSpectrogramArgs({
  required String inputPath,
  required String outPath,
}) {
  validateMediaPath(inputPath, name: 'input path');
  validateMediaPath(outPath, name: 'output path');
  return '-y -i "$inputPath" -lavfi "showspectrumpic=s=1280x720:legend=1" -frames:v 1 "$outPath"';
}

String buildClipAudioArgs({
  required String inputPath,
  required String outPath,
  required String startHms,
  required String endHms,
}) {
  validateMediaPath(inputPath, name: 'input path');
  validateMediaPath(outPath, name: 'output path');
  validateTimeHms(startHms, name: 'start time');
  validateTimeHms(endHms, name: 'end time');
  return '-y -i "$inputPath" -ss $startHms -to $endHms -c copy "$outPath"';
}

String buildMultitrackMixArgs({
  required List<String> inputPaths,
  required List<double> gains,
  required List<double> pans,
  required String outPath,
  required String container,
  int bitDepth = 16,
}) {
  validateMediaPath(outPath, name: 'output path');
  if (inputPaths.isEmpty) {
    throw ArgumentError('ERR: Multi-track mix requires at least one input.');
  }
  for (final p in inputPaths) {
    validateMediaPath(p, name: 'mix input track path');
  }
  final chainParts = <String>[];
  final mixLabels = <String>[];
  for (int i = 0; i < inputPaths.length; i++) {
    final gain = i < gains.length ? gains[i] : 1.0;
    final pan = i < pans.length ? pans[i] : 0.0;
    if (!gain.isFinite || gain < 0) {
      throw ArgumentError('ERR: Track gain must be non-negative.');
    }
    if (!pan.isFinite || pan < -1.0 || pan > 1.0) {
      throw ArgumentError('ERR: Track pan must be between -1.0 (left) and +1.0 (right).');
    }
    final left = (pan <= 0 ? 1.0 : 1.0 - pan).toStringAsFixed(2);
    final right = (pan >= 0 ? 1.0 : 1.0 + pan).toStringAsFixed(2);
    chainParts.add("[$i:a]aresample=48000:ocl=stereo:resampler=soxr,volume=${gain.toStringAsFixed(2)},pan=stereo|c0=$left*c0|c1=$right*c1[a$i]");
    mixLabels.add("[a$i]");
  }
  final filterComplex = "${chainParts.join(';')};${mixLabels.join('')}amix=inputs=${inputPaths.length}:duration=longest:normalize=0,alimiter=limit=0.95:attack=5:release=50";
  final inputArgs = inputPaths.map((p) => '-i "$p"').join(' ');
  final codec = buildAudioCodecArgs(container, bitDepth: bitDepth);
  return '-y $inputArgs -filter_complex "$filterComplex" $codec "$outPath"';
}
