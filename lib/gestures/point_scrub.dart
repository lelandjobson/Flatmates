import 'dart:ui';

/// Two deliberate reversals close to a point, independent of event frequency.
class PointScrub {
  Offset? _anchor, _axis;
  double _extreme = 0;
  int _direction = 0, _reversals = 0;
  Duration? _started;

  void reset() {
    _anchor = _axis = null;
    _started = null;
    _extreme = 0;
    _direction = _reversals = 0;
  }

  bool update(Offset pointer, Offset point, Duration time) {
    if ((pointer - point).distance > 28) {
      reset();
      return false;
    }
    if (_started == null ||
        time - _started! > const Duration(milliseconds: 700)) {
      reset();
      _started = time;
      _anchor = pointer;
      return false;
    }
    final delta = pointer - _anchor!;
    if (_axis == null) {
      if (delta.distance < 10) return false;
      _axis = delta / delta.distance;
      _direction = 1;
      _extreme = delta.distance;
      return false;
    }
    final value = delta.dx * _axis!.dx + delta.dy * _axis!.dy;
    if ((value - _extreme) * _direction >= 0) {
      _extreme = value;
    } else if ((value - _extreme).abs() >= 10) {
      _direction = -_direction;
      _extreme = value;
      _reversals++;
      if (_reversals >= 2) {
        reset();
        return true;
      }
    }
    return false;
  }
}
