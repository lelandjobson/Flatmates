import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

enum WipeDirection { horizontal, vertical }
enum WipeMode { show, hide }

class WipeAnimation {
  WipeAnimation({
    required this.direction,
    required this.mode,
    required this.duration,
    required TickerProvider vsync,
    VoidCallback? onComplete,
  }) : controller = AnimationController(vsync: vsync, duration: duration) {
    if (onComplete != null) {
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) onComplete();
      });
    }
  }

  final WipeDirection direction;
  final WipeMode mode;
  final Duration duration;
  final AnimationController controller;

  /// The fraction of total duration over which a single element fades.
  /// Smaller values produce a sharper wavefront; larger values a softer one.
  static const double _elementFadeFraction = 0.35;

  double get progress => controller.value;

  /// Returns opacity (0.0-1.0) for an element at [normalizedPosition]
  /// (0.0 = leading edge, 1.0 = trailing edge) along the wipe axis.
  double opacityAt(double normalizedPosition) {
    final t = progress;
    final span = _elementFadeFraction;
    final windowEnd = normalizedPosition * (1.0 - span) + span;
    final windowStart = windowEnd - span;

    double opacity;
    if (t <= windowStart) {
      opacity = 0.0;
    } else if (t >= windowEnd) {
      opacity = 1.0;
    } else {
      opacity = (t - windowStart) / span;
    }

    if (mode == WipeMode.hide) opacity = 1.0 - opacity;
    return opacity.clamp(0.0, 1.0);
  }

  void forward() => controller.forward(from: 0.0);

  void reverse() => controller.reverse(from: 1.0);

  bool get isAnimating => controller.isAnimating;

  void dispose() => controller.dispose();
}
