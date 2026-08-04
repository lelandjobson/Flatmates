import 'dart:math' as math;

/// Produces a deterministic, spatially coherent angle field by placing
/// "magnetic charges" on an irregular coarse grid and summing their
/// inverse-distance contributions at any tile coordinate.
///
/// Charges are never precomputed — they are generated on-the-fly from cell
/// coordinates and a seed, so the field works for infinite maps at O(1) cost
/// per sample (constant number of cells checked).
class MagneticFieldSampler {
  MagneticFieldSampler({this.cellSize = 24, this.seed = 0});

  /// Coarse grid cell size in tiles (minimum charge spacing).
  final int cellSize;

  /// World seed mixed into per-cell RNG for deterministic charge placement.
  final int seed;

  /// Return the field angle in degrees [0, 360) at tile ([tileX], [tileY]).
  ///
  /// Sums contributions from charges in a 5x5 neighbourhood of coarse cells.
  /// Each charge has a random polarity (+1 / -1) and the contribution uses
  /// inverse-distance falloff to keep influence broad despite the 24-tile
  /// spacing.
  double sampleAngleDeg(int tileX, int tileY) {
    double dx = 0, dy = 0;

    final cellX = tileX ~/ cellSize - (tileX < 0 ? 1 : 0);
    final cellY = tileY ~/ cellSize - (tileY < 0 ? 1 : 0);

    for (var cx = cellX - 2; cx <= cellX + 2; cx++) {
      for (var cy = cellY - 2; cy <= cellY + 2; cy++) {
        final r = math.Random(cx * 73856093 ^ cy * 19349663 ^ seed);

        // 25% dropout — charge is simply absent from this cell
        if (r.nextDouble() < 0.25) continue;

        // Jitter position within cell (±10 tiles from cell centre)
        final chX = cx * cellSize + cellSize ~/ 2 +
            ((r.nextDouble() - 0.5) * 20).round();
        final chY = cy * cellSize + cellSize ~/ 2 +
            ((r.nextDouble() - 0.5) * 20).round();

        final polarity = r.nextBool() ? 1.0 : -1.0;

        final toX = (chX - tileX).toDouble();
        final toY = (chY - tileY).toDouble();
        final dist = math.sqrt(toX * toX + toY * toY);
        if (dist < 1.0) continue;

        // Inverse-distance falloff (not inverse-square) for broad influence
        dx += polarity * toX / dist;
        dy += polarity * toY / dist;
      }
    }

    // Fallback: if contributions cancel out, use a per-tile random angle
    if (dx * dx + dy * dy < 0.001) {
      return math.Random(tileX * 73856093 ^ tileY * 19349663)
              .nextDouble() *
          360.0;
    }

    return (math.atan2(dy, dx) * 180.0 / math.pi + 360.0) % 360.0;
  }
}
