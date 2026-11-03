import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';

/// Distances are in tile widths. Smooth bands avoid popping while orbiting.
class WallRevealSettings {
  const WallRevealSettings({
    this.closeDistance = 4,
    this.farDistance = 8,
    this.innerRadius = 1,
    this.outerRadius = 2.5,
    this.minimumOpacity = .08,
  });
  final double closeDistance,
      farDistance,
      innerRadius,
      outerRadius,
      minimumOpacity;
}

const wallRevealSettings = WallRevealSettings();

double wallRevealOpacity({
  required Vector3 camera,
  required Vector3 target,
  required Vector3 roomCenter,
  required Vector3 wallCenter,
  WallRevealSettings settings = wallRevealSettings,
}) {
  double smooth(double a, double b, double value) {
    final t = ((value - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  final outward = Vector3(
    wallCenter.x - roomCenter.x,
    0,
    wallCenter.z - roomCenter.z,
  );
  final eye = Vector3(camera.x - roomCenter.x, 0, camera.z - roomCenter.z);
  if (outward.length2 < 1e-8 || eye.length2 < 1e-8) return 1;
  final facing = outward.normalized().dot(eye.normalized());
  final radius = math.sqrt(
    math.pow(target.x - roomCenter.x, 2) + math.pow(target.z - roomCenter.z, 2),
  );
  final zoom =
      1 -
      smooth(
        settings.closeDistance,
        settings.farDistance,
        camera.distanceTo(target),
      );
  final proximity =
      1 - smooth(settings.innerRadius, settings.outerRadius, radius);
  final alignment = smooth(0, .25, facing);
  // Other stories stay intact when looking above or below this room.
  final level = 1 - smooth(.6, 1.5, (target.y - roomCenter.y).abs());
  return 1 -
      (1 - settings.minimumOpacity) * zoom * proximity * alignment * level;
}
