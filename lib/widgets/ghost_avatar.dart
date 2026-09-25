// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import '../core/ghost_settings.dart';

enum GhostEmotion { sarcastic, happy, serious }

enum GhostState { idle, materializing, active, laughing, dematerializing }

class GhostParticle {
  final GhostEmotion emotion;
  Offset position;
  Offset velocity;
  Color color;
  double life;
  double size;
  int charIndex;
  bool active;

  GhostParticle({
    required this.emotion,
    required this.position,
    required this.velocity,
    required this.color,
    this.life = 1.0,
    this.size = 4.0,
    this.charIndex = 0,
    this.active = true,
  });

  void update(double dt) {
    if (!active) return;
    position += velocity * dt;
    velocity *= 0.92;
    life -= dt * 2.5;
    if (life <= 0) active = false;
  }

  void render(Canvas canvas, double progress) {
    if (!active) return;
    final alpha = (life.clamp(0.0, 1.0) * 255).toInt();
    final paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;

    final currentSize = size * life.clamp(0.0, 1.0);

    switch (emotion) {
      case GhostEmotion.sarcastic:
        // Glitch squares
        canvas.drawRect(
          Rect.fromCenter(
              center: position, width: currentSize, height: currentSize),
          paint,
        );
        // Glitch offset square
        if (Random().nextDouble() < 0.3) {
          canvas.drawRect(
            Rect.fromCenter(
              center: position +
                  Offset((Random().nextDouble() - 0.5) * 4,
                      (Random().nextDouble() - 0.5) * 4),
              width: currentSize * 0.8,
              height: currentSize * 0.8,
            ),
            paint..color = color.withAlpha((alpha * 0.5).toInt()),
          );
        }
        break;
      case GhostEmotion.happy:
        // Circles with glow
        canvas.drawCircle(position, currentSize, paint);
        // Inner glow
        canvas.drawCircle(
          position,
          currentSize * 0.5,
          paint..color = color.withAlpha((alpha * 0.3).toInt()),
        );
        break;
      case GhostEmotion.serious:
        // Machine characters
        final textPainter = TextPainter(
          text: TextSpan(
            text: _machineChars[charIndex % _machineChars.length],
            style: TextStyle(
              fontFamily: 'VT323',
              fontSize: currentSize * 3,
              color: color.withAlpha(alpha),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          position - Offset(textPainter.width / 2, textPainter.height / 2),
        );
        break;
    }
  }

  static const List<String> _machineChars = [
    '0',
    '1',
    'â–ˆ',
    'â–“',
    'â–’',
    'â–‘',
    'â– ',
    'â–¡',
    'â—†',
    'â—‡',
    'â—‰',
    'â—‹',
    'â—',
    'â—†',
    'â–²',
    'â–¼',
  ];
}

class _GhostAvatarPainter extends CustomPainter {
  final Path ghostPath;
  final double glitchIntensity;
  final double wobble;
  final double laughIntensity;
  final Color accentColor;
  final Color ghostColor;
  final List<GhostParticle> particles;
  final double time;
  final bool reduceMotion;
  final bool isLaughing;

  _GhostAvatarPainter({
    required this.ghostPath,
    required this.glitchIntensity,
    required this.wobble,
    required this.laughIntensity,
    required this.accentColor,
    required this.ghostColor,
    required this.particles,
    required this.time,
    required this.reduceMotion,
    required this.isLaughing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (reduceMotion) {
      // Simple render without glitch
      _drawGhost(canvas, size, Offset.zero, 1.0);
      _drawParticles(canvas);
      return;
    }

    // Glitch: RGB shift
    if (glitchIntensity > 0) {
      final shiftX = sin(time * 50) * glitchIntensity * 3;
      final redPaint = Paint()
        ..color = Colors.red.withAlpha((glitchIntensity * 180).toInt())
        ..style = PaintingStyle.fill;
      final cyanPaint = Paint()
        ..color = Colors.cyan.withAlpha((glitchIntensity * 180).toInt())
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(shiftX, 0);
      _drawGhost(canvas, size, Offset.zero, 1.0, redPaint);
      canvas.restore();

      canvas.save();
      canvas.translate(-shiftX, 0);
      _drawGhost(canvas, size, Offset.zero, 1.0, cyanPaint);
      canvas.restore();
    }

    // Main ghost with wobble
    _drawGhost(canvas, size, Offset(0, sin(time * 30) * wobble * 2), 1.0);

    // Glitch scanlines
    if (glitchIntensity > 0 && Random().nextDouble() < 0.15) {
      final scanlinePaint = Paint()
        ..color = Colors.white.withAlpha((glitchIntensity * 100).toInt())
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      for (int y = 0; y < size.height; y += 4) {
        if (Random().nextDouble() < glitchIntensity * 0.3) {
          canvas.drawLine(
            Offset(0, y.toDouble()),
            Offset(size.width, y.toDouble()),
            scanlinePaint,
          );
        }
      }
    }

    // Particles
    _drawParticles(canvas);

    // Laugh text bubble
    if (isLaughing && laughIntensity > 0) {
      _drawLaughBubble(canvas, size);
    }
  }

  void _drawGhost(Canvas canvas, Size size, Offset offset, double scale,
      [Paint? customPaint]) {
    final ghostPaint = customPaint ?? Paint()
      ..color = ghostColor
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = accentColor.withAlpha(60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final s = size.shortestSide / 100.0;
    canvas.save();
    canvas.translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    canvas.scale(s * scale, s * scale);
    canvas.translate(-50.0, -49.0);

    canvas.drawPath(ghostPath, glowPaint);
    canvas.drawPath(ghostPath, ghostPaint);

    if (customPaint == null) {
      final facePaint = Paint()
        ..color = const Color(0xFF14141C)
        ..style = PaintingStyle.fill;
      canvas.drawOval(Rect.fromCenter(center: const Offset(38, 45), width: 11, height: 17), facePaint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(62, 45), width: 11, height: 17), facePaint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(50, 64), width: 10, height: 8), facePaint);
    }

    canvas.restore();
  }

  void _drawParticles(Canvas canvas) {
    for (final particle in particles) {
      particle.render(canvas, 0);
    }
  }

  void _drawLaughBubble(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bubbleCenter = center + Offset(0, -size.height * 0.6);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'hahaha',
        style: TextStyle(
          fontFamily: 'VT323',
          fontSize: 18,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
            Shadow(color: Colors.red, blurRadius: 8, offset: Offset(0, 0)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final bubbleRect = Rect.fromCenter(
      center: bubbleCenter,
      width: textPainter.width + 24,
      height: textPainter.height + 16,
    );

    // Bubble background
    final bubblePaint = Paint()
      ..color = Colors.black.withAlpha(200)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(12)),
      bubblePaint,
    );

    // Bubble border
    final borderPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubbleRect, const Radius.circular(12)),
      borderPaint,
    );

    // Text
    textPainter.paint(
      canvas,
      bubbleCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GhostAvatar extends StatefulWidget {
  final double size;
  final ValueNotifier<Color> accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GhostAvatar({
    super.key,
    this.size = 80,
    required this.accentColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<GhostAvatar> createState() => GhostAvatarState();
}

class GhostAvatarState extends State<GhostAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Path _ghostPath;
  late final List<GhostParticle> _particles;

  // Expose these methods for the controller
  Future<void> materialize() => _materialize();
  Future<void> dematerialize() => _dematerialize();
  Future<void> glitchLaugh() => _glitchLaugh();
  void setEmotion(GhostEmotion emotion) => _setEmotion(emotion);

  // Private fields
  GhostState _state = GhostState.idle;
  double _glitchIntensity = 0.0;
  double _wobble = 0.0;
  double _laughIntensity = 0.0;
  double _scale = 0.0;
  double _opacity = 0.0;
  bool _isLaughing = false;
  Timer? _stateTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 16))
      ..addListener(_tick);

    _ghostPath = _createGhostPath();
    _particles = List.generate(
        24,
        (i) => GhostParticle(
              emotion: GhostEmotion.serious,
              position: Offset.zero,
              velocity: Offset.zero,
              color: Colors.white,
            ));

    // Start animation loop
    _controller.repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _state == GhostState.idle) {
        _materialize(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _stateTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
  }

  Path _createGhostPath() {
    final path = Path();
    path.moveTo(20, 80);
    path.lineTo(20, 42);
    path.cubicTo(20, 18, 33, 8, 50, 8);
    path.cubicTo(67, 8, 80, 18, 80, 42);
    path.lineTo(80, 80);
    path.quadraticBezierTo(72.5, 92, 65, 83);
    path.quadraticBezierTo(57.5, 92, 50, 83);
    path.quadraticBezierTo(42.5, 92, 35, 83);
    path.quadraticBezierTo(27.5, 92, 20, 80);
    path.close();
    return path;
  }

  void _emitParticles(GhostEmotion emotion, {int count = 12, Offset? origin}) {
    final emitOrigin = origin ?? Offset(widget.size / 2, widget.size * 0.75);

    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + (Random().nextDouble() - 0.5) * 0.5;
      final speed = 60.0 + Random().nextDouble() * 100.0;

      // Weighted emotion selection
      GhostEmotion particleEmotion;
      final rand = Random().nextDouble();
      if (emotion == GhostEmotion.sarcastic) {
        particleEmotion = rand < 0.72
            ? GhostEmotion.sarcastic
            : (rand < 0.86 ? GhostEmotion.happy : GhostEmotion.serious);
      } else if (emotion == GhostEmotion.happy) {
        particleEmotion = rand < 0.72
            ? GhostEmotion.happy
            : (rand < 0.86 ? GhostEmotion.sarcastic : GhostEmotion.serious);
      } else {
        particleEmotion = rand < 0.72
            ? GhostEmotion.serious
            : (rand < 0.86 ? GhostEmotion.happy : GhostEmotion.sarcastic);
      }

      Color particleColor;
      switch (particleEmotion) {
        case GhostEmotion.sarcastic:
          particleColor =
              Colors.redAccent.withAlpha(200 + Random().nextInt(55));
          break;
        case GhostEmotion.happy:
          particleColor =
              Colors.cyanAccent.withAlpha(200 + Random().nextInt(55));
          break;
        case GhostEmotion.serious:
          particleColor =
              Colors.greenAccent.withAlpha(200 + Random().nextInt(55));
          break;
      }

      final idx = _particles.indexWhere((p) => !p.active);
      if (idx >= 0) {
        _particles[idx] = GhostParticle(
          emotion: particleEmotion,
          position: emitOrigin,
          velocity: Offset(cos(angle) * speed, sin(angle) * speed),
          color: particleColor,
          life: 1.0,
          size: 3.0 + Random().nextDouble() * 3,
          charIndex: Random().nextInt(16),
        );
      }
    }
  }

  Future<void> _materialize({bool silent = false}) async {
    if (_state != GhostState.idle) return;
    _state = GhostState.materializing;
    if (!silent) TapFeedback.machineTap();

    await _animateTo(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      update: (t) {
        _scale = t;
        _opacity = t;
        _glitchIntensity = (1 - t) * 0.3;
      },
    );

    _state = GhostState.active;
    _emitParticles(GhostEmotion.serious, count: 8);
  }

  Future<void> _dematerialize() async {
    if (_state == GhostState.dematerializing || _state == GhostState.idle) {
      return;
    }
    _state = GhostState.dematerializing;
    TapFeedback.machineBoop();

    await _animateTo(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInBack,
      update: (t) {
        _scale = 1 - t;
        _opacity = 1 - t;
        _glitchIntensity = t * 0.5;
      },
    );

    _state = GhostState.idle;
    _scale = 0;
    _opacity = 0;
    for (final p in _particles) {
      p.active = false;
    }
  }

  Future<void> _glitchLaugh() async {
    if (_state == GhostState.laughing) return;
    _state = GhostState.laughing;
    _isLaughing = true;
    TapFeedback.machineConfirm();

    // Phase 1: Build up
    await _animateTo(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      update: (t) {
        _glitchIntensity = t * 0.8;
        _wobble = t * 0.18;
        _laughIntensity = t;
      },
    );

    // Phase 2: Laugh burst
    _emitParticles(GhostEmotion.sarcastic, count: 20);
    await _animateTo(
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      update: (t) {
        _wobble = 0.18 * (1 - t * 0.5);
        _glitchIntensity = 0.8 * (1 - t * 0.3);
      },
    );

    // Phase 3: Typewriter "hahaha"
    await Future.delayed(const Duration(milliseconds: 200));
    for (int i = 0; i < 3; i++) {
      await Future.delayed(Duration(milliseconds: 150 + i * 50));
      if (mounted) setState(() {}); // Trigger text bubble update
    }

    // Phase 4: Wind down
    await _animateTo(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      update: (t) {
        _glitchIntensity = 0.8 * (1 - t);
        _wobble = 0.18 * (1 - t);
        _laughIntensity = 1 - t;
      },
    );

    _isLaughing = false;
    _state = GhostState.active;
    _emitParticles(GhostEmotion.happy, count: 8);
  }

  Future<void> _animateTo({
    required Duration duration,
    required Curve curve,
    required void Function(double) update,
  }) async {
    final startTime = DateTime.now();
    final endTime = startTime.add(duration);

    while (DateTime.now().isBefore(endTime)) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final t = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);
      final curved = curve.transform(t);
      update(curved);
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 16));
    }
    update(1.0);
    if (mounted) setState(() {});
  }

  void _setEmotion(GhostEmotion emotion) {
    _emitParticles(emotion, count: 6);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: widget.accentColor,
      builder: (context, accentColor, child) {
        final ghostColor = Color.lerp(Colors.grey[50]!, accentColor, 0.15)!;

        return GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedOpacity(
            opacity: _opacity.clamp(0.0, 1.0),
            duration: const Duration(milliseconds: 200),
            child: Transform.scale(
              scale: _scale.clamp(0.0, double.infinity),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _GhostAvatarPainter(
                    ghostPath: _ghostPath,
                    glitchIntensity: GhostSettings.reduceMotion.value
                        ? 0.0
                        : _glitchIntensity,
                    wobble: GhostSettings.reduceMotion.value ? 0.0 : _wobble,
                    laughIntensity: GhostSettings.reduceMotion.value
                        ? 0.0
                        : _laughIntensity,
                    accentColor: accentColor,
                    ghostColor: ghostColor,
                    particles: _particles,
                    time: DateTime.now().millisecondsSinceEpoch / 1000.0,
                    reduceMotion: GhostSettings.reduceMotion.value,
                    isLaughing: _isLaughing,
                  ),
                  size: Size(widget.size, widget.size),
                ),
              ),
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
}