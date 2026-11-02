// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/feedback_settings.dart';
import 'machine_rain.dart';

class CyberBackdrop extends StatefulWidget {
  final Color accentColor;
  final BackdropVariant variant;
  final double intensity;

  const CyberBackdrop({
    super.key,
    required this.accentColor,
    this.variant = BackdropVariant.generic,
    this.intensity = 1.0,
  });

  static String assetFor(BackdropVariant variant) => switch (variant) {
        BackdropVariant.grabber => 'assets/backgrounds/bg_grabber.webp',
        BackdropVariant.forge => 'assets/backgrounds/bg_forge.webp',
        BackdropVariant.pipeline => 'assets/backgrounds/bg_pipeline.webp',
        BackdropVariant.workbench => 'assets/backgrounds/bg_workbench.webp',
        BackdropVariant.library => 'assets/backgrounds/bg_library.webp',
        BackdropVariant.generic => 'assets/backgrounds/bg_theater.webp',
      };

  static ColorFilter accentColorFilter(Color accent, {double brightness = 0.72}) {
    final k = brightness.clamp(0.0, 2.0);
    final r = (accent.r * 0.92 + 0.08) * k;
    final g = (accent.g * 0.92 + 0.08) * k;
    final b = (accent.b * 0.92 + 0.08) * k;
    return ColorFilter.matrix(<double>[
      0.2126 * r, 0.7152 * r, 0.0722 * r, 0, 0,
      0.2126 * g, 0.7152 * g, 0.0722 * g, 0, 0,
      0.2126 * b, 0.7152 * b, 0.0722 * b, 0, 0,
      0,          0,          0,          1, 0,
    ]);
  }

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
  bool _resumed = true;

  static Future<ui.FragmentProgram?> _load() {
    return _loading ??= ui.FragmentProgram.fromAsset('shaders/backdrop.frag').then<ui.FragmentProgram?>((p) {
      _program = p;
      return p;
    }).catchError((Object e) {
      debugPrint('BACKDROP: shader load FAILED, falling back to the painted backdrop: $e');
      _loading = null;
      return null;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    _resumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ticker = createTicker(_onTick);
    FeedbackSettings.backdrop.addListener(_syncTicker);
    if (_program != null) {
      _tryBindShader();
    } else {
      _load().then((program) {
        if (!mounted || program == null) return;
        if (_tryBindShader()) setState(() {});
      });
    }
    _syncTicker();
  }

  bool _tryBindShader() {
    try {
      _shader = _program!.fragmentShader();
      return true;
    } catch (e) {
      debugPrint('BACKDROP: fragmentShader() FAILED, falling back to the painted backdrop: $e');
      _shader = null;
      return false;
    }
  }

  void _syncTicker() {
    final shouldRun = _resumed && FeedbackSettings.backdrop.value;
    if (shouldRun && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _elapsed += dt.clamp(0.0, 0.05);
    _frame++;
    if (_frame.isEven) _time.value = _elapsed;
  }

  @override
  void dispose() {
    FeedbackSettings.backdrop.removeListener(_syncTicker);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _shader?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: FeedbackSettings.backdrop,
          builder: (context, enabled, _) {
            if (!enabled) return const ColoredBox(color: Colors.black);
            return ValueListenableBuilder<double>(
              valueListenable: FeedbackSettings.backdropIntensity,
              builder: (context, userIntensity, _) {
                final effective = (widget.intensity * userIntensity).clamp(0.15, 1.80);
                final shader = _shader;
                final artChild = AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: SizedBox.expand(
                    key: ValueKey<BackdropVariant>(widget.variant),
                    child: Image.asset(
                      CyberBackdrop.assetFor(widget.variant),
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, _) {
                        debugPrint('BACKDROP: scene art unavailable (${widget.variant.name}): $error');
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                );

                return ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      ValueListenableBuilder<double>(
                        valueListenable: _time,
                        child: artChild,
                        builder: (context, t, child) {
                          final phase = widget.variant.index * 1.15;
                          final scale = 1.09 + 0.032 * math.sin(t * 0.21 + phase);
                          final dx = 11.0 * math.sin(t * 0.14 + phase);
                          final dy = 8.0 * math.cos(t * 0.11 + phase);
                          final breath = (0.58 + 0.12 * math.sin(t * 0.72 + phase)) * effective;
                          return ColorFiltered(
                            colorFilter: CyberBackdrop.accentColorFilter(widget.accentColor, brightness: breath),
                            child: Transform.translate(
                              offset: Offset(dx, dy),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                      ),
                      if (shader != null)
                        CustomPaint(
                          size: Size.infinite,
                          painter: _BackdropPainter(
                            shader: shader,
                            time: _time,
                            accent: widget.accentColor,
                            variant: widget.variant.index.toDouble(),
                            intensity: effective * 0.85,
                          ),
                        )
                      else
                        AmbientBackdrop(
                          accentColor: widget.accentColor,
                          variant: widget.variant,
                          intensity: effective,
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.44),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.38),
                            ],
                            stops: const [0.0, 0.18, 0.82, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
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

  _BackdropPainter({
    required this.shader,
    required this.time,
    required this.accent,
    required this.variant,
    required this.intensity,
  }) : super(repaint: time);

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
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.accent != accent ||
      oldDelegate.variant != variant ||
      oldDelegate.intensity != intensity;
}
