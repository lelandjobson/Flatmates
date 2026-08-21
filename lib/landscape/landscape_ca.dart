import 'landscape_generator.dart';
import 'landscape_grid.dart';
import 'landscape_material.dart';

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

  /// Returns number of cells filled this generation.
  int step(LandscapeGrid grid) {
    final side = grid.side;
    final counts = List<int>.filled(LandscapeMaterial.values.length, 0);
    final fills = <(int, int, LandscapeMaterial)>[];

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (!grid.isEmpty(x, y) || grid.isVoid(x, y)) continue;

        counts.fillRange(0, counts.length, 0);
        var any = false;
        for (final (dx, dy) in _moore) {
          final nx = x + dx;
          final ny = y + dy;
          if (!grid.inBounds(nx, ny)) continue;
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
