// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';

class CyberPageTransitionsBuilder extends PageTransitionsBuilder {
  const CyberPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outgoing = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    final accent = Theme.of(context).colorScheme.primary;
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 0.96).animate(outgoing),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(incoming),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(incoming),
            child: CustomPaint(
              foregroundPainter: _SweepPainter(animation, accent),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  _SweepPainter(this.animation, this.color) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0.0 || t >= 1.0 || animation.status == AnimationStatus.reverse) return;
    final y = Curves.easeInOutCubic.transform(t) * size.height;
    final fade = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    final band = Rect.fromLTWH(0, y - 36, size.width, 36);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.22 * fade)],
        ).createShader(band),
    );
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
      ..color = color.withValues(alpha: 0.9 * fade)
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) => oldDelegate.animation != animation || oldDelegate.color != color;
}
