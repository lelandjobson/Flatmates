import 'dart:math' as math;
import 'dart:ui';

import '../flatgram/flatgram_models.dart';

/// Fixed top-down camera. Grid Y grows down the screen; Z grows up.
class TilewalkProjector {
  const TilewalkProjector({
    required this.origin,
    required this.scale,
    required this.focusX,
    required this.focusY,
  });

  factory TilewalkProjector.fit(Size size, Rect bounds) {
    final span = math.max(bounds.width, bounds.height).clamp(1.0, 12.0);
    final shortest = math.min(size.width, size.height);
    final scale = shortest <= 0 ? 48.0 : shortest / (span * 1.22);
    return TilewalkProjector(
      origin: Offset(size.width / 2, size.height * 0.46),
      scale: scale,
      focusX: bounds.center.dx,
      focusY: bounds.center.dy,
    );
  }

  final Offset origin;
  final double scale;
  final double focusX;
  final double focusY;

  static const double _yaw = 0.34;
  static const double _camBack = 8.4;
  static const double _camUp = 6.6;
  static const double _focal = 7.4;

  static final double _cos = math.cos(_yaw);
  static final double _sin = math.sin(_yaw);
  static final double _len = math.sqrt(_camBack * _camBack + _camUp * _camUp);

  /// Camera sits south of the board and above it, looking back toward -Y.
  static final double _fy = -_camBack / _len;
  static final double _fz = -_camUp / _len;

  /// View up, flipped so world +Z points toward the top of the screen.
  static final double _uy = _fz;
  static final double _uz = -_fy;

  Offset project(double x, double y, double z) {
    final view = _view(x, y, z);
    final depth = view.depth < 0.25 ? 0.25 : view.depth;
    return Offset(
      origin.dx + view.right / depth * _focal * scale,
      origin.dy - view.up / depth * _focal * scale,
    );
  }

  double depth(double x, double y, double z) => _view(x, y, z).depth;

  ({double depth, double right, double up}) _view(double x, double y, double z) {
    final dx = x - focusX;
    final dy = y - focusY;
    final rx = dx * _cos - dy * _sin;
    final ry = dx * _sin + dy * _cos;
    final relY = ry - _camBack;
    final relZ = z - _camUp;
    return (
      depth: relY * _fy + relZ * _fz,
      right: rx,
      up: relY * _uy + relZ * _uz,
    );
  }

  /// Grid anchor whose projected corner sits closest to [screen].
  GridPoint nearestAnchor(Offset screen, Rect bounds) {
    final minX = bounds.left.floor() - 3;
    final maxX = bounds.right.ceil() + 3;
    final minY = bounds.top.floor() - 3;
    final maxY = bounds.bottom.ceil() + 3;
    var best = GridPoint(minX, minY);
    var bestDistance = double.infinity;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final projected = project(x.toDouble(), y.toDouble(), 0.18);
        final distance = (projected - screen).distanceSquared;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = GridPoint(x, y);
        }
      }
    }
    return best;
  }
}
