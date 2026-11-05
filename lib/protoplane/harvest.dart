import 'geometry.dart';
import 'models.dart';
import 'layered_terrain.dart';

class NaturalPaperPatch {
  const NaturalPaperPatch(this.region, this.color);
  final Region region;
  final PaperColor color;
}

class HarvestResult {
  HarvestResult(
    this.planeId,
    this.outline,
    this.patches, {
    this.layerId,
    this.elevation = 0,
  });
  final String? layerId;
  final double elevation;
  final String planeId;
  final Region outline;
  final List<NaturalPaperPatch> patches;
  Map<PaperColor, double> get units {
    final result = <PaperColor, double>{};
    for (final p in patches) {
      result.update(
        p.color,
        (v) => v + p.region.area * 128,
        ifAbsent: () => p.region.area * 128,
      );
    }
    return result;
  }
}

/// Versioned, world-locked paper field. Its polygons are the single source for
/// both visible coverage and inventory yield. Depletion never edits CraftPlane.
class PaperLandscape {
  PaperLandscape({this.seed = 42}) : terrain = LayeredTerrain.starter();
  LayeredTerrain terrain;
  final int seed;
  static const generationVersion = 1;
  final Map<String, List<NaturalPaperPatch>> _remaining = {};
  final Map<PaperMaterial, double> remainders = {
    for (final material in paperMaterials) material: 0,
  };

  int revision(String id) => terrain.revision(id);

  List<NaturalPaperPatch> remaining(CraftPlane plane) {
    final tile = terrain.tiles[plane.id];
    if (tile == null) return [];
    return _remaining.putIfAbsent(
      plane.id,
      () => [
        for (final r in terrain.exposed(plane.id))
          for (final cell in slabs([r], r.contains))
            NaturalPaperPatch(Region(cell), tile.sheet.material),
      ],
    );
  }

  HarvestResult? preview(CraftPlane plane, Region outline) {
    final patches = <NaturalPaperPatch>[];
    for (final patch in remaining(plane)) {
      if (!patch.region.bounds.overlaps(outline.bounds)) continue;
      for (final cell in slabs([
        patch.region,
        outline,
      ], (p) => patch.region.contains(p) && outline.contains(p))) {
        patches.add(NaturalPaperPatch(Region(cell), patch.color));
      }
    }
    if (patches.fold<double>(0, (v, p) => v + p.region.area) <
        geometryEpsilon) {
      return null;
    }
    return HarvestResult(
      plane.id,
      outline,
      patches,
      layerId: terrain.tiles[plane.id]?.sheet.id,
      elevation: plane.origin.y,
    );
  }

  int eraseGraphite(String id, List<int> cells, double area) {
    terrain.erase(id, cells);
    final tile = terrain.tiles[id]!;
    for (final t in terrain.tiles.values.where(
      (t) => t.x == tile.x && t.y == tile.y,
    )) {
      _remaining.remove(t.id);
    }
    const material = PaperMaterial.graphite;
    final total = remainders[material]! + area * 128;
    final whole = (total + 1e-9).floor();
    remainders[material] = (total - whole).clamp(0.0, 1.0);
    return whole;
  }

  void deplete(String id, Region region) {
    terrain.deplete(id, region);
    final tile = terrain.tiles[id]!;
    for (final t in terrain.tiles.values.where(
      (t) => t.x == tile.x && t.y == tile.y,
    )) {
      _remaining.remove(t.id);
    }
  }

  Map<PaperColor, int> collect(HarvestResult result) {
    final credits = <PaperColor, int>{};
    for (final entry in result.units.entries) {
      final total = remainders[entry.key]! + entry.value;
      final whole = (total + 1e-9).floor();
      credits[entry.key] = whole;
      remainders[entry.key] = (total - whole).clamp(0.0, 1.0);
    }
    for (final patch in result.patches) {
      deplete(result.planeId, patch.region);
    }
    return credits;
  }

  Map<String, dynamic> toJson() => {
    'seed': seed,
    'sheets': terrain.toJson(),
    'preset': 'paper',
    'generationVersion': generationVersion,
    'depleted':
        <String, dynamic>{}, // v6–v9 compatibility; cuts live on sheets.
    'remainders': {for (final e in remainders.entries) e.key.id: e.value},
  };

  factory PaperLandscape.fromJson(
    Map<String, dynamic> json,
    Map<String, CraftPlane> planes,
  ) {
    if (json['seed'] is! int ||
        json['generationVersion'] != generationVersion) {
      throw const FormatException('Invalid paper landscape version or seed');
    }
    if (json['preset'] != null && json['preset'] != 'paper') {
      throw const FormatException('Landscape preset mismatch');
    }
    final result = PaperLandscape(seed: json['seed']);
    result.terrain = LayeredTerrain.fromJson(json['sheets'] as List);
    for (final tile in result.terrain.tiles.values) {
      final p = planes[tile.id];
      if (p == null ||
          (p.origin - tile.plane().origin).length > geometryEpsilon ||
          (p.u - tile.plane().u).length > geometryEpsilon ||
          (p.v - tile.plane().v).length > geometryEpsilon ||
          p.owner != null ||
          !p.region.containsRegion(rectangle(1, 1)) ||
          (p.region.area - 1).abs() > geometryEpsilon) {
        throw const FormatException('Terrain tile mismatch');
      }
    }
    if (planes.keys.where((id) => id.startsWith('ground-')).length !=
        result.terrain.tiles.length) {
      throw const FormatException('Unexpected terrain tile');
    }
    for (final color in paperMaterials) {
      final value =
          (json['remainders'][color.id] ?? json['remainders'][color.name]);
      if (value is! num || !value.isFinite || value < 0 || value >= 1) {
        throw const FormatException('Invalid paper remainder');
      }
      result.remainders[color] = value.toDouble();
    }
    if ((json['depleted'] as Map).isNotEmpty) {
      throw const FormatException('Paper depletion must belong to a layer');
    }
    return result;
  }
}
