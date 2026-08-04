import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../rendering/iso/iso_coordinate.dart';
import '../../rendering/iso/iso_painter.dart';
import '../../rendering/iso/terrain_height_sampler.dart';
import '../tiles.dart';

/// Provider interface for isometric tiles
abstract class IsoTileProvider {
  Future<List<IsoTileData>> fetchTiles(IsoTileViewport viewport);
}

/// Viewport specification for isometric tile loading
class IsoTileViewport {
  const IsoTileViewport({
    required this.centerX,
    required this.centerY,
    required this.radius,
    this.zoom = 0,
  });

  final int centerX;
  final int centerY;
  final int radius;
  final int zoom; // For compatibility with existing system

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IsoTileViewport &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.radius == radius &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(centerX, centerY, radius, zoom);

  @override
  String toString() =>
      'IsoTileViewport(center: ($centerX, $centerY), radius: $radius, zoom: $zoom)';
}

const Color _defaultGrey = Color(0xFF6B6B6B);

/// Default material IDs when CraftsTechProvider is not loaded.
const List<String> _defaultRawIds = [
  'fm-clay', 'fm-coal', 'fm-cotton', 'fm-sand', 'fm-logs',
  'fm-iron-ore', 'fm-fabric-dye', 'fm-foam-rubber',
];

/// Adapts existing RandomSeedVectorTileProvider to isometric
class IsoRandomSeedTileProvider implements IsoTileProvider {
  IsoRandomSeedTileProvider({
    this.worldSeed = 42,
    this.rawCatalogIds,
    this.materialIdToColor,
    this.terrainSampler,
  });

  final int worldSeed;

  /// When non-null, tiles receive Perlin-noise elevation values.
  final TerrainHeightSampler? terrainSampler;

  /// Material IDs from crafts (raws). When null, uses default subset.
  final List<String>? rawCatalogIds;

  /// Color lookup from crafts. When null, uses fallback greys.
  final Map<String, Color>? materialIdToColor;

  List<String> get _availableMaterials =>
      rawCatalogIds?.isNotEmpty == true ? rawCatalogIds! : _defaultRawIds;

  Color _colorFor(String materialId) =>
      materialIdToColor?[materialId] ?? _defaultGrey;

  @override
  Future<List<IsoTileData>> fetchTiles(IsoTileViewport viewport) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final tiles = <IsoTileData>[];

    for (
      var x = viewport.centerX - viewport.radius;
      x <= viewport.centerX + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.centerY - viewport.radius;
        y <= viewport.centerY + viewport.radius;
        y++
      ) {
        tiles.add(_buildTile(x, y, viewport.zoom));
      }
    }

    return tiles;
  }

  IsoTileData _buildTile(int x, int y, int zoom) {
    final coordinate = IsoCoordinate(x: x, y: y, z: zoom);

    final tileSeed = _hashCoordinate(x, y, 0, worldSeed);
    final random = math.Random(tileSeed);

    final yields = _generateYields(random);

    final dominant = yields.reduce((a, b) => a.amount > b.amount ? a : b);
    final color = _colorFor(dominant.materialId);

    return IsoTileData(
      coordinate: coordinate,
      color: color,
      elevation: terrainSampler?.sample(x, y) ?? 0.0,
      materialId: dominant.materialId,
      materialAmount: dominant.amount,
    );
  }

  List<MaterialYield> _generateYields(math.Random random) {
    final available = _availableMaterials;
    if (available.isEmpty) {
      return [const MaterialYield(materialId: '', amount: 0)];
    }

    final yields = <MaterialYield>[];
    final materialCount = math.min(1 + random.nextInt(3), available.length);
    final shuffled = List<String>.from(available)..shuffle(random);
    final selected = shuffled.take(materialCount).toList();

    const defaultAmount = 20;
    if (selected.length == 1) {
      yields.add(MaterialYield(
        materialId: selected[0],
        amount: defaultAmount,
      ));
    } else if (selected.length == 2) {
      yields.add(MaterialYield(materialId: selected[0], amount: defaultAmount));
      yields.add(MaterialYield(
        materialId: selected[1],
        amount: (defaultAmount * 0.5).round(),
      ));
    } else {
      yields.add(MaterialYield(materialId: selected[0], amount: defaultAmount));
      yields.add(MaterialYield(
        materialId: selected[1],
        amount: (defaultAmount * 0.6).round(),
      ));
      yields.add(MaterialYield(
        materialId: selected[2],
        amount: (defaultAmount * 0.3).round(),
      ));
    }

    return yields;
  }

  int _hashCoordinate(int x, int y, int zoom, int worldSeed) {
    return Object.hash(x, y, zoom, worldSeed);
  }
}

/// Simple flat colored tile provider for testing
class IsoFlatTileProvider implements IsoTileProvider {
  const IsoFlatTileProvider();

  @override
  Future<List<IsoTileData>> fetchTiles(IsoTileViewport viewport) async {
    final tiles = <IsoTileData>[];

    for (
      var x = viewport.centerX - viewport.radius;
      x <= viewport.centerX + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.centerY - viewport.radius;
        y <= viewport.centerY + viewport.radius;
        y++
      ) {
        final color = _colorForCoordinate(x, y);
        tiles.add(
          IsoTileData(
            coordinate: IsoCoordinate(x: x, y: y, z: viewport.zoom),
            color: color,
          ),
        );
      }
    }

    return tiles;
  }

  Color _colorForCoordinate(int x, int y) {
    // Color based only on (x, y) - independent of view direction
    final hue = ((x * 17 + y * 31) % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.5).toColor();
  }
}

/// Checkerboard pattern provider for testing
class IsoCheckerboardTileProvider implements IsoTileProvider {
  const IsoCheckerboardTileProvider({
    this.color1 = const Color(0xFF3E4942),
    this.color2 = const Color(0xFF637368),
  });

  final Color color1;
  final Color color2;

  @override
  Future<List<IsoTileData>> fetchTiles(IsoTileViewport viewport) async {
    final tiles = <IsoTileData>[];

    for (
      var x = viewport.centerX - viewport.radius;
      x <= viewport.centerX + viewport.radius;
      x++
    ) {
      for (
        var y = viewport.centerY - viewport.radius;
        y <= viewport.centerY + viewport.radius;
        y++
      ) {
        final isEven = (x + y) % 2 == 0;
        tiles.add(
          IsoTileData(
            coordinate: IsoCoordinate(x: x, y: y, z: viewport.zoom),
            color: isEven ? color1 : color2,
          ),
        );
      }
    }

    return tiles;
  }
}
