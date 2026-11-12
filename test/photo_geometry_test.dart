// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:sovereign_tagger/core/photo_editor.dart';

void main() {
  group('PhotoEditGeometry EXIF Orientation Matrix', () {
    test('Orientation 1 is identity', () {
      final g = PhotoEditGeometry.fromPhoto(width: 1920, height: 1080, orientation: 1, previewWidth: 0, previewHeight: 0);
      expect(g.swapsDimensions, isFalse);
      expect(g.correctedWidth, 1920);
      expect(g.correctedHeight, 1080);
      expect(g.exifCorrectionFilters, isEmpty);
    });

    test('Orientation 3 applies hflip and vflip', () {
      final g = PhotoEditGeometry.fromPhoto(width: 1920, height: 1080, orientation: 3, previewWidth: 0, previewHeight: 0);
      expect(g.swapsDimensions, isFalse);
      expect(g.correctedWidth, 1920);
      expect(g.correctedHeight, 1080);
      expect(g.exifCorrectionFilters, ['hflip', 'vflip']);
    });

    test('Orientation 6 transposes 90 deg CW and swaps dimensions', () {
      final g = PhotoEditGeometry.fromPhoto(width: 1920, height: 1080, orientation: 6, previewWidth: 0, previewHeight: 0);
      expect(g.swapsDimensions, isTrue);
      expect(g.correctedWidth, 1080);
      expect(g.correctedHeight, 1920);
      expect(g.exifCorrectionFilters, ['transpose=1']);
    });

    test('Orientation 8 transposes 90 deg CCW and swaps dimensions', () {
      final g = PhotoEditGeometry.fromPhoto(width: 1920, height: 1080, orientation: 8, previewWidth: 0, previewHeight: 0);
      expect(g.swapsDimensions, isTrue);
      expect(g.correctedWidth, 1080);
      expect(g.correctedHeight, 1920);
      expect(g.exifCorrectionFilters, ['transpose=2']);
    });

    test('Orientation 2 applies hflip', () {
      final g = PhotoEditGeometry.fromPhoto(width: 800, height: 600, orientation: 2, previewWidth: 0, previewHeight: 0);
      expect(g.residualFlipH, isTrue);
      expect(g.exifCorrectionFilters, ['hflip']);
    });

    test('Orientation 4 applies vflip', () {
      final g = PhotoEditGeometry.fromPhoto(width: 800, height: 600, orientation: 4, previewWidth: 0, previewHeight: 0);
      expect(g.residualFlipV, isTrue);
      expect(g.exifCorrectionFilters, ['vflip']);
    });
  });

  group('Photo Crop Calculations', () {
    test('largestCenteredRect square aspect ratio', () {
      final rect = largestCenteredRect(1.0);
      expect(rect, const ui.Rect.fromLTWH(0, 0, 1, 1));
    });

    test('largestCenteredRect widescreen 16:9 aspect ratio', () {
      final rect = largestCenteredRect(16 / 9);
      expect(rect.left, 0.0);
      expect(rect.width, 1.0);
      expect((rect.height - (9 / 16)).abs(), lessThan(0.0001));
      expect((rect.top - (7 / 32)).abs(), lessThan(0.0001));
    });

    test('rotateCropRectCw transforms rectangle corners', () {
      const orig = ui.Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
      final rotated = rotateCropRectCw(orig);
      expect((rotated.left - 0.4).abs(), lessThan(0.0001));
      expect((rotated.top - 0.1).abs(), lessThan(0.0001));
      expect((rotated.width - 0.4).abs(), lessThan(0.0001));
      expect((rotated.height - 0.3).abs(), lessThan(0.0001));
    });

    test('flipCropRectH mirrors horizontally', () {
      const orig = ui.Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
      final flipped = flipCropRectH(orig);
      expect((flipped.left - 0.6).abs(), lessThan(0.0001));
      expect((flipped.top - 0.2).abs(), lessThan(0.0001));
      expect((flipped.width - 0.3).abs(), lessThan(0.0001));
      expect((flipped.height - 0.4).abs(), lessThan(0.0001));
    });
  });
}
