// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

const List<String> supportedVideoContainers = ['mp4', 'mkv', 'webm'];

const List<String> supportedVideoOps = [
  "Video Trim (Re-Encode)",
  "Video Rotate / Flip",
  "Video Scale / Resize",
  "Video Crop (Center)",
  "Mute Video (Drop Audio)",
  "Extract Audio (Video to M4A)",
  "Video Convert (Container)",
  "Mux Video + Audio",
];

String buildVideoCodecArgs(String container) {
  switch (container.toLowerCase()) {
    case 'webm':
      return '-c:v libvpx-vp9 -crf 30 -b:v 0 -pix_fmt yuv420p -c:a libopus -b:a 192k';
    default:
      return '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 192k';
  }
}

String buildVideoAudioCodecArgs(String container) {
  return container.toLowerCase() == 'webm' ? '-c:a libopus -b:a 192k' : '-c:a aac -b:a 192k';
}

String buildVideoRotateFilter({String rotate = "NONE", bool flipH = false, bool flipV = false}) {
  final parts = <String>[];
  switch (rotate) {
    case "90 CW":
      parts.add("transpose=1");
      break;
    case "180":
      parts.add("transpose=1,transpose=1");
      break;
    case "90 CCW":
      parts.add("transpose=2");
      break;
  }
  if (flipH) parts.add("hflip");
  if (flipV) parts.add("vflip");
  return parts.join(',');
}

int buildVideoScaleHeight(String resolution) {
  switch (resolution) {
    case "720p":
      return 720;
    case "480p":
      return 480;
    default:
      return 1080;
  }
}

String buildVideoCropFilter(String aspect) {
  switch (aspect) {
    case "4:3":
      return "crop='min(iw,ih*4/3)':'min(ih,iw*3/4)'";
    case "1:1":
      return "crop='min(iw,ih)':'min(iw,ih)'";
    case "9:16":
      return "crop='min(iw,ih*9/16)':'min(ih,iw*16/9)'";
    default:
      return "crop='min(iw,ih*16/9)':'min(ih,iw*9/16)'";
  }
}

String buildVideoOpSuffix(String op) {
  switch (op) {
    case "Video Trim (Re-Encode)":
      return "_trim";
    case "Video Rotate / Flip":
      return "_rot";
    case "Video Scale / Resize":
      return "_scale";
    case "Video Crop (Center)":
      return "_crop";
    case "Mute Video (Drop Audio)":
      return "_mute";
    case "Extract Audio (Video to M4A)":
      return "_m4a";
    case "Video Convert (Container)":
      return "_conv";
    case "Mux Video + Audio":
      return "_mux";
    default:
      return "_mod";
  }
}

String buildClipVideoArgs({
  required String inputPath,
  required String outPath,
  required String startHms,
  required String endHms,
}) {
  Duration parseHms(String s) {
    final p = s.split(':').map((e) => int.parse(e)).toList();
    return Duration(hours: p[0], minutes: p[1], seconds: p[2]);
  }
  final start = parseHms(startHms);
  final end = parseHms(endHms);
  if (start > Duration.zero) {
    String two(int n) => n.toString().padLeft(2, '0');
    final diff = end - start;
    final diffFmt = "${two(diff.inHours)}:${two(diff.inMinutes.remainder(60))}:${two(diff.inSeconds.remainder(60))}";
    return '-y -ss $startHms -i "$inputPath" -t $diffFmt -c copy -avoid_negative_ts make_zero "$outPath"';
  } else {
    return '-y -i "$inputPath" -to $endHms -c copy -avoid_negative_ts make_zero "$outPath"';
  }
}

String buildVideoCommand({
  required String op,
  required String inputPath,
  required String outPath,
  int? durationMs,
  String startHms = "00:00:00",
  String endHms = "00:00:15",
  String rotate = "NONE",
  bool flipH = false,
  bool flipV = false,
  String scale = "1080p",
  String cropAspect = "16:9",
  String targetVideoFormat = "mp4",
  String? secondFilePath,
}) {
  final parts = inputPath.split('.');
  final srcExt = parts.length > 1 ? parts.last.toLowerCase() : "";
  final container = supportedVideoContainers.contains(srcExt) ? srcExt : "mp4";
  final vcodecs = buildVideoCodecArgs(container);
  switch (op) {
    case "Video Trim (Re-Encode)": {
      final timeFmt = RegExp(r'^\d{1,2}:\d{2}:\d{2}$');
      final startText = startHms.trim();
      final endText = endHms.trim();
      if (!timeFmt.hasMatch(startText) || !timeFmt.hasMatch(endText)) {
        throw StateError("ERR: Clip Bounds Must Be HH:MM:SS.");
      }
      Duration parseHms(String s) {
        final p = s.split(':').map((e) => int.parse(e)).toList();
        return Duration(hours: p[0], minutes: p[1], seconds: p[2]);
      }
      final start = parseHms(startText);
      final end = parseHms(endText);
      if (end <= start) throw StateError("ERR: END Must Exceed START.");
      if (durationMs != null && end.inMilliseconds > durationMs + 500) {
        String two(int n) => n.toString().padLeft(2, '0');
        final dur = Duration(milliseconds: durationMs);
        final fmt = "${two(dur.inHours)}:${two(dur.inMinutes.remainder(60))}:${two(dur.inSeconds.remainder(60))}";
        throw StateError("ERR: END Exceeds Source Duration ($fmt).");
      }
      return '-y -i "$inputPath" -ss $startText -to $endText -map 0:v:0 -map 0:a? $vcodecs "$outPath"';
    }
    case "Video Rotate / Flip": {
      final chain = buildVideoRotateFilter(rotate: rotate, flipH: flipH, flipV: flipV);
      if (chain.isEmpty) {
        throw StateError("ERR: NOTHING TO ROTATE OR FLIP. Pick a rotation or a flip first.");
      }
      return '-y -i "$inputPath" -vf "$chain" -map 0:v:0 -map 0:a? $vcodecs "$outPath"';
    }
    case "Video Scale / Resize":
      final h = buildVideoScaleHeight(scale);
      return '-y -i "$inputPath" -vf "scale=-2:$h" -map 0:v:0 -map 0:a? $vcodecs "$outPath"';
    case "Video Crop (Center)":
      final crop = buildVideoCropFilter(cropAspect);
      return '-y -i "$inputPath" -vf "$crop" -map 0:v:0 -map 0:a? $vcodecs "$outPath"';
    case "Mute Video (Drop Audio)":
      return '-y -i "$inputPath" -map 0:v:0 -c:v copy "$outPath"';
    case "Extract Audio (Video to M4A)":
      return '-y -i "$inputPath" -vn -c:a aac -b:a 256k "$outPath"';
    case "Video Convert (Container)": {
      final targetCodecs = buildVideoCodecArgs(targetVideoFormat);
      return '-y -i "$inputPath" -map 0:v:0 -map 0:a? $targetCodecs "$outPath"';
    }
    case "Mux Video + Audio": {
      if (secondFilePath == null || secondFilePath.isEmpty) {
        throw StateError("ERR: MOUNT SECOND MEDIA FIRST (AUDIO TRACK).");
      }
      final acodec = buildVideoAudioCodecArgs(container);
      return '-y -i "$inputPath" -i "$secondFilePath" -map 0:v:0 -map 1:a:0 -c:v copy $acodec -shortest "$outPath"';
    }
    default:
      throw StateError("ERR: OP '$op' HAS NO VIDEO CHAIN.");
  }
}
