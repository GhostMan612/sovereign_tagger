// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';

class AnimatedTabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const AnimatedTabStack({super.key, required this.index, required this.children});

  @override
  State<AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<AnimatedTabStack> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
  late int _current = widget.index;
  int? _previous;
  double _direction = 1;

  @override
  void didUpdateWidget(covariant AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _current) return;
    _previous = _current;
    _direction = widget.index > _current ? 1 : -1;
    _current = widget.index;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _anim.value = 1;
      _previous = null;
      return;
    }
    _anim.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _previous = null);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_anim.value);
        return Stack(
          fit: StackFit.expand,
          children: [for (var i = 0; i < widget.children.length; i++) _slot(i, t)],
        );
      },
    );
  }

  Widget _slot(int i, double t) {
    final active = i == _current;
    final leaving = i == _previous;
    var opacity = 1.0;
    var dx = 0.0;
    if (active) {
      opacity = t;
      dx = _direction * 36 * (1 - t);
    } else if (leaving) {
      opacity = 1 - t;
      dx = -_direction * 24 * t;
    }
    return Offstage(
      offstage: !active && !leaving,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: widget.children[i],
            ),
          ),
        ),
      ),
    );
  }
}
