// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show HitTestTarget, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../core/feedback_settings.dart';
import '../core/sfx.dart';
import '../core/tap_feedback.dart';

class TapFxTint extends SingleChildRenderObjectWidget {
  final Color color;

  const TapFxTint({super.key, required this.color, super.child});

  @override
  RenderTapFxTint createRenderObject(BuildContext context) => RenderTapFxTint(color);

  @override
  void updateRenderObject(BuildContext context, RenderTapFxTint renderObject) {
    renderObject.color = color;
  }
}

class RenderTapFxTint extends RenderProxyBox {
  Color color;

  RenderTapFxTint(this.color);
}

class TapFxLayer extends StatefulWidget {
  final Widget child;
  final ValueListenable<Color> accent;

  const TapFxLayer({super.key, required this.child, required this.accent});

  @override
  State<TapFxLayer> createState() => _TapFxLayerState();
}

class _TapFxLayerState extends State<TapFxLayer> with SingleTickerProviderStateMixin {
  final _TapFxModel _model = _TapFxModel();
  final Map<int, _PendingTap> _pending = {};
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _model.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _model.advance(dt.clamp(0.0, 0.05));
    if (_model.isIdle) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  void _wake() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  bool get _motionAllowed => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  _HitInfo? _findClickable(Offset globalPosition, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, globalPosition, viewId);
    final entries = result.path.toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      final target = entries[i].target;
      if (!_isTappable(target)) continue;
      final box = target as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final self = context.findRenderObject();
      if (self is! RenderBox || !self.attached) return null;
      final rect = MatrixUtils.transformRect(box.getTransformTo(self), Offset.zero & box.size);
      Color? tint;
      for (var j = i + 1; j < entries.length; j++) {
        final outer = entries[j].target;
        if (outer is RenderTapFxTint) {
          tint = outer.color;
          break;
        }
      }
      final screen = self.size;
      final large = rect.width * rect.height > screen.width * screen.height * 0.35;
      return _HitInfo(rect, tint, large);
    }
    return null;
  }

  bool _isTappable(HitTestTarget target) {
    if (target is SemanticsAnnotationsMixin) return target.properties.onTap != null;
    if (target is RenderSemanticsGestureHandler) return target.onTap != null;
    if (target is RenderMouseRegion) return target.cursor == SystemMouseCursors.click;
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    final hit = _findClickable(event.position, event.viewId);
    if (hit == null) return;
    final color = hit.tint ?? widget.accent.value;
    _pending[event.pointer] = _PendingTap(event.localPosition, event.timeStamp, hit.rect, color);
    if (_motionAllowed && FeedbackSettings.pulse.value && !hit.large) {
      _model.addPulse(hit.rect, color);
      _wake();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pending = _pending[event.pointer];
    if (pending == null) return;
    if ((event.localPosition - pending.origin).distance > kTouchSlop) {
      _pending.remove(event.pointer);
      _model.releasePulses();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final pending = _pending.remove(event.pointer);
    if (pending == null) return;
    _model.releasePulses();
    if (event.timeStamp - pending.downTime > const Duration(milliseconds: 700)) return;
    TapFeedback.play(SfxId.tap, haptic: HapticFeedback.selectionClick);
    if (!_motionAllowed) return;
    final at = pending.origin;
    final maxRadius = math.min(180.0, math.max(56.0, pending.rect.longestSide * 0.6));
    if (FeedbackSettings.ring.value) _model.addRing(at, maxRadius, pending.color);
    if (FeedbackSettings.burst.value) _model.addBurst(at, pending.color);
    _wake();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pending.remove(event.pointer) != null) _model.releasePulses();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _TapFxPainter(_model)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitInfo {
  final Rect rect;
  final Color? tint;
  final bool large;

  const _HitInfo(this.rect, this.tint, this.large);
}

class _PendingTap {
  final Offset origin;
  final Duration downTime;
  final Rect rect;
  final Color color;

  const _PendingTap(this.origin, this.downTime, this.rect, this.color);
}

class _Pulse {
  final Rect rect;
  final Color color;
  double age = 0;
  bool held = true;

  _Pulse(this.rect, this.color);
}

class _Ring {
  final Offset center;
  final double maxRadius;
  final Color color;
  double age = 0;

  _Ring(this.center, this.maxRadius, this.color);
}

class _Flash {
  final Offset center;
  final Color color;
  double age = 0;

  _Flash(this.center, this.color);
}

class _Spark {
  Offset position;
  Offset velocity;
  final double life;
  final double length;
  final bool pixel;
  final Color color;
  double age = 0;

  _Spark(this.position, this.velocity, this.life, this.length, this.pixel, this.color);
}

class _TapFxModel extends ChangeNotifier {
  static const double pulseIn = 0.12;
  static const double pulseOut = 0.38;
  static const double ringLife = 0.45;
  static const double flashLife = 0.16;

  final List<_Pulse> pulses = [];
  final List<_Ring> rings = [];
  final List<_Flash> flashes = [];
  final List<_Spark> sparks = [];
  final math.Random _rng = math.Random();

  bool get isIdle => pulses.isEmpty && rings.isEmpty && flashes.isEmpty && sparks.isEmpty;

  void addPulse(Rect rect, Color color) {
    pulses.add(_Pulse(rect, color));
    notifyListeners();
  }

  void releasePulses() {
    for (final p in pulses) {
      if (p.held) {
        p.held = false;
        p.age = math.max(p.age, pulseIn);
      }
    }
  }

  void addRing(Offset center, double maxRadius, Color color) {
    rings.add(_Ring(center, maxRadius, color));
    notifyListeners();
  }

  void addBurst(Offset center, Color color) {
    flashes.add(_Flash(center, color));
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = i / count * math.pi * 2 + (_rng.nextDouble() - 0.5) * 0.45;
      final speed = 330 + _rng.nextDouble() * 320;
      final pixel = i % 3 == 0;
      sparks.add(_Spark(
        center,
        Offset(math.cos(angle), math.sin(angle)) * speed,
        0.32 + _rng.nextDouble() * 0.22,
        pixel ? 3.2 : 9 + _rng.nextDouble() * 8,
        pixel,
        color,
      ));
    }
    notifyListeners();
  }

  void advance(double dt) {
    for (final p in pulses) {
      p.age = p.held ? math.min(p.age + dt, pulseIn) : p.age + dt;
    }
    pulses.removeWhere((p) => !p.held && p.age >= pulseIn + pulseOut);
    if (pulses.length > 4) pulses.removeRange(0, pulses.length - 4);
    for (final r in rings) {
      r.age += dt;
    }
    rings.removeWhere((r) => r.age >= ringLife);
    for (final f in flashes) {
      f.age += dt;
    }
    flashes.removeWhere((f) => f.age >= flashLife);
    final drag = math.pow(0.015, dt).toDouble();
    for (final s in sparks) {
      s.age += dt;
      s.velocity = Offset(s.velocity.dx * drag, s.velocity.dy * drag + 240 * dt);
      s.position += s.velocity * dt;
    }
    sparks.removeWhere((s) => s.age >= s.life);
    notifyListeners();
  }
}

class _TapFxPainter extends CustomPainter {
  final _TapFxModel model;

  _TapFxPainter(this.model) : super(repaint: model);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in model.pulses) {
      _paintPulse(canvas, p);
    }
    for (final r in model.rings) {
      _paintRing(canvas, r);
    }
    for (final f in model.flashes) {
      _paintFlash(canvas, f);
    }
    for (final s in model.sparks) {
      _paintSpark(canvas, s);
    }
  }

  void _paintPulse(Canvas canvas, _Pulse p) {
    final grow = Curves.easeOutCubic.transform((p.age / _TapFxModel.pulseIn).clamp(0.0, 1.0));
    final fade = p.held ? 1.0 : 1 - ((p.age - _TapFxModel.pulseIn) / _TapFxModel.pulseOut).clamp(0.0, 1.0);
    final expand = p.held ? 2.0 * grow : 2.0 + 10.0 * Curves.easeOutCubic.transform(1 - fade);
    final radius = math.min(14.0, p.rect.shortestSide / 2) + expand;
    final rrect = RRect.fromRectAndRadius(p.rect.inflate(expand), Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = p.color.withValues(alpha: 0.16 * fade * grow));
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = p.color.withValues(alpha: 0.9 * fade * grow));
  }

  void _paintRing(Canvas canvas, _Ring r) {
    final t = (r.age / _TapFxModel.ringLife).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(t);
    final alpha = math.pow(1 - t, 1.5).toDouble();
    canvas.drawCircle(r.center, r.maxRadius * e, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 + 3.0 * (1 - t)
      ..color = r.color.withValues(alpha: 0.85 * alpha));
    canvas.drawCircle(r.center, r.maxRadius * e * 0.62, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.35 * alpha));
  }

  void _paintFlash(Canvas canvas, _Flash f) {
    final t = (f.age / _TapFxModel.flashLife).clamp(0.0, 1.0);
    final radius = 18 + 22 * t;
    final rect = Rect.fromCircle(center: f.center, radius: radius);
    canvas.drawCircle(f.center, radius, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: 0.85 * (1 - t)),
        f.color.withValues(alpha: 0.45 * (1 - t)),
        f.color.withValues(alpha: 0),
      ], stops: const [0, 0.35, 1]).createShader(rect));
  }

  void _paintSpark(Canvas canvas, _Spark s) {
    final life = 1 - (s.age / s.life).clamp(0.0, 1.0);
    final color = Color.lerp(Colors.white, s.color, 1 - life)!.withValues(alpha: life);
    if (s.pixel) {
      canvas.drawRect(Rect.fromCenter(center: s.position, width: s.length, height: s.length), Paint()..color = color);
      return;
    }
    final speed = s.velocity.distance;
    if (speed < 1) return;
    final tail = s.position - s.velocity / speed * s.length * life;
    canvas.drawLine(tail, s.position, Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _TapFxPainter oldDelegate) => oldDelegate.model != model;
}
