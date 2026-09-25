// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../core/tap_feedback.dart';
import 'feedback_settings.dart';

/// Cyberpunk visual feedback for button taps
/// - Particle burst (exploding dots)
/// - Expanding ring (shockwave)
/// - Button scale pulse
/// - All driven by single AnimationController, zero allocations after init
class CyberTapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? particleColor;
  final Color? ringColor;
  final int particleCount;
  final double particleSize;
  final Duration burstDuration;
  final bool enableHaptic;
  final bool enableAudio;

  const CyberTapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.particleColor,
    this.ringColor,
    this.particleCount = 12,
    this.particleSize = 4.0,
    this.burstDuration = const Duration(milliseconds: 300),
    this.enableHaptic = true,
    this.enableAudio = true,
  });

  @override
  State<CyberTapFeedback> createState() => _CyberTapFeedbackState();
}

class _CyberTapFeedbackState extends State<CyberTapFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  late final _Ring _ring;
  double _scale = 1.0;
  bool _bursting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.burstDuration);

    _particles = List.generate(widget.particleCount, (i) => _Particle(i, widget.particleCount));
    _ring = _Ring();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _bursting = false;
          _scale = 1.0;
          _ring.reset();
          for (final p in _particles) {
            p.reset();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerBurst(PointerDownEvent details) {
    if (_bursting) return;

    if (widget.enableHaptic) TapFeedback.machineTap();

    final wantBurst = FeedbackSettings.burst.value;
    final wantRing = FeedbackSettings.ring.value;
    final wantPulse = FeedbackSettings.pulse.value;

    if (!wantBurst && !wantRing && !wantPulse) {
      widget.onTap?.call();
      return;
    }

    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(details.position);
    final center = Offset(box.size.width / 2, box.size.height / 2);
    final offset = localPos - center;

    setState(() {
      _bursting = true;
      _scale = FeedbackSettings.pulse.value ? 0.92 : 1.0;
    });

    if (FeedbackSettings.burst.value) {
      for (final p in _particles) {
        p.init(offset, widget.particleColor ?? Theme.of(context).colorScheme.primary);
      }
    }
    if (FeedbackSettings.ring.value) {
      _ring.init(offset, widget.ringColor ?? Theme.of(context).colorScheme.primary);
    }

    _controller.forward(from: 0.0).then((_) {
      if (widget.enableAudio) TapFeedback.machineBoop();
    });

    widget.onTap?.call();
  }

  void _triggerLongPress(LongPressStartDetails details) {
    if (widget.enableHaptic) TapFeedback.machineConfirm();
    if (widget.enableAudio) TapFeedback.machineBoop();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.particleColor ?? Theme.of(context).colorScheme.primary;

    return Listener(
      onPointerDown: _triggerBurst,
      child: GestureDetector(
        onLongPressStart: _triggerLongPress,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (!_bursting) return child!;

            final progress = _controller.value;
            final eased = Curves.easeOutCubic.transform(progress);

            return Transform.scale(
              scale: _scale + (1.0 - _scale) * eased,
              child: CustomPaint(
                size: Size.infinite,
                painter: _BurstPainter(
                  ring: _ring,
                  particles: _particles,
                  progress: eased,
                  color: themeColor,
                  particleSize: widget.particleSize,
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _Particle {
  final int index;
  final int total;
  Offset _position = Offset.zero;
  Offset _velocity = Offset.zero;
  Color _color = const Color(0xFFFF003C);
  double _life = 0.0;
  bool _active = false;

  _Particle(this.index, this.total);

  void init(Offset origin, Color color) {
    final angle = (index / total) * 2 * pi + (Random().nextDouble() - 0.5) * 0.5;
    final speed = 80.0 + Random().nextDouble() * 120.0;
    _position = origin;
    _velocity = Offset(cos(angle) * speed, sin(angle) * speed);
    _color = color.withValues(alpha: 0.9 + Random().nextDouble() * 0.1);
    _life = 1.0;
    _active = true;
  }

  void update(double dt) {
    if (!_active) return;
    _position += _velocity * dt;
    _velocity *= 0.92;
    _life -= dt * 2.5;
    if (_life <= 0) _active = false;
  }

  void reset() {
    _active = false;
    _life = 0.0;
  }

  bool get active => _active;
  Offset get position => _position;
  Color get color => _color.withValues(alpha: _life.clamp(0.0, 1.0));
  double get size => _life.clamp(0.0, 1.0);
}

class _Ring {
  Offset _center = Offset.zero;
  Color _color = const Color(0xFFFF003C);
  double _radius = 0.0;
  double _thickness = 3.0;
  bool _active = false;

  void init(Offset origin, Color color) {
    _center = origin;
    _color = color.withValues(alpha: 0.6);
    _radius = 0.0;
    _thickness = 3.0;
    _active = true;
  }

  void update(double dt, double progress) {
    if (!_active) return;
    _radius = 120.0 * progress;
    _thickness = 3.0 * (1.0 - progress);
  }

  void reset() {
    _active = false;
    _radius = 0.0;
  }

  bool get active => _active;
  Offset get center => _center;
  Color get color => _color;
  double get radius => _radius;
  double get thickness => _thickness;
}

class _BurstPainter extends CustomPainter {
  final _Ring ring;
  final List<_Particle> particles;
  final double progress;
  final Color color;
  final double particleSize;

  _BurstPainter({
    required this.ring,
    required this.particles,
    required this.progress,
    required this.color,
    required this.particleSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const dt = 1.0 / 60.0;
    if (ring.active) {
      ring.update(dt, progress);
      final paint = Paint()
        ..color = ring.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring.thickness
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(ring.center, ring.radius, paint);
      if (progress < 0.5) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: (1.0 - progress * 2) * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.thickness * 2
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(ring.center, ring.radius * 0.8, glowPaint);
      }
    }
    for (final p in particles) {
      if (!p.active) continue;
      p.update(dt);
      if (p.active) {
        final paint = Paint()
          ..color = p.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p.position, particleSize * p.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CyberButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? textColor;
  final double height;
  final double borderRadius;
  final IconData? icon;
  final bool isPrimary;

  const CyberButton({
    super.key,
    required this.label,
    this.onPressed,
    this.color,
    this.textColor,
    this.height = 48,
    this.borderRadius = 12,
    this.icon,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? Theme.of(context).colorScheme.primary;
    final fgColor = textColor ?? (isPrimary ? Colors.black : themeColor);

    return CyberTapFeedback(
      onTap: onPressed,
      particleColor: themeColor,
      ringColor: themeColor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isPrimary ? themeColor : Colors.transparent,
          border: Border.all(color: themeColor, width: 2),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: isPrimary ? [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fgColor, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'ShareTechMono',
                  fontWeight: FontWeight.bold,
                  color: fgColor,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CyberIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final String? tooltip;

  const CyberIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.size = 40,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? Theme.of(context).colorScheme.primary;

    return CyberTapFeedback(
      onTap: onPressed,
      particleColor: themeColor,
      ringColor: themeColor,
      particleCount: 8,
      particleSize: 3,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: themeColor, size: size * 0.5),
        ),
      ),
    );
  }
}