part of 'controller.dart';

final _orthogonalGrids = Expando<CraftGrid>();

CraftGrid orthogonalGrid(CraftGrid grid) =>
    _orthogonalGrids[grid] ??= CraftGrid(
      id: grid.id,
      name: grid.name,
      nodes: grid.nodes,
      recipes: grid.recipes,
      examples: grid.examples,
      tiled: grid.tiled,
      connectionStyle: GridConnections.orthogonal,
      edges: grid.edges.where((edge) {
        final delta = grid.nodes[edge.a] - grid.nodes[edge.b];
        return edge.control == null &&
            (delta.dx.abs() < geometryEpsilon ||
                delta.dy.abs() < geometryEpsilon);
      }).toList(),
    );

/// A stable support frame spanning connected, exposed, coplanar terrain.
/// Physical tiles keep their own material, depletion and persistence identity.
extension LandscapeDrawing on ProtoplaneController {
  bool get sharedLandscapeFocus =>
      activePlaneId?.startsWith('landscape-drawing-') == true;

  CraftGrid? get orthogonalDrawingGrid {
    final plane = activePlane;
    if (plane == null) return null;
    return plane.grids[gridIndex.clamp(0, plane.grids.length - 1)];
  }

  Region _inFrame(Region region, CraftPlane source, CraftPlane target) =>
      Region(
        region.outer.map((p) => target.local(source.point(p))).toList(),
        region.holes
            .map(
              (ring) => ring.map((p) => target.local(source.point(p))).toList(),
            )
            .toList(),
      );

  void _enterLandscapeDrawing(String tileId) {
    if (!inPlaceDrawing) return;
    final tile = landscape.terrain.tiles[tileId];
    final basis = planes[tileId];
    if (tile == null || basis == null) return;
    final exposed = surfaceRegions(basis);
    // Disconnected remnants remain separate supports.
    if (exposed.length != 1) return;
    var region = exposed.single;
    final members = <String>[tileId];
    final pending = landscape.terrain.tiles.values
        .where(
          (other) =>
              other.id != tileId &&
              ownsTerrainTile(other.id) &&
              other.sheet.island == tile.sheet.island &&
              (other.sheet.elevation - tile.sheet.elevation).abs() <
                  geometryEpsilon,
        )
        .toList();
    var changed = true;
    while (changed) {
      changed = false;
      for (final other in pending.toList()) {
        final source = planes[other.id]!;
        final parts = surfaceRegions(source);
        if (parts.length != 1) continue;
        final mapped = _inFrame(parts.single, source, basis);
        if (!region.bounds.inflate(geometryEpsilon).overlaps(mapped.bounds)) {
          continue;
        }
        final union = region.union(mapped);
        if (union.length != 1 || !union.single.valid) continue;
        region = union.single;
        members.add(other.id);
        pending.remove(other);
        changed = true;
      }
    }
    members.sort();
    // Include tile corners, with a single node at shared corners. Never stretch
    // one tile's lattice over the full landscape bounds.
    final nodes = <Offset>[];
    for (final id in members) {
      final source = planes[id]!;
      for (final corner in source.region.outer) {
        final point = basis.local(source.point(corner));
        if (region.contains(point) && !nodes.any((n) => near(n, point))) {
          nodes.add(point);
        }
      }
    }
    final id = 'landscape-drawing-$tileId';
    final frame = CraftPlane(
      id: id,
      origin: basis.origin,
      u: basis.u,
      v: basis.v,
      region: region,
      supports: [tileId, ...members.where((id) => id != tileId)],
      grids: [lattice(id, region, existingNodes: nodes, name: 'Landscape')],
    );
    // Occupied frames must never change underneath existing objects.
    if (objects.values.any((o) => o.planeId == id)) {
      final previous = planes[id];
      if (previous != null &&
          jsonEncode(previous.region.toJson()) != jsonEncode(region.toJson())) {
        final freshId = '$id-$nextId';
        planes[freshId] = CraftPlane(
          id: freshId,
          origin: frame.origin,
          u: frame.u,
          v: frame.v,
          region: region,
          supports: frame.supports,
          grids: [
            lattice(freshId, region, existingNodes: nodes, name: 'Landscape'),
          ],
        );
        activePlaneId = freshId;
        return;
      }
    }
    planes[id] = frame;
    activePlaneId = id;
  }

  bool _landscapeSupports(CraftPlane frame, Region outline) {
    var remaining = [outline];
    for (final id in frame.supports) {
      final source = planes[id];
      if (source == null) continue;
      for (final region in surfaceRegions(source)) {
        final support = _inFrame(region, source, frame);
        remaining = remaining.expand((r) => r.subtract(support)).toList();
      }
    }
    return remaining.isEmpty;
  }
}
