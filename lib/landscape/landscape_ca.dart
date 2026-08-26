import '../crafting/placed_paper.dart';
import '../gameplay/walls/wall_regions.dart';
import 'landscape_generator.dart';
import 'landscape_grid.dart';
import 'landscape_material.dart';

/// True when ([x], [y]) is inside this CA domain.
typedef LandscapeCaMask = bool Function(int x, int y);

/// Maps volume/wall tiles onto landscape pixels (one subtile per material cell).
Set<(int, int)> landscapePixelsForTiles(
  Iterable<(int, int)> tiles,
  int subtilesPerTile,
) {
  final n = subtilesPerTile < 1 ? 1 : subtilesPerTile;
  final out = <(int, int)>{};
  for (final (tx, ty) in tiles) {
    final x0 = tx * n;
    final y0 = ty * n;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        out.add((x0 + x, y0 + y));
      }
    }
  }
  return out;
}

/// Overnight regen. Open ground and each walled region are exclusive targets.
///
/// Open ground refills erased cells from neighboring landscape materials.
/// Walled regions never receive landscape regen; erased cells there grow
/// paper paint from painted neighbors inside that same region.
class MorningLandscapeCA {
  static const int generationsPerDay = 5;

  static int run({
    required LandscapeGrid grid,
    required LandscapeGenerator generator,
    required Iterable<WallRegion> regions,
    required int subtilesPerTile,
    int generations = generationsPerDay,
  }) {
    final landscape = LandscapeCA(generator);
    final paint = RegionPaintCA();
    final regionPixels = [
      for (final region in regions)
        landscapePixelsForTiles(region.tiles, subtilesPerTile),
    ];
    final enclosed = <(int, int)>{
      for (final pixels in regionPixels) ...pixels,
    };

    var filled = 0;
    filled += landscape.stepGenerations(
      grid,
      generations,
      inDomain: (x, y) => !enclosed.contains((x, y)),
    );
    for (final pixels in regionPixels) {
      filled += paint.stepGenerations(
        grid,
        generations,
        inDomain: (x, y) => pixels.contains((x, y)),
      );
    }
    return filled;
  }
}

/// Paper-paint growth inside one walled region. Only erased cells are written;
/// existing landscape and paint are left alone, and influence never leaves
/// [inDomain].
class RegionPaintCA {
  static const _moore = <(int, int)>[
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ];

  int stepGenerations(
    LandscapeGrid grid,
    int n, {
    required LandscapeCaMask inDomain,
  }) {
    var total = 0;
    for (var i = 0; i < n; i++) {
      final filled = step(grid, inDomain: inDomain);
      if (filled == 0) break;
      total += filled;
    }
    return total;
  }

  int step(LandscapeGrid grid, {required LandscapeCaMask inDomain}) {
    final side = grid.side;
    final counts = List<int>.filled(PaperColor.values.length, 0);
    final fills = <(int, int, PaperColor)>[];

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (!inDomain(x, y)) continue;
        if (!grid.isEmpty(x, y) || grid.isVoid(x, y)) continue;
        if (grid.paintIds[grid.index(x, y)] >= 0) continue;

        counts.fillRange(0, counts.length, 0);
        var any = false;
        for (final (dx, dy) in _moore) {
          final nx = x + dx;
          final ny = y + dy;
          if (!grid.inBounds(nx, ny)) continue;
          if (!inDomain(nx, ny) || grid.isVoid(nx, ny)) continue;
          final paintId = grid.paintIds[grid.index(nx, ny)];
          if (paintId < 0 || paintId >= counts.length) continue;
          counts[paintId]++;
          any = true;
        }
        if (!any) continue;

        final chosen = _choosePaint(counts);
        if (chosen != null) {
          fills.add((x, y, chosen));
        }
      }
    }

    for (final (x, y, color) in fills) {
      grid.paint(x, y, color);
    }
    return fills.length;
  }

  PaperColor? _choosePaint(List<int> counts) {
    var bestCount = 0;
    PaperColor? best;
    for (final color in PaperColor.values) {
      final c = counts[color.index];
      if (c > bestCount) {
        bestCount = c;
        best = color;
      }
    }
    return best;
  }
}

/// One generation of material cellular automata over empty cells only.
class LandscapeCA {
  LandscapeCA(this.generator);

  final LandscapeGenerator generator;

  static const _moore = <(int, int)>[
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ];

  /// Plurality tie-break priority among common materials.
  static const _pluralityPriority = <LandscapeMaterial>[
    LandscapeMaterial.rock,
    LandscapeMaterial.water,
    LandscapeMaterial.dirt,
    LandscapeMaterial.grass,
  ];

  /// Runs [n] generations. Stops early if a generation fills nothing.
  int stepGenerations(
    LandscapeGrid grid,
    int n, {
    LandscapeCaMask? inDomain,
  }) {
    var total = 0;
    for (var i = 0; i < n; i++) {
      final filled = step(grid, inDomain: inDomain);
      if (filled == 0) break;
      total += filled;
    }
    return total;
  }

  /// Returns number of empty cells filled this generation.
  ///
  /// Only [kLandscapeEmpty] cells are written. Void / covered cells are never
  /// targets or neighbor samples. [inDomain] further restricts both writes
  /// and influence so walled regions and open ground stay exclusive.
  int step(LandscapeGrid grid, {LandscapeCaMask? inDomain}) {
    bool allowed(int x, int y) => inDomain == null || inDomain(x, y);

    final side = grid.side;
    final counts = List<int>.filled(LandscapeMaterial.values.length, 0);
    final fills = <(int, int, LandscapeMaterial)>[];

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (!allowed(x, y)) continue;
        if (!grid.isEmpty(x, y) || grid.isVoid(x, y)) continue;

        counts.fillRange(0, counts.length, 0);
        var any = false;
        for (final (dx, dy) in _moore) {
          final nx = x + dx;
          final ny = y + dy;
          if (!grid.inBounds(nx, ny)) continue;
          if (!allowed(nx, ny) || grid.isVoid(nx, ny)) continue;
          final m = grid.materialAt(nx, ny);
          if (m == null) continue;
          counts[m.index]++;
          any = true;
        }
        if (!any) continue;

        final chosen = _chooseMaterial(counts);
        if (chosen != null) {
          fills.add((x, y, chosen));
        }
      }
    }

    for (final (x, y, m) in fills) {
      final t = generator.gaussianUnit(x, y, m.index);
      grid.setMaterial(x, y, m, t);
    }
    return fills.length;
  }

  LandscapeMaterial? _chooseMaterial(List<int> counts) {
    final rock = counts[LandscapeMaterial.rock.index];
    if (rock >= 2) return LandscapeMaterial.rock;

    final water = counts[LandscapeMaterial.water.index];
    if (water >= 3) return LandscapeMaterial.water;

    for (final rare in const [
      LandscapeMaterial.flowers,
      LandscapeMaterial.fruits,
      LandscapeMaterial.vegetables,
    ]) {
      if (counts[rare.index] >= 2) return rare;
    }

    // Plurality among common materials only.
    LandscapeMaterial? best;
    var bestCount = 0;
    for (final m in _pluralityPriority) {
      final c = counts[m.index];
      if (c > bestCount) {
        bestCount = c;
        best = m;
      }
      // Equal counts: keep earlier priority (already ordered).
    }
    if (best != null && bestCount > 0) return best;

    // Fallback: any non-zero material by enum order.
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > 0) return LandscapeMaterial.values[i];
    }
    return null;
  }
}
