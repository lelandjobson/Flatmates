import 'dart:math' as math;
import 'dart:ui' show Color, lerpDouble;

/// Configuration for procedurally placing ingredient-decoration assets on tiles
/// that contain a matching material. Each tile gets a deterministically
/// randomized asset instance (scale, rotation, color, position jitter) based on
/// its coordinate, so the result is stable across frames.
class IngredientDecorationConfig {
  const IngredientDecorationConfig({
    required this.materialId,
    required this.assetTypeId,
    this.minScale = 0.7,
    this.maxScale = 1.3,
    this.colorLight = const Color(0xFF889677),
    this.colorDark = const Color(0xFF4C5F4D),
    this.maxPositionJitter = 0.15,
    this.maxRotationDeg = 360.0,
  });

  /// Material ID this decoration applies to (e.g. `fm-logs`).
  final String materialId;

  /// Asset type ID to render (registered in AssetDatabase).
  final String assetTypeId;

  /// Scale range relative to the asset's base definition scale.
  final double minScale;
  final double maxScale;

  /// Color endpoints for random tint interpolation.
  final Color colorLight;
  final Color colorDark;

  /// Maximum fractional tile offset from center (0.0 = center, 0.5 = edge).
  final double maxPositionJitter;

  /// Maximum facing angle in degrees (0-360) for sprite selection.
  final double maxRotationDeg;

  /// Return a seeded [Random] for the given tile coordinate so that each
  /// tile always produces the same decoration parameters.
  math.Random seededRandom(int tileX, int tileY) {
    return math.Random(tileX * 73856093 ^ tileY * 19349663);
  }

  /// Randomized scale for a tile at (x, y).
  double scaleFor(int tileX, int tileY) {
    final r = seededRandom(tileX, tileY);
    return lerpDouble(minScale, maxScale, r.nextDouble())!;
  }

  /// Randomized facing angle in degrees (0-360) for a tile at (x, y).
  /// Used with `facingAngleDeg` on `IsoAssetInstance` to pick a pre-rendered
  /// sprite at a different Y-axis rotation.
  double rotationDegFor(int tileX, int tileY) {
    final r = seededRandom(tileX, tileY);
    r.nextDouble(); // consume one to decorrelate from scale
    return r.nextDouble() * maxRotationDeg;
  }

  /// Randomized tint color for a tile at (x, y).
  Color colorFor(int tileX, int tileY) {
    final r = seededRandom(tileX, tileY);
    r.nextDouble();
    r.nextDouble();
    final t = r.nextDouble();
    return Color.lerp(colorLight, colorDark, t)!;
  }

  /// Randomized fractional position offset from tile center for (x, y).
  (double dx, double dy) jitterFor(int tileX, int tileY) {
    final r = seededRandom(tileX, tileY);
    r.nextDouble();
    r.nextDouble();
    r.nextDouble();
    final dx = (r.nextDouble() * 2 - 1) * maxPositionJitter;
    final dy = (r.nextDouble() * 2 - 1) * maxPositionJitter;
    return (dx, dy);
  }
}

/// Default decoration configs keyed by material ID.
/// Trees (fm-logs) are now handled by the foliage system, not tile decorations.
const List<IngredientDecorationConfig> defaultDecorationConfigs = [];
