// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'ffmpeg_executor.dart';
import 'storage_client.dart';

enum PhotoOutputFormat { original, jpeg, png, webp }

class PhotoEditSettings {
  final ui.Rect crop;
  final int rotateSteps;
  final bool flipH;
  final bool flipV;
  final double brightness;
  final double contrast;
  final double saturation;
  final double sharpen;
  final PhotoOutputFormat format;

  const PhotoEditSettings({
    required this.crop,
    this.rotateSteps = 0,
    this.flipH = false,
    this.flipV = false,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.sharpen = 0,
    this.format = PhotoOutputFormat.original,
  });

  bool get hasChanges =>
      rotateSteps % 4 != 0 ||
      flipH ||
      flipV ||
      crop.left > 0.001 ||
      crop.top > 0.001 ||
      crop.width < 0.999 ||
      crop.height < 0.999 ||
      brightness != 0 ||
      contrast != 1 ||
      saturation != 1 ||
      sharpen > 0 ||
      format != PhotoOutputFormat.original;
}

class PhotoEditGeometry {
  final int storedWidth;
  final int storedHeight;
  final int orientation;

  const PhotoEditGeometry({
    required this.storedWidth,
    required this.storedHeight,
    required this.orientation,
  });

  static PhotoEditGeometry fromPhoto({
    required int width,
    required int height,
    required int orientation,
    required int previewWidth,
    required int previewHeight,
  }) {
    var w = width;
    var h = height;
    if (w <= 0 || h <= 0) {
      if (orientation == 6 || orientation == 8) {
        w = previewHeight;
        h = previewWidth;
      } else {
        w = previewWidth;
        h = previewHeight;
      }
    }
    if (w <= 0 || h <= 0) {
      w = 1024;
      h = 1024;
    }
    return PhotoEditGeometry(storedWidth: w, storedHeight: h, orientation: orientation);
  }

  bool get swapsDimensions => orientation >= 5 && orientation <= 8;
  int get correctedWidth => swapsDimensions ? storedHeight : storedWidth;
  int get correctedHeight => swapsDimensions ? storedWidth : storedHeight;

  List<String> get exifCorrectionFilters {
    switch (orientation) {
      case 2:
        return const ['hflip'];
      case 3:
        return const ['hflip', 'vflip'];
      case 4:
        return const ['vflip'];
      case 5:
        return const ['transpose=0'];
      case 6:
        return const ['transpose=1'];
      case 7:
        return const ['transpose=3'];
      case 8:
        return const ['transpose=2'];
      default:
        return const [];
    }
  }

  int get residualQuarterTurns {
    switch (orientation) {
      case 5:
        return 3;
      case 7:
        return 1;
      default:
        return 0;
    }
  }

  bool get residualFlipH => orientation == 2;
  bool get residualFlipV => orientation == 4 || orientation == 5 || orientation == 7;

  ui.Size finalSize(int rotateSteps) {
    final odd = rotateSteps % 2 == 1;
    final w = odd ? correctedHeight : correctedWidth;
    final h = odd ? correctedWidth : correctedHeight;
    return ui.Size(w.toDouble(), h.toDouble());
  }
}

class PhotoOutputSpec {
  final String extension;
  final String encoderArgs;
  const PhotoOutputSpec({required this.extension, required this.encoderArgs});
}

PhotoOutputSpec resolvePhotoOutput(PhotoOutputFormat format, String displayName, String mime) {
  String ext = '';
  if (format == PhotoOutputFormat.original) {
    final dot = displayName.lastIndexOf('.');
    if (dot >= 0 && dot < displayName.length - 1) ext = displayName.substring(dot + 1).toLowerCase();
    if (ext.isEmpty) {
      if (mime == 'image/png') ext = 'png';
      if (mime == 'image/webp') ext = 'webp';
    }
  } else if (format == PhotoOutputFormat.jpeg) {
    ext = 'jpg';
  } else if (format == PhotoOutputFormat.png) {
    ext = 'png';
  } else {
    ext = 'webp';
  }
  switch (ext) {
    case 'png':
      return const PhotoOutputSpec(extension: 'png', encoderArgs: '-c:v png');
    case 'webp':
      return const PhotoOutputSpec(extension: 'webp', encoderArgs: '-c:v libwebp -quality 90');
    default:
      return const PhotoOutputSpec(extension: 'jpg', encoderArgs: '-c:v mjpeg -q:v 2');
  }
}

String editedPhotoDisplayName(String displayName, String extension) {
  final dot = displayName.lastIndexOf('.');
  final base = dot > 0 ? displayName.substring(0, dot) : displayName;
  final safe = base.isEmpty ? 'sovereign_photo' : base;
  return '${safe}_edited.$extension';
}

String buildPhotoFilterChain({
  required PhotoEditGeometry geometry,
  required PhotoEditSettings settings,
  required int outWidth,
  required int outHeight,
}) {
  final filters = <String>[];
  filters.addAll(geometry.exifCorrectionFilters);
  final steps = settings.rotateSteps % 4;
  if (steps == 1) filters.add('transpose=1');
  if (steps == 2) filters.add('transpose=1,transpose=1');
  if (steps == 3) filters.add('transpose=2');
  if (settings.flipH) filters.add('hflip');
  if (settings.flipV) filters.add('vflip');
  final c = settings.crop;
  if (c.left > 0.001 || c.top > 0.001 || c.width < 0.999 || c.height < 0.999) {
    final x = (c.left * outWidth).round().clamp(0, math.max(0, outWidth - 2));
    final y = (c.top * outHeight).round().clamp(0, math.max(0, outHeight - 2));
    final w = (c.width * outWidth).round().clamp(2, math.max(2, outWidth - x));
    final h = (c.height * outHeight).round().clamp(2, math.max(2, outHeight - y));
    filters.add('crop=$w:$h:$x:$y');
  }
  if (settings.brightness != 0 || settings.contrast != 1 || settings.saturation != 1) {
    filters.add('eq=brightness=${settings.brightness.toStringAsFixed(2)}:contrast=${settings.contrast.toStringAsFixed(2)}:saturation=${settings.saturation.toStringAsFixed(2)}');
  }
  if (settings.sharpen > 0) {
    filters.add('unsharp=5:5:${settings.sharpen.toStringAsFixed(2)}');
  }
  return filters.join(',');
}

List<double> photoColorMatrix(double brightness, double contrast, double saturation) {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  final s = saturation;
  final c = contrast;
  final t = 0.5 * (1 - c) + brightness;
  return [
    c * (lr + (1 - lr) * s),
    c * (lg - lg * s),
    c * (lb - lb * s),
    0,
    t,
    c * (lr - lr * s),
    c * (lg + (1 - lg) * s),
    c * (lb - lb * s),
    0,
    t,
    c * (lr - lr * s),
    c * (lg - lg * s),
    c * (lb + (1 - lb) * s),
    0,
    t,
    0,
    0,
    0,
    1,
    0,
  ];
}

ui.Rect rotateCropRectCw(ui.Rect r) => ui.Rect.fromLTWH(1 - r.bottom, r.left, r.height, r.width);

ui.Rect rotateCropRectCcw(ui.Rect r) => ui.Rect.fromLTWH(r.top, 1 - r.right, r.height, r.width);

ui.Rect flipCropRectH(ui.Rect r) => ui.Rect.fromLTWH(1 - r.right, r.top, r.width, r.height);

ui.Rect flipCropRectV(ui.Rect r) => ui.Rect.fromLTWH(r.left, 1 - r.bottom, r.width, r.height);

ui.Rect largestCenteredRect(double aspect) {
  if (aspect >= 1) return ui.Rect.fromLTWH(0, (1 - 1 / aspect) / 2, 1, 1 / aspect);
  return ui.Rect.fromLTWH((1 - aspect) / 2, 0, aspect, 1);
}

class PhotoEditJob {
  final String inputPath;
  final List<int>? fallbackBytes;
  final String displayName;
  final String sourceMime;
  final PhotoEditGeometry geometry;
  final PhotoEditSettings settings;

  const PhotoEditJob({
    required this.inputPath,
    required this.fallbackBytes,
    required this.displayName,
    required this.sourceMime,
    required this.geometry,
    required this.settings,
  });
}

class PhotoEditRunner {
  static Future<String> _render(PhotoEditJob job) async {
    final output = resolvePhotoOutput(job.settings.format, job.displayName, job.sourceMime);
    final temp = await StorageClient.tempDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    String? stagedSrc;
    var src = job.inputPath;
    if (src.isEmpty || !File(src).existsSync()) {
      final bytes = job.fallbackBytes;
      if (bytes == null || bytes.isEmpty) throw StateError('Photo file is not reachable.');
      src = '$temp/photo_edit_src_$stamp.jpg';
      await File(src).writeAsBytes(bytes);
      stagedSrc = src;
    }
    final outPath = '$temp/photo_edit_$stamp.${output.extension}';
    try {
      final size = job.geometry.finalSize(job.settings.rotateSteps);
      final chain = buildPhotoFilterChain(
        geometry: job.geometry,
        settings: job.settings,
        outWidth: size.width.toInt(),
        outHeight: size.height.toInt(),
      );
      final vfArg = chain.isEmpty ? '' : '-vf "$chain" ';
      final command = '-y -i "$src" $vfArg-frames:v 1 -map_metadata -1 ${output.encoderArgs} "$outPath"';
      final session = await FFmpegExecutor.execute(command, description: 'photo-edit');
      final outFile = File(outPath);
      final ok = ReturnCode.isSuccess(session.getReturnCode()) && outFile.existsSync() && outFile.lengthSync() > 0;
      if (!ok) {
        String tail = '';
        try {
          final full = await FFmpegExecutor.probeOutput(session) ?? '';
          tail = full.length > 300 ? full.substring(full.length - 300) : full;
        } catch (_) {}
        try {
          if (outFile.existsSync()) outFile.deleteSync();
        } catch (_) {}
        throw StateError('Photo edit failed (rc=${session.getReturnCode()}). $tail');
      }
      return outPath;
    } finally {
      if (stagedSrc != null) {
        try {
          File(stagedSrc).deleteSync();
        } catch (_) {}
      }
    }
  }

  static Future<List<int>> renderPreview(PhotoEditJob job) async {
    final outPath = await _render(job);
    try {
      return await File(outPath).readAsBytes();
    } finally {
      try {
        File(outPath).deleteSync();
      } catch (_) {}
    }
  }

  static Future<String> renderAndSave(PhotoEditJob job) async {
    final output = resolvePhotoOutput(job.settings.format, job.displayName, job.sourceMime);
    final outPath = await _render(job);
    try {
      final name = editedPhotoDisplayName(job.displayName, output.extension);
      final saved = await StorageClient.exportPhotoFileToPictures(filePath: outPath, displayName: name);
      if (saved == null) throw StateError('Save failed: Pictures refused the edited copy.');
      return saved;
    } finally {
      try {
        File(outPath).deleteSync();
      } catch (_) {}
    }
  }
}
