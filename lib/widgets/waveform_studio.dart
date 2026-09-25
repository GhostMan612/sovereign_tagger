// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ffmpeg_executor.dart';
import '../core/tap_feedback.dart';

class WaveformStudio extends StatefulWidget {
  final String filePath;
  final int durationMs;
  final Duration initialIn;
  final Duration initialOut;
  final void Function(Duration selIn, Duration selOut)? onSelection;

  const WaveformStudio({
    super.key,
    required this.filePath,
    required this.durationMs,
    required this.initialIn,
    required this.initialOut,
    this.onSelection,
  });

  @override
  State<WaveformStudio> createState() => _WaveformStudioState();
}

class _WaveformStudioState extends State<WaveformStudio> {
  List<double>? _peaks;
  double _viewStart = 0.0;
  double _viewEnd = 1.0;
  late double _selIn;
  late double _selOut;
  int _dragMode = 0;

  @override
  void initState() {
    super.initState();
    final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
    _selIn = widget.initialIn.inMilliseconds / total;
    _selOut = widget.initialOut.inMilliseconds / total;
    _loadPeaks();
  }

  @override
  void didUpdateWidget(WaveformStudio old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
      setState(() {
        _peaks = null;
        _viewStart = 0.0;
        _viewEnd = 1.0;
        _selIn = widget.initialIn.inMilliseconds / total;
        _selOut = widget.initialOut.inMilliseconds / total;
      });
      _loadPeaks();
    }
  }

  Future<void> _loadPeaks() async {
    final data = await _extractPeaks(widget.filePath);
    if (!mounted) return;
    setState(() => _peaks = data);
  }

  Future<List<double>> _extractPeaks(String path) async {
    final tempDir = await const MethodChannel('com.sovereign.tagger/storage').invokeMethod<String>('getTempDirectory') ?? '';
    final raw = "$tempDir/wfstudio_${DateTime.now().millisecondsSinceEpoch}.raw";
    try {
      await FFmpegExecutor.execute('-y -i "$path" -vn -ac 1 -ar 8000 -f s16le "$raw"');
      final bytes = await File(raw).readAsBytes();
      final data = bytes.buffer.asInt16List(0, bytes.lengthInBytes ~/ 2);
      const targetBars = 1200;
      final samplesPerBucket = (data.length / targetBars).ceil().clamp(1, data.length);
      final bucketCount = (data.length / samplesPerBucket).floor().clamp(1, 4000);
      final peaks = List<double>.filled(bucketCount, 0.0);
      for (int i = 0; i < bucketCount; i++) {
        double peak = 0.0;
        final start = i * samplesPerBucket;
        final end = (start + samplesPerBucket).clamp(0, data.length);
        for (int j = start; j < end; j++) {
          final v = data[j].abs() / 32768.0;
          if (v > peak) peak = v;
        }
        peaks[i] = peak;
      }
      return peaks;
    } finally {
      try { File(raw).delete(); } catch (_) {}
    }
  }

  double _fracFromLocalX(double dx, double width) {
    final span = _viewEnd - _viewStart;
    final frac = _viewStart + (dx / width) * span;
    return frac.clamp(0.0, 1.0);
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    _applyDrag(d.localPosition.dx, width);
  }

  void _onDragStart(DragStartDetails d, double width) {
    _dragMode = 0;
    _applyDrag(d.localPosition.dx, width);
  }

  void _applyDrag(double dx, double width) {
    final f = _fracFromLocalX(dx, width);
    if (_dragMode == 0) {
      _dragMode = f > ((_selIn + _selOut) / 2) && (f - _selIn).abs() > (f - _selOut).abs() ? 2 : 1;
      if ((f - _selIn).abs() < 0.02) _dragMode = 1;
      if ((f - _selOut).abs() < 0.02) _dragMode = 2;
    }
    setState(() {
      if (_dragMode == 1) {
        _selIn = f;
      } else if (_dragMode == 2) {
        _selOut = f;
      } else {
        _selIn = f;
        _selOut = f;
      }
      if (_selIn > _selOut) {
        final t = _selIn;
        _selIn = _selOut;
        _selOut = t;
        _dragMode = _dragMode == 1 ? 2 : 1;
      }
    });
  }

  void _emitSelection() {
    final total = widget.durationMs;
    widget.onSelection?.call(
      Duration(milliseconds: (_selIn * total).round()),
      Duration(milliseconds: (_selOut * total).round()),
    );
  }

  void _zoom(double factor, {double? focal}) {
    setState(() {
      final span = (_viewEnd - _viewStart) * factor;
      final clamped = span.clamp(0.01, 1.0);
      final center = focal ?? (_viewStart + _viewEnd) / 2;
      _viewStart = (center - clamped / 2).clamp(0.0, 1.0 - clamped);
      _viewEnd = _viewStart + clamped;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 6),
              const Expanded(child: Text("WAVEFORM STUDIO", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent))),
              IconButton(icon: const Icon(Icons.zoom_out, size: 18, color: Colors.white70), tooltip: "ZOOM OUT", constraints: const BoxConstraints(minWidth: 32, minHeight: 28), padding: EdgeInsets.zero, onPressed: () => _zoom(1.6)),
              IconButton(icon: const Icon(Icons.zoom_in, size: 18, color: Colors.white70), tooltip: "ZOOM IN", constraints: const BoxConstraints(minWidth: 32, minHeight: 28), padding: EdgeInsets.zero, onPressed: () => _zoom(0.62)),
              OutlinedButton(onPressed: () => setState(() { _viewStart = 0.0; _viewEnd = 1.0; }), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text("FIT", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.white70))),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, cons) {
            final w = cons.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 34),
                  painter: _RulerPainter(viewStart: _viewStart, viewEnd: _viewEnd, durationMs: total),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) => _onDragStart(d, w),
                  onHorizontalDragUpdate: (d) => _onDragUpdate(d, w),
                  onHorizontalDragEnd: (_) {
                    _dragMode = 0;
                    TapFeedback.machineTap();
                    _emitSelection();
                  },
                  child: SizedBox(
                    height: 96,
                    child: _peaks == null
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)))
                        : CustomPaint(
                            size: Size(w, 96),
                            painter: _WavePainter(peaks: _peaks!, viewStart: _viewStart, viewEnd: _viewEnd, selIn: _selIn, selOut: _selOut),
                          ),
                  ),
                ),
              ],
            );
          }),
          RangeSlider(
            values: RangeValues(_viewStart, _viewEnd),
            min: 0.0,
            max: 1.0,
            divisions: 500,
            activeColor: Colors.cyanAccent,
            inactiveColor: Colors.white12,
            onChanged: (v) => setState(() { _viewStart = v.start; _viewEnd = v.end; }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("IN ${_fmtHms(_selIn)}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.greenAccent)),
              const Text("DRAG WAVE TO SELECT • PINCH STRIP TO PAN", style: TextStyle(fontFamily: 'ShareTechMono', fontSize: 9, color: Colors.white24)),
              Text("OUT ${_fmtHms(_selOut)}", style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 10, color: Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtHms(double frac) {
    final d = Duration(milliseconds: (widget.durationMs * frac).round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}

class _RulerPainter extends CustomPainter {
  final double viewStart;
  final double viewEnd;
  final int durationMs;
  _RulerPainter({required this.viewStart, required this.viewEnd, required this.durationMs});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white24..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final spanMs = (durationMs * (viewEnd - viewStart)).round();
    const steps = [100, 250, 500, 1000, 2000, 5000, 10000, 15000, 30000, 60000, 300000];
    int step = steps.last;
    for (final s in steps) {
      if (spanMs / s <= 7) { step = s; break; }
    }
    final startMs = (durationMs * viewStart).round();
    final firstTick = ((startMs / step).floor() + 1) * step;
    for (int ms = firstTick; ms <= durationMs * viewEnd; ms += step) {
      final frac = ms / durationMs;
      if (frac < viewStart || frac > viewEnd) continue;
      final x = (frac - viewStart) / (viewEnd - viewStart) * size.width;
      canvas.drawLine(Offset(x, size.height - 6), Offset(x, size.height), p);
      tp.text = TextSpan(
        text: _label(ms),
        style: const TextStyle(fontFamily: 'ShareTechMono', fontSize: 8, color: Colors.white38),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 2, 0));
    }
  }

  String _label(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inHours > 0) return "${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
    if (d.inSeconds >= 60) return "${d.inMinutes.remainder(60)}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
    return "${d.inMilliseconds / 1000.0}";
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.viewStart != viewStart || old.viewEnd != viewEnd;
}

class _WavePainter extends CustomPainter {
  final List<double> peaks;
  final double viewStart;
  final double viewEnd;
  final double selIn;
  final double selOut;
  _WavePainter({required this.peaks, required this.viewStart, required this.viewEnd, required this.selIn, required this.selOut});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A1416));
    final mid = size.height / 2;
    final span = viewEnd - viewStart;
    final barCount = (size.width / 3).floor();
    final paintSel = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.85);
    final paintDim = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.25);

    for (int b = 0; b < barCount; b++) {
      final fracA = viewStart + (b / barCount) * span;
      final fracB = viewStart + ((b + 1) / barCount) * span;
      final idxA = (fracA * peaks.length).floor().clamp(0, peaks.length - 1);
      final idxB = (fracB * peaks.length).floor().clamp(idxA, peaks.length);
      double peak = 0;
      for (int i = idxA; i < idxB; i++) {
        if (peaks[i] > peak) peak = peaks[i];
      }
      final h = (peak * (size.height - 6)).clamp(1.5, size.height - 6);
      final inSel = fracA >= selIn && fracB <= selOut;
      canvas.drawLine(Offset(b * 3.0 + 1.0, mid - h / 2), Offset(b * 3.0 + 1.0, mid + h / 2), inSel ? paintSel : paintDim);
    }

    final selX1 = ((selIn - viewStart) / span) * size.width;
    final selX2 = ((selOut - viewStart) / span) * size.width;
    final shade = Paint()..color = Colors.white.withValues(alpha: 0.06);
    if (selX1 > 0) canvas.drawRect(Rect.fromLTWH(0, 0, selX1.clamp(0.0, size.width), size.height), shade);
    if (selX2 < size.width) canvas.drawRect(Rect.fromLTWH(selX2.clamp(0.0, size.width), 0, (size.width - selX2).clamp(0.0, size.width), size.height), shade);
    final lineP = Paint()..color = Colors.greenAccent..strokeWidth = 2;
    canvas.drawLine(Offset(selX1, 0), Offset(selX1, size.height), lineP);
    final lineP2 = Paint()..color = Colors.redAccent..strokeWidth = 2;
    canvas.drawLine(Offset(selX2, 0), Offset(selX2, size.height), lineP2);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.viewStart != viewStart || old.viewEnd != viewEnd || old.selIn != selIn || old.selOut != selOut || !identical(old.peaks, peaks);
}
