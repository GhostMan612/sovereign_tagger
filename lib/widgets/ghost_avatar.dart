// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/ghost_settings.dart';
import '../core/sfx.dart';

enum GhostEmotion { serious, happy, sarcastic }

enum GhostMood { idle, listening, thinking, talking }

class GhostAvatar extends StatefulWidget {
  final double size;
  final ValueNotifier<Color> accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GhostAvatar({
    super.key,
    this.size = 64,
    required this.accentColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<GhostAvatar> createState() => GhostAvatarState();
}

class GhostAvatarState extends State<GhostAvatar> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _GhostMotion _motion = _GhostMotion();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _foreground = true;
  int _frame = 0;
  TextPainter? _laughText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    GhostSettings.reduceMotion.addListener(_onSettingsChanged);
    _motion.reduceMotion = GhostSettings.reduceMotion.value;
    _ticker = createTicker(_onTick);
    _motion.presenceTarget = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _motion.materialize();
      _wake();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    GhostSettings.reduceMotion.removeListener(_onSettingsChanged);
    _ticker.dispose();
    _motion.dispose();
    _laughText?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _wake();
    } else if (_ticker.isActive) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _onSettingsChanged() {
    _motion.reduceMotion = GhostSettings.reduceMotion.value;
    _wake();
  }

  void _onGlobalPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(event.position) - box.size.center(Offset.zero);
    final distance = local.distance;
    if (distance < 1) return;
    _motion.glance(local / distance);
    _wake();
  }

  void _wake() {
    if (!_foreground || _ticker.isActive) return;
    _last = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final busy = _motion.advance(dt.clamp(0.0, 0.05));
    _frame++;
    if (busy || _frame.isEven) _motion.notify();
    if (_motion.dormant) {
      _ticker.stop();
      _last = Duration.zero;
      _motion.notify();
    }
  }

  Future<void> _materialize({bool silent = false}) async {
    if (!silent) Sfx.play(SfxId.open);
    _motion.materialize();
    _wake();
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  Future<void> _dematerialize() async {
    Sfx.play(SfxId.close);
    _motion.dematerialize();
    _wake();
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  Future<void> _glitchLaugh() async {
    Sfx.play(SfxId.glitch);
    _laughText ??= TextPainter(
      text: const TextSpan(
        text: 'hahaha',
        style: TextStyle(
          fontFamily: 'VT323',
          fontSize: 18,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
            Shadow(color: Colors.redAccent, blurRadius: 8),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _motion.laugh();
    _wake();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  }

  void _setEmotion(GhostEmotion emotion) {
    _motion.setEmotion(emotion);
    _wake();
  }

  void _setMood(GhostMood mood) {
    _motion.mood = mood;
    _wake();
  }

  void _talk() {
    _motion.talk();
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: widget.accentColor,
      builder: (context, accent, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _GhostPainter(motion: _motion, accent: accent, laughText: _laughText),
            ),
          ),
        );
      },
    );
  }
}

class GhostAvatarController {
  final GlobalKey<GhostAvatarState> _key;

  GhostAvatarController(this._key);

  GhostAvatarState? get _state => _key.currentState;

  Future<void> materialize() => _state?._materialize() ?? Future.value();
  Future<void> dematerialize() => _state?._dematerialize() ?? Future.value();
  Future<void> glitchLaugh() => _state?._glitchLaugh() ?? Future.value();
  void setEmotion(GhostEmotion emotion) => _state?._setEmotion(emotion);
  void setMood(GhostMood mood) => _state?._setMood(mood);
  void talk() => _state?._talk();
}

class _Wisp {
  Offset position;
  Offset velocity;
  final double life;
  final double size;
  final Color color;
  double age = 0;

  _Wisp(this.position, this.velocity, this.life, this.size, this.color);
}

class _GhostMotion extends ChangeNotifier {
  final math.Random _rng = math.Random();

  bool reduceMotion = false;
  GhostMood mood = GhostMood.idle;
  GhostEmotion emotion = GhostEmotion.serious;

  double time = 0;
  double presence = 0;
  double presenceTarget = 1;
  double _presenceFrom = 0;
  double _presenceAge = 10;
  double _presenceDuration = 0.6;

  double laughAge = 10;
  double emotionAge = 10;
  double blink = 0;
  double _nextBlink = 2.5;
  double _blinkAge = 10;
  double mouth = 0;
  double _mouthTarget = 0;
  double listen = 0;
  double think = 0;
  Offset eye = Offset.zero;
  Offset _eyeTarget = Offset.zero;
  double _eyeHold = 0;
  double _nextWander = 3;
  double _nextWisp = 1.5;
  final List<_Wisp> wisps = [];

  bool get laughing => laughAge < 1.4;
  double get emotionGlow => (1 - emotionAge / 1.4).clamp(0.0, 1.0);

  double get glitch {
    final materializing = _presenceAge < _presenceDuration ? (1 - _presenceAge / _presenceDuration) * 0.6 : 0.0;
    var laughGlitch = 0.0;
    if (laughing) {
      if (laughAge < 0.3) {
        laughGlitch = laughAge / 0.3 * 0.8;
      } else if (laughAge < 0.9) {
        laughGlitch = 0.8;
      } else {
        laughGlitch = 0.8 * (1 - (laughAge - 0.9) / 0.5);
      }
    }
    return reduceMotion ? 0 : math.max(materializing, laughGlitch).clamp(0.0, 1.0);
  }

  double get wobble {
    if (!laughing || reduceMotion) return 0;
    final envelope = laughAge < 0.3 ? laughAge / 0.3 : (1 - (laughAge - 0.3) / 1.1).clamp(0.0, 1.0);
    return math.sin(laughAge * 38) * 0.16 * envelope;
  }

  double get floatOffset => reduceMotion ? 0 : math.sin(time * 1.7) * 3.0 + (laughing ? math.sin(laughAge * 20) * 2 : 0);
  double get breathe => reduceMotion ? 1 : 1 + 0.025 * math.sin(time * 2.3);
  double get tailPhase => reduceMotion ? 0 : time * 4.2;

  bool get dormant => presence <= 0.001 && presenceTarget == 0 && wisps.isEmpty;

  void notify() => notifyListeners();

  void materialize() {
    _presenceFrom = presence;
    presenceTarget = 1;
    _presenceAge = 0;
    _presenceDuration = 0.6;
    _burst(8, GhostEmotion.serious);
  }

  void dematerialize() {
    _presenceFrom = presence;
    presenceTarget = 0;
    _presenceAge = 0;
    _presenceDuration = 0.4;
  }

  void laugh() {
    laughAge = 0;
    _burst(18, GhostEmotion.sarcastic);
  }

  void setEmotion(GhostEmotion value) {
    emotion = value;
    emotionAge = 0;
    _burst(6, value);
  }

  void talk() {
    _mouthTarget = 0.45 + _rng.nextDouble() * 0.55;
  }

  void glance(Offset direction) {
    _eyeTarget = direction;
    _eyeHold = 1.6;
  }

  bool advance(double dt) {
    time += dt;
    var busy = false;

    if (_presenceAge < _presenceDuration) {
      _presenceAge += dt;
      final t = (_presenceAge / _presenceDuration).clamp(0.0, 1.0);
      final curve = presenceTarget > _presenceFrom ? Curves.easeOutBack : Curves.easeInBack;
      presence = _presenceFrom + (presenceTarget - _presenceFrom) * curve.transform(t);
      busy = true;
    } else {
      presence = presenceTarget;
    }

    if (laughing) {
      laughAge += dt;
      busy = true;
    }
    if (emotionAge < 1.4) {
      emotionAge += dt;
      busy = true;
    }

    _blinkAge += dt;
    _nextBlink -= dt;
    if (_nextBlink <= 0) {
      _blinkAge = 0;
      _nextBlink = 2.2 + _rng.nextDouble() * 3.5;
      if (_rng.nextDouble() < 0.18) _nextBlink = 0.22;
    }
    blink = _blinkAge < 0.14 ? math.sin(_blinkAge / 0.14 * math.pi) : 0;

    _eyeHold -= dt;
    _nextWander -= dt;
    if (_eyeHold <= 0) {
      if (mood == GhostMood.listening) {
        _eyeTarget = const Offset(-0.55, -0.7);
      } else if (mood == GhostMood.thinking) {
        _eyeTarget = const Offset(0.5, -0.85);
      } else if (_nextWander <= 0) {
        _nextWander = 2.5 + _rng.nextDouble() * 4;
        _eyeTarget = _rng.nextDouble() < 0.4 ? Offset.zero : Offset(_rng.nextDouble() * 2 - 1, _rng.nextDouble() * 1.4 - 0.7);
      }
    }
    eye = Offset.lerp(eye, _eyeTarget, 1 - math.pow(0.0015, dt).toDouble())!;

    final talking = mood == GhostMood.talking;
    _mouthTarget = talking ? _mouthTarget * math.pow(0.02, dt).toDouble() : 0;
    mouth += (_mouthTarget - mouth) * (1 - math.pow(0.0001, dt).toDouble());
    listen += ((mood == GhostMood.listening ? 1.0 : 0.0) - listen) * (1 - math.pow(0.01, dt).toDouble());
    think += ((mood == GhostMood.thinking ? 1.0 : 0.0) - think) * (1 - math.pow(0.01, dt).toDouble());
    if (talking || think > 0.02) busy = true;

    _nextWisp -= dt;
    if (!reduceMotion && presence > 0.9 && _nextWisp <= 0) {
      _nextWisp = 1.2 + _rng.nextDouble() * 2.2;
      _spawnWisp(null);
    }
    for (final w in wisps) {
      w.age += dt;
      w.position += w.velocity * dt;
      w.velocity = Offset(w.velocity.dx * math.pow(0.4, dt).toDouble(), w.velocity.dy - 10 * dt);
    }
    wisps.removeWhere((w) => w.age >= w.life);
    if (wisps.isNotEmpty) busy = busy || wisps.length > 3;
    return busy;
  }

  void _burst(int count, GhostEmotion flavor) {
    if (reduceMotion) return;
    for (var i = 0; i < count; i++) {
      _spawnWisp(flavor, angle: i / count * math.pi * 2, fast: true);
    }
  }

  void _spawnWisp(GhostEmotion? flavor, {double? angle, bool fast = false}) {
    if (wisps.length > 30) return;
    final a = angle ?? (-math.pi / 2 + (_rng.nextDouble() - 0.5) * 1.2);
    final speed = fast ? 40 + _rng.nextDouble() * 45 : 10 + _rng.nextDouble() * 12;
    final origin = fast ? const Offset(50, 55) : Offset(28 + _rng.nextDouble() * 44, 82);
    Color color;
    switch (flavor) {
      case GhostEmotion.sarcastic:
        color = Colors.redAccent;
        break;
      case GhostEmotion.happy:
        color = Colors.cyanAccent;
        break;
      case GhostEmotion.serious:
        color = Colors.greenAccent;
        break;
      case null:
        color = Colors.white;
        break;
    }
    wisps.add(_Wisp(origin, Offset(math.cos(a), math.sin(a)) * speed, fast ? 0.7 + _rng.nextDouble() * 0.4 : 1.6 + _rng.nextDouble(), fast ? 2.2 + _rng.nextDouble() * 1.8 : 1.4 + _rng.nextDouble(), color));
  }
}

class _GhostPainter extends CustomPainter {
  final _GhostMotion motion;
  final Color accent;
  final TextPainter? laughText;

  _GhostPainter({required this.motion, required this.accent, required this.laughText}) : super(repaint: motion);

  Path _body(double phase) {
    final path = Path()..moveTo(20, 80);
    path.lineTo(20, 42);
    path.cubicTo(20, 18, 33, 8, 50, 8);
    path.cubicTo(67, 8, 80, 18, 80, 42);
    path.lineTo(80, 80);
    const scallops = 4;
    for (var i = 0; i < scallops; i++) {
      final x0 = 80 - i * 15.0;
      final lift = math.sin(phase + i * 1.3) * 2.6;
      final dip = math.sin(phase + i * 1.3 + 0.8) * 2.2;
      path.quadraticBezierTo(x0 - 7.5, 92 + lift, x0 - 15, 83 + dip);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = motion;
    final presence = m.presence.clamp(0.0, 1.2);
    if (presence <= 0.001 && m.wisps.isEmpty) return;
    final unit = size.shortestSide / 100.0;
    final ghostWhite = Color.lerp(const Color(0xFFF4F7FA), accent, 0.12)!;
    final emotionColor = switch (m.emotion) {
      GhostEmotion.happy => Colors.cyanAccent,
      GhostEmotion.sarcastic => Colors.redAccent,
      GhostEmotion.serious => accent,
    };
    final glowColor = Color.lerp(accent, emotionColor, m.emotionGlow)!;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);

    final shadowScale = 1 - m.floatOffset / 20;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 47), width: 46 * shadowScale * presence, height: 7 * shadowScale * presence),
      Paint()
        ..color = glowColor.withValues(alpha: 0.22 * presence)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.save();
    canvas.translate(0, m.floatOffset);
    canvas.rotate(m.wobble);
    final scale = presence * m.breathe * (1 + 0.12 * m.listen);
    canvas.scale(scale, scale * (1 + 0.03 * m.listen));
    canvas.translate(-50, -50);

    final body = _body(m.tailPhase);
    final glitch = m.glitch;

    canvas.drawPath(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = glowColor.withValues(alpha: 0.35 + 0.25 * m.emotionGlow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));

    if (glitch > 0.02) {
      final shift = glitch * 5;
      canvas.drawPath(body.shift(Offset(-shift, 0)), Paint()..color = Colors.redAccent.withValues(alpha: 0.45 * glitch));
      canvas.drawPath(body.shift(Offset(shift, 0)), Paint()..color = Colors.cyanAccent.withValues(alpha: 0.45 * glitch));
    }

    canvas.drawPath(body, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [ghostWhite, ghostWhite.withValues(alpha: 0.92), glowColor.withValues(alpha: 0.55)],
        stops: const [0, 0.6, 1],
      ).createShader(const Rect.fromLTWH(20, 8, 60, 86)));

    canvas.save();
    canvas.clipPath(body);
    final scanShift = (m.time * 14) % 5;
    final scan = Paint()
      ..color = glowColor.withValues(alpha: 0.10)
      ..strokeWidth = 0.8;
    for (var y = 6.0 + scanShift; y < 96; y += 5) {
      canvas.drawLine(Offset(18, y), Offset(82, y), scan);
    }
    if (glitch > 0.1) {
      final band = (m.time * 97) % 70 + 10;
      canvas.drawRect(Rect.fromLTWH(18, band, 64, 4 + glitch * 6), Paint()..color = glowColor.withValues(alpha: 0.35 * glitch));
    }
    canvas.restore();

    _paintFace(canvas, glowColor);
    canvas.restore();

    if (m.think > 0.02) _paintThinking(canvas, glowColor);

    for (final w in m.wisps) {
      final life = 1 - (w.age / w.life).clamp(0.0, 1.0);
      final p = w.position - const Offset(50, 50);
      canvas.drawCircle(p, w.size * (0.6 + 0.4 * life), Paint()..color = w.color.withValues(alpha: 0.75 * life));
    }

    if (m.laughing && laughText != null && m.laughAge > 0.35) {
      final fade = m.laughAge > 1.1 ? (1 - (m.laughAge - 1.1) / 0.3).clamp(0.0, 1.0) : 1.0;
      canvas.save();
      canvas.scale(1 / unit);
      final t = laughText!;
      final lift = 26 * unit + (m.laughAge - 0.35) * 18;
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: fade));
      t.paint(canvas, Offset(-t.width / 2, -size.height / 2 - lift));
      canvas.restore();
      canvas.restore();
    }

    canvas.restore();
  }

  void _paintFace(Canvas canvas, Color glowColor) {
    final m = motion;
    final eyeOpen = (1 - m.blink).clamp(0.08, 1.0);
    final eyeScale = 1 + 0.18 * m.listen;
    final look = Offset(m.eye.dx.clamp(-1.0, 1.0) * 3.2, m.eye.dy.clamp(-1.0, 1.0) * 2.4);
    const eyeColor = Color(0xFF07090C);
    for (final cx in const [39.0, 61.0]) {
      final center = Offset(cx, 44) + look;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: 9 * eyeScale, height: 12 * eyeScale * eyeOpen),
        Paint()..color = eyeColor,
      );
      if (eyeOpen > 0.4) {
        canvas.drawCircle(center + const Offset(-1.8, -2.6), 1.6 * eyeScale, Paint()..color = Colors.white.withValues(alpha: 0.95));
        canvas.drawCircle(center + const Offset(1.6, 2.2), 0.8 * eyeScale, Paint()..color = glowColor.withValues(alpha: 0.9));
      }
    }

    if (m.emotion == GhostEmotion.happy || m.laughing) {
      final blush = Paint()..color = Colors.pinkAccent.withValues(alpha: 0.25 + 0.2 * m.emotionGlow);
      canvas.drawOval(Rect.fromCenter(center: const Offset(31, 55) + look * 0.4, width: 8, height: 4), blush);
      canvas.drawOval(Rect.fromCenter(center: const Offset(69, 55) + look * 0.4, width: 8, height: 4), blush);
    }

    final mouthCenter = const Offset(50, 60) + look * 0.5;
    if (m.mouth > 0.04 || m.laughing) {
      final open = m.laughing ? 0.6 + 0.4 * math.sin(m.laughAge * 30).abs() : m.mouth;
      canvas.drawOval(Rect.fromCenter(center: mouthCenter, width: 7 + 2 * open, height: 1.5 + 6.5 * open), Paint()..color = eyeColor);
      return;
    }
    final stroke = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path();
    switch (m.emotion) {
      case GhostEmotion.happy:
        path.moveTo(mouthCenter.dx - 4.5, mouthCenter.dy - 1);
        path.quadraticBezierTo(mouthCenter.dx, mouthCenter.dy + 4, mouthCenter.dx + 4.5, mouthCenter.dy - 1);
        break;
      case GhostEmotion.sarcastic:
        path.moveTo(mouthCenter.dx - 4.5, mouthCenter.dy + 0.5);
        path.quadraticBezierTo(mouthCenter.dx + 1, mouthCenter.dy + 2, mouthCenter.dx + 5, mouthCenter.dy - 2);
        break;
      case GhostEmotion.serious:
        path.moveTo(mouthCenter.dx - 3.5, mouthCenter.dy);
        path.quadraticBezierTo(mouthCenter.dx, mouthCenter.dy + 1.6, mouthCenter.dx + 3.5, mouthCenter.dy);
        break;
    }
    canvas.drawPath(path, stroke);
  }

  void _paintThinking(Canvas canvas, Color glowColor) {
    final m = motion;
    for (var i = 0; i < 3; i++) {
      final angle = m.time * 3.2 + i * math.pi * 2 / 3;
      final p = Offset(math.cos(angle) * 20, -46 + math.sin(angle) * 6 + m.floatOffset);
      final depth = (math.sin(angle) + 1) / 2;
      canvas.drawCircle(p, 2 + depth * 1.6, Paint()..color = glowColor.withValues(alpha: (0.45 + 0.5 * depth) * m.think));
    }
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) => oldDelegate.accent != accent || oldDelegate.laughText != laughText;
}
