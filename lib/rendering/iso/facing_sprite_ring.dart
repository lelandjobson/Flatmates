import 'iso_sprite.dart';

/// Stores N sprites evenly spaced around 360 degrees, with efficient
/// angle-to-sprite lookup.
///
/// Sprites are indexed such that `sprites[0]` corresponds to 0 degrees
/// (north / grid -Y), and each subsequent index advances by
/// [stepDegrees] clockwise.
///
/// For evenly-spaced rings, [getNearest] is O(1) via direct computation
/// (equivalent to binary search but faster). A true binary search fallback
/// can be added later for non-uniform spacing if needed.
class FacingSpriteRing {
  FacingSpriteRing(this.sprites)
      : count = sprites.length,
        stepDegrees = 360.0 / sprites.length {
    assert(sprites.isNotEmpty, 'FacingSpriteRing must have at least 1 sprite');
    assert(
      sprites.length % 4 == 0,
      'Sprite count must be a multiple of 4 (got ${sprites.length})',
    );
  }

  /// Number of sprites in the ring.
  final int count;

  /// Angular step between consecutive sprites in degrees.
  final double stepDegrees;

  /// The sprite list. `sprites[0]` = 0 deg (north), etc.
  final List<IsoSprite> sprites;

  /// O(1) nearest sprite for the given angle in degrees.
  ///
  /// The angle is normalised to [0, 360) before lookup.
  IsoSprite getNearest(double angleDeg) {
    return sprites[_nearestIndex(angleDeg)];
  }

  /// Returns `(index, sprite)` for the nearest match.
  (int, IsoSprite) getNearestEntry(double angleDeg) {
    final i = _nearestIndex(angleDeg);
    return (i, sprites[i]);
  }

  /// All sprites whose angles fall within [fromDeg, toDeg] (inclusive),
  /// wrapping around 360. Returns `(index, sprite)` pairs in angular order.
  ///
  /// If [fromDeg] == [toDeg], returns the single nearest sprite.
  List<(int, IsoSprite)> getRange(double fromDeg, double toDeg) {
    final startIdx = _nearestIndex(fromDeg);
    final endIdx = _nearestIndex(toDeg);

    final result = <(int, IsoSprite)>[];

    if (startIdx <= endIdx) {
      for (var i = startIdx; i <= endIdx; i++) {
        result.add((i, sprites[i]));
      }
    } else {
      // Wraps around 0
      for (var i = startIdx; i < count; i++) {
        result.add((i, sprites[i]));
      }
      for (var i = 0; i <= endIdx; i++) {
        result.add((i, sprites[i]));
      }
    }

    return result;
  }

  /// The angle in degrees for a given sprite index.
  double angleAt(int index) => (index * stepDegrees) % 360.0;

  int _nearestIndex(double angleDeg) {
    final normalised = ((angleDeg % 360.0) + 360.0) % 360.0;
    return (normalised / stepDegrees).round() % count;
  }
}
