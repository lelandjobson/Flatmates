import 'dart:math' as math;

/// 16-point compass enum for deterministic direction naming.
///
/// Provides named constants for common angles (22.5-degree steps) and
/// conversions between degrees, radians, and enum values.
///
/// This is a **naming utility** -- it gives deterministic names to common
/// angles (e.g., `CompassDirection.n.degrees == 0.0`) but is not the sprite
/// indexing mechanism itself.
enum CompassDirection {
  n,
  nne,
  ne,
  ene,
  e,
  ese,
  se,
  sse,
  s,
  ssw,
  sw,
  wsw,
  w,
  wnw,
  nw,
  nnw;

  static const int count = 16;

  /// The angle of this direction in degrees (0 = north, 90 = east, etc.).
  double get degrees => index * (360.0 / values.length);

  /// The angle of this direction in radians.
  double get radians => degrees * math.pi / 180.0;

  /// Returns the nearest [CompassDirection] for a given angle in degrees.
  ///
  /// The angle is normalised to [0, 360) before lookup.
  static CompassDirection fromDegrees(double deg) {
    final step = 360.0 / values.length; // 22.5
    final normalised = ((deg % 360.0) + 360.0) % 360.0;
    final idx = (normalised / step).round() % values.length;
    return values[idx];
  }

  /// Returns the [CompassDirection] for a 16-step index (wrapping).
  static CompassDirection fromIndex16(int i) => values[i % values.length];
}
