// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/ghost_settings.dart';
import '../core/sfx.dart';
import '../screens/main_shell.dart';

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

class GhostAvatarState extends State<GhostAvatar> with WidgetsBindingObserver {
  static Future<ui.FragmentProgram?>? _loadingProgram;
  static ui.FragmentProgram? _program;

  final _GhostMotion _motion = _GhostMotion();
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  ui.FragmentShader? _shader;
  int _lastUs = 0;
  bool _foreground = true;
  bool _tickerEnabled = true;
  TextPainter? _laughText;

  static Future<ui.FragmentProgram?> _loadProgram() {
    return _loadingProgram ??= ui.FragmentProgram.fromAsset('shaders/ghost.frag').then<ui.FragmentProgram?>((p) {
      _program = p;
      return p;
    }).catchError((Object e) {
      debugPrint('GHOST: shader load failed, falling back to 2.5D painter: $e');
      _loadingProgram = null;
      return null;
    });
  }

  bool _tryBindShader() {
    final prog = _program;
    if (prog == null) return false;
    try {
      _shader?.dispose();
      _shader = prog.fragmentShader();
      return true;
    } catch (e) {
      debugPrint('GHOST: fragmentShader() failed, falling back to 2.5D painter: $e');
      _shader = null;
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    GhostSettings.reduceMotion.addListener(_onSettingsChanged);
    _motion.reduceMotion = GhostSettings.reduceMotion.value;
    _motion.presenceTarget = 0;
    if (_program != null) {
      _tryBindShader();
    } else {
      _loadProgram().then((program) {
        if (!mounted || program == null) return;
        if (_tryBindShader()) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _motion.materialize();
      _wake();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled != enabled) {
      _tickerEnabled = enabled;
      if (_tickerEnabled) {
        _wake();
      } else {
        _stopTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    GhostSettings.reduceMotion.removeListener(_onSettingsChanged);
    _stopTimer();
    _shader?.dispose();
    _motion.dispose();
    _laughText?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _wake();
    } else {
      _stopTimer();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _lastUs = 0;
  }

  void _onSettingsChanged() {
    _motion.reduceMotion = GhostSettings.reduceMotion.value;
    _motion.notify();
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
    if (!_foreground || !_tickerEnabled || _timer != null) return;
    _clock
      ..reset()
      ..start();
    _lastUs = 0;
    _scheduleStep(const Duration(milliseconds: 33));
  }

  void _scheduleStep(Duration delay) {
    _timer = Timer(delay, _onStep);
  }

  void _onStep() {
    _timer = null;
    if (!mounted || !_foreground || !_tickerEnabled) {
      _clock.stop();
      return;
    }
    final nowUs = _clock.elapsedMicroseconds;
    final dt = _lastUs == 0 ? (1.0 / 30.0) : (nowUs - _lastUs) / 1e6;
    _lastUs = nowUs;
    final step = dt.clamp(0.0, 0.08);
    _motion.musicPlaying = AudioService.isPlaying;
    final busy = _motion.advance(step);
    if (busy || !_motion.reduceMotion) {
      _motion.notify();
    }
    if (_motion.dormant || (_motion.reduceMotion && !busy)) {
      _clock.stop();
      _lastUs = 0;
      _motion.notify();
      return;
    }
    _scheduleStep(Duration(milliseconds: busy ? 33 : 50));
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
          fontSize: 19,
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

  void _poke() {
    _motion.poke();
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
              painter: _GhostPainter(
                motion: _motion,
                accent: accent,
                shader: _shader,
                laughText: _laughText,
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
  void setMood(GhostMood mood) => _state?._setMood(mood);
  void talk() => _state?._talk();
  void poke() => _state?._poke();
}

enum _WispShape { orb, diamond, glitchBar }

class _Wisp {
  Offset position;
  Offset velocity;
  final double life;
  final double size;
  final Color color;
  final _WispShape shape;
  double age = 0;

  _Wisp(this.position, this.velocity, this.life, this.size, this.color, this.shape);
}

class _GhostMotion extends ChangeNotifier {
  final math.Random _rng = math.Random();

  bool reduceMotion = false;
  bool musicPlaying = false;
  GhostMood mood = GhostMood.idle;
  GhostEmotion emotion = GhostEmotion.serious;
  double emotionId = 0;

  double time = 0;
  double presence = 0;
  double presenceTarget = 1;
  double _presenceFrom = 0;
  double _presenceAge = 10;
  double _presenceDuration = 0.6;

  double laughAge = 10;
  double emotionAge = 10;
  double pokeAge = 10;
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
  double _nextWisp = 1.3;
  final List<_Wisp> wisps = [];

  bool get laughing => laughAge < 1.4;
  bool get poking => pokeAge < 0.65;
  double get emotionGlow => (1 - emotionAge / 1.6).clamp(0.0, 1.0);

  double get glitch {
    final materializing = _presenceAge < _presenceDuration ? (1 - _presenceAge / _presenceDuration) * 0.65 : 0.0;
    var laughGlitch = 0.0;
    if (laughing) {
      if (laughAge < 0.3) {
        laughGlitch = laughAge / 0.3 * 0.85;
      } else if (laughAge < 0.9) {
        laughGlitch = 0.85;
      } else {
        laughGlitch = 0.85 * (1 - (laughAge - 0.9) / 0.5);
      }
    }
    final pokeGlitch = poking ? math.exp(-pokeAge * 9.0) * 0.28 : 0.0;
    return reduceMotion ? 0 : math.max(materializing, math.max(laughGlitch, pokeGlitch)).clamp(0.0, 1.0);
  }

  double get pokeSpring {
    if (!poking || reduceMotion) return 0;
    return math.exp(-pokeAge * 7.2) * math.sin(pokeAge * 25.0);
  }

  double get beat {
    if (reduceMotion) return 0;
    final musicBeat = musicPlaying ? 0.24 * (0.5 + 0.5 * math.sin(time * 6.0)) : 0.0;
    final pokeHop = poking ? math.exp(-pokeAge * 5.8) * math.sin(pokeAge * math.pi / 0.32).clamp(-0.4, 1.0) * 0.85 : 0.0;
    return (musicBeat + pokeHop).clamp(-0.35, 1.2);
  }

  double get wobble {
    if (!laughing || reduceMotion) return 0;
    final envelope = laughAge < 0.3 ? laughAge / 0.3 : (1 - (laughAge - 0.3) / 1.1).clamp(0.0, 1.0);
    return math.sin(laughAge * 38) * 0.14 * envelope;
  }

  double get floatOffset =>
      reduceMotion ? 0 : math.sin(time * 2.1) * 2.8 + (laughing ? math.sin(laughAge * 20) * 2.0 : 0) - beat * 3.2;
  double get breathe => reduceMotion ? 1 : 1 + 0.026 * math.sin(time * 2.5) + 0.04 * beat;
  double get tailPhase => reduceMotion ? 0 : time * 4.4;

  bool get dormant => presence <= 0.001 && presenceTarget == 0 && wisps.isEmpty;

  void notify() => notifyListeners();

  void materialize() {
    _presenceFrom = presence;
    presenceTarget = 1;
    _presenceAge = 0;
    _presenceDuration = 0.62;
    _burst(10, GhostEmotion.serious);
  }

  void dematerialize() {
    _presenceFrom = presence;
    presenceTarget = 0;
    _presenceAge = 0;
    _presenceDuration = 0.42;
    _burst(8, emotion);
  }

  void laugh() {
    laughAge = 0;
    _burst(18, GhostEmotion.sarcastic);
  }

  void poke() {
    pokeAge = 0;
    _burst(10, emotion == GhostEmotion.serious ? GhostEmotion.happy : emotion);
  }

  void setEmotion(GhostEmotion value) {
    emotion = value;
    emotionAge = 0;
    _burst(7, value);
  }

  void talk() {
    _mouthTarget = 0.50 + _rng.nextDouble() * 0.50;
  }

  void glance(Offset direction) {
    _eyeTarget = direction;
    _eyeHold = 1.7;
  }

  bool advance(double dt) {
    time = (time + dt) % 3600.0;
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
    if (poking) {
      pokeAge += dt;
      busy = true;
    }
    if (emotionAge < 1.6) {
      emotionAge += dt;
      busy = true;
    }

    final targetEmotionId = laughing
        ? 1.0
        : switch (emotion) {
            GhostEmotion.serious => 0.0,
            GhostEmotion.happy => 1.0,
            GhostEmotion.sarcastic => 2.0,
          };
    final emoStep = 1 - math.pow(0.0008, dt).toDouble();
    emotionId += (targetEmotionId - emotionId) * emoStep;
    if ((targetEmotionId - emotionId).abs() > 0.01) busy = true;

    _blinkAge += dt;
    _nextBlink -= dt;
    if (_nextBlink <= 0) {
      _blinkAge = 0;
      _nextBlink = 2.3 + _rng.nextDouble() * 3.4;
      if (_rng.nextDouble() < 0.18) _nextBlink = 0.22;
    }
    blink = _blinkAge < 0.14 ? math.sin(_blinkAge / 0.14 * math.pi) : 0;
    if (blink > 0.01) busy = true;

    _eyeHold -= dt;
    _nextWander -= dt;
    if (_eyeHold <= 0) {
      if (mood == GhostMood.listening) {
        _eyeTarget = const Offset(-0.52, -0.58);
      } else if (mood == GhostMood.thinking) {
        _eyeTarget = const Offset(0.48, -0.76);
      } else if (_nextWander <= 0) {
        _nextWander = 2.4 + _rng.nextDouble() * 3.8;
        _eyeTarget = _rng.nextDouble() < 0.38
            ? Offset.zero
            : Offset(_rng.nextDouble() * 1.8 - 0.9, _rng.nextDouble() * 1.2 - 0.6);
      }
    }
    eye = Offset.lerp(eye, _eyeTarget, 1 - math.pow(0.0014, dt).toDouble())!;
    if ((eye - _eyeTarget).distance > 0.02) busy = true;

    final talking = mood == GhostMood.talking;
    _mouthTarget = talking ? _mouthTarget * math.pow(0.02, dt).toDouble() : 0;
    mouth += (_mouthTarget - mouth) * (1 - math.pow(0.0001, dt).toDouble());
    listen += ((mood == GhostMood.listening ? 1.0 : 0.0) - listen) * (1 - math.pow(0.008, dt).toDouble());
    think += ((mood == GhostMood.thinking ? 1.0 : 0.0) - think) * (1 - math.pow(0.008, dt).toDouble());
    if (talking || mouth > 0.02 || listen > 0.02 || think > 0.02) busy = true;

    _nextWisp -= dt;
    if (!reduceMotion && presence > 0.85 && _nextWisp <= 0) {
      _nextWisp = (musicPlaying ? 0.75 : 1.25) + _rng.nextDouble() * 1.8;
      _spawnWisp(emotion == GhostEmotion.serious ? null : emotion);
    }
    for (final w in wisps) {
      w.age += dt;
      w.position += w.velocity * dt;
      w.velocity = Offset(w.velocity.dx * math.pow(0.38, dt).toDouble(), w.velocity.dy - 11 * dt);
    }
    wisps.removeWhere((w) => w.age >= w.life);
    if (wisps.length > 3) busy = true;
    return busy;
  }

  void _burst(int count, GhostEmotion flavor) {
    if (reduceMotion) return;
    for (var i = 0; i < count; i++) {
      _spawnWisp(flavor, angle: i / count * math.pi * 2, fast: true);
    }
  }

  void _spawnWisp(GhostEmotion? flavor, {double? angle, bool fast = false}) {
    if (wisps.length > 34) return;
    final a = angle ?? (-math.pi / 2 + (_rng.nextDouble() - 0.5) * 1.3);
    final speed = fast ? 38 + _rng.nextDouble() * 46 : 9 + _rng.nextDouble() * 13;
    final origin = fast ? const Offset(50, 52) : Offset(26 + _rng.nextDouble() * 48, 80);
    final (color, shape) = switch (flavor) {
      GhostEmotion.sarcastic => (Colors.redAccent, _WispShape.glitchBar),
      GhostEmotion.happy => (Colors.cyanAccent, _WispShape.diamond),
      GhostEmotion.serious => (Colors.greenAccent, _WispShape.diamond),
      null => (Colors.white, _WispShape.orb),
    };
    wisps.add(
      _Wisp(
        origin,
        Offset(math.cos(a), math.sin(a)) * speed,
        fast ? 0.65 + _rng.nextDouble() * 0.45 : 1.5 + _rng.nextDouble() * 0.9,
        fast ? 2.2 + _rng.nextDouble() * 1.9 : 1.4 + _rng.nextDouble() * 1.1,
        color,
        shape,
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  final _GhostMotion motion;
  final Color accent;
  final ui.FragmentShader? shader;
  final TextPainter? laughText;

  _GhostPainter({
    required this.motion,
    required this.accent,
    required this.shader,
    required this.laughText,
  }) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    final m = motion;
    final presence = m.presence.clamp(0.0, 1.2);
    if (presence <= 0.001 && m.wisps.isEmpty) return;

    final unit = size.shortestSide / 100.0;
    final emotionColor = switch (m.emotion) {
      GhostEmotion.happy => Colors.cyanAccent,
      GhostEmotion.sarcastic => Colors.redAccent,
      GhostEmotion.serious => accent,
    };
    final baseTint = m.emotion == GhostEmotion.serious ? 0.0 : 0.42;
    final emotionMix = math.max(baseTint, m.emotionGlow).clamp(0.0, 1.0);
    final glowColor = Color.lerp(accent, emotionColor, emotionMix)!;

    final s = shader;
    if (s != null) {
      _paintShader(canvas, size, s, presence, emotionColor, emotionMix);
      _paintOverlays(canvas, size, unit, glowColor);
      return;
    }

    _paintFallback(canvas, size, unit, presence, glowColor);
    _paintOverlays(canvas, size, unit, glowColor);
  }

  void _paintShader(
    Canvas canvas,
    Size size,
    ui.FragmentShader s,
    double presence,
    Color emotionColor,
    double emotionMix,
  ) {
    final m = motion;
    final mouthDrive = m.laughing
        ? (0.58 + 0.42 * math.sin(m.laughAge * 30).abs()).clamp(0.0, 1.0)
        : m.mouth.clamp(0.0, 1.0);
    final spring = m.pokeSpring;

    s
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, m.reduceMotion ? 0.0 : m.time)
      ..setFloat(3, accent.r)
      ..setFloat(4, accent.g)
      ..setFloat(5, accent.b)
      ..setFloat(6, 1.0)
      ..setFloat(7, emotionColor.r)
      ..setFloat(8, emotionColor.g)
      ..setFloat(9, emotionColor.b)
      ..setFloat(10, emotionMix)
      ..setFloat(11, m.eye.dx.clamp(-1.0, 1.0))
      ..setFloat(12, m.eye.dy.clamp(-1.0, 1.0))
      ..setFloat(13, presence)
      ..setFloat(14, m.blink.clamp(0.0, 1.0))
      ..setFloat(15, mouthDrive)
      ..setFloat(16, m.listen.clamp(0.0, 1.0))
      ..setFloat(17, m.think.clamp(0.0, 1.0))
      ..setFloat(18, m.glitch)
      ..setFloat(19, m.emotionId.clamp(0.0, 2.0))
      ..setFloat(20, m.beat);

    canvas.save();
    if (spring.abs() > 0.002) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(1.0 + spring * 0.13, 1.0 - spring * 0.13);
      canvas.translate(-size.width / 2, -size.height / 2);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
    canvas.restore();
  }

  void _paintOverlays(Canvas canvas, Size size, double unit, Color glowColor) {
    final m = motion;
    if (m.wisps.isEmpty && !(m.laughing && laughText != null && m.laughAge > 0.35)) return;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);

    for (final w in m.wisps) {
      final life = (1 - (w.age / w.life)).clamp(0.0, 1.0);
      final p = w.position - const Offset(50, 50);
      final r = w.size * (0.55 + 0.45 * life);
      final col = (w.color == Colors.greenAccent ? glowColor : w.color).withValues(alpha: 0.82 * life);
      switch (w.shape) {
        case _WispShape.orb:
          canvas.drawCircle(p, r, Paint()..color = col);
          break;
        case _WispShape.diamond:
          final star = Path()
            ..moveTo(p.dx, p.dy - r * 1.45)
            ..lineTo(p.dx + r * 0.95, p.dy)
            ..lineTo(p.dx, p.dy + r * 1.45)
            ..lineTo(p.dx - r * 0.95, p.dy)
            ..close();
          canvas.drawPath(star, Paint()..color = col);
          break;
        case _WispShape.glitchBar:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: p, width: r * 2.8, height: r * 0.85),
              const Radius.circular(1.0),
            ),
            Paint()..color = col,
          );
          break;
      }
    }

    if (m.laughing && laughText != null && m.laughAge > 0.35) {
      final fade = m.laughAge > 1.1 ? (1 - (m.laughAge - 1.1) / 0.3).clamp(0.0, 1.0) : 1.0;
      canvas.save();
      canvas.scale(1 / unit);
      final t = laughText!;
      final lift = 28 * unit + (m.laughAge - 0.35) * 18;
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: fade));
      t.paint(canvas, Offset(-t.width / 2, -size.height / 2 - lift));
      canvas.restore();
      canvas.restore();
    }

    canvas.restore();
  }

  Path _bodyPath(double phase) {
    final path = Path()..moveTo(21, 79);
    path.lineTo(22, 41);
    path.cubicTo(22, 17, 34, 8, 50, 8);
    path.cubicTo(66, 8, 78, 17, 78, 41);
    path.lineTo(79, 79);
    const scallops = 4;
    for (var i = 0; i < scallops; i++) {
      final x0 = 79 - i * 14.5;
      final lift = math.sin(phase + i * 1.35) * 2.8;
      final dip = math.sin(phase + i * 1.35 + 0.85) * 2.3;
      path.quadraticBezierTo(x0 - 7.25, 91 + lift, x0 - 14.5, 82 + dip);
    }
    path.close();
    return path;
  }

  void _paintFallback(Canvas canvas, Size size, double unit, double presence, Color glowColor) {
    final m = motion;
    final ghostWhite = Color.lerp(const Color(0xFFF2F7FF), glowColor, 0.18)!;
    final spring = m.pokeSpring;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);

    if (m.listen > 0.02) {
      for (var k = 0; k < 2; k++) {
        final phase = ((m.time * 0.85) + k * 0.5) % 1.0;
        final radius = 28 + phase * 22;
        canvas.drawCircle(
          const Offset(0, -2),
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = glowColor.withValues(alpha: (1 - phase) * 0.55 * m.listen),
        );
      }
    }

    final shadowScale = (1 - m.floatOffset / 24).clamp(0.6, 1.3);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 46), width: 46 * shadowScale * presence, height: 7 * shadowScale * presence),
      Paint()
        ..color = glowColor.withValues(alpha: 0.28 * presence)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );

    canvas.save();
    canvas.translate(0, m.floatOffset);
    canvas.rotate(m.wobble - m.eye.dx * 0.05);
    final scale = presence * m.breathe * (1 + 0.08 * m.listen);
    canvas.scale(scale * (1 + spring * 0.13), scale * (1 - spring * 0.13));
    canvas.translate(-50, -50);

    final body = _bodyPath(m.tailPhase);
    final glitch = m.glitch;

    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..color = glowColor.withValues(alpha: 0.42 + 0.25 * m.emotionGlow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    if (glitch > 0.02) {
      final shift = glitch * 5;
      canvas.drawPath(body.shift(Offset(-shift, 0)), Paint()..color = Colors.redAccent.withValues(alpha: 0.45 * glitch));
      canvas.drawPath(body.shift(Offset(shift, 0)), Paint()..color = Colors.cyanAccent.withValues(alpha: 0.45 * glitch));
    }

    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ghostWhite, ghostWhite.withValues(alpha: 0.88), glowColor.withValues(alpha: 0.58)],
          stops: const [0, 0.58, 1],
        ).createShader(const Rect.fromLTWH(20, 8, 60, 86)),
    );

    final handBob = m.reduceMotion ? 0.0 : math.sin(m.time * 2.9) * 2.4;
    final talkWave = m.reduceMotion ? 0.0 : math.sin(m.time * 18.0) * 2.8 * m.mouth;
    final leftHand = Offset(13 + 4 * m.think, 54 + handBob - 5 * m.listen + talkWave);
    final rightHand = Offset(87 - 4 * m.think, 54 - handBob - talkWave);
    for (final hc in [leftHand, rightHand]) {
      canvas.drawCircle(hc, 6.2, Paint()..color = glowColor.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(hc, 5.0, Paint()..color = ghostWhite.withValues(alpha: 0.92));
    }

    final look = Offset(m.eye.dx.clamp(-1.0, 1.0) * 4.2, m.eye.dy.clamp(-1.0, 1.0) * 2.8);
    final visorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(50, 42) + look * 0.65, width: 38, height: 22),
      const Radius.circular(10),
    );
    canvas.drawRRect(visorRect, Paint()..color = const Color(0xEE070A10));
    canvas.drawRRect(
      visorRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = glowColor.withValues(alpha: 0.65),
    );

    _paintFallbackVisorFace(canvas, look, glowColor);
    canvas.restore();

    if (m.think > 0.02) {
      for (var i = 0; i < 4; i++) {
        final angle = m.time * 3.4 + i * math.pi / 2;
        final p = Offset(math.cos(angle) * 23, -44 + math.sin(angle) * 6 + m.floatOffset);
        final depth = (math.sin(angle) + 1) / 2;
        canvas.drawCircle(
          p,
          2.0 + depth * 1.8,
          Paint()..color = Colors.cyanAccent.withValues(alpha: (0.4 + 0.55 * depth) * m.think),
        );
      }
    }

    canvas.restore();
  }

  void _paintFallbackVisorFace(Canvas canvas, Offset look, Color glowColor) {
    final m = motion;
    final eyeOpen = (1 - m.blink).clamp(0.08, 1.0);
    final emit = Color.lerp(glowColor, Colors.white, 0.45)!;
    final happy = m.emotion == GhostEmotion.happy || m.laughing;
    final sarcastic = m.emotion == GhostEmotion.sarcastic && !m.laughing;

    for (var side = 0; side < 2; side++) {
      final cx = side == 0 ? 41.0 : 59.0;
      final center = Offset(cx, 40.5) + look;
      if (happy && eyeOpen > 0.35) {
        final arch = Path()
          ..moveTo(center.dx - 4.2, center.dy + 1.5)
          ..quadraticBezierTo(center.dx, center.dy - 4.5, center.dx + 4.2, center.dy + 1.5);
        canvas.drawPath(
          arch,
          Paint()
            ..color = emit
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      } else {
        final h = (sarcastic && side == 0 ? 4.2 : 6.8) * eyeOpen * (1 + 0.15 * m.listen);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 6.2, height: h), const Radius.circular(3)),
          Paint()..color = emit,
        );
        if (eyeOpen > 0.45) {
          canvas.drawCircle(center + const Offset(-1.2, -1.4), 1.1, Paint()..color = Colors.white);
        }
      }
    }

    if (happy) {
      final blush = Paint()..color = Colors.pinkAccent.withValues(alpha: 0.45);
      canvas.drawOval(Rect.fromCenter(center: const Offset(35, 46.5) + look * 0.65, width: 5.5, height: 2.6), blush);
      canvas.drawOval(Rect.fromCenter(center: const Offset(65, 46.5) + look * 0.65, width: 5.5, height: 2.6), blush);
    }

    final mouthCenter = const Offset(50, 48.2) + look * 0.7;
    if (m.mouth > 0.04 || m.laughing) {
      final amp = m.laughing ? 0.65 + 0.35 * math.sin(m.laughAge * 30).abs() : m.mouth;
      final barPaint = Paint()
        ..color = emit
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var b = -2; b <= 2; b++) {
        final bx = mouthCenter.dx + b * 2.5;
        final bh = (1.2 + 3.6 * amp * (0.55 + 0.45 * math.cos(b * 1.3 + m.time * 24))).clamp(0.8, 4.8);
        canvas.drawLine(Offset(bx, mouthCenter.dy - bh / 2), Offset(bx, mouthCenter.dy + bh / 2), barPaint);
      }
      return;
    }

    final mouthStroke = Paint()
      ..color = emit
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final mp = Path();
    if (happy) {
      mp.moveTo(mouthCenter.dx - 4.0, mouthCenter.dy - 0.8);
      mp.quadraticBezierTo(mouthCenter.dx, mouthCenter.dy + 3.0, mouthCenter.dx + 4.0, mouthCenter.dy - 0.8);
    } else if (sarcastic) {
      mp.moveTo(mouthCenter.dx - 3.8, mouthCenter.dy + 0.6);
      mp.quadraticBezierTo(mouthCenter.dx + 0.8, mouthCenter.dy + 1.4, mouthCenter.dx + 4.2, mouthCenter.dy - 1.5);
    } else {
      mp.moveTo(mouthCenter.dx - 3.2, mouthCenter.dy);
      mp.quadraticBezierTo(mouthCenter.dx, mouthCenter.dy + 1.2, mouthCenter.dx + 3.2, mouthCenter.dy);
    }
    canvas.drawPath(mp, mouthStroke);
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.shader != shader || oldDelegate.laughText != laughText;
}
