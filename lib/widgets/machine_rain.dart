// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

class MachineRain extends StatefulWidget {
  final Color accentColor;
  final double opacity;
  const MachineRain({super.key, required this.accentColor, this.opacity = 0.18});

  @override
  State<MachineRain> createState() => _MachineRainState();
}

class _MachineRainState extends State<MachineRain> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _MachineRainPainter(
          tick: _controller.value,
          accentColor: widget.accentColor,
          opacity: widget.opacity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _MachineRainPainter extends CustomPainter {
  final double tick;
  final Color accentColor;
  final double opacity;
  final TextPainter tp = TextPainter(textDirection: TextDirection.ltr);

  _MachineRainPainter({required this.tick, required this.accentColor, required this.opacity});

  static const String _glyphs = "01ｱｶｻﾀﾅﾊﾐﾔﾗﾜｦﾝｧｨｩｪｫｬｭｮｯﾜｦﾝ0123456789ABCDEF";

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / 18).ceil().clamp(12, 36);
    final colW = size.width / cols;

    for (int c = 0; c < cols; c++) {
      final rng = Random(1000 + c * 7);
      final speed = 0.8 + rng.nextDouble() * 1.6;
      final offset = (tick * speed * 400 + rng.nextDouble() * 200) % (size.height + 200);
      final len = 7 + rng.nextInt(8);
      final headX = c * colW + colW * 0.3;
      final columnGlyphs = List<String>.generate(24, (_) => _glyphs[rng.nextInt(_glyphs.length)]);

      for (int i = 0; i < len; i++) {
        final y = offset - i * 18;
        if (y < -20 || y > size.height + 20) continue;
        final fade = (1 - i / len) * opacity;
        if (fade < 0.02) continue;
        final glyph = columnGlyphs[i % columnGlyphs.length];
        final isHead = i == 0;
        tp.text = TextSpan(
          text: glyph,
          style: TextStyle(
            fontFamily: 'ShareTechMono',
            fontSize: isHead ? 16 : 13,
            color: isHead ? Colors.white.withValues(alpha: fade + 0.3) : accentColor.withValues(alpha: fade),
            shadows: isHead ? [Shadow(color: accentColor.withValues(alpha: 0.8), blurRadius: 8)] : null,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(headX, y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MachineRainPainter oldDelegate) => oldDelegate.tick != tick || oldDelegate.accentColor != accentColor || oldDelegate.opacity != opacity;
}

enum BackdropVariant { grabber, forge, pipeline, workbench, generic }

class AmbientBackdrop extends StatefulWidget {
  final Color accentColor;
  final BackdropVariant variant;
  const AmbientBackdrop({super.key, required this.accentColor, this.variant = BackdropVariant.generic});

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _ctrl.repeat();
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [widget.accentColor.withValues(alpha: 0.06), Colors.transparent],
          ),
        ),
        child: CustomPaint(
          painter: _PulsingGridPainter(color: widget.accentColor.withValues(alpha: 0.035), controller: _ctrl, variant: widget.variant),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PulsingGridPainter extends CustomPainter {
  final Color color;
  final Animation<double> controller;
  final BackdropVariant variant;
  _PulsingGridPainter({required this.color, required this.controller, required this.variant}) : super(repaint: controller);

  final Paint _grid = Paint()..strokeWidth = 0.5;
  final Paint _spark = Paint()
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  final Paint _dot = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _glow = Paint()
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint _big = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

  @override
  void paint(Canvas canvas, Size size) {
    final tick = (controller.value * 30).floorToDouble() / 30;
    _grid.color = color;
    final p = _grid;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }

    final sparkPaint = _spark..color = color.withValues(alpha: 0.18);

    final rng = Random(variant.index * 99);
    final sparkCount = switch (variant) {
      BackdropVariant.grabber => 3,
      BackdropVariant.forge => 2,
      BackdropVariant.pipeline => 4,
      BackdropVariant.workbench => 3,
      BackdropVariant.generic => 2,
    };

    for (int s = 0; s < sparkCount; s++) {
      final seed = rng.nextDouble();
      final vertical = variant == BackdropVariant.grabber || (variant == BackdropVariant.generic && s.isEven);
      final horizontal = variant == BackdropVariant.pipeline || variant == BackdropVariant.workbench;

      if (vertical || (!horizontal && rng.nextBool())) {
        final col = (seed * (size.width / step)).floor() * step;
        final progress = (tick + seed) % 1.0;
        final y = progress * size.height;
        final len = 18 + seed * 28;
        canvas.drawLine(Offset(col, y), Offset(col, (y + len).clamp(0, size.height)), sparkPaint);
        canvas.drawCircle(Offset(col, y), 1.8, _dot..color = Colors.white.withValues(alpha: 0.22));
      } else {
        final row = (seed * (size.height / step)).floor() * step;
        final progress = (tick + seed * 1.3) % 1.0;
        final x = progress * size.width;
        final len = 20 + seed * 30;
        canvas.drawLine(Offset(x, row), Offset((x + len).clamp(0, size.width), row), sparkPaint);
        canvas.drawCircle(Offset(x, row), 1.8, _dot..color = Colors.white.withValues(alpha: 0.22));
      }
    }

    _paintArcs(canvas, size, rng, step, tick);
    _paintTravelers(canvas, size, rng, step, tick);
  }

  void _paintArcs(Canvas canvas, Size size, Random rng, double step, double tick) {
    final arcCount = switch (variant) {
      BackdropVariant.grabber => 2,
      BackdropVariant.forge => 1,
      BackdropVariant.pipeline => 2,
      BackdropVariant.workbench => 2,
      BackdropVariant.generic => 1,
    };

    for (int a = 0; a < arcCount; a++) {
      final seed = rng.nextDouble();
      final cycle = ((tick * (0.5 + seed * 0.5)) + seed * 3.0) % 1.0;
      if (cycle > 0.45) continue;

      final fade = (1.0 - cycle / 0.45).clamp(0.0, 1.0);
      final vertical = variant == BackdropVariant.grabber || rng.nextBool();
      final lineIndex = (seed * (vertical ? size.height / step : size.width / step)).floor();
      final base = lineIndex * step;
      final travel = cycle * (vertical ? size.width : size.height);
      final reach = (40 + seed * 60);

      final path = Path();
      Offset prev;
      if (vertical) {
        prev = Offset(travel.clamp(0.0, size.width), base);
        path.moveTo(prev.dx, prev.dy);
        final dir = seed > 0.5 ? 1.0 : -1.0;
        for (double x = prev.dx; (x - travel).abs() < reach && x > 0 && x < size.width; x += dir * step) {
          final jitter = (rng.nextDouble() - 0.5) * 10;
          prev = Offset(x, (base + jitter).clamp(0.0, size.height));
          path.lineTo(prev.dx, prev.dy);
        }
      } else {
        prev = Offset(base, travel.clamp(0.0, size.height));
        path.moveTo(prev.dx, prev.dy);
        final dir = seed > 0.5 ? 1.0 : -1.0;
        for (double y = prev.dy; (y - travel).abs() < reach && y > 0 && y < size.height; y += dir * step) {
          final jitter = (rng.nextDouble() - 0.5) * 10;
          prev = Offset((base + jitter).clamp(0.0, size.width), y);
          path.lineTo(prev.dx, prev.dy);
        }
      }

      final arcPaint = _arc..color = color.withValues(alpha: 0.30 * fade);
      canvas.drawPath(path, arcPaint);

      canvas.drawCircle(prev, 2.2, _big..color = Colors.white.withValues(alpha: 0.45 * fade));
    }
  }

  void _paintTravelers(Canvas canvas, Size size, Random rng, double step, double tick) {
    final count = switch (variant) {
      BackdropVariant.grabber => 2,
      BackdropVariant.forge => 1,
      BackdropVariant.pipeline => 3,
      BackdropVariant.workbench => 2,
      BackdropVariant.generic => 2,
    };

    for (int t = 0; t < count; t++) {
      final seed = rng.nextDouble();
      final speed = 0.06 + seed * 0.08;
      final progress = ((tick * speed) + seed * 2.0) % 1.0;
      final vertical = variant == BackdropVariant.grabber || (variant != BackdropVariant.pipeline && seed > 0.5);
      const tail = 0.10;

      final linePos = ((seed * 7.31) % 1.0) * (vertical ? size.width : size.height);
      final glow = _glow;

      for (double k = 0; k <= 1.0; k += 0.125) {
        final p = (progress - k * tail) % 1.0;
        if (p < 0) continue;
        final fade = (1.0 - k) * 0.28;
        final head = vertical ? Offset(linePos, p * size.height) : Offset(p * size.width, linePos);
        glow.color = color.withValues(alpha: fade);
        canvas.drawCircle(head, 2.0 - k, glow);
      }

      final head = vertical ? Offset(linePos, progress * size.height) : Offset(progress * size.width, linePos);
      canvas.drawCircle(head, 1.6, _glow..color = Colors.white.withValues(alpha: 0.35));
    }
  }

  @override
  bool shouldRepaint(covariant _PulsingGridPainter oldDelegate) => oldDelegate.color != color || oldDelegate.variant != variant || oldDelegate.controller != controller;
}
