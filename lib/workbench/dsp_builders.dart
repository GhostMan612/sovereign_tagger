// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:math';

const List<String> preservedAudioContainers = ['mp3', 'flac', 'wav', 'm4a', 'ogg', 'opus'];

const List<int> equalizer15Frequencies = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

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
  return "aresample=$sampleRate:resampler=soxr";
}

String buildVolumeDetectArgs(String path) {
  return '-y -i "$path" -af volumedetect -f null -';
}

String buildSilenceDetectArgs(String path, {double noiseDb = -45.0, double minDurationSec = 0.3}) {
  return '-y -i "$path" -af silencedetect=noise=${noiseDb.toStringAsFixed(0)}dB:d=${minDurationSec.toStringAsFixed(1)} -f null -';
}

String buildEbuR128Args(String path) {
  return '-y -i "$path" -af ebur128 -f null -';
}

String buildLoudnormFirstPassArgs(String path, {double targetI = -14.0, double targetLra = 11.0, double targetTp = -1.5}) {
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
  if (measured != null && measured.containsKey('input_i')) {
    return 'loudnorm=I=${targetI.toStringAsFixed(0)}:LRA=${targetLra.toStringAsFixed(0)}:TP=${targetTp.toStringAsFixed(1)}:measured_I=${measured['input_i']}:measured_LRA=${measured['input_lra']}:measured_TP=${measured['input_tp']}:measured_thresh=${measured['input_thresh']}:offset=${measured['target_offset']}:linear=true';
  }
  return 'loudnorm=I=${targetI.toStringAsFixed(0)}:LRA=${targetLra.toStringAsFixed(0)}:TP=${targetTp.toStringAsFixed(1)}';
}

Map<String, String>? parseLoudnormMeasurements(String output) {
  try {
    final matches = RegExp(r'\{[^{}]*"input_i"[^{}]*\}').allMatches(output);
    if (matches.isNotEmpty) {
      final last = matches.last.group(0)!;
      final decoded = jsonDecode(last);
      if (decoded is Map<String, dynamic> && decoded.containsKey('input_i')) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ""));
      }
    }
  } catch (_) {}
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
  return null;
}

List<({double start, double? end})> parseSilences(String output) {
  final starts = RegExp(r'silence_start:\s*([\d.]+)').allMatches(output).map((m) => double.tryParse(m.group(1) ?? "") ?? 0.0).toList();
  final ends = RegExp(r'silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)').allMatches(output).map((m) => double.tryParse(m.group(1) ?? "") ?? 0.0).toList();
  final out = <({double start, double? end})>[];
  for (int i = 0; i < starts.length; i++) {
    out.add((start: starts[i], end: i < ends.length ? ends[i] : null));
  }
  return out;
}

List<({double start, double end})> splitSegmentsFromSilence(String output, int? durationMs, {double minSegmentSec = 2.0}) {
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
    if (bands[i] != 0) {
      final freq = equalizer15Frequencies[i];
      filters.add("equalizer=f=$freq:t=q:w=1.2:g=${bands[i].toStringAsFixed(1)}");
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
  if (bass == 0 && lowMid == 0 && mid == 0 && highMid == 0 && treble == 0) {
    throw StateError("ERR: All EQ Bands At Zero. Nothing To Apply.");
  }
  return "firequalizer=gain_entry='entry(100,${bass.toStringAsFixed(1)});entry(320,${lowMid.toStringAsFixed(1)});entry(1000,${mid.toStringAsFixed(1)});entry(3500,${highMid.toStringAsFixed(1)});entry(8000,${treble.toStringAsFixed(1)})'";
}

String buildDeleteRegionFilter({required double startSec, required double endSec}) {
  if (endSec <= startSec) throw StateError("ERR: END Must Exceed START (use wave selection).");
  return "aselect='not(between(t,$startSec,$endSec))',asetpts=N/SR/TB";
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
  final codec = buildAudioCodecArgs(container, bitDepth: bitDepth);
  return '-y -i "$firstPath" -i "$secondPath" -filter_complex "[0:a]aresample=48000:ocl=stereo:resampler=soxr[a0];[1:a]aresample=48000:ocl=stereo:resampler=soxr[a1];[a0][a1]concat=n=2:v=0:a=1[out]" -map "[out]" $codec "$outPath"';
}

String buildToneArgs({
  required String toneType,
  required double freq,
  required double durationSec,
  required String outPath,
}) {
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
  return '-y -i "$inputPath" -lavfi "showspectrumpic=s=1280x720:legend=1" -frames:v 1 "$outPath"';
}

String buildClipAudioArgs({
  required String inputPath,
  required String outPath,
  required String startHms,
  required String endHms,
}) {
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
  final chainParts = <String>[];
  final mixLabels = <String>[];
  for (int i = 0; i < inputPaths.length; i++) {
    final gain = i < gains.length ? gains[i] : 1.0;
    final pan = i < pans.length ? pans[i] : 0.0;
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
