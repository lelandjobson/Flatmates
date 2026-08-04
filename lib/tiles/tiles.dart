import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/prefabs/prefab_factory.dart';

class TileCoordinate {
  const TileCoordinate({
    required this.x,
    required this.y,
    required this.z,
    this.h = 0,
  });

  final int x;
  final int y;
  final int z;
  final int h;

  String get key => '$x:$y:$z:$h';

  TileCoordinate copyWith({int? x, int? y, int? z, int? h}) {
    return TileCoordinate(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      h: h ?? this.h,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TileCoordinate &&
        other.x == x &&
        other.y == y &&
        other.z == z &&
        other.h == h;
  }

  @override
  int get hashCode => Object.hash(x, y, z, h);

  @override
  String toString() => 'TileCoordinate($x, $y, z=$z, h=$h)';
}

class TileViewport {
  const TileViewport({
    required this.center,
    required this.radius,
    required this.zoom,
  });

  final TileCoordinate center;
  final int radius;
  final int zoom;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TileViewport &&
        other.center == center &&
        other.radius == radius &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(center, radius, zoom);
}

class VectorTile {
  const VectorTile({required this.coordinate, required this.layers});

  final TileCoordinate coordinate;
  final List<VectorTileLayer> layers;
}

class VectorTileLayer {
  const VectorTileLayer({required this.id, required this.features});

  final String id;
  final List<VectorTileFeature> features;
}

abstract class VectorTileFeature {
  const VectorTileFeature({required this.id, this.highlightOnClick = true});

  final String id;
  final bool highlightOnClick;
}

class TileSurfaceFeature extends VectorTileFeature {
  TileSurfaceFeature({
    required super.id,
    bool highlightOnClick = true,
    required this.edgeSize,
    required this.height,
    required this.color,
    this.elevation = 0,
    List<double>? topOffsets,
    Vector2? offset,
  }) : offset = offset ?? Vector2.zero(),
       topOffsets = topOffsets,
       super(highlightOnClick: highlightOnClick);

  final double edgeSize;
  final double height;
  final double elevation;
  final Vector2 offset;
  final Color color;
  final List<double>? topOffsets;
}

class GeometryFeature extends VectorTileFeature {
  GeometryFeature({
    required super.id,
    bool highlightOnClick = true,
    required this.geometry,
    this.scale = 1.0,
    Vector3? offset,
    Vector3? rotation,
    this.elevation = 0,
    Color? color,
  }) : offset = offset ?? Vector3.zero(),
       rotation = rotation ?? Vector3.zero(),
       color = color ?? Colors.white,
       super(highlightOnClick: highlightOnClick);

  final GeometryPrefabs geometry;
  final double scale;
  final Vector3 offset;
  final Vector3 rotation;
  final double elevation;
  final Color color;
}

class GeometryInstance {
  const GeometryInstance({
    required this.coordinate,
    required this.feature,
    required this.layerId,
  });

  final TileCoordinate coordinate;
  final GeometryFeature feature;
  final String layerId;
}

/// Sentinel for "no material" (empty tile).
const String kNoMaterialId = '';

/// Represents a material yield on a tile. Material IDs come from crafts.json.
class MaterialYield {
  const MaterialYield({required this.materialId, required this.amount})
    : assert(amount >= 0 && amount <= 100, 'Yield must be between 0 and 100');

  final String materialId;
  final int amount;

  MaterialYield copyWith({String? materialId, int? amount}) {
    return MaterialYield(
      materialId: materialId ?? this.materialId,
      amount: amount ?? this.amount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MaterialYield &&
        other.materialId == materialId &&
        other.amount == amount;
  }

  @override
  int get hashCode => Object.hash(materialId, amount);
}

/// Feature that stores material yields for a tile
class YieldTileFeature extends VectorTileFeature {
  YieldTileFeature({
    required super.id,
    bool highlightOnClick = true,
    required this.yields,
    required this.edgeSize,
    required this.height,
    required this.color,
    this.elevation = 0,
    Vector2? offset,
    List<double>? topOffsets,
  }) : assert(yields.isNotEmpty, 'Tile must have at least one material yield'),
       offset = offset ?? Vector2.zero(),
       topOffsets = topOffsets,
       super(highlightOnClick: highlightOnClick);

  final List<MaterialYield> yields;
  final double edgeSize;
  final double height;
  final Color color;
  final double elevation;
  final Vector2 offset;
  final List<double>? topOffsets;

  /// Get the dominant material ID (highest yield)
  String get dominantMaterialId {
    return yields.reduce((a, b) => a.amount > b.amount ? a : b).materialId;
  }

  /// Get the yield amount for a specific material
  int getYieldFor(String materialId) {
    final yield = yields.firstWhere(
      (y) => y.materialId == materialId,
      orElse: () => MaterialYield(materialId: materialId, amount: 0),
    );
    return yield.amount;
  }

  /// Create a copy with updated yields
  YieldTileFeature copyWithYields(List<MaterialYield> newYields) {
    return YieldTileFeature(
      id: id,
      highlightOnClick: highlightOnClick,
      yields: newYields,
      edgeSize: edgeSize,
      height: height,
      color: color,
      elevation: elevation,
      offset: offset,
      topOffsets: topOffsets,
    );
  }

  /// Create a copy with updated color (e.g., when theme changes)
  YieldTileFeature copyWithColor(Color newColor) {
    return YieldTileFeature(
      id: id,
      highlightOnClick: highlightOnClick,
      yields: yields,
      edgeSize: edgeSize,
      height: height,
      color: newColor,
      elevation: elevation,
      offset: offset,
      topOffsets: topOffsets,
    );
  }
}
