// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class CyberInk extends InteractiveInkFeature {
  static const InteractiveInkFeatureFactory splashFactory = _CyberInkFactory();

  static const Duration _growUnconfirmed = Duration(milliseconds: 600);
  static const Duration _growConfirmed = Duration(milliseconds: 260);
  static const Duration _fadeDuration = Duration(milliseconds: 380);
  static const Duration _cancelDuration = Duration(milliseconds: 140);

  final Offset _position;
  final BorderRadius _borderRadius;
  final double _targetRadius;
  final RectCallback? _clipCallback;
  final TextDirection _textDirection;
  late final AnimationController _grow;
  late final AnimationController _fade;

  CyberInk({
    required MaterialInkController controller,
    required super.referenceBox,
    required Offset position,
    required super.color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    super.customBorder,
    double? radius,
    super.onRemoved,
  })  : _position = position,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _textDirection = textDirection,
        _targetRadius = radius ?? _radiusFor(referenceBox, rectCallback),
        _clipCallback = rectCallback ?? (containedInkWell ? () => Offset.zero & referenceBox.size : null),
        super(controller: controller) {
    _grow = AnimationController(duration: _growUnconfirmed, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..forward();
    _fade = AnimationController(duration: _fadeDuration, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener((status) {
        if (status.isCompleted) dispose();
      });
    controller.addInkFeature(this);
  }

  static double _radiusFor(RenderBox referenceBox, RectCallback? rectCallback) {
    final size = rectCallback != null ? rectCallback().size : referenceBox.size;
    final d1 = size.bottomRight(Offset.zero).distance;
    final d2 = (size.topRight(Offset.zero) - size.bottomLeft(Offset.zero)).distance;
    return math.max(d1, d2) / 2.0 + 6.0;
  }

  @override
  void confirm() {
    _grow
      ..duration = _growConfirmed
      ..forward();
    _fade.animateTo(1.0, duration: _fadeDuration, curve: Curves.easeIn);
  }

  @override
  void cancel() {
    _fade.animateTo(1.0, duration: _cancelDuration);
  }

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final visibility = 1.0 - _fade.value;
    if (visibility <= 0) return;
    final grow = Curves.easeOutCubic.transform(_grow.value);
    final rect = _clipCallback?.call();
    final target = rect != null ? rect.center : referenceBox.size.center(Offset.zero);
    final center = Offset.lerp(_position, target, grow * 0.5)!;
    final radius = _targetRadius * (0.2 + 0.85 * grow);
    final baseAlpha = color.a;
    final ringAlpha = math.min(1.0, baseAlpha * 5.0);

    void circle(Paint paint, double r) {
      paintInkCircle(
        canvas: canvas,
        transform: transform,
        paint: paint,
        center: center,
        radius: r,
        textDirection: _textDirection,
        customBorder: customBorder,
        borderRadius: _borderRadius,
        clipCallback: _clipCallback,
      );
    }

    circle(Paint()..color = color.withValues(alpha: baseAlpha * visibility), radius);
    circle(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: ringAlpha * visibility),
      radius,
    );
    circle(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color.withValues(alpha: ringAlpha * 0.45 * visibility),
      radius * 0.6,
    );
  }
}

class _CyberInkFactory extends InteractiveInkFeatureFactory {
  const _CyberInkFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return CyberInk(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
    );
  }
}
