// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'machine_rain.dart';

class CyberBackdrop extends StatefulWidget {
  final Color accentColor;
  final BackdropVariant variant;
  final double intensity;

  const CyberBackdrop({super.key, required this.accentColor, this.variant = BackdropVariant.generic, this.intensity = 1.0});

  @override
  State<CyberBackdrop> createState() => _CyberBackdropState();
}

class _CyberBackdropState extends State<CyberBackdrop> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? _program;

  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final Ticker _ticker;
  ui.FragmentShader? _shader;
  Duration _last = Duration.zero;
  double _elapsed = 0;
  int _frame = 0;

  static Future<ui.FragmentProgram?> _load() {
    return _loading ??= ui.FragmentProgram.fromAsset('shaders/backdrop.frag').then<ui.FragmentProgram?>((p) {
      _program = p;
      return p;
    }).catchError((Object _) => null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    if (_program != null) {
      _shader = _program!.fragmentShader();
      _ticker.start();
    } else {
      _load().then((program) {
        if (!mounted || program == null) return;
        setState(() => _shader = program.fragmentShader());
        _ticker.start();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_shader == null) return;
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _elapsed += dt.clamp(0.0, 0.1);
    _frame++;
    if (_frame.isEven) _time.value = _elapsed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _shader?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return AmbientBackdrop(accentColor: widget.accentColor, variant: widget.variant);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _BackdropPainter(
            shader: shader,
            time: _time,
            accent: widget.accentColor,
            variant: widget.variant.index.toDouble(),
            intensity: widget.intensity,
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final Color accent;
  final double variant;
  final double intensity;

  _BackdropPainter({required this.shader, required this.time, required this.accent, required this.variant, required this.intensity}) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, accent.r)
      ..setFloat(4, accent.g)
      ..setFloat(5, accent.b)
      ..setFloat(6, 1.0)
      ..setFloat(7, variant)
      ..setFloat(8, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.shader != shader || oldDelegate.accent != accent || oldDelegate.variant != variant || oldDelegate.intensity != intensity;
}
