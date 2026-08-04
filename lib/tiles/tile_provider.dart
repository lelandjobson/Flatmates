import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/prefabs/prefab_factory.dart';
import '../tiles/tiles.dart';

abstract class TileProvider {
  Future<List<VectorTile>> fetchTiles(TileViewport viewport);
}

class MockRandomVectorTileProvider implements TileProvider {
  const MockRandomVectorTileProvider({
    this.tileExtent = 220,
    this.baseThickness = 8,
    this.structureHeightMin = 40,
    this.structureHeightMax = 140,
  });

  final double tileExtent;
  final double baseThickness;
  final double structureHeightMin;
  final double structureHeightMax;

  @override
  Future<List<VectorTile>> fetchTiles(TileViewport viewport) async {
    await Future<void>.delayed(const Duration(milliseconds: 35));

    final tiles = <VectorTile>[];
    for (
      var x = viewport.center.x - viewport.radius;
      x <= viewport.center.x + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.center.y - viewport.radius;
        y <= viewport.center.y + viewport.radius;
        y++
      ) {
        tiles.add(_buildTile(x, y, viewport.zoom));
      }
    }
    return tiles;
  }

  VectorTile _buildTile(int x, int y, int zoom) {
    final seed = Object.hash(x, y, zoom);
    final random = math.Random(seed);
    final heightOffset = random.nextInt(3);
    final coordinate = TileCoordinate(x: x, y: y, z: zoom, h: heightOffset);

    final terrainLayer = VectorTileLayer(
      id: 'terrain',
      features: [
        TileSurfaceFeature(
          id: 'terrain-${coordinate.key}',
          edgeSize: tileExtent,
          height: baseThickness,
          color: _terrainColorFor(coordinate),
          elevation: 0,
        ),
      ],
    );

    final structureFeatures = <VectorTileFeature>[];
    final hasStructures = random.nextDouble() > 0.35;
    if (hasStructures) {
      final structureCount = 1 + random.nextInt(2);
      for (var i = 0; i < structureCount; i++) {
        final id = 'structure_${coordinate.key}_$i';
        final edge =
            tileExtent * (0.25 + random.nextDouble() * 0.35); // 25-60% tile
        final height =
            structureHeightMin +
            random.nextDouble() * (structureHeightMax - structureHeightMin);
        final offsetRange = (tileExtent - edge) / 2.5;
        final offset = Vector2(
          (random.nextDouble() - 0.5) * offsetRange,
          (random.nextDouble() - 0.5) * offsetRange,
        );
        structureFeatures.add(
          TileSurfaceFeature(
            id: id,
            edgeSize: edge,
            height: height,
            elevation: baseThickness,
            color: _structureColorFor(height),
            offset: offset,
          ),
        );
      }
    }

    final layers = [terrainLayer];
    if (structureFeatures.isNotEmpty) {
      layers.add(
        VectorTileLayer(id: 'structures', features: structureFeatures),
      );
    }

    return VectorTile(coordinate: coordinate, layers: layers);
  }

  Color _terrainColorFor(TileCoordinate coordinate) {
    final normalized = (coordinate.x + coordinate.y + coordinate.z) % 4;
    switch (normalized.abs()) {
      case 0:
        return Colors.teal.shade400;
      case 1:
        return Colors.green.shade600;
      case 2:
        return Colors.blueGrey.shade600;
      default:
        return Colors.lightGreen.shade700;
    }
  }

  Color _structureColorFor(double height) {
    final ratio =
        ((height - structureHeightMin) /
                (structureHeightMax - structureHeightMin))
            .clamp(0.0, 1.0);
    final hsl = HSLColor.fromColor(Colors.deepOrangeAccent);
    final adjusted = hsl.withLightness((0.5 + ratio * 0.4).clamp(0.2, 0.9));
    return adjusted.toColor();
  }
}

class MockFlatVectorTileProvider implements TileProvider {
  const MockFlatVectorTileProvider({this.tileExtent = 220});

  final double tileExtent;

  @override
  Future<List<VectorTile>> fetchTiles(TileViewport viewport) async {
    return [
      for (
        var x = viewport.center.x - viewport.radius;
        x <= viewport.center.x + viewport.radius;
        x++
      )
        for (
          var y = viewport.center.y - viewport.radius;
          y <= viewport.center.y + viewport.radius;
          y++
        )
          _buildFlatTile(x, y, viewport.zoom),
    ];
  }

  VectorTile _buildFlatTile(int x, int y, int zoom) {
    final coordinate = TileCoordinate(x: x, y: y, z: zoom, h: 0);
    final color = _colorForCoordinate(coordinate);
    return VectorTile(
      coordinate: coordinate,
      layers: [
        VectorTileLayer(
          id: 'flat',
          features: [
            TileSurfaceFeature(
              id: 'flat-${coordinate.key}',
              edgeSize: tileExtent,
              height: 6,
              color: color,
              elevation: 0,
            ),
          ],
        ),
      ],
    );
  }

  Color _colorForCoordinate(TileCoordinate coordinate) {
    final hue = ((coordinate.x * 17 + coordinate.y * 31) % 360).toDouble();
    final saturation = 0.45 + ((coordinate.z % 5) * 0.05);
    final lightness = 0.45 + ((coordinate.h % 3) * 0.04);
    return HSLColor.fromAHSL(
      1,
      hue,
      saturation.clamp(0.35, 0.8),
      lightness.clamp(0.35, 0.75),
    ).toColor();
  }
}

class LandscapeTileProvider implements TileProvider {
  LandscapeTileProvider({this.tileExtent = 220, this.maxHeight = 18});

  final double tileExtent;
  final double maxHeight;

  @override
  Future<List<VectorTile>> fetchTiles(TileViewport viewport) async {
    final tiles = <VectorTile>[];
    for (
      var x = viewport.center.x - viewport.radius;
      x <= viewport.center.x + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.center.y - viewport.radius;
        y <= viewport.center.y + viewport.radius;
        y++
      ) {
        tiles.add(_buildTile(x, y, viewport.zoom));
      }
    }
    return tiles;
  }

  VectorTile _buildTile(int x, int y, int zoom) {
    final coordinate = TileCoordinate(x: x, y: y, z: zoom, h: 0);
    final color = _colorForCoordinate(coordinate);
    final offsets = _topOffsetsForCoordinate(coordinate);
    return VectorTile(
      coordinate: coordinate,
      layers: [
        VectorTileLayer(
          id: 'landscape',
          features: [
            TileSurfaceFeature(
              id: 'landscape-${coordinate.key}',
              edgeSize: tileExtent,
              height: maxHeight,
              color: color,
              elevation: 0,
              topOffsets: offsets,
            ),
          ],
        ),
      ],
    );
  }

  List<double> _topOffsetsForCoordinate(TileCoordinate coordinate) {
    final offsets = <double>[];
    final seed = Object.hash(coordinate.x, coordinate.y, coordinate.z);
    final random = math.Random(seed);
    for (var i = 0; i < 4; i++) {
      final value = (random.nextDouble() - 0.5);
      offsets.add(value.clamp(-0.5, 0.5));
    }
    return offsets;
  }

  Color _colorForCoordinate(TileCoordinate coordinate) {
    final normalized = ((coordinate.x + coordinate.y) % 6).abs();
    switch (normalized) {
      case 0:
        return Colors.green.shade600;
      case 1:
        return Colors.green.shade500;
      case 2:
        return Colors.lightGreen.shade600;
      case 3:
        return Colors.teal.shade400;
      case 4:
        return Colors.teal.shade500;
      default:
        return Colors.blueGrey.shade500;
    }
  }
}

class MockStructureTileProvider implements TileProvider {
  const MockStructureTileProvider();

  static const List<_StructureDefinition> _structures = <_StructureDefinition>[
    _StructureDefinition(
      coordinate: TileCoordinate(x: 0, y: 0, z: 0),
      geometry: GeometryPrefabs.house,
      scale: 0.9,
      color: Colors.orangeAccent,
    ),
    _StructureDefinition(
      coordinate: TileCoordinate(x: 20, y: 0, z: 0),
      geometry: GeometryPrefabs.cube,
      scale: 0.6,
      color: Colors.cyanAccent,
    ),
    _StructureDefinition(
      coordinate: TileCoordinate(x: 5, y: -15, z: 0),
      geometry: GeometryPrefabs.cube,
      scale: 0.7,
      color: Colors.deepPurpleAccent,
    ),
    _StructureDefinition(
      coordinate: TileCoordinate(x: 2, y: 3, z: 0),
      geometry: GeometryPrefabs.frog,
      scale: 0.85,
      color: Colors.lightGreenAccent,
    ),
  ];

  @override
  Future<List<VectorTile>> fetchTiles(TileViewport viewport) async {
    final tiles = <VectorTile>[];
    final radius = viewport.radius + 1;
    for (final structure in _structures) {
      final dx = (structure.coordinate.x - viewport.center.x).abs();
      final dy = (structure.coordinate.y - viewport.center.y).abs();
      if (dx > radius || dy > radius) {
        continue;
      }
      tiles.add(
        VectorTile(
          coordinate: TileCoordinate(
            x: structure.coordinate.x,
            y: structure.coordinate.y,
            z: viewport.zoom,
            h: structure.coordinate.h,
          ),
          layers: [
            VectorTileLayer(
              id: 'structures',
              features: [
                GeometryFeature(
                  id: 'structure_${structure.coordinate.x}_${structure.coordinate.y}_${structure.geometry.name}',
                  geometry: structure.geometry,
                  scale: structure.scale,
                  color: structure.color ?? Colors.white,
                ),
              ],
            ),
          ],
        ),
      );
    }
    return tiles;
  }
}

class _StructureDefinition {
  const _StructureDefinition({
    required this.coordinate,
    required this.geometry,
    this.scale = 1.0,
    this.color,
  });

  final TileCoordinate coordinate;
  final GeometryPrefabs geometry;
  final double scale;
  final Color? color;
}

/// Tile provider that uses a seeded random generator for deterministic tile generation
class RandomSeedVectorTileProvider implements TileProvider {
  RandomSeedVectorTileProvider({
    this.tileExtent = 220,
    this.maxHeight = 18,
    this.worldSeed = 42,
  });

  final double tileExtent;
  final double maxHeight;
  final int worldSeed;

  static const List<String> _defaultRawIds = [
    'fm-clay', 'fm-coal', 'fm-cotton', 'fm-sand', 'fm-logs',
    'fm-iron-ore', 'fm-fabric-dye', 'fm-foam-rubber',
  ];

  static const Map<String, Color> _defaultColors = {
    'fm-clay': Color(0xFFBF8040),
    'fm-coal': Color(0xFF424242),
    'fm-cotton': Color(0xFFE8DFD4),
    'fm-sand': Color(0xFFD4B896),
    'fm-logs': Color(0xFF795548),
    'fm-iron-ore': Color(0xFF78909C),
    'fm-fabric-dye': Color(0xFF9C27B0),
    'fm-foam-rubber': Color(0xFFBDBDBD),
  };

  @override
  Future<List<VectorTile>> fetchTiles(TileViewport viewport) async {
    final tiles = <VectorTile>[];
    for (
      var x = viewport.center.x - viewport.radius;
      x <= viewport.center.x + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.center.y - viewport.radius;
        y <= viewport.center.y + viewport.radius;
        y++
      ) {
        tiles.add(_buildTile(x, y, viewport.zoom));
      }
    }
    return tiles;
  }

  VectorTile _buildTile(int x, int y, int zoom) {
    final coordinate = TileCoordinate(x: x, y: y, z: zoom, h: 0);

    // Create deterministic seed for this tile
    final tileSeed = _hashCoordinate(x, y, zoom, worldSeed);
    final random = math.Random(tileSeed);

    // Generate material yields for this tile
    final yields = _generateYields(random);

    final dominant = yields.reduce((a, b) => a.amount > b.amount ? a : b);
    final color = _defaultColors[dominant.materialId] ??
        const Color(0xFF6B6B6B);

    // Generate height variation
    final offsets = _generateTopOffsets(random);

    return VectorTile(
      coordinate: coordinate,
      layers: [
        VectorTileLayer(
          id: 'yield_terrain',
          features: [
            YieldTileFeature(
              id: 'yield-${coordinate.key}',
              edgeSize: tileExtent,
              height: maxHeight,
              color: color,
              elevation: 0,
              topOffsets: offsets,
              yields: yields,
            ),
          ],
        ),
      ],
    );
  }

  List<MaterialYield> _generateYields(math.Random random) {
    final available = _defaultRawIds;
    if (available.isEmpty) {
      return [const MaterialYield(materialId: '', amount: 0)];
    }
    final yields = <MaterialYield>[];
    final materialCount = math.min(1 + random.nextInt(3), available.length);
    final shuffled = List<String>.from(available)..shuffle(random);
    final selected = shuffled.take(materialCount).toList();

    if (selected.length == 1) {
      yields.add(MaterialYield(
        materialId: selected[0],
        amount: 60 + random.nextInt(41),
      ));
    } else if (selected.length == 2) {
      final dominant = 40 + random.nextInt(51);
      final secondary = math.min(100 - dominant, 20 + random.nextInt(31));
      yields.add(MaterialYield(materialId: selected[0], amount: dominant));
      yields.add(MaterialYield(materialId: selected[1], amount: secondary));
    } else {
      final first = 30 + random.nextInt(41);
      final second = 20 + random.nextInt(31);
      final third = 10 + random.nextInt(21);
      yields.add(MaterialYield(materialId: selected[0], amount: first));
      yields.add(MaterialYield(materialId: selected[1], amount: second));
      yields.add(MaterialYield(materialId: selected[2], amount: third));
    }
    return yields;
  }

  /// Generate height offsets for tile corners
  List<double> _generateTopOffsets(math.Random random) {
    final offsets = <double>[];
    for (var i = 0; i < 4; i++) {
      final value = (random.nextDouble() - 0.5);
      offsets.add(value.clamp(-0.5, 0.5));
    }
    return offsets;
  }

  /// Create a deterministic hash for a coordinate
  int _hashCoordinate(int x, int y, int zoom, int worldSeed) {
    return Object.hash(x, y, zoom, worldSeed);
  }
}
