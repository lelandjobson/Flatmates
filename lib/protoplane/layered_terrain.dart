import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';
import 'geometry.dart';
import 'models.dart';
import 'spatial_index.dart';
import 'graphite_eraser.dart';

Region shiftedRegion(Region region, Offset delta) => Region(
  region.outer.map((p) => p + delta).toList(),
  region.holes.map((r) => r.map((p) => p + delta).toList()).toList(),
);

/// A sheet owns material and depletion. Tiles are only stable editing windows.
class TerrainSheet {
  TerrainSheet(
    this.id,
    this.island,
    this.material,
    this.footprint,
    this.elevation,
    this.thickness,
  );
  final String id, island;
  final PaperMaterial material;
  final Region footprint;
  final double elevation, thickness;
  final List<Region> cuts = [];
  final Map<String, GraphiteMask> erased = {};
  int revision = 0;
  List<Region>? _remaining;
  List<Region> get remaining => _remaining ??= cuts.fold<List<Region>>([
    footprint,
  ], (regions, cut) => regions.expand((r) => r.subtract(cut)).toList());
  void deplete(Region cut) {
    cuts.add(cut);
    _remaining = null;
    revision++;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'island': island,
    'material': material.id,
    'footprint': footprint.toJson(),
    'elevation': elevation,
    'thickness': thickness,
    'cuts': cuts.map((r) => r.toJson()).toList(),
    if (erased.isNotEmpty)
      'eraser': {
        'version': 1,
        'tiles': {
          for (final e in erased.entries) e.key: base64Encode(e.value.bytes),
        },
      },
  };
}

class TerrainTile {
  TerrainTile(this.sheet, this.x, this.y);
  final TerrainSheet sheet;
  final int x, y;
  String get id => 'ground-${sheet.id}-$x-$y';
  String get maskKey => '$x,$y';
  Offset get origin => Offset(x.toDouble(), y.toDouble());
  Region get bounds => shiftedRegion(rectangle(1, 1), origin);
  CraftPlane plane({int count = 5}) {
    final region = rectangle(1, 1);
    return CraftPlane(
      id: id,
      origin: Vector3(x.toDouble(), sheet.elevation, -y.toDouble()),
      u: Vector3(1, 0, 0),
      v: Vector3(0, 0, -1),
      region: region,
      grids: [lattice(id, region, count: count, name: sheet.material.label)],
    );
  }
}

class LayeredTerrain {
  LayeredTerrain(this.sheets) {
    for (final sheet in sheets) {
      final box = sheet.footprint.bounds;
      for (var y = box.top.floor(); y < box.bottom.ceil(); y++) {
        for (var x = box.left.floor(); x < box.right.ceil(); x++) {
          final tile = TerrainTile(sheet, x, y);
          if (_clip([sheet.footprint], tile.bounds).isNotEmpty) {
            tiles[tile.id] = tile;
          }
        }
      }
    }
    index = CraftSpatialIndex({
      for (final t in tiles.values)
        t.id: craftBounds(
          t.bounds.outer.expand(
            (p) => [
              Vector3(p.dx, t.sheet.elevation, -p.dy),
              Vector3(p.dx, t.sheet.elevation - t.sheet.thickness, -p.dy),
            ],
          ),
        ),
    });
  }
  final List<TerrainSheet> sheets;
  final Map<String, TerrainTile> tiles = {};
  late final CraftSpatialIndex<String> index;
  final Map<String, List<Region>> _exposed = {}, _tileRemaining = {};
  final Map<String, int> _revisions = {};
  final Map<String, String> _signatures = {}, _wallSignatures = {};
  String signature(String id) => _signatures.putIfAbsent(id, () {
    final tile = tiles[id]!;
    return jsonEncode([
      for (final s in sheets.where(
        (s) =>
            s.island == tile.sheet.island &&
            s.elevation >= tile.sheet.elevation,
      ))
        [
          s.id,
          s.material.id,
          s.footprint.toJson(),
          s.elevation,
          s.thickness,
          if (s.erased[tile.maskKey] case final mask?) base64Encode(mask.bytes),
          for (final cut in s.cuts.where(
            (r) => r.bounds.overlaps(tile.bounds.bounds),
          ))
            cut.toJson(),
        ],
    ]);
  });
  int revision(String id) => _revisions[id] ?? 0;

  factory LayeredTerrain.starter() {
    List<TerrainSheet> stack(
      String island,
      double side,
      double degrees,
      Offset center,
    ) {
      final result = <TerrainSheet>[];
      var previousAngle = degrees, elevation = 0.0;
      for (var i = 0; i < 3; i++) {
        final angle = degrees + [0, -2, 2][i];
        if (i > 0) {
          final delta = (angle - previousAngle).abs() * math.pi / 180;
          side = side * (math.cos(delta) + math.sin(delta)) + .2;
        }
        final radians = angle * math.pi / 180;
        final region = Region([
          for (final p in [
            Offset(-side / 2, -side / 2),
            Offset(side / 2, -side / 2),
            Offset(side / 2, side / 2),
            Offset(-side / 2, side / 2),
          ])
            center +
                Offset(
                  p.dx * math.cos(radians) - p.dy * math.sin(radians),
                  p.dx * math.sin(radians) + p.dy * math.cos(radians),
                ),
        ]);
        final thickness = [.03, .06, .18][i];
        result.add(
          TerrainSheet(
            '$island-${paperMaterials[i].name}',
            island,
            paperMaterials[i],
            region,
            elevation,
            thickness,
          ),
        );
        elevation -= thickness;
        previousAngle = angle;
      }
      return result;
    }

    final first = stack('starter', 5, 4, Offset.zero);
    final second = stack('northeast', 8, -3, Offset.zero);
    final a = first.last.footprint.bounds, b = second.last.footprint.bounds;
    final shift = Offset(a.right + 2 - b.left, a.bottom + 2 - b.top);
    return LayeredTerrain([
      ...first,
      for (final s in second)
        TerrainSheet(
          s.id,
          s.island,
          s.material,
          shiftedRegion(s.footprint, shift),
          s.elevation,
          s.thickness,
        ),
    ]);
  }

  static List<Region> _clip(List<Region> regions, Region window) => [
    for (final r in regions)
      if (r.bounds.overlaps(window.bounds))
        for (final cell in slabs([
          r,
          window,
        ], (p) => r.contains(p) && window.contains(p)))
          if (Region(cell).area > geometryEpsilon) Region(cell),
  ];

  /// Local tile coordinates. Higher sheets mask lower ones, including at rims.
  List<Region> exposed(String id) => _exposed.putIfAbsent(id, () {
    final tile = tiles[id];
    if (tile == null) return [];
    var visible = remainingInTile(
      id,
    ).map((r) => shiftedRegion(r, tile.origin)).toList();
    for (final above in sheets.where(
      (s) =>
          s.island == tile.sheet.island && s.elevation > tile.sheet.elevation,
    )) {
      final aboveTile = TerrainTile(above, tile.x, tile.y);
      for (final region in remainingInTile(
        aboveTile.id,
      ).map((r) => shiftedRegion(r, tile.origin))) {
        visible = visible.expand((r) => r.subtract(region)).toList();
      }
    }
    return [for (final r in visible) shiftedRegion(r, -tile.origin)];
  });

  List<Region> remainingInTile(String id) => _tileRemaining.putIfAbsent(id, () {
    final tile = tiles[id];
    if (tile == null) return [];
    final base = _clip(
      tile.sheet.remaining,
      tile.bounds,
    ).map((r) => shiftedRegion(r, -tile.origin)).toList();
    final mask = tile.sheet.erased[tile.maskKey];
    if (mask == null) return base;
    return [
      for (final rect in mask.rectangles())
        ...intersectRegions(base, rectRegion(rect)),
    ];
  });

  /// A mask edit invalidates only the selected column, not the whole sheet.
  void erase(String id, List<int> cells) {
    if (cells.isEmpty) return;
    final tile = tiles[id]!;
    if (tile.sheet.material != PaperMaterial.graphite) {
      throw StateError('Not graphite');
    }
    final mask = tile.sheet.erased.putIfAbsent(tile.maskKey, GraphiteMask.new);
    for (final i in cells) {
      mask.remove(i);
    }
    _invalidateColumn(tile);
  }

  String wallSignature(String id) => _wallSignatures.putIfAbsent(id, () {
    final tile = tiles[id]!;
    return jsonEncode([
      tile.sheet.footprint.toJson(),
      for (final cut in tile.sheet.cuts.where(
        (c) => c.bounds.overlaps(tile.bounds.bounds),
      ))
        cut.toJson(),
      for (final offset in [
        Offset.zero,
        const Offset(-1, 0),
        const Offset(1, 0),
        const Offset(0, -1),
        const Offset(0, 1),
      ])
        base64Encode(
          tile
                  .sheet
                  .erased['${tile.x + offset.dx.toInt()},${tile.y + offset.dy.toInt()}']
                  ?.bytes ??
              [],
        ),
    ]);
  });

  bool supports(String id, Region region) {
    var uncovered = [region];
    for (final surface in exposed(id)) {
      uncovered = uncovered.expand((r) => r.subtract(surface)).toList();
    }
    return uncovered.fold<double>(0, (a, r) => a + r.area) < geometryEpsilon;
  }

  void deplete(String id, Region local) {
    final tile = tiles[id]!;
    tile.sheet.deplete(shiftedRegion(local, tile.origin));
    _invalidateColumn(tile);
  }

  void _invalidateColumn(TerrainTile tile) {
    for (final other in tiles.values.where(
      (t) =>
          identical(t.sheet, tile.sheet) &&
          (t.x - tile.x).abs() + (t.y - tile.y).abs() <= 1,
    )) {
      _wallSignatures.remove(other.id);
    }
    // Only this XY column changes exposure; upper-layer cuts cannot alter neighbors.
    final column = MapAabb(
      Vector3(
        tile.x.toDouble(),
        sheets.map((s) => s.elevation - s.thickness).reduce(math.min),
        -tile.y - 1.0,
      ),
      Vector3(
        tile.x + 1.0,
        sheets.map((s) => s.elevation).reduce(math.max),
        -tile.y.toDouble(),
      ),
    );
    for (final other
        in index
            .query(column)
            .map((id) => tiles[id]!)
            .where(
              (t) =>
                  t.x == tile.x &&
                  t.y == tile.y &&
                  t.sheet.island == tile.sheet.island,
            )) {
      _tileRemaining.remove(other.id);
      _exposed.remove(other.id);
      _signatures.remove(other.id);
      _revisions[other.id] = revision(other.id) + 1;
    }
  }

  String? nextExposed(String id) {
    final t = tiles[id];
    if (t == null) return null;
    if (exposed(id).isNotEmpty) return id;
    return tiles.values
        .where(
          (o) =>
              o.x == t.x &&
              o.y == t.y &&
              o.sheet.island == t.sheet.island &&
              exposed(o.id).isNotEmpty,
        )
        .map((o) => o.id)
        .firstOrNull;
  }

  List<Map<String, dynamic>> toJson() => sheets.map((s) => s.toJson()).toList();
  factory LayeredTerrain.fromJson(List<dynamic> json) {
    if (json.isEmpty || json.length > 64) {
      throw const FormatException('Invalid terrain sheets');
    }
    final sheets = <TerrainSheet>[];
    for (final j in json) {
      final region = Region.fromJson(j['footprint']);
      final elevation = j['elevation'], thickness = j['thickness'];
      final material = PaperMaterial.decode(j['material']);
      if (j['id'] is! String ||
          j['island'] is! String ||
          sheets.any((s) => s.id == j['id']) ||
          !paperMaterials.contains(material) ||
          !region.valid ||
          region.rings
              .expand((r) => r)
              .any(
                (p) => !p.dx.isFinite || !p.dy.isFinite || p.distance > 1000,
              ) ||
          region.bounds.width > 64 ||
          region.bounds.height > 64 ||
          elevation is! num ||
          !elevation.isFinite ||
          elevation.abs() > 100 ||
          thickness is! num ||
          !thickness.isFinite ||
          thickness <= 0 ||
          thickness > 10) {
        throw const FormatException('Invalid terrain sheet');
      }
      final sheet = TerrainSheet(
        j['id'],
        j['island'],
        material,
        region,
        elevation.toDouble(),
        thickness.toDouble(),
      );
      for (final c in j['cuts'] as List) {
        final cut = Region.fromJson(c);
        if (!cut.valid ||
            cut.rings
                .expand((r) => r)
                .any((p) => !p.dx.isFinite || !p.dy.isFinite) ||
            !region.containsRegion(cut)) {
          throw const FormatException('Invalid layer depletion');
        }
        sheet.deplete(cut);
      }
      final eraser = j['eraser'];
      if (eraser != null) {
        if (material != PaperMaterial.graphite ||
            eraser is! Map ||
            eraser['version'] != 1 ||
            eraser['tiles'] is! Map) {
          throw const FormatException('Invalid graphite eraser');
        }
        for (final entry in (eraser['tiles'] as Map).entries) {
          if (entry.key is! String ||
              !RegExp(r'^-?\d+,-?\d+$').hasMatch(entry.key) ||
              entry.value is! String) {
            throw const FormatException('Invalid graphite tile mask');
          }
          final bytes = base64Decode(entry.value);
          if (bytes.length != GraphiteMask.byteCount) {
            throw const FormatException('Invalid graphite mask size');
          }
          sheet.erased[entry.key] = GraphiteMask(bytes);
        }
      }
      sheets.add(sheet);
    }
    final terrain = LayeredTerrain(sheets);
    for (final sheet in sheets) {
      for (final above in sheets.where(
        (s) => s.island == sheet.island && s.elevation > sheet.elevation,
      )) {
        if (above.elevation - above.thickness <
            sheet.elevation - geometryEpsilon) {
          throw const FormatException('Terrain layers intersect');
        }
        for (final cut in sheet.cuts) {
          if (terrain.tiles.values
              .where(
                (t) =>
                    identical(t.sheet, above) &&
                    t.bounds.bounds.overlaps(cut.bounds),
              )
              .any(
                (t) => terrain
                    .remainingInTile(t.id)
                    .any((r) => shiftedRegion(r, t.origin).overlaps(cut)),
              )) {
            throw const FormatException(
              'Depleted material is covered by an intact layer',
            );
          }
        }
      }
      if (sheets.any(
        (s) =>
            s != sheet &&
            s.island == sheet.island &&
            s.elevation == sheet.elevation,
      )) {
        throw const FormatException('Duplicate terrain elevation');
      }
    }
    for (final tile in terrain.tiles.values.where(
      (t) => t.sheet.material == PaperMaterial.graphite,
    )) {
      final mask = tile.sheet.erased[tile.maskKey];
      if (mask == null) continue;
      final base = _clip(
        tile.sheet.remaining,
        tile.bounds,
      ).map((r) => shiftedRegion(r, -tile.origin)).toList();
      final above = [
        for (final s in sheets.where(
          (s) =>
              s.island == tile.sheet.island &&
              s.elevation > tile.sheet.elevation,
        ))
          ..._clip(
            s.remaining,
            tile.bounds,
          ).map((r) => shiftedRegion(r, -tile.origin)),
      ];
      for (var i = 0; i < GraphiteMask.count; i++) {
        if (!mask.removed(i)) continue;
        final fragments = intersectRegions(
          base,
          rectRegion(GraphiteMask.cell(i)),
        );
        if (fragments.isEmpty || above.any((r) => fragments.any(r.overlaps))) {
          throw const FormatException('Erased graphite is absent or covered');
        }
      }
    }
    for (final sheet in sheets) {
      for (final key in sheet.erased.keys) {
        if (!terrain.tiles.values.any(
          (t) => identical(t.sheet, sheet) && t.maskKey == key,
        )) {
          throw const FormatException('Unknown graphite mask tile');
        }
      }
    }
    return terrain;
  }
}
