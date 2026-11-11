// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/photo_editor.dart';
import '../core/storage_client.dart';
import 'main_shell.dart';

class PhotoEditorScreen extends StatefulWidget {
  final String uri;
  final String path;
  final String displayName;
  final String mime;
  final int width;
  final int height;
  final Uint8List previewBytes;

  const PhotoEditorScreen({
    required this.uri,
    required this.path,
    required this.displayName,
    required this.mime,
    required this.width,
    required this.height,
    required this.previewBytes,
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  PhotoEditGeometry? _geometry;
  ui.Rect _crop = const ui.Rect.fromLTWH(0, 0, 1, 1);
  double? _aspect;
  int _rotateSteps = 0;
  bool _flipH = false;
  bool _flipV = false;
  double _brightness = 0;
  double _contrast = 1;
  double _saturation = 1;
  double _sharpen = 0;
  PhotoOutputFormat _format = PhotoOutputFormat.original;
  Uint8List? _renderedBytes;
  bool _busy = false;
  bool _dirty = false;
  bool _savedOnce = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var orientation = 1;
    try {
      orientation = await StorageClient.photoOrientation(uri: widget.uri);
    } catch (_) {}
    var previewWidth = 0;
    var previewHeight = 0;
    try {
      final decoded = await ui.decodeImageFromList(widget.previewBytes);
      previewWidth = decoded.width;
      previewHeight = decoded.height;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _geometry = PhotoEditGeometry.fromPhoto(
        width: widget.width,
        height: widget.height,
        orientation: orientation,
        previewWidth: previewWidth,
        previewHeight: previewHeight,
      );
    });
  }

  PhotoEditSettings get _settings => PhotoEditSettings(
        crop: _crop,
        rotateSteps: _rotateSteps,
        flipH: _flipH,
        flipV: _flipV,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        sharpen: _sharpen,
        format: _format,
      );

  PhotoEditJob get _job => PhotoEditJob(
        inputPath: widget.path,
        fallbackBytes: widget.previewBytes,
        displayName: widget.displayName,
        sourceMime: widget.mime,
        geometry: _geometry!,
        settings: _settings,
      );

  void _markDirty() {
    setState(() {
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _applyAspect(double? aspect) {
    setState(() {
      _aspect = aspect;
      _crop = aspect == null ? const ui.Rect.fromLTWH(0, 0, 1, 1) : largestCenteredRect(aspect);
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _rotateCw() {
    setState(() {
      _rotateSteps = (_rotateSteps + 1) % 4;
      _crop = rotateCropRectCw(_crop);
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _rotateCcw() {
    setState(() {
      _rotateSteps = (_rotateSteps + 3) % 4;
      _crop = rotateCropRectCcw(_crop);
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _flipHorizontal() {
    setState(() {
      _flipH = !_flipH;
      _crop = flipCropRectH(_crop);
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _flipVertical() {
    setState(() {
      _flipV = !_flipV;
      _crop = flipCropRectV(_crop);
      _dirty = true;
      _renderedBytes = null;
    });
  }

  void _resetAll() {
    setState(() {
      _crop = const ui.Rect.fromLTWH(0, 0, 1, 1);
      _aspect = null;
      _rotateSteps = 0;
      _flipH = false;
      _flipV = false;
      _brightness = 0;
      _contrast = 1;
      _saturation = 1;
      _sharpen = 0;
      _format = PhotoOutputFormat.original;
      _renderedBytes = null;
      _dirty = false;
      _status = 'Reset.';
    });
  }

  Future<void> _preview() async {
    final geometry = _geometry;
    if (geometry == null || _busy) return;
    if (!_settings.hasChanges) {
      setState(() => _status = 'No changes to preview.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Rendering preview...';
    });
    try {
      final bytes = await PhotoEditRunner.renderPreview(_job);
      if (!mounted) return;
      setState(() {
        _renderedBytes = Uint8List.fromList(bytes);
        _busy = false;
        _status = 'Preview rendered. SAVE COPY to keep it.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'ERR: $e';
      });
    }
  }

  Future<void> _save() async {
    final geometry = _geometry;
    if (geometry == null || _busy) return;
    if (!_dirty || !_settings.hasChanges) {
      setState(() => _status = 'Nothing new to save.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Saving copy...';
    });
    try {
      final saved = await PhotoEditRunner.renderAndSave(_job);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
        _savedOnce = true;
        _status = 'Saved to $saved';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'ERR: $e';
      });
    }
  }

  ui.Size _fitBox(BoxConstraints constraints, double aspect) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    if (maxW <= 0 || maxH <= 0) return ui.Size.zero;
    if (maxW / maxH > aspect) return ui.Size(maxH * aspect, maxH);
    return ui.Size(maxW, maxW / aspect);
  }

  Widget _buildPreviewImage(ui.Size displaySize) {
    final geometry = _geometry!;
    final rendered = _renderedBytes;
    if (rendered != null) {
      return SizedBox(
        width: displaySize.width,
        height: displaySize.height,
        child: Image.memory(rendered, fit: BoxFit.fill),
      );
    }
    final totalQuarters = (geometry.residualQuarterTurns + _rotateSteps) % 4;
    final odd = totalQuarters % 2 == 1;
    final innerW = odd ? displaySize.height : displaySize.width;
    final innerH = odd ? displaySize.width : displaySize.height;
    final flipH = geometry.residualFlipH != _flipH;
    final flipV = geometry.residualFlipV != _flipV;
    final angle = totalQuarters * math.pi / 2;
    final matrix = ui.Matrix4.identity()
      ..scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0)
      ..rotateZ(angle);
    final image = Image.memory(widget.previewBytes, fit: BoxFit.fill);
    final filtered = (_brightness != 0 || _contrast != 1 || _saturation != 1)
        ? ColorFiltered(
            colorFilter: ColorFilter.matrix(photoColorMatrix(_brightness, _contrast, _saturation)),
            child: image,
          )
        : image;
    return SizedBox(
      width: displaySize.width,
      height: displaySize.height,
      child: Center(
        child: SizedBox(
          width: innerW,
          height: innerH,
          child: Transform(alignment: Alignment.center, transform: matrix, child: filtered),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, Color themeColor) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: selected ? themeColor : Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        minimumSize: const Size(0, 30),
      ),
      child: Text(
        label,
        style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: selected ? themeColor : Colors.white70),
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged, Color themeColor) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white70)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: themeColor,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              onChanged(v);
              _markDirty();
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(Color themeColor) {
    return Container(
      height: 258,
      color: Colors.black,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ASPECT', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _chip('FREE', _aspect == null, () => _applyAspect(null), themeColor),
                _chip('1:1', _aspect == 1, () => _applyAspect(1), themeColor),
                _chip('4:3', _aspect == 4 / 3, () => _applyAspect(4 / 3), themeColor),
                _chip('16:9', _aspect == 16 / 9, () => _applyAspect(16 / 9), themeColor),
              ],
            ),
            const SizedBox(height: 10),
            Text('ROTATE / FLIP', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _chip('ROTATE L', false, _rotateCcw, themeColor),
                _chip('ROTATE R', false, _rotateCw, themeColor),
                _chip('FLIP H', _flipH, _flipHorizontal, themeColor),
                _chip('FLIP V', _flipV, _flipVertical, themeColor),
                _chip('RESET CROP', false, () {
                  setState(() {
                    _crop = _aspect == null ? const ui.Rect.fromLTWH(0, 0, 1, 1) : largestCenteredRect(_aspect!);
                    _dirty = true;
                    _renderedBytes = null;
                  });
                }, themeColor),
              ],
            ),
            const SizedBox(height: 10),
            Text('ADJUST', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
            _sliderRow('BRIGHTNESS', _brightness, -0.5, 0.5, (v) => _brightness = v, themeColor),
            _sliderRow('CONTRAST', _contrast, 0.5, 1.5, (v) => _contrast = v, themeColor),
            _sliderRow('SATURATION', _saturation, 0, 2, (v) => _saturation = v, themeColor),
            _sliderRow('SHARPEN', _sharpen, 0, 2, (v) => _sharpen = v, themeColor),
            const SizedBox(height: 6),
            Text('FORMAT', style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: themeColor)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _chip('ORIGINAL', _format == PhotoOutputFormat.original, () {
                  setState(() => _format = PhotoOutputFormat.original);
                  _markDirty();
                }, themeColor),
                _chip('JPEG', _format == PhotoOutputFormat.jpeg, () {
                  setState(() => _format = PhotoOutputFormat.jpeg);
                  _markDirty();
                }, themeColor),
                _chip('PNG', _format == PhotoOutputFormat.png, () {
                  setState(() => _format = PhotoOutputFormat.png);
                  _markDirty();
                }, themeColor),
                _chip('WEBP', _format == PhotoOutputFormat.webp, () {
                  setState(() => _format = PhotoOutputFormat.webp);
                  _markDirty();
                }, themeColor),
                _chip('RESET ALL', false, _resetAll, themeColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Edits never touch the original. Every save writes a new copy to Pictures/Sovereign Tagger. EXIF is dropped on export; orientation is baked into the pixels.',
              style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = SovereignState.accentColor.value;
    final geometry = _geometry;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeColor),
          onPressed: () => Navigator.pop(context, _savedOnce),
        ),
        title: Text(
          'EDIT ${widget.displayName}',
          style: TextStyle(fontFamily: 'ShareTechMono', color: themeColor, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: IconThemeData(color: themeColor),
        actions: [
          IconButton(
            tooltip: 'PREVIEW',
            icon: Icon(Icons.visibility, color: themeColor),
            onPressed: _busy || geometry == null ? null : _preview,
          ),
          IconButton(
            tooltip: 'SAVE COPY',
            icon: _busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                : Icon(Icons.save_alt, color: themeColor),
            onPressed: _busy || geometry == null || !_dirty ? null : _save,
          ),
        ],
      ),
      body: geometry == null
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final finalSize = geometry.finalSize(_rotateSteps);
                      final aspect = finalSize.width / finalSize.height;
                      final display = _fitBox(constraints, aspect);
                      return Center(
                        child: SizedBox(
                          width: display.width,
                          height: display.height,
                          child: Stack(
                            children: [
                              _buildPreviewImage(display),
                              if (_renderedBytes == null)
                                _CropOverlay(
                                  size: display,
                                  fractions: _crop,
                                  aspect: _aspect,
                                  accent: themeColor,
                                  onChanged: (r) {
                                    setState(() {
                                      _crop = r;
                                      _dirty = true;
                                      _renderedBytes = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.black,
                  child: Text(
                    _status.isEmpty ? '${geometry.correctedWidth}x${geometry.correctedHeight}   Drag corners to crop' : _status,
                    style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
                _buildPanel(themeColor),
              ],
            ),
    );
  }
}

class _CropOverlay extends StatefulWidget {
  final ui.Size size;
  final ui.Rect fractions;
  final double? aspect;
  final Color accent;
  final ValueChanged<ui.Rect> onChanged;

  const _CropOverlay({
    required this.size,
    required this.fractions,
    required this.aspect,
    required this.accent,
    required this.onChanged,
  });

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  int _mode = 0;
  int _corner = 0;
  ui.Rect _startFractions = ui.Rect.zero;
  ui.Offset _startLocal = ui.Offset.zero;

  ui.Rect get _rectPx => ui.Rect.fromLTWH(
        widget.fractions.left * widget.size.width,
        widget.fractions.top * widget.size.height,
        widget.fractions.width * widget.size.width,
        widget.fractions.height * widget.size.height,
      );

  ui.Offset _cornerPoint(ui.Rect r, int index) {
    switch (index) {
      case 0:
        return r.topLeft;
      case 1:
        return r.topRight;
      case 2:
        return r.bottomRight;
      default:
        return r.bottomLeft;
    }
  }

  void _onPanDown(DragDownDetails details) {
    final local = details.localPosition;
    final r = _rectPx;
    var best = -1;
    var bestDist = 30.0;
    for (var i = 0; i < 4; i++) {
      final d = (_cornerPoint(r, i) - local).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    _startFractions = widget.fractions;
    _startLocal = local;
    if (best >= 0) {
      _mode = 2;
      _corner = best;
    } else if (r.contains(local)) {
      _mode = 1;
    } else {
      _mode = 0;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_mode == 0) return;
    final local = details.localPosition;
    final dx = (local.dx - _startLocal.dx) / widget.size.width;
    final dy = (local.dy - _startLocal.dy) / widget.size.height;
    if (_mode == 1) {
      final w = _startFractions.width;
      final h = _startFractions.height;
      final left = math.min(math.max(_startFractions.left + dx, 0.0), 1.0 - w);
      final top = math.min(math.max(_startFractions.top + dy, 0.0), 1.0 - h);
      widget.onChanged(ui.Rect.fromLTWH(left, top, w, h));
      return;
    }
    final anchor = _cornerPoint(_startFractions, (_corner + 2) % 4);
    final startDrag = _cornerPoint(_startFractions, _corner);
    final px = math.min(math.max(startDrag.dx + dx, 0.0), 1.0);
    final py = math.min(math.max(startDrag.dy + dy, 0.0), 1.0);
    final dirX = px >= anchor.dx ? 1.0 : -1.0;
    final dirY = py >= anchor.dy ? 1.0 : -1.0;
    final maxW = dirX > 0 ? 1.0 - anchor.dx : anchor.dx;
    final maxH = dirY > 0 ? 1.0 - anchor.dy : anchor.dy;
    var w = math.min(math.max((px - anchor.dx).abs(), 0.05), math.max(0.05, maxW));
    var h = math.min(math.max((py - anchor.dy).abs(), 0.05), math.max(0.05, maxH));
    final aspect = widget.aspect;
    if (aspect != null) {
      final hFromW = w / aspect;
      if (hFromW <= maxH) {
        h = hFromW;
      } else {
        w = maxH * aspect;
        h = maxH;
      }
      if (w < 0.05) {
        w = 0.05;
        h = math.min(w / aspect, math.max(0.05, maxH));
      }
      if (h < 0.05) {
        h = 0.05;
        w = math.min(h * aspect, math.max(0.05, maxW));
      }
    }
    final left = dirX > 0 ? anchor.dx : anchor.dx - w;
    final top = dirY > 0 ? anchor.dy : anchor.dy - h;
    widget.onChanged(ui.Rect.fromLTWH(left, top, w, h));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: _onPanDown,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) {
        _mode = 0;
      },
      child: CustomPaint(
        size: widget.size,
        painter: _CropPainter(fractions: widget.fractions, accent: widget.accent),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Rect fractions;
  final Color accent;

  _CropPainter({required this.fractions, required this.accent});

  @override
  void paint(Canvas canvas, ui.Size size) {
    final r = ui.Rect.fromLTWH(
      fractions.left * size.width,
      fractions.top * size.height,
      fractions.width * size.width,
      fractions.height * size.height,
    );
    final dim = Paint()..color = const Color(0x88000000);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, r.top), dim);
    canvas.drawRect(ui.Rect.fromLTWH(0, r.bottom, size.width, size.height - r.bottom), dim);
    canvas.drawRect(ui.Rect.fromLTWH(0, r.top, r.left, r.height), dim);
    canvas.drawRect(ui.Rect.fromLTWH(r.right, r.top, size.width - r.right, r.height), dim);
    final border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, border);
    final thirds = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = r.left + r.width * i / 3;
      canvas.drawLine(ui.Offset(x, r.top), ui.Offset(x, r.bottom), thirds);
      final y = r.top + r.height * i / 3;
      canvas.drawLine(ui.Offset(r.left, y), ui.Offset(r.right, y), thirds);
    }
    final handle = Paint()..color = accent;
    for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
      canvas.drawRect(ui.Rect.fromCenter(center: c, width: 12, height: 12), handle);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.fractions != fractions || old.accent != accent;
}
