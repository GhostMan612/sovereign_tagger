// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'package:flutter/material.dart';
import '../widgets/tap_fx_layer.dart';
import 'feedback_settings.dart';

class CyberTapFeedback extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final Color? fxColor;

  const CyberTapFeedback({super.key, required this.child, this.pressedScale = 0.94, this.fxColor});

  @override
  State<CyberTapFeedback> createState() => _CyberTapFeedbackState();
}

class _CyberTapFeedbackState extends State<CyberTapFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    if (value && !FeedbackSettings.pulse.value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: _pressed ? const Duration(milliseconds: 70) : const Duration(milliseconds: 320),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.fxColor == null ? widget.child : TapFxTint(color: widget.fxColor!, child: widget.child),
      ),
    );
  }
}
