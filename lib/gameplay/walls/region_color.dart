import 'package:flutter/painting.dart';

import 'wall_regions.dart';

/// Orange, yellow, green, blue, indigo, violet, and brown. Red is reserved
/// for alerts.
const kRegionPaletteVividArgb = <int>[
  0xFFFB8C00,
  0xFFFDD835,
  0xFF43A047,
  0xFF1E88E5,
  0xFF3949AB,
  0xFF8E24AA,
  0xFF6D4C41,
];

/// Drawn saturation relative to [kRegionPaletteVividArgb].
const kRegionPaletteSaturation = 0.5;

const kRegionPaletteSize = 7;

const kRegionAlertArgb = 0xFFE53935;

/// Half-saturated OYGBIV + brown for region borders.
final kRegionPaletteArgb = [
  for (final argb in kRegionPaletteVividArgb)
    desaturateArgb(argb, kRegionPaletteSaturation),
];

/// Scale HSL saturation, keeping hue and lightness.
int desaturateArgb(int argb, double saturationScale) {
  final hsl = HSLColor.fromColor(Color(argb));
  return hsl
      .withSaturation((hsl.saturation * saturationScale).clamp(0.0, 1.0))
      .toColor()
      .toARGB32();
}

/// Color index per region, parallel to the input list.
class RegionColorAssignment {
  const RegionColorAssignment(this.indices);

  final List<int> indices;

  int argbAt(int regionIndex) =>
      kRegionPaletteArgb[indices[regionIndex] % kRegionPaletteSize];

  @override
  bool operator ==(Object other) =>
      other is RegionColorAssignment &&
      other.indices.length == indices.length &&
      _sameIndices(other.indices);

  bool _sameIndices(List<int> other) {
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] != other[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(indices);
}

/// Orthogonal neighbors: a shared side, whether or not a wall is there.
List<Set<int>> regionAdjacency(List<Playground> regions) {
  final owner = <(int, int), int>{};
  for (var i = 0; i < regions.length; i++) {
    for (final tile in regions[i].tiles) {
      owner[tile] = i;
    }
  }
  final adj = List<Set<int>>.generate(regions.length, (_) => <int>{});
  const deltas = [(0, -1), (1, 0), (0, 1), (-1, 0)];
  for (var i = 0; i < regions.length; i++) {
    for (final (tx, ty) in regions[i].tiles) {
      for (final (dx, dy) in deltas) {
        final j = owner[(tx + dx, ty + dy)];
        if (j != null && j != i) adj[i].add(j);
      }
    }
  }
  return adj;
}

/// Greedy coloring. Prefers a prior region's color when tiles still overlap.
RegionColorAssignment assignRegionColors(
  List<Playground> regions, {
  List<Playground>? previousRegions,
  RegionColorAssignment? previous,
}) {
  final n = regions.length;
  if (n == 0) return const RegionColorAssignment([]);

  final adj = regionAdjacency(regions);
  final preferred = List<int?>.filled(n, null);
  final prev = previousRegions;
  final prevColors = previous;
  if (prev != null &&
      prevColors != null &&
      prev.length == prevColors.indices.length) {
    for (var i = 0; i < n; i++) {
      final match = _bestOverlap(regions[i], prev);
      if (match != null) preferred[i] = prevColors.indices[match];
    }
  }

  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final pa = preferred[a] != null ? 0 : 1;
      final pb = preferred[b] != null ? 0 : 1;
      if (pa != pb) return pa - pb;
      final da = adj[b].length - adj[a].length;
      if (da != 0) return da;
      return _regionKey(regions[a]).compareTo(_regionKey(regions[b]));
    });

  final indices = List<int>.filled(n, 0);
  final assigned = List<bool>.filled(n, false);
  for (final i in order) {
    final used = <int>{};
    for (final j in adj[i]) {
      if (assigned[j]) used.add(indices[j]);
    }
    indices[i] = _pickColor(used, preferred[i]);
    assigned[i] = true;
  }
  return RegionColorAssignment(indices);
}

int _pickColor(Set<int> used, int? preferred) {
  if (preferred != null &&
      preferred >= 0 &&
      preferred < kRegionPaletteSize &&
      !used.contains(preferred)) {
    return preferred;
  }
  for (var i = 0; i < kRegionPaletteSize; i++) {
    if (!used.contains(i)) return i;
  }
  return preferred ?? 0;
}

int? _bestOverlap(Playground next, List<Playground> previous) {
  var best = -1;
  var bestCount = 0;
  for (var i = 0; i < previous.length; i++) {
    var count = 0;
    for (final tile in next.tiles) {
      if (previous[i].tiles.contains(tile)) count++;
    }
    if (count > bestCount) {
      bestCount = count;
      best = i;
    }
  }
  return bestCount > 0 ? best : null;
}

String _regionKey(Playground region) {
  var minTx = 1 << 30;
  var minTy = 1 << 30;
  for (final (tx, ty) in region.tiles) {
    if (tx < minTx || (tx == minTx && ty < minTy)) {
      minTx = tx;
      minTy = ty;
    }
  }
  return '$minTx,$minTy,${region.tiles.length}';
}
