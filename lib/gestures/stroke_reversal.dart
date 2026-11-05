import 'dart:ui';

/// A sparse reverse sample can consume a straight tail, never cut across a bend.
int? reversedTail(List<Offset> points, Offset target) {
  if (points.length < 2) return null;
  final start = points.last, delta = target - start;
  if (delta.distance < 1e-8) return null;
  for (var i = points.length - 2; i >= 0; i--) {
    final p = points[i] - start;
    final t = (p.dx * delta.dx + p.dy * delta.dy) / delta.distanceSquared;
    if ((p.dx * delta.dy - p.dy * delta.dx).abs() > 1e-7 * delta.distance ||
        t < -1e-8 ||
        t > 1 + 1e-8) {
      return null;
    }
    if ((points[i] - target).distance < 1e-7) return i;
  }
  return null;
}

/// Three deliberate reversals in a compact envelope. Distances are logical px.
class StrokeShake {
  Offset? _anchor, _axis;
  Duration? _started;
  double _extreme = 0;
  int _direction = 1, _reversals = 0;
  void reset() {
    _anchor = _axis = null;
    _started = null;
    _extreme = 0;
    _direction = 1;
    _reversals = 0;
  }

  bool update(Offset point, Duration time) {
    if (_anchor == null ||
        time - _started! > const Duration(milliseconds: 650) ||
        (point - _anchor!).distance > 32) {
      reset();
      _anchor = point;
      _started = time;
      return false;
    }
    final delta = point - _anchor!;
    if (_axis == null) {
      if (delta.distance < 12) return false;
      _axis = delta / delta.distance;
      _extreme = delta.distance;
      return false;
    }
    final value = delta.dx * _axis!.dx + delta.dy * _axis!.dy;
    if ((value - _extreme) * _direction >= 0) {
      _extreme = value;
    } else if ((value - _extreme).abs() >= 12) {
      _direction = -_direction;
      _extreme = value;
      if (++_reversals >= 3) {
        reset();
        return true;
      }
    }
    return false;
  }
}
