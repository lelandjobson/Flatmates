import 'dart:ui';

/// A fast scrub: the pointer reverses hard, twice, inside a short window.
///
/// One sharp corner is not enough, and a slow zigzag is not enough. The
/// pointer has to be moving quickly both before and after each reversal,
/// and the turn itself has to be a high acceleration.
class AsmrScrub {
  static const double minSpeed = 1600;
  static const double minAccel = 45000;
  static const Duration gap = Duration(milliseconds: 60);
  static const Duration window = Duration(milliseconds: 420);
  static const int reversalsNeeded = 2;

  Offset? _at;
  Duration? _when;
  Offset? _velocity;
  int _reversals = 0;
  Duration? _windowStart;

  void reset() {
    _at = null;
    _when = null;
    _velocity = null;
    _reversals = 0;
    _windowStart = null;
  }

  /// Adds one sample. True when the samples so far are a scrub, and the
  /// watcher is reset so the next scrub has to be earned again.
  bool add(Duration time, Offset position) {
    final at = _at;
    final when = _when;
    _at = position;
    _when = time;
    if (at == null || when == null) return false;
    final dt = (time - when).inMicroseconds / 1e6;
    if (dt < 0.004 || dt > gap.inMicroseconds / 1e6) {
      _velocity = null;
      _reversals = 0;
      _windowStart = null;
      return false;
    }
    final velocity = (position - at) / dt;
    final speed = velocity.distance;
    final previous = _velocity;
    _velocity = velocity;
    if (previous == null || speed < minSpeed) return false;
    final previousSpeed = previous.distance;
    if (previousSpeed < minSpeed) return false;
    final dot = velocity.dx * previous.dx + velocity.dy * previous.dy;
    if (dot / (speed * previousSpeed) > -0.5) return false;
    final accel = (velocity - previous).distance / dt;
    if (accel < minAccel) return false;
    if (_windowStart == null || time - _windowStart! > window) {
      _windowStart = time;
      _reversals = 0;
    }
    _reversals++;
    if (_reversals < reversalsNeeded) return false;
    reset();
    return true;
  }
}
