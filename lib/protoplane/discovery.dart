import 'dart:math' as math;
import 'dart:ui';
import 'geometry.dart';
import 'layered_terrain.dart';

/// Authored geographic areas stay stable when their material is depleted.
class WorldArea {
  WorldArea(this.id, this.footprints);
  final String id;
  final List<Region> footprints;
  Rect get bounds =>
      footprints.map((r) => r.bounds).reduce((a, b) => a.expandToInclude(b));
  bool contains(Offset point) => footprints.any((r) => r.contains(point));
  double distance(Offset point) {
    if (contains(point)) return 0;
    var result = double.infinity;
    for (final region in footprints) {
      for (final ring in region.rings) {
        for (final edge in edges(ring)) {
          final d = edge.$2 - edge.$1;
          final relative = point - edge.$1;
          // Boost.Geometry projected_point: clamp the projected segment parameter.
          final t = d.distanceSquared == 0
              ? 0.0
              : ((relative.dx * d.dx + relative.dy * d.dy) / d.distanceSquared)
                    .clamp(0.0, 1.0);
          result = math.min(result, (point - (edge.$1 + d * t)).distance);
        }
      }
    }
    return result;
  }

  static Map<String, WorldArea> fromTerrain(LayeredTerrain? terrain) {
    final groups = <String, List<Region>>{};
    for (final sheet in terrain?.sheets ?? <TerrainSheet>[]) {
      (groups[sheet.island] ??= []).add(sheet.footprint);
    }
    return {
      for (final e in groups.entries)
        e.key: WorldArea(e.key, List.unmodifiable(e.value)),
    };
  }
}

class AreaRevealed {
  const AreaRevealed(this.areaId, this.source);
  final String areaId, source;
}

double distanceToDiscovered(
  Iterable<WorldArea> areas,
  Set<String> revealed,
  Offset point,
) {
  var distance = 32.0;
  for (final area in areas) {
    if (revealed.contains(area.id)) {
      distance = math.min(distance, area.distance(point));
    }
  }
  return distance;
}
