import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Generic flashing animation controller
/// Flashes a visual element with a given frequency
class FlashAnimator extends ChangeNotifier {
  FlashAnimator({
    required this.flashesPerSecond,
    required TickerProvider vsync,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  final double flashesPerSecond;
  late final Ticker _ticker;

  double _opacity = 1.0;

  /// Current opacity (0.0 to 1.0)
  double get opacity => _opacity;

  /// Whether animation is active
  bool get isFlashing => _ticker.isActive;

  void start() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void stop() {
    _ticker.stop();
    _opacity = 1.0;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    // Calculate opacity using fast transitions with long dwell times
    // Period = 1 / flashesPerSecond
    final period = 1.0 / flashesPerSecond;
    final seconds = elapsed.inMicroseconds / 1e6;
    final cycle = (seconds / period) % 1.0;

    // Fast transitions at 10% and 60% of cycle, with long dwells at 1.0 and 0.0
    // Pattern: 1.0 (0-8%), fade down (8-12%), 0.0 (12-58%), fade up (58-62%), 1.0 (62-100%)
    if (cycle < 0.08) {
      _opacity = 1.0; // Full opacity dwell
    } else if (cycle < 0.12) {
      // Fast fade down (4% of cycle)
      final t = (cycle - 0.08) / 0.04;
      _opacity = 1.0 - t;
    } else if (cycle < 0.58) {
      _opacity = 0.0; // Hidden dwell
    } else if (cycle < 0.62) {
      // Fast fade up (4% of cycle)
      final t = (cycle - 0.58) / 0.04;
      _opacity = t;
    } else {
      _opacity = 1.0; // Full opacity dwell
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
