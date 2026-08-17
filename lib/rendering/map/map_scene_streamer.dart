import 'dart:async';

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import '../scene/scene.dart';
import 'map_aabb.dart';
import 'map_octree.dart';
import 'map_placement.dart';

/// Attaches placement meshes to [scene] when they enter a load window and
/// detaches them past an unload radius. Template geometry is shared.
class MapSceneStreamer {
  MapSceneStreamer({
    required this.scene,
    required this.octree,
    required this.tileSize,
    required this.tilesSide,
    this.loadPadding = 2,
    this.unloadPadding = 2,
  });

  final Scene scene;
  final MapOctree octree;
  final double tileSize;
  final int tilesSide;
  final int loadPadding;
  final int unloadPadding;

  final Map<int, MapPlacement> placements = {};
  List<Mesh> template = const [];

  final Set<int> _loaded = {};
  final Map<int, List<String>> _meshIds = {};
  int _syncGen = 0;

  int get drawnCount => _loaded.length;
  int get placedCount => placements.length;

  double get _mapHalf => tilesSide * tileSize * 0.5;

  void place(MapPlacement placement) {
    placements[placement.id] = placement;
    octree.insert(
      placement.id,
      MapAabb.tile(
        tx: placement.tx,
        ty: placement.ty,
        tileSize: tileSize,
        mapHalf: _mapHalf,
      ),
    );
  }

  /// Query the octree around [lookTx],[lookTy] and attach/detach instances.
  Future<void> sync({
    required int lookTx,
    required int lookTy,
    required int drawRadius,
  }) async {
    final gen = ++_syncGen;
    final loadRadius = drawRadius + loadPadding;
    final unloadRadius = loadRadius + unloadPadding;

    final tx0 = (lookTx - loadRadius).clamp(0, tilesSide - 1);
    final ty0 = (lookTy - loadRadius).clamp(0, tilesSide - 1);
    final tx1 = (lookTx + loadRadius).clamp(0, tilesSide - 1);
    final ty1 = (lookTy + loadRadius).clamp(0, tilesSide - 1);
    final ids = octree.query(
      MapAabb.tiles(
        tx0: tx0,
        ty0: ty0,
        tx1: tx1,
        ty1: ty1,
        tileSize: tileSize,
        mapHalf: _mapHalf,
      ),
    );

    final inLoad = ids.toSet();
    final toUnload = <int>[
      for (final id in _loaded)
        if (!_inChebyshev(id, lookTx, lookTy, unloadRadius)) id,
    ];
    for (final id in toUnload) {
      _detach(id);
    }

    for (final id in inLoad) {
      if (gen != _syncGen) return;
      if (_loaded.contains(id)) continue;
      _attach(id);
      await Future<void>.delayed(Duration.zero);
    }
  }

  bool _inChebyshev(int id, int lookTx, int lookTy, int radius) {
    final p = placements[id];
    if (p == null) return false;
    final dx = (p.tx - lookTx).abs();
    final dy = (p.ty - lookTy).abs();
    return dx <= radius && dy <= radius;
  }

  void _attach(int id) {
    final placement = placements[id];
    if (placement == null || template.isEmpty) return;
    final meshes = [
      for (final t in template)
        Mesh(
          id: '${placement.craftName}_${placement.id}_${t.id}',
          name: t.name,
          geometry: t.geometry,
          material: t.material,
          position: Vector3.copy(placement.origin),
        ),
    ];
    scene.addMeshes(meshes);
    _meshIds[id] = [for (final m in meshes) m.id];
    _loaded.add(id);
  }

  void _detach(int id) {
    final ids = _meshIds.remove(id);
    _loaded.remove(id);
    if (ids == null) return;
    for (final meshId in ids) {
      scene.removeMeshById(meshId);
    }
  }
}
