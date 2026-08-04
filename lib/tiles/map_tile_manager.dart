import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/scene.dart';
import 'tile_provider.dart';
import 'tiles.dart';

class MapTileManager {
  MapTileManager({
    required Scene scene,
    required List<TileProvider> tileProviders,
    required this.tileSize,
    required this.heightPerLevel,
  }) : assert(tileProviders.isNotEmpty, 'tileProviders cannot be empty'),
       _scene = scene,
       _tileProviders = List.unmodifiable(tileProviders);

  final Scene _scene;
  final List<TileProvider> _tileProviders;
  final double tileSize;
  final double heightPerLevel;
  final ValueNotifier<List<VectorTile>> tilesNotifier =
      ValueNotifier<List<VectorTile>>(const []);

  static String structureMeshId(
    TileCoordinate coordinate,
    String layerId,
    GeometryFeature feature,
  ) => 'structure_${layerId}_${feature.id}_${coordinate.key}';

  static String surfaceMeshId(
    TileCoordinate coordinate,
    String layerId,
    VectorTileFeature feature,
  ) => '${layerId}_${feature.id}_${coordinate.key}';

  bool _isFetching = false;
  bool _isDisposed = false;
  TileViewport? _pendingViewport;
  TileViewport? _lastAppliedViewport;

  Future<void> updateViewport(TileViewport viewport) async {
    if (_isDisposed) {
      return;
    }
    if (viewport == _lastAppliedViewport) {
      return;
    }
    _pendingViewport = viewport;
    if (_isFetching) {
      return;
    }
    while (_pendingViewport != null && !_isDisposed) {
      final current = _pendingViewport!;
      _pendingViewport = null;
      _isFetching = true;
      final combinedTiles = <VectorTile>[];
      for (final provider in _tileProviders) {
        final tiles = await provider.fetchTiles(current);
        combinedTiles.addAll(tiles);
      }
      if (_isDisposed) {
        return;
      }
      
      // Preserve non-tile meshes (like friends) when updating viewport
      final existingMeshes = _scene.meshes;
      final friendMeshes = existingMeshes
          .where((mesh) => mesh.id.startsWith('friend_'))
          .toList();
      
      final tileMeshes = combinedTiles
          .expand(_buildMeshesForTile)
          .toList(growable: false);
      
      // Add tile meshes first, then friend meshes on top
      _scene.setMeshes([...tileMeshes, ...friendMeshes]);
      
      tilesNotifier.value = List.unmodifiable(combinedTiles);
      _lastAppliedViewport = current;
      _isFetching = false;
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingViewport = null;
    tilesNotifier.dispose();
  }

  Iterable<Mesh> _buildMeshesForTile(VectorTile tile) sync* {
    for (final layer in tile.layers) {
      for (final feature in layer.features) {
        if (feature is YieldTileFeature) {
          yield _buildYieldTileMesh(tile.coordinate, layer.id, feature);
          continue;
        }
        if (feature is TileSurfaceFeature) {
          yield _buildSurfaceMesh(tile.coordinate, layer.id, feature);
          continue;
        }
        if (feature is GeometryFeature) {
          yield _buildStructureMesh(tile.coordinate, layer.id, feature);
        }
      }
    }
  }

  Mesh _buildYieldTileMesh(
    TileCoordinate coordinate,
    String layerId,
    YieldTileFeature feature,
  ) {
    final meshId = surfaceMeshId(coordinate, layerId, feature);
    final geometryId = 'geom_$meshId';
    final vertices = _prismVertices(
      feature.edgeSize,
      feature.height,
      feature.topOffsets,
    );
    final rawGeometry = Geometry(
      id: geometryId,
      name: 'yield-tile-$layerId',
      vertices: vertices,
      faces: _cubeFaces,
    );
    final geometry = ensureOutwardFacingGeometry(rawGeometry);
    final mesh = Mesh(
      id: meshId,
      name: 'Tile ${coordinate.x}/${coordinate.y}',
      geometry: geometry,
      material: MaterialModel(color: feature.color, doubleSided: true),
      highlightOnClick: feature.highlightOnClick,
    );
    final baseX = coordinate.x * tileSize + feature.offset.x;
    final baseZ = coordinate.y * tileSize + feature.offset.y;
    final baseY = coordinate.h * heightPerLevel + feature.elevation;
    mesh.setPosition(Vector3(baseX, baseY, baseZ));
    return mesh;
  }

  Mesh _buildSurfaceMesh(
    TileCoordinate coordinate,
    String layerId,
    TileSurfaceFeature feature,
  ) {
    final meshId = surfaceMeshId(coordinate, layerId, feature);
    final geometryId = 'geom_$meshId';
    final vertices = _prismVertices(
      feature.edgeSize,
      feature.height,
      feature.topOffsets,
    );
    final rawGeometry = Geometry(
      id: geometryId,
      name: 'tile-$layerId',
      vertices: vertices,
      faces: _cubeFaces,
    );
    final geometry = ensureOutwardFacingGeometry(rawGeometry);
    final mesh = Mesh(
      id: meshId,
      name: 'Tile ${coordinate.x}/${coordinate.y}',
      geometry: geometry,
      material: MaterialModel(color: feature.color, doubleSided: true),
      highlightOnClick: feature.highlightOnClick,
    );
    final baseX = coordinate.x * tileSize + feature.offset.x;
    final baseZ = coordinate.y * tileSize + feature.offset.y;
    final baseY = coordinate.h * heightPerLevel + feature.elevation;
    mesh.setPosition(Vector3(baseX, baseY, baseZ));
    return mesh;
  }

  Mesh _buildStructureMesh(
    TileCoordinate coordinate,
    String layerId,
    GeometryFeature feature,
  ) {
    final meshId = structureMeshId(coordinate, layerId, feature);
    final geometry = buildGeometry(feature);
    final mesh = Mesh(
      id: meshId,
      name: 'Structure ${feature.geometry.name}',
      geometry: geometry,
      material: MaterialModel(color: feature.color, doubleSided: true),
      highlightOnClick: feature.highlightOnClick,
    );
    final baseX = coordinate.x * tileSize + feature.offset.x;
    final baseZ = coordinate.y * tileSize + feature.offset.z;
    final baseY =
        coordinate.h * heightPerLevel + feature.elevation + feature.offset.y;
    mesh
      ..setPosition(Vector3(baseX, baseY, baseZ))
      ..setRotation(feature.rotation);
    return mesh;
  }

  List<Vector3> _prismVertices(
    double width,
    double height, [
    List<double>? topOffsets,
  ]) {
    final edge = math.max(1.0, width);
    final clampedHeight = math.max(2.0, height);
    final half = edge / 2;
    final baseVertices = [
      Vector3(-half, 0, -half),
      Vector3(half, 0, -half),
      Vector3(half, 0, half),
      Vector3(-half, 0, half),
    ];
    final topVertices = <Vector3>[];
    if (topOffsets != null && topOffsets.length >= baseVertices.length) {
      for (var i = 0; i < baseVertices.length; i++) {
        final offset = topOffsets[i].clamp(-0.5, 0.5) * clampedHeight;
        final vertex = Vector3.copy(baseVertices[i]);
        vertex.y = clampedHeight + offset;
        topVertices.add(vertex);
      }
    } else {
      for (var i = 0; i < baseVertices.length; i++) {
        final vertex = Vector3.copy(baseVertices[i]);
        vertex.y = clampedHeight;
        topVertices.add(vertex);
      }
    }
    return [...baseVertices, ...topVertices];
  }
}

const List<List<int>> _cubeFaces = <List<int>>[
  [0, 3, 2, 1],
  [4, 5, 6, 7],
  [0, 1, 5, 4],
  [3, 7, 6, 2],
  [1, 2, 6, 5],
  [0, 4, 7, 3],
];
