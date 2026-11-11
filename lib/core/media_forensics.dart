// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'ffmpeg_executor.dart';
import 'media_probe.dart';
import 'storage_client.dart';
import 'tag_io.dart';

enum ForensicVerdict {
  trueLossless,
  zeroPaddedBitDepth,
  suspectLossyShelf,
  fakeLosslessBrickwall,
  lossyNative,
  corruptStream,
  unknown,
}

class StreamEntry {
  final int index;
  final String type;
  final String codec;
  final String codecLong;
  final String profile;
  final String codecTag;
  final int? bitrateBps;
  final int? sampleRateHz;
  final int? channels;
  final String channelLayout;
  final String sampleFormat;
  final int? bitsPerSample;
  final int? width;
  final int? height;
  final String sar;
  final String dar;
  final String avgFrameRate;
  final String realFrameRate;
  final bool isVariableFrameRate;
  final String pixelFormat;
  final String colorSpace;
  final String colorTransfer;
  final String colorPrimaries;
  final String language;
  final String title;
  final bool isAttachedPic;
  final bool isDefault;
  final int? nbFrames;
  final Map<String, String> tags;

  const StreamEntry({
    required this.index,
    required this.type,
    required this.codec,
    required this.codecLong,
    required this.profile,
    required this.codecTag,
    required this.bitrateBps,
    required this.sampleRateHz,
    required this.channels,
    required this.channelLayout,
    required this.sampleFormat,
    required this.bitsPerSample,
    required this.width,
    required this.height,
    required this.sar,
    required this.dar,
    required this.avgFrameRate,
    required this.realFrameRate,
    required this.isVariableFrameRate,
    required this.pixelFormat,
    required this.colorSpace,
    required this.colorTransfer,
    required this.colorPrimaries,
    required this.language,
    required this.title,
    required this.isAttachedPic,
    required this.isDefault,
    required this.nbFrames,
    required this.tags,
  });
}

class ChapterEntry {
  final int id;
  final double startSeconds;
  final double endSeconds;
  final String title;

  const ChapterEntry({
    required this.id,
    required this.startSeconds,
    required this.endSeconds,
    required this.title,
  });

  double get durationSeconds => math.max(0.0, endSeconds - startSeconds);
}

class EmbeddedCoverInfo {
  final int byteLength;
  final String format;
  final int? width;
  final int? height;
  final Uint8List bytes;

  const EmbeddedCoverInfo({
    required this.byteLength,
    required this.format,
    required this.width,
    required this.height,
    required this.bytes,
  });
}

class ForensicAuditReport {
  final ForensicVerdict verdict;
  final String verdictLabel;
  final String verdictDetail;
  final double? integratedLufs;
  final double? loudnessRangeLu;
  final double? truePeakDbtp;
  final double? rmsLevelDb;
  final double? peakLevelDb;
  final double? dynamicRangeDb;
  final double? dcOffset;
  final String effectiveBitDepth;
  final double? band16kRmsDb;
  final double? band19k5RmsDb;
  final double? flatFactor;
  final int nanInfCount;
  final List<String> decodeErrors;
  final int elapsedMs;

  const ForensicAuditReport({
    required this.verdict,
    required this.verdictLabel,
    required this.verdictDetail,
    required this.integratedLufs,
    required this.loudnessRangeLu,
    required this.truePeakDbtp,
    required this.rmsLevelDb,
    required this.peakLevelDb,
    required this.dynamicRangeDb,
    required this.dcOffset,
    required this.effectiveBitDepth,
    required this.band16kRmsDb,
    required this.band19k5RmsDb,
    required this.flatFactor,
    required this.nanInfCount,
    required this.decodeErrors,
    required this.elapsedMs,
  });

  Map<String, dynamic> toJson() => {
        'verdict': verdict.name,
        'verdictLabel': verdictLabel,
        'verdictDetail': verdictDetail,
        'integratedLufs': integratedLufs,
        'loudnessRangeLu': loudnessRangeLu,
        'truePeakDbtp': truePeakDbtp,
        'rmsLevelDb': rmsLevelDb,
        'peakLevelDb': peakLevelDb,
        'dynamicRangeDb': dynamicRangeDb,
        'dcOffset': dcOffset,
        'effectiveBitDepth': effectiveBitDepth,
        'band16kRmsDb': band16kRmsDb,
        'band19k5RmsDb': band19k5RmsDb,
        'flatFactor': flatFactor,
        'nanInfCount': nanInfCount,
        'decodeErrors': decodeErrors,
        'elapsedMs': elapsedMs,
      };
}

class LosslessRemuxOutcome {
  final bool ok;
  final String summary;
  final List<String> exportedUris;

  const LosslessRemuxOutcome({
    required this.ok,
    required this.summary,
    this.exportedUris = const [],
  });
}

class MediaInspectionReport {
  final String filePath;
  final String fileName;
  final String extension;
  final int fileSizeBytes;
  final String containerFormat;
  final String containerLongFormat;
  final double durationSeconds;
  final double startTimeSeconds;
  final int? overallBitrateBps;
  final String bitrateMode;
  final String writingApp;
  final bool? isFastStart;
  final List<StreamEntry> streams;
  final List<ChapterEntry> chapters;
  final Map<String, String> containerTags;
  final Map<String, String> id3Tags;
  final EmbeddedCoverInfo? coverInfo;
  final Map<String, dynamic> rawProbeMap;

  const MediaInspectionReport({
    required this.filePath,
    required this.fileName,
    required this.extension,
    required this.fileSizeBytes,
    required this.containerFormat,
    required this.containerLongFormat,
    required this.durationSeconds,
    required this.startTimeSeconds,
    required this.overallBitrateBps,
    required this.bitrateMode,
    required this.writingApp,
    required this.isFastStart,
    required this.streams,
    required this.chapters,
    required this.containerTags,
    required this.id3Tags,
    required this.coverInfo,
    required this.rawProbeMap,
  });

  List<StreamEntry> get audioStreams =>
      streams.where((s) => s.type == 'audio' && !s.isAttachedPic).toList();

  List<StreamEntry> get videoStreams =>
      streams.where((s) => s.type == 'video' && !s.isAttachedPic).toList();

  List<StreamEntry> get subtitleStreams =>
      streams.where((s) => s.type == 'subtitle').toList();

  List<StreamEntry> get attachmentStreams =>
      streams.where((s) => s.isAttachedPic || s.type == 'attachment').toList();

  StreamEntry? get primaryAudio => audioStreams.isEmpty ? null : audioStreams.first;

  StreamEntry? get primaryVideo => videoStreams.isEmpty ? null : videoStreams.first;

  bool get claimsLosslessAudio {
    final a = primaryAudio;
    if (a == null) return false;
    final c = a.codec.toLowerCase();
    return c == 'flac' ||
        c == 'alac' ||
        c == 'wavpack' ||
        c == 'ape' ||
        c == 'tta' ||
        c == 'tak' ||
        c.startsWith('pcm_') ||
        c.startsWith('dsd_');
  }

  bool get supportsFastStart =>
      const {'mp4', 'm4a', 'm4b', 'mov'}.contains(extension.toLowerCase());

  String toCompactSummary({ForensicAuditReport? audit}) {
    final parts = <String>[
      '$fileName (${MediaForensics.formatBytes(fileSizeBytes)}, ${MediaForensics.formatDurationPrecise(durationSeconds)})',
    ];
    final a = primaryAudio;
    if (a != null) {
      final sr = a.sampleRateHz != null ? '${(a.sampleRateHz! / 1000.0).toStringAsFixed(1)} kHz' : 'unknown Hz';
      final bits = a.bitsPerSample != null ? '${a.bitsPerSample}-bit ' : '';
      final br = a.bitrateBps != null
          ? '${(a.bitrateBps! / 1000.0).round()} kbps'
          : (overallBitrateBps != null ? '~${(overallBitrateBps! / 1000.0).round()} kbps' : bitrateMode);
      final ch = a.channelLayout.isNotEmpty ? a.channelLayout : '${a.channels ?? 2}ch';
      parts.add('Audio: ${a.codec.toUpperCase()} $bits• $sr • $ch • $br');
    }
    final v = primaryVideo;
    if (v != null && v.width != null && v.height != null) {
      parts.add('Video: ${v.codec.toUpperCase()} ${v.width}x${v.height}${v.avgFrameRate.isEmpty ? '' : ' @ ${v.avgFrameRate} fps'}');
    }
    if (chapters.isNotEmpty) {
      parts.add('Chapters: ${chapters.length}');
    }
    if (audit != null) {
      final lufs = audit.integratedLufs != null ? '${audit.integratedLufs!.toStringAsFixed(1)} LUFS' : 'n/a';
      final dr = audit.dynamicRangeDb != null ? 'DR${audit.dynamicRangeDb!.round()}' : '';
      parts.add('Forensics: ${audit.verdictLabel} ($lufs${dr.isEmpty ? '' : ', $dr'})');
    }
    return parts.join('\n');
  }

  String toMediaInfoText({ForensicAuditReport? audit}) {
    final sb = StringBuffer();
    void line(String key, String value) {
      if (value.trim().isEmpty) return;
      sb.writeln('${key.padRight(30)}: $value');
    }

    sb.writeln('General');
    line('Complete name', filePath);
    line('File name', fileName);
    line('Format', containerFormat.toUpperCase());
    line('Format/Info', containerLongFormat);
    line('File size', '${MediaForensics.formatBytes(fileSizeBytes)} ($fileSizeBytes bytes)');
    line('Duration', MediaForensics.formatDurationPrecise(durationSeconds));
    line('Overall bit rate mode', bitrateMode);
    if (overallBitrateBps != null) {
      line('Overall bit rate', MediaForensics.formatBitrate(overallBitrateBps!));
    }
    if (isFastStart != null) {
      line('IsStreamable (FastStart)', isFastStart! ? 'Yes (moov atom before mdat)' : 'No (mdat precedes moov)');
    }
    line('Writing application', writingApp);
    if (coverInfo != null) {
      final dims = (coverInfo!.width != null && coverInfo!.height != null)
          ? '${coverInfo!.width}x${coverInfo!.height}'
          : 'dimensions unknown';
      line('Cover', 'Yes (${coverInfo!.format}, $dims, ${MediaForensics.formatBytes(coverInfo!.byteLength)})');
    }
    final mergedTags = <String, String>{...containerTags};
    for (final e in id3Tags.entries) {
      if (e.key == 'ARTWORK_BASE64' || e.key == 'DURATION_MS' || e.value.trim().isEmpty) continue;
      mergedTags.putIfAbsent(e.key, () => e.value);
    }
    for (final e in mergedTags.entries) {
      if (e.key.toLowerCase() == 'lyrics') {
        final linesCount = e.value.split('\n').length;
        line('Lyrics', 'Embedded ($linesCount lines, ${e.value.length} chars)');
      } else {
        line('Tag/${e.key}', e.value.replaceAll('\n', ' / '));
      }
    }

    var vIdx = 1;
    for (final v in videoStreams) {
      sb.writeln();
      sb.writeln('Video #$vIdx');
      vIdx++;
      line('Stream index', '${v.index}');
      line('Format', v.codec.toUpperCase());
      line('Format/Info', v.codecLong);
      line('Format profile', v.profile);
      line('Codec ID', v.codecTag);
      if (v.bitrateBps != null) line('Bit rate', MediaForensics.formatBitrate(v.bitrateBps!));
      if (v.width != null) line('Width', '${v.width} pixels');
      if (v.height != null) line('Height', '${v.height} pixels');
      line('Display aspect ratio', v.dar);
      line('Sample aspect ratio', v.sar);
      line('Frame rate mode', v.isVariableFrameRate ? 'Variable (VFR)' : 'Constant (CFR)');
      line('Frame rate', v.avgFrameRate.isEmpty ? '' : '${v.avgFrameRate} FPS');
      if (v.isVariableFrameRate && v.realFrameRate.isNotEmpty) {
        line('Real base frame rate', '${v.realFrameRate} FPS');
      }
      line('Pixel format', v.pixelFormat);
      if (v.bitsPerSample != null) line('Bit depth', '${v.bitsPerSample} bits');
      line('Color space', v.colorSpace);
      line('Transfer characteristics', v.colorTransfer);
      line('Color primaries', v.colorPrimaries);
      if (v.nbFrames != null) line('Frame count', '${v.nbFrames}');
      line('Language', v.language);
      line('Title', v.title);
    }

    var aIdx = 1;
    for (final a in audioStreams) {
      sb.writeln();
      sb.writeln('Audio #$aIdx');
      aIdx++;
      line('Stream index', '${a.index}');
      line('Format', a.codec.toUpperCase());
      line('Format/Info', a.codecLong);
      line('Format profile', a.profile);
      line('Codec ID', a.codecTag);
      line('Compression mode', MediaForensics.isLosslessCodec(a.codec) ? 'Lossless' : 'Lossy');
      if (a.bitrateBps != null) line('Bit rate', MediaForensics.formatBitrate(a.bitrateBps!));
      if (a.channels != null) line('Channel(s)', '${a.channels} channels');
      line('Channel layout', a.channelLayout);
      if (a.sampleRateHz != null) line('Sampling rate', '${(a.sampleRateHz! / 1000.0).toStringAsFixed(3)} kHz (${a.sampleRateHz} Hz)');
      line('Sample format', a.sampleFormat);
      if (a.bitsPerSample != null) line('Bit depth', '${a.bitsPerSample} bits');
      line('Language', a.language);
      line('Title', a.title);
      for (final t in a.tags.entries) {
        if (t.key.toLowerCase() == 'language' || t.key.toLowerCase() == 'title') continue;
        line('StreamTag/${t.key}', t.value);
      }
    }

    var sIdx = 1;
    for (final s in subtitleStreams) {
      sb.writeln();
      sb.writeln('Text #$sIdx');
      sIdx++;
      line('Stream index', '${s.index}');
      line('Format', s.codec.toUpperCase());
      line('Format/Info', s.codecLong);
      line('Language', s.language);
      line('Title', s.title);
    }

    if (chapters.isNotEmpty) {
      sb.writeln();
      sb.writeln('Menu (${chapters.length} Chapters)');
      for (var i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        final stamp = MediaForensics.formatTimestampMs((c.startSeconds * 1000).round());
        final endStamp = MediaForensics.formatTimestampMs((c.endSeconds * 1000).round());
        line('$stamp - $endStamp', c.title.isEmpty ? 'Chapter ${i + 1}' : c.title);
      }
    }

    if (audit != null) {
      sb.writeln();
      sb.writeln('Audio Forensics (FFmpeg DSP Audit)');
      line('Authenticity verdict', audit.verdictLabel);
      line('Forensic detail', audit.verdictDetail);
      if (audit.integratedLufs != null) line('Integrated loudness (I)', '${audit.integratedLufs!.toStringAsFixed(2)} LUFS');
      if (audit.loudnessRangeLu != null) line('Loudness range (LRA)', '${audit.loudnessRangeLu!.toStringAsFixed(2)} LU');
      if (audit.truePeakDbtp != null) line('True peak (dBTP)', '${audit.truePeakDbtp!.toStringAsFixed(2)} dBTP');
      if (audit.peakLevelDb != null) line('Sample peak', '${audit.peakLevelDb!.toStringAsFixed(2)} dBFS');
      if (audit.rmsLevelDb != null) line('Overall RMS', '${audit.rmsLevelDb!.toStringAsFixed(2)} dBFS');
      if (audit.dynamicRangeDb != null) line('Crest dynamic range', 'DR${audit.dynamicRangeDb!.round()} (${audit.dynamicRangeDb!.toStringAsFixed(2)} dB)');
      if (audit.dcOffset != null) line('DC offset', audit.dcOffset!.toStringAsFixed(6));
      line('Effective bit depth', audit.effectiveBitDepth);
      if (audit.band16kRmsDb != null) line('Spectral energy >=16.2 kHz', '${audit.band16kRmsDb!.toStringAsFixed(1)} dBFS');
      if (audit.band19k5RmsDb != null) line('Spectral energy >=19.5 kHz', '${audit.band19k5RmsDb!.toStringAsFixed(1)} dBFS');
      line('NaN / Inf samples', '${audit.nanInfCount}');
      line('Decode errors', audit.decodeErrors.isEmpty ? '0 (Clean bitstream)' : '${audit.decodeErrors.length}: ${audit.decodeErrors.join(' | ')}');
      line('Audit duration', '${audit.elapsedMs} ms');
    }

    return sb.toString().trimRight();
  }

  String toRawJsonText({ForensicAuditReport? audit}) {
    final payload = <String, dynamic>{
      ...rawProbeMap,
      if (isFastStart != null) 'faststart_moov_before_mdat': isFastStart,
      if (audit != null) 'sovereign_forensics': audit.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}

class MediaForensics {
  static bool isLosslessCodec(String codec) {
    final c = codec.toLowerCase();
    return c == 'flac' ||
        c == 'alac' ||
        c == 'wavpack' ||
        c == 'ape' ||
        c == 'tta' ||
        c == 'tak' ||
        c.startsWith('pcm_') ||
        c.startsWith('dsd_');
  }

  static String? losslessAudioExtensionForCodec(String codec) {
    final c = codec.toLowerCase();
    if (c == 'aac' || c == 'alac' || c == 'ac3' || c == 'eac3') return 'm4a';
    if (c == 'mp3') return 'mp3';
    if (c == 'opus') return 'opus';
    if (c == 'vorbis') return 'ogg';
    if (c == 'flac') return 'flac';
    if (c.startsWith('pcm_')) return 'wav';
    return null;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024.0).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024.0 * 1024.0)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024.0 * 1024.0 * 1024.0)).toStringAsFixed(2)} GB';
  }

  static String formatBitrate(int bps) {
    if (bps >= 1000000) return '${(bps / 1000000.0).toStringAsFixed(2)} Mbps';
    return '${(bps / 1000.0).round()} kbps';
  }

  static String formatDurationPrecise(double seconds) {
    if (seconds <= 0) return '00:00.000';
    final totalMs = (seconds * 1000).round();
    return formatTimestampMs(totalMs);
  }

  static String formatTimestampMs(int totalMs) {
    final clamped = math.max(0, totalMs);
    final hrs = clamped ~/ 3600000;
    final mins = (clamped % 3600000) ~/ 60000;
    final secs = (clamped % 60000) ~/ 1000;
    final ms = clamped % 1000;
    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');
    final msStr = ms.toString().padLeft(3, '0');
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:$mStr:$sStr.$msStr';
    }
    return '$mStr:$sStr.$msStr';
  }

  static Future<MediaInspectionReport> inspect(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Media file not found on disk', path);
    }
    final fileSize = file.lengthSync();
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dotIdx = fileName.lastIndexOf('.');
    final ext = dotIdx > 0 ? fileName.substring(dotIdx + 1).toLowerCase() : '';

    final probeSession = await FFprobeKit.getMediaInformationAsync(path);
    final info = probeSession.getMediaInformation();

    Map<String, String> id3 = const {};
    if (TagIO.canWrite(path)) {
      id3 = await TagIO.read(path, withArtwork: true);
    }

    EmbeddedCoverInfo? coverInfo;
    final b64 = id3['ARTWORK_BASE64'] ?? '';
    if (b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        if (bytes.isNotEmpty) {
          coverInfo = _inspectImageBytes(bytes);
        }
      } catch (_) {}
    }

    final formatMap = info?.allProperties ?? <String, dynamic>{};
    final containerTags = <String, String>{};
    final rawFormatTags = info?.tags;
    if (rawFormatTags != null) {
      for (final e in rawFormatTags.entries) {
        containerTags[e.key.toString()] = e.value?.toString() ?? '';
      }
    }

    final durationSec = double.tryParse(info?.duration ?? '') ??
        ((int.tryParse(id3['DURATION_MS'] ?? '') ?? 0) / 1000.0);
    final startSec = double.tryParse(info?.startTime ?? '') ?? 0.0;
    final overallBps = int.tryParse(info?.bitrate ?? '');

    final streams = <StreamEntry>[];
    final rawStreamMaps = <Map<String, dynamic>>[];

    for (final s in info?.streams ?? const <StreamInformation>[]) {
      final props = s.allProperties ?? s.toJson();
      rawStreamMaps.add(props);

      final sTags = <String, String>{};
      if (s.tags != null) {
        for (final e in s.tags!.entries) {
          sTags[e.key.toString()] = e.value?.toString() ?? '';
        }
      }

      final disposition = props['disposition'];
      final attachedPic = disposition is Map && (disposition['attached_pic'] == 1 || disposition['attached_pic'] == true);
      final defaultDisp = disposition is Map && (disposition['default'] == 1 || disposition['default'] == true);

      final rawBits = int.tryParse(props['bits_per_raw_sample']?.toString() ?? '');
      final codedBits = int.tryParse(props['bits_per_sample']?.toString() ?? '');
      final sampleFmt = s.sampleFormat ?? props['sample_fmt']?.toString() ?? '';
      final inferredBits = (rawBits != null && rawBits > 0)
          ? rawBits
          : ((codedBits != null && codedBits > 0) ? codedBits : _inferBitDepthFromSampleFmt(sampleFmt));

      final avgFr = _formatRatioFps(s.averageFrameRate ?? props['avg_frame_rate']?.toString() ?? '');
      final realFr = _formatRatioFps(s.realFrameRate ?? props['r_frame_rate']?.toString() ?? '');
      final avgVal = _evalFraction(s.averageFrameRate ?? '');
      final realVal = _evalFraction(s.realFrameRate ?? '');
      final isVfr = avgVal != null && realVal != null && (avgVal - realVal).abs() > 0.08;

      String lang = '';
      String sTitle = '';
      for (final e in sTags.entries) {
        final lk = e.key.toLowerCase();
        if (lk == 'language' && lang.isEmpty) lang = e.value;
        if (lk == 'title' && sTitle.isEmpty) sTitle = e.value;
      }

      streams.add(
        StreamEntry(
          index: s.index ?? streams.length,
          type: (s.type ?? props['codec_type']?.toString() ?? 'unknown').toLowerCase(),
          codec: s.codec ?? props['codec_name']?.toString() ?? 'unknown',
          codecLong: s.codecLong ?? props['codec_long_name']?.toString() ?? '',
          profile: props['profile']?.toString() ?? '',
          codecTag: props['codec_tag_string']?.toString() ?? '',
          bitrateBps: int.tryParse(s.bitrate ?? props['bit_rate']?.toString() ?? ''),
          sampleRateHz: int.tryParse(s.sampleRate ?? props['sample_rate']?.toString() ?? ''),
          channels: int.tryParse(props['channels']?.toString() ?? ''),
          channelLayout: s.channelLayout ?? props['channel_layout']?.toString() ?? '',
          sampleFormat: sampleFmt,
          bitsPerSample: inferredBits,
          width: s.width ?? int.tryParse(props['width']?.toString() ?? ''),
          height: s.height ?? int.tryParse(props['height']?.toString() ?? ''),
          sar: s.sampleAspectRatio ?? props['sample_aspect_ratio']?.toString() ?? '',
          dar: s.displayAspectRatio ?? props['display_aspect_ratio']?.toString() ?? '',
          avgFrameRate: avgFr,
          realFrameRate: realFr,
          isVariableFrameRate: isVfr,
          pixelFormat: props['pix_fmt']?.toString() ?? '',
          colorSpace: props['color_space']?.toString() ?? '',
          colorTransfer: props['color_transfer']?.toString() ?? '',
          colorPrimaries: props['color_primaries']?.toString() ?? '',
          language: lang,
          title: sTitle,
          isAttachedPic: attachedPic,
          isDefault: defaultDisp,
          nbFrames: int.tryParse(props['nb_frames']?.toString() ?? ''),
          tags: sTags,
        ),
      );
    }

    final chapters = <ChapterEntry>[];
    final rawChapters = <Map<String, dynamic>>[];
    for (var i = 0; i < (info?.chapters.length ?? 0); i++) {
      final c = info!.chapters[i];
      if (c.allProperties != null) {
        rawChapters.add(c.allProperties!);
      }
      final start = double.tryParse(c.startTime ?? '') ?? 0.0;
      final end = double.tryParse(c.endTime ?? '') ?? start;
      String cTitle = '';
      if (c.tags != null) {
        for (final e in c.tags!.entries) {
          if (e.key.toString().toLowerCase() == 'title') {
            cTitle = e.value?.toString() ?? '';
            break;
          }
        }
      }
      chapters.add(
        ChapterEntry(
          id: c.id ?? i,
          startSeconds: start,
          endSeconds: end,
          title: cTitle.isEmpty ? 'Chapter ${i + 1}' : cTitle,
        ),
      );
    }

    String writingApp = '';
    for (final k in const ['encoder', 'ENCODER', 'writing_app', 'compatible_brands', 'major_brand']) {
      final v = containerTags[k] ?? id3[k] ?? '';
      if (v.trim().isNotEmpty) {
        writingApp = v.trim();
        break;
      }
    }

    final fastStart = const {'mp4', 'm4a', 'm4b', 'mov'}.contains(ext) ? _detectMp4FastStart(path) : null;
    final primaryAud = streams.where((s) => s.type == 'audio' && !s.isAttachedPic).firstOrNull;
    final bitrateMode = _inferBitrateMode(primaryAud, overallBps);

    final rawProbeMap = <String, dynamic>{
      'format': formatMap.isNotEmpty
          ? formatMap
          : {
              'filename': path,
              'format_name': info?.format ?? ext,
              'format_long_name': info?.longFormat ?? '',
              'duration': durationSec.toStringAsFixed(6),
              'size': fileSize.toString(),
              if (overallBps != null) 'bit_rate': overallBps.toString(),
              'tags': containerTags,
            },
      'streams': rawStreamMaps,
      if (rawChapters.isNotEmpty) 'chapters': rawChapters,
    };

    return MediaInspectionReport(
      filePath: path,
      fileName: fileName,
      extension: ext,
      fileSizeBytes: fileSize,
      containerFormat: info?.format ?? (ext.isEmpty ? 'unknown' : ext),
      containerLongFormat: info?.longFormat ?? '',
      durationSeconds: durationSec,
      startTimeSeconds: startSec,
      overallBitrateBps: overallBps,
      bitrateMode: bitrateMode,
      writingApp: writingApp,
      isFastStart: fastStart,
      streams: streams,
      chapters: chapters,
      containerTags: containerTags,
      id3Tags: id3,
      coverInfo: coverInfo,
      rawProbeMap: rawProbeMap,
    );
  }

  static Future<ForensicAuditReport> runDeepAudioAudit(
    MediaInspectionReport report, {
    void Function(String stage)? onStage,
  }) async {
    final sw = Stopwatch()..start();
    final path = report.filePath.replaceAll('"', r'\"');
    final audio = report.primaryAudio;
    if (audio == null) {
      return ForensicAuditReport(
        verdict: ForensicVerdict.unknown,
        verdictLabel: 'NO AUDIO STREAM PRESENT',
        verdictDetail: 'Container holds no decodable audio stream to audit.',
        integratedLufs: null,
        loudnessRangeLu: null,
        truePeakDbtp: null,
        rmsLevelDb: null,
        peakLevelDb: null,
        dynamicRangeDb: null,
        dcOffset: null,
        effectiveBitDepth: 'N/A',
        band16kRmsDb: null,
        band19k5RmsDb: null,
        flatFactor: null,
        nanInfCount: 0,
        decodeErrors: const [],
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    onStage?.call('PASS 1/2: FULL BITSTREAM INTEGRITY + EBU R128 + ASTATS...');
    final mainSession = await FFmpegExecutor.execute(
      '-hide_banner -nostats -i "$path" -map 0:a:0 -af "astats=metadata=0:reset=0,ebur128=peak=true" -f null -',
      durationMs: report.durationSeconds > 0 ? (report.durationSeconds * 1000).round() : null,
      description: 'forensics_main',
    );
    final mainOut = mainSession.getOutput() ?? '';

    final decodeErrors = _extractDecodeErrors(mainOut);
    final rmsDb = _lastDoubleMatch(RegExp(r'RMS level dB:\s*(-?\d+(?:\.\d+)?)'), mainOut);
    final peakDb = _lastDoubleMatch(RegExp(r'Peak level dB:\s*(-?\d+(?:\.\d+)?)'), mainOut);
    final dcOffset = _lastDoubleMatch(RegExp(r'DC offset:\s*(-?\d+(?:\.\d+)?)'), mainOut);
    final flatFactor = _lastDoubleMatch(RegExp(r'Flat factor:\s*(-?\d+(?:\.\d+)?)'), mainOut);
    final bitDepthMatch = RegExp(r'Bit depth:\s*(\d+/\d+)').allMatches(mainOut);
    final effBits = bitDepthMatch.isNotEmpty ? bitDepthMatch.last.group(1)! : (audio.bitsPerSample != null ? '${audio.bitsPerSample}/${audio.bitsPerSample}' : 'unknown');

    final nanCount = _lastIntMatch(RegExp(r'Number of NaNs:\s*(\d+)'), mainOut) ?? 0;
    final infCount = _lastIntMatch(RegExp(r'Number of Infs:\s*(\d+)'), mainOut) ?? 0;

    final integratedLufs = _lastDoubleMatch(RegExp(r'\bI:\s*(-?\d+(?:\.\d+)?)\s*LUFS'), mainOut);
    final lraLu = _lastDoubleMatch(RegExp(r'\bLRA:\s*(-?\d+(?:\.\d+)?)\s*LU'), mainOut);
    final truePeak = _lastDoubleMatch(RegExp(r'True peak:\s*[\r\n]+\s*Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS'), mainOut) ??
        peakDb;

    final drScore = (peakDb != null && rmsDb != null && rmsDb > -110.0) ? math.max(0.0, peakDb - rmsDb) : null;

    double? band16k;
    double? band19k5;
    final sr = audio.sampleRateHz ?? 44100;
    if (sr >= 44100 && report.durationSeconds >= 1.5) {
      onStage?.call('PASS 2/2: HIGH-FREQUENCY BRICKWALL SHELF PROBE (16.2 / 19.5 KHZ)...');
      final seekSec = report.durationSeconds > 60.0 ? 15 : 0;
      final seekArg = seekSec > 0 ? '-ss $seekSec ' : '';
      final s16 = await FFmpegExecutor.execute(
        '-hide_banner -nostats $seekArg-t 30 -i "$path" -map 0:a:0 -af "highpass=f=16200,highpass=f=16200,astats=metadata=0:reset=0" -f null -',
        description: 'forensics_hf16',
      );
      band16k = _lastDoubleMatch(RegExp(r'RMS level dB:\s*(-?\d+(?:\.\d+)?)'), s16.getOutput() ?? '') ?? -120.0;

      final s19 = await FFmpegExecutor.execute(
        '-hide_banner -nostats $seekArg-t 30 -i "$path" -map 0:a:0 -af "highpass=f=19500,highpass=f=19500,astats=metadata=0:reset=0" -f null -',
        description: 'forensics_hf19',
      );
      band19k5 = _lastDoubleMatch(RegExp(r'RMS level dB:\s*(-?\d+(?:\.\d+)?)'), s19.getOutput() ?? '') ?? -120.0;
    }

    final (verdict, label, detail) = _classifyVerdict(
      report: report,
      audio: audio,
      rmsDb: rmsDb,
      band16k: band16k,
      band19k5: band19k5,
      effectiveBitDepth: effBits,
      decodeErrors: decodeErrors,
    );

    sw.stop();
    return ForensicAuditReport(
      verdict: verdict,
      verdictLabel: label,
      verdictDetail: detail,
      integratedLufs: integratedLufs,
      loudnessRangeLu: lraLu,
      truePeakDbtp: truePeak,
      rmsLevelDb: rmsDb,
      peakLevelDb: peakDb,
      dynamicRangeDb: drScore,
      dcOffset: dcOffset,
      effectiveBitDepth: effBits,
      band16kRmsDb: band16k,
      band19k5RmsDb: band19k5,
      flatFactor: flatFactor,
      nanInfCount: nanCount + infCount,
      decodeErrors: decodeErrors,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  static Future<String?> renderSpectrogram(String filePath) async {
    final temp = await StorageClient.tempDir();
    final outPath = '$temp/inspector_spec_${DateTime.now().millisecondsSinceEpoch}.png';
    final escapedIn = filePath.replaceAll('"', r'\"');
    final escapedOut = outPath.replaceAll('"', r'\"');

    var session = await FFmpegExecutor.execute(
      '-y -hide_banner -i "$escapedIn" -lavfi "showspectrumpic=s=1600x800:legend=1:color=intensity:scale=log" -frames:v 1 "$escapedOut"',
      description: 'inspector_spectrogram',
    );
    if (!ReturnCode.isSuccess(session.getReturnCode()) || !File(outPath).existsSync()) {
      session = await FFmpegExecutor.execute(
        '-y -hide_banner -i "$escapedIn" -lavfi "showspectrumpic=s=1280x720:legend=1" -frames:v 1 "$escapedOut"',
        description: 'inspector_spectrogram_fallback',
      );
    }
    if (ReturnCode.isSuccess(session.getReturnCode()) && File(outPath).existsSync() && File(outPath).lengthSync() > 0) {
      return outPath;
    }
    try {
      final f = File(outPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    return null;
  }

  static Future<LosslessRemuxOutcome> extractAudioLossless(MediaInspectionReport report) async {
    final audio = report.primaryAudio;
    if (audio == null) {
      return const LosslessRemuxOutcome(ok: false, summary: 'ERR: Source has no audio stream to extract.');
    }
    final outExt = losslessAudioExtensionForCodec(audio.codec);
    if (outExt == null) {
      return LosslessRemuxOutcome(
        ok: false,
        summary: 'ERR: Codec ${audio.codec.toUpperCase()} has no standalone lossless-copy audio container. Use Workbench Convert Format instead.',
      );
    }
    final temp = await StorageClient.tempDir();
    final base = _stripExtension(report.fileName);
    final tempOut = '$temp/remux_audio_${DateTime.now().millisecondsSinceEpoch}.$outExt';
    final escapedIn = report.filePath.replaceAll('"', r'\"');
    final escapedOut = tempOut.replaceAll('"', r'\"');
    final fastStartFlag = outExt == 'm4a' ? '-movflags +faststart ' : '';
    try {
      final session = await FFmpegExecutor.execute(
        '-y -hide_banner -i "$escapedIn" -map 0:a:0 -vn -sn -dn -c:a copy $fastStartFlag"$escapedOut"',
        description: 'lossless_audio_extract',
      );
      if (!ReturnCode.isSuccess(session.getReturnCode()) || !File(tempOut).existsSync()) {
        return const LosslessRemuxOutcome(ok: false, summary: 'ERR: FFmpeg lossless stream copy failed.');
      }
      final verified = await probeStreams(tempOut);
      if ((verified['audio'] ?? 0) <= 0) {
        return const LosslessRemuxOutcome(ok: false, summary: 'ERR: Remuxed output failed audio stream verification.');
      }
      final saved = await StorageClient.exportToLibrary(tempOut, '${base}_lossless_audio');
      return LosslessRemuxOutcome(
        ok: true,
        summary: 'Lossless audio stream (${audio.codec.toUpperCase()} -> .$outExt, zero re-encode) saved to Music:\n${saved.displayName}',
        exportedUris: [saved.uri],
      );
    } catch (e) {
      return LosslessRemuxOutcome(ok: false, summary: 'ERR: Lossless Extract Fault: $e');
    } finally {
      try {
        final f = File(tempOut);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static Future<LosslessRemuxOutcome> remuxFastStart(MediaInspectionReport report) async {
    if (!report.supportsFastStart) {
      return const LosslessRemuxOutcome(ok: false, summary: 'ERR: FastStart optimization applies only to MP4 / M4A / M4B / MOV containers.');
    }
    final temp = await StorageClient.tempDir();
    final ext = report.extension.isEmpty ? 'm4a' : report.extension;
    final base = _stripExtension(report.fileName);
    final tempOut = '$temp/faststart_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final escapedIn = report.filePath.replaceAll('"', r'\"');
    final escapedOut = tempOut.replaceAll('"', r'\"');
    try {
      final session = await FFmpegExecutor.execute(
        '-y -hide_banner -i "$escapedIn" -map 0 -c copy -movflags +faststart "$escapedOut"',
        description: 'lossless_faststart',
      );
      if (!ReturnCode.isSuccess(session.getReturnCode()) || !File(tempOut).existsSync()) {
        return const LosslessRemuxOutcome(ok: false, summary: 'ERR: FastStart remux failed.');
      }
      final verified = await probeStreams(tempOut);
      if ((verified['audio'] ?? 0) <= 0 && (verified['video'] ?? 0) <= 0) {
        return const LosslessRemuxOutcome(ok: false, summary: 'ERR: FastStart output failed stream verification.');
      }
      final saved = await StorageClient.exportToLibrary(tempOut, '${base}_faststart');
      return LosslessRemuxOutcome(
        ok: true,
        summary: 'FastStart remux complete (moov relocated ahead of mdat, zero re-encode):\n${saved.displayName}',
        exportedUris: [saved.uri],
      );
    } catch (e) {
      return LosslessRemuxOutcome(ok: false, summary: 'ERR: FastStart Fault: $e');
    } finally {
      try {
        final f = File(tempOut);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static Future<LosslessRemuxOutcome> splitChaptersLossless(
    MediaInspectionReport report, {
    void Function(int current, int total, String chapterTitle)? onProgress,
  }) async {
    if (report.chapters.isEmpty) {
      return const LosslessRemuxOutcome(ok: false, summary: 'ERR: Container holds zero embedded chapters to split.');
    }
    final audio = report.primaryAudio;
    final String outExt;
    if (audio != null && losslessAudioExtensionForCodec(audio.codec) != null) {
      final mapped = losslessAudioExtensionForCodec(audio.codec)!;
      outExt = const {'mp3', 'm4a', 'flac', 'ogg', 'opus', 'wav'}.contains(report.extension) ? report.extension : mapped;
    } else if (report.extension.isNotEmpty) {
      outExt = report.extension;
    } else {
      outExt = 'm4a';
    }

    final temp = await StorageClient.tempDir();
    final albumFallback = (report.id3Tags['ALBUM'] ?? '').trim().isNotEmpty
        ? report.id3Tags['ALBUM']!.trim()
        : _stripExtension(report.fileName);
    final artistFallback = (report.id3Tags['ARTIST'] ?? '').trim();
    final exported = <String>[];
    final escapedIn = report.filePath.replaceAll('"', r'\"');

    for (var i = 0; i < report.chapters.length; i++) {
      final ch = report.chapters[i];
      if (ch.endSeconds <= ch.startSeconds + 0.05) continue;
      final trackNum = (i + 1).toString().padLeft(2, '0');
      final cleanTitle = ch.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final displayTitle = '$trackNum - ${cleanTitle.isEmpty ? 'Chapter ${i + 1}' : cleanTitle}';
      onProgress?.call(i + 1, report.chapters.length, displayTitle);

      final tempOut = '$temp/chapter_${DateTime.now().millisecondsSinceEpoch}_$trackNum.$outExt';
      final escapedOut = tempOut.replaceAll('"', r'\"');
      final startArg = ch.startSeconds.toStringAsFixed(3);
      final endArg = ch.endSeconds.toStringAsFixed(3);
      final fastStartFlag = outExt == 'm4a' ? '-movflags +faststart ' : '';
      final mapArgs = audio != null ? '-map 0:a:0 -vn -c:a copy' : '-map 0 -c copy';

      try {
        final session = await FFmpegExecutor.execute(
          '-y -hide_banner -ss $startArg -to $endArg -i "$escapedIn" $mapArgs $fastStartFlag"$escapedOut"',
          description: 'chapter_split_${i + 1}',
        );
        if (!ReturnCode.isSuccess(session.getReturnCode()) || !File(tempOut).existsSync()) {
          continue;
        }
        final verified = await probeStreams(tempOut);
        if ((verified['audio'] ?? 0) <= 0 && (verified['video'] ?? 0) <= 0) {
          continue;
        }
        if (TagIO.canWrite(tempOut)) {
          await TagIO.write(tempOut, {
            'TITLE': cleanTitle.isEmpty ? 'Chapter ${i + 1}' : cleanTitle,
            'ALBUM': albumFallback,
            if (artistFallback.isNotEmpty) 'ARTIST': artistFallback,
            'TRACK': '${i + 1}',
            'TRACK_TOTAL': '${report.chapters.length}',
          });
        }
        final saved = await StorageClient.exportToLibrary(tempOut, displayTitle);
        exported.add(saved.uri);
      } finally {
        try {
          final f = File(tempOut);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }

    if (exported.isEmpty) {
      return const LosslessRemuxOutcome(ok: false, summary: 'ERR: Zero chapters exported. Verify source stream compatibility.');
    }
    return LosslessRemuxOutcome(
      ok: true,
      summary: 'Split & exported ${exported.length}/${report.chapters.length} chapters losslessly (.$outExt, -c copy) to Music.',
      exportedUris: exported,
    );
  }

  static (ForensicVerdict, String, String) _classifyVerdict({
    required MediaInspectionReport report,
    required StreamEntry audio,
    required double? rmsDb,
    required double? band16k,
    required double? band19k5,
    required String effectiveBitDepth,
    required List<String> decodeErrors,
  }) {
    if (decodeErrors.isNotEmpty) {
      return (
        ForensicVerdict.corruptStream,
        'BITSTREAM INTEGRITY FAULT',
        'Decoder reported ${decodeErrors.length} stream error(s): ${decodeErrors.first}',
      );
    }

    if (!report.claimsLosslessAudio) {
      final srStr = audio.sampleRateHz != null ? '${(audio.sampleRateHz! / 1000.0).toStringAsFixed(1)} kHz' : 'lossy';
      return (
        ForensicVerdict.lossyNative,
        'CLEAN LOSSY BITSTREAM (${audio.codec.toUpperCase()})',
        'Native ${audio.codec.toUpperCase()} ($srStr) decoded cleanly with zero frame errors.',
      );
    }

    if (rmsDb != null && rmsDb > -55.0) {
      final drop16 = band16k != null ? (rmsDb - band16k) : 0.0;
      final drop19 = band19k5 != null ? (rmsDb - band19k5) : 0.0;
      if (band16k != null && band16k < -76.0 && drop16 > 44.0) {
        return (
          ForensicVerdict.fakeLosslessBrickwall,
          'FAKE LOSSLESS (~128K MP3 BRICKWALL)',
          'Hard spectral cutoff around 16 kHz (${band16k.toStringAsFixed(1)} dBFS vs ${rmsDb.toStringAsFixed(1)} dBFS full-band) inside a ${audio.codec.toUpperCase()} container.',
        );
      }
      if (band19k5 != null && band19k5 < -80.0 && drop19 > 46.0 && (band16k == null || band16k > -72.0)) {
        return (
          ForensicVerdict.suspectLossyShelf,
          'SUSPECT TRANSCODE (~192-256K SHELF)',
          'Steep high-frequency shelf above 19.5 kHz (${band19k5.toStringAsFixed(1)} dBFS) suggests a lossy source re-wrapped as ${audio.codec.toUpperCase()}.',
        );
      }
    }

    final declared = audio.bitsPerSample ?? 16;
    final effParts = effectiveBitDepth.split('/');
    final effLow = effParts.isNotEmpty ? int.tryParse(effParts.first) : null;
    if (declared >= 24 && effLow != null && effLow <= 16) {
      return (
        ForensicVerdict.zeroPaddedBitDepth,
        'ZERO-PADDED $declared-BIT (TRUE $effLow-BIT)',
        'Container declares $declared-bit samples, but LSB audit shows only $effLow active bits (upsampled/padded bit depth).',
      );
    }

    return (
      ForensicVerdict.trueLossless,
      'VERIFIED TRUE LOSSLESS',
      'Full-bandwidth ${audio.codec.toUpperCase()} signal with active $effectiveBitDepth bit depth and zero decode errors.',
    );
  }

  static List<String> _extractDecodeErrors(String output) {
    final found = <String>[];
    final rx = RegExp(
      r'(Error while decoding|Invalid data found|corrupt|CRC mismatch|MD5 mismatch|Header missing|Packet corrupt|Truncated|overread)',
      caseSensitive: false,
    );
    for (final rawLine in output.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (rx.hasMatch(line)) {
        final cleaned = line.length > 120 ? '${line.substring(0, 120)}...' : line;
        if (!found.contains(cleaned)) {
          found.add(cleaned);
          if (found.length >= 6) break;
        }
      }
    }
    return found;
  }

  static double? _lastDoubleMatch(RegExp rx, String text) {
    final matches = rx.allMatches(text);
    if (matches.isEmpty) return null;
    return double.tryParse(matches.last.group(1) ?? '');
  }

  static int? _lastIntMatch(RegExp rx, String text) {
    final matches = rx.allMatches(text);
    if (matches.isEmpty) return null;
    return int.tryParse(matches.last.group(1) ?? '');
  }

  static int? _inferBitDepthFromSampleFmt(String fmt) {
    final f = fmt.toLowerCase();
    if (f.startsWith('u8')) return 8;
    if (f.startsWith('s16')) return 16;
    if (f.startsWith('s24')) return 24;
    if (f.startsWith('s32') || f.startsWith('flt')) return 32;
    if (f.startsWith('dbl') || f.startsWith('s64')) return 64;
    return null;
  }

  static double? _evalFraction(String raw) {
    if (raw.isEmpty) return null;
    if (!raw.contains('/')) return double.tryParse(raw);
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final numVal = double.tryParse(parts[0]);
    final denVal = double.tryParse(parts[1]);
    if (numVal == null || denVal == null || denVal == 0) return null;
    return numVal / denVal;
  }

  static String _formatRatioFps(String raw) {
    final v = _evalFraction(raw);
    if (v == null || v <= 0) return '';
    if ((v - v.roundToDouble()).abs() < 0.005) return v.round().toString();
    return v.toStringAsFixed(3);
  }

  static String _inferBitrateMode(StreamEntry? audio, int? overallBps) {
    if (audio == null) return overallBps != null ? 'VBR' : 'UNKNOWN';
    final c = audio.codec.toLowerCase();
    if (c.startsWith('pcm_') || c.startsWith('dsd_')) return 'CBR (UNCOMPRESSED)';
    if (isLosslessCodec(c)) return 'VBR (LOSSLESS)';
    if (c == 'opus' || c == 'vorbis') return 'VBR';
    if (c == 'mp3' && audio.bitrateBps != null) {
      const cbrRates = {64000, 96000, 128000, 160000, 192000, 224000, 256000, 320000};
      return cbrRates.contains(audio.bitrateBps) ? 'CBR' : 'VBR';
    }
    return audio.bitrateBps != null ? 'CBR / ABR' : 'VBR';
  }

  static bool? _detectMp4FastStart(String path) {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      final totalLen = file.lengthSync();
      if (totalLen < 16) return null;
      raf = file.openSync(mode: FileMode.read);
      var offset = 0;
      int? moovPos;
      int? mdatPos;
      var guard = 0;
      while (offset + 8 <= totalLen && guard < 64) {
        guard++;
        raf.setPositionSync(offset);
        final header = raf.readSync(16);
        if (header.length < 8) break;
        final bd = ByteData.sublistView(header);
        var boxSize = bd.getUint32(0, Endian.big);
        final boxType = String.fromCharCodes(header.sublist(4, 8));
        if (boxType == 'moov' && moovPos == null) moovPos = offset;
        if (boxType == 'mdat' && mdatPos == null) mdatPos = offset;
        if (moovPos != null && mdatPos != null) break;
        if (boxSize == 1) {
          if (header.length < 16) break;
          boxSize = bd.getUint64(8, Endian.big);
        } else if (boxSize == 0) {
          break;
        }
        if (boxSize < 8) break;
        offset += boxSize;
      }
      if (moovPos == null && mdatPos == null) return null;
      if (moovPos != null && mdatPos == null) return true;
      if (moovPos == null && mdatPos != null) return false;
      return moovPos! < mdatPos!;
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static EmbeddedCoverInfo _inspectImageBytes(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint32(16, Endian.big);
      final h = bd.getUint32(20, Endian.big);
      return EmbeddedCoverInfo(byteLength: bytes.length, format: 'PNG', width: w, height: h, bytes: bytes);
    }
    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var i = 2;
      while (i + 9 < bytes.length) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        if (i + 4 >= bytes.length) break;
        final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
        if (segLen < 2) break;
        if ((marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF)) {
          if (i + 9 < bytes.length) {
            final h = (bytes[i + 5] << 8) | bytes[i + 6];
            final w = (bytes[i + 7] << 8) | bytes[i + 8];
            return EmbeddedCoverInfo(byteLength: bytes.length, format: 'JPEG', width: w, height: h, bytes: bytes);
          }
          break;
        }
        i += 2 + segLen;
      }
      return EmbeddedCoverInfo(byteLength: bytes.length, format: 'JPEG', width: null, height: null, bytes: bytes);
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return EmbeddedCoverInfo(byteLength: bytes.length, format: 'WEBP', width: null, height: null, bytes: bytes);
    }
    return EmbeddedCoverInfo(byteLength: bytes.length, format: 'BINARY', width: null, height: null, bytes: bytes);
  }

  static String _stripExtension(String name) {
    final idx = name.lastIndexOf('.');
    return idx > 0 ? name.substring(0, idx) : name;
  }
}
