import 'dart:ui';

import '../rendering/iso/perlin_noise.dart';
import 'geometry.dart';
import 'models.dart';

class NaturalPaperPatch {
  const NaturalPaperPatch(this.region, this.color, this.grain);
  final Region region;
  final PaperColor color;
  final double grain;
}

class HarvestResult {
  HarvestResult(this.planeId, this.outline, this.patches);
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
  PaperLandscape({this.seed = 42, this.preset = WorldPreset.ink});
  final WorldPreset preset;
  final int seed;
  static const generationVersion = 1;
  static const subdivisions = 16;
  late final _noise = PerlinNoise(seed: seed);
  final Map<String, List<Region>> _depleted = {};
  final Map<String, List<NaturalPaperPatch>> _generated = {}, _remaining = {};
  final Map<String, int> _revisions = {};
  late final Map<PaperMaterial, double> remainders = {
    for (final material in preset.materials) material: 0,
  };

  int revision(String id) => _revisions[id] ?? 0;
  List<Region> depleted(String id) => List.unmodifiable(_depleted[id] ?? []);

  double sample(double x, double y) => _noise.fbm2(
    x * .48 + 11.73,
    y * .48 - 8.19,
    octaves: 2,
    persistence: .25,
  );

  late final List<double> inkThresholds = () {
    final values = <double>[];
    // Sample the actual 8×8 starter domain, independent of tile access order.
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        values.add(sample(-4 + (x + .5) / 32, -4 + (y + .5) / 32));
      }
    }
    values.sort();
    return [
      -double.infinity,
      for (final q in [.40, .60, .75, .90, .98])
        values[(q * values.length).floor()],
      double.infinity,
    ];
  }();

  List<NaturalPaperPatch> generated(CraftPlane plane) => _generated.putIfAbsent(
    plane.id,
    () {
      final result = <NaturalPaperPatch>[];
      final bands = preset == WorldPreset.ink
          ? inkThresholds
          : [-double.infinity, -.21, -.065, .065, .21, double.infinity];
      final colors = preset == WorldPreset.ink
          ? inkMaterials
          : [
              PaperColor.blue,
              PaperColor.green,
              PaperColor.sand,
              PaperColor.yellow,
              PaperColor.red,
            ];
      final box = plane.region.bounds;
      for (var y = 0; y < subdivisions; y++) {
        for (var x = 0; x < subdivisions; x++) {
          Offset point(int dx, int dy) => Offset(
            box.left + (x + dx) * box.width / subdivisions,
            box.top + (y + dy) * box.height / subdivisions,
          );
          final corners = [point(0, 0), point(1, 0), point(1, 1), point(0, 1)];
          final values = corners.map((p) {
            final world = plane.point(p);
            return (p, sample(world.x, -world.z));
          }).toList();
          for (final indices in [
            [0, 1, 2],
            [0, 2, 3],
          ]) {
            final triangle = indices.map((i) => values[i]).toList();
            for (var band = 0; band < colors.length; band++) {
              var polygon = triangle;
              if (bands[band].isFinite) {
                polygon = _clipBand(polygon, bands[band], true);
              }
              if (bands[band + 1].isFinite) {
                polygon = _clipBand(polygon, bands[band + 1], false);
              }
              if (polygon.length < 3) continue;
              final region = Region(
                simplifyRing(polygon.map((p) => p.$1).toList()),
              );
              if (region.area < 1e-12) continue;
              final world = plane.point(region.bounds.center);
              result.add(
                NaturalPaperPatch(
                  region,
                  colors[band],
                  preset == WorldPreset.ink
                      ? 0
                      : _noise.noise2(
                              world.x * 23.1 + 4.7,
                              world.z * 23.1 - 2.3,
                            ) *
                            .045,
                ),
              );
            }
          }
        }
      }
      return List.unmodifiable(result);
    },
  );

  List<NaturalPaperPatch> remaining(CraftPlane plane) => _remaining.putIfAbsent(
    plane.id,
    () {
      var patches = generated(plane);
      for (final cut in _depleted[plane.id] ?? <Region>[]) {
        final next = <NaturalPaperPatch>[];
        for (final patch in patches) {
          if (!patch.region.bounds.overlaps(cut.bounds)) {
            next.add(patch);
            continue;
          }
          for (final cell in slabs([
            patch.region,
            cut,
          ], (p) => patch.region.contains(p) && !cut.contains(p))) {
            next.add(NaturalPaperPatch(Region(cell), patch.color, patch.grain));
          }
        }
        patches = next;
      }
      return List.unmodifiable(patches);
    },
  );

  HarvestResult? preview(CraftPlane plane, Region outline) {
    final patches = <NaturalPaperPatch>[];
    for (final patch in remaining(plane)) {
      if (!patch.region.bounds.overlaps(outline.bounds)) continue;
      for (final cell in slabs([
        patch.region,
        outline,
      ], (p) => patch.region.contains(p) && outline.contains(p))) {
        patches.add(NaturalPaperPatch(Region(cell), patch.color, patch.grain));
      }
    }
    if (patches.fold<double>(0, (v, p) => v + p.region.area) <
        geometryEpsilon) {
      return null;
    }
    return HarvestResult(plane.id, outline, patches);
  }

  void deplete(String id, Region region) {
    (_depleted[id] ??= []).add(region);
    _remaining.remove(id);
    _revisions[id] = revision(id) + 1;
  }

  Map<PaperColor, int> collect(HarvestResult result) {
    final credits = <PaperColor, int>{};
    for (final entry in result.units.entries) {
      final total = remainders[entry.key]! + entry.value;
      final whole = (total + 1e-9).floor();
      credits[entry.key] = whole;
      remainders[entry.key] = (total - whole).clamp(0.0, 1.0);
    }
    deplete(result.planeId, result.outline);
    return credits;
  }

  Map<String, dynamic> toJson() => {
    'seed': seed,
    'preset': preset.name,
    'generationVersion': generationVersion,
    'depleted': {
      for (final e in _depleted.entries)
        e.key: e.value.map((r) => r.toJson()).toList(),
    },
    'remainders': {for (final e in remainders.entries) e.key.id: e.value},
  };

  factory PaperLandscape.fromJson(
    Map<String, dynamic> json,
    Map<String, CraftPlane> planes, {
    WorldPreset preset = WorldPreset.pastel,
  }) {
    if (json['seed'] is! int ||
        json['generationVersion'] != generationVersion) {
      throw const FormatException('Invalid paper landscape version or seed');
    }
    if (json['preset'] != null && json['preset'] != preset.name) {
      throw const FormatException('Landscape preset mismatch');
    }
    final result = PaperLandscape(seed: json['seed'], preset: preset);
    for (final color in preset.materials) {
      final value =
          (json['remainders'][color.id] ?? json['remainders'][color.name]);
      if (value is! num || !value.isFinite || value < 0 || value >= 1) {
        throw const FormatException('Invalid paper remainder');
      }
      result.remainders[color] = value.toDouble();
    }
    for (final entry in (json['depleted'] as Map).entries) {
      final plane = planes[entry.key];
      if (plane == null || !plane.id.startsWith('ground-')) {
        throw const FormatException('Invalid harvested tile');
      }
      for (final encoded in entry.value as List) {
        final region = Region.fromJson(encoded);
        if (region.rings
                .expand((r) => r)
                .any((p) => !p.dx.isFinite || !p.dy.isFinite) ||
            !region.valid ||
            !plane.region.containsRegion(region)) {
          throw const FormatException('Invalid harvested region');
        }
        result.deplete(plane.id, region);
      }
    }
    return result;
  }
}

// Linear scalar clipping on each triangle. Like segment intersection, the
// crossing parameter is a ratio along the edge; a flat edge never divides by 0.
List<(Offset, double)> _clipBand(
  List<(Offset, double)> polygon,
  double level,
  bool above,
) {
  final result = <(Offset, double)>[];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    final insideA = above ? a.$2 >= level : a.$2 <= level;
    final insideB = above ? b.$2 >= level : b.$2 <= level;
    if (insideA) result.add(a);
    if (insideA != insideB) {
      final t = (level - a.$2) / (b.$2 - a.$2);
      result.add((a.$1 + (b.$1 - a.$1) * t, level));
    }
  }
  return result;
}

/// Keep the old nine indices while appending quarter-tile dots. Edges come from
/// the new lattice, so long legacy steps expand through the intermediate dots.
CraftGrid harvestGrid(CraftGrid old, Region region) {
  final fine = lattice(
    old.id,
    region,
    count: 5,
    connections: old.connectionStyle ?? GridConnections.orthogonal,
    recipes: old.recipes,
    name: old.name,
  );
  final nodes = [...old.nodes];
  final remap = <int>[];
  for (final p in fine.nodes) {
    var index = nodes.indexWhere((n) => near(n, p));
    if (index < 0) {
      index = nodes.length;
      nodes.add(p);
    }
    remap.add(index);
  }
  return CraftGrid(
    id: old.id,
    name: old.name,
    connectionStyle: fine.connectionStyle,
    nodes: nodes,
    edges: fine.edges.map((e) => GridEdge(remap[e.a], remap[e.b])).toList(),
    recipes: old.recipes,
    examples: old.examples,
    tiled: old.tiled,
  );
}
