import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';

Future<Map<String, int>> probeStreams(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformationAsync(path);
    final info = session.getMediaInformation();
    if (info == null) return {};
    int video = 0, audio = 0;
    for (final s in info.streams) {
      if (s.type == 'video') video++;
      if (s.type == 'audio') audio++;
    }
    return {'video': video, 'audio': audio};
  } catch (_) {
    return {};
  }
}

Future<int?> probeDurationMs(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformationAsync(path);
    final info = session.getMediaInformation();
    final seconds = double.tryParse(info?.duration ?? "");
    if (seconds == null || seconds <= 0) return null;
    return (seconds * 1000).round();
  } catch (_) {
    return null;
  }
}
