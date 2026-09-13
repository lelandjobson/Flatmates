import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/paths/path_shape.dart';
import '../../gameplay/paths/path_store.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/walls/wall_edge.dart';
import '../../gameplay/walls/wall_mesh.dart';
import '../../gameplay/walls/wall_store.dart';
import '../../rendering/scene/camera.dart';

enum PlacementGhostKind { volume, path, wall, delete, pathSplit, regionOpening }

const kPlacementGhostRemove = Color(0xCCEF5350);

/// Translucent preview of the item that a click at the crosshair would place.
class PlacementGhostOverlay extends StatelessWidget {
  const PlacementGhostOverlay({
    super.key,
    required this.kind,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.tile,
    this.wallEdge,
    this.wallEdges = const [],
    this.removeWallEdges = const [],
    this.paths,
    this.listenable,
    this.color = const Color(0x99F4EFE6),
    this.removing = false,
  });

  final PlacementGhostKind kind;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final (int, int)? tile;
  final WallEdge? wallEdge;
  final List<WallEdge> wallEdges;
  final List<WallEdge> removeWallEdges;
  final PathStore? paths;
  final Listenable? listenable;
  final Color color;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _GhostPainter(
          kind: kind,
          grid: grid,
          camera: camera,
          viewport: viewport,
          tile: tile,
          wallEdge: wallEdge,
          wallEdges: wallEdges,
          removeWallEdges: removeWallEdges,
          paths: paths,
          color: color,
          removing: removing,
        ),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.kind,
    required this.grid,
    required this.camera,
    required this.viewport,
    required this.tile,
    required this.wallEdge,
    required this.wallEdges,
    required this.removeWallEdges,
    required this.paths,
    required this.color,
    required this.removing,
  });

  final PlacementGhostKind kind;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final (int, int)? tile;
  final WallEdge? wallEdge;
  final List<WallEdge> wallEdges;
  final List<WallEdge> removeWallEdges;
  final PathStore? paths;
  final Color color;
  final bool removing;

  @override
  void paint(Canvas canvas, Size size) {
    if (kind == PlacementGhostKind.wall &&
        (wallEdges.isNotEmpty || removeWallEdges.isNotEmpty)) {
      _drawQuads(canvas, _fenceQuads(wallEdges), color, removing: false);
      _drawQuads(
        canvas,
        _fenceQuads(removeWallEdges),
        kPlacementGhostRemove,
        removing: true,
      );
      return;
    }
    _drawQuads(canvas, _quads(), removing ? kPlacementGhostRemove : color,
        removing: removing);
  }

  void _drawQuads(
    Canvas canvas,
    List<List<Vector3>> quads,
    Color edge, {
    required bool removing,
  }) {
    final fill = Paint()
      ..color = edge.withValues(alpha: removing ? 0.32 : 0.50)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = edge.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;

    for (final quad in quads) {
      final path = Path();
      var started = false;
      var ok = true;
      for (final p in quad) {
        final s = camera.projectToScreen(p, viewport);
        if (s == null) {
          ok = false;
          break;
        }
        if (!started) {
          path.moveTo(s.dx, s.dy);
          started = true;
        } else {
          path.lineTo(s.dx, s.dy);
        }
      }
      if (!ok || !started) continue;
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  List<List<Vector3>> _fenceQuads(List<WallEdge> edges) {
    final dummy = WallStore(grid: grid);
    return [
      for (final edge in edges) _fenceQuad(dummy, edge),
    ];
  }

  List<Vector3> _fenceQuad(WallStore store, WallEdge edge) {
    final a = store.vertexWorld(edge.x0, edge.y0);
    final b = store.vertexWorld(edge.x1, edge.y1);
    return [
      Vector3(a.x, 0, a.z),
      Vector3(b.x, 0, b.z),
      Vector3(b.x, kFenceHeight, b.z),
      Vector3(a.x, kFenceHeight, a.z),
    ];
  }

  List<List<Vector3>> _quads() {
    switch (kind) {
      case PlacementGhostKind.volume:
        final t = tile;
        if (t == null) return const [];
        final box = BoxPrimitive();
        final min = box.worldMin(grid, t.$1, t.$2);
        final max = box.worldMax(grid, t.$1, t.$2);
        return [
          [
            Vector3(min.x, min.y, min.z),
            Vector3(max.x, min.y, min.z),
            Vector3(max.x, min.y, max.z),
            Vector3(min.x, min.y, max.z),
          ],
          [
            Vector3(min.x, max.y, min.z),
            Vector3(max.x, max.y, min.z),
            Vector3(max.x, max.y, max.z),
            Vector3(min.x, max.y, max.z),
          ],
          [
            Vector3(min.x, min.y, min.z),
            Vector3(min.x, max.y, min.z),
            Vector3(max.x, max.y, min.z),
            Vector3(max.x, min.y, min.z),
          ],
          [
            Vector3(min.x, min.y, max.z),
            Vector3(max.x, min.y, max.z),
            Vector3(max.x, max.y, max.z),
            Vector3(min.x, max.y, max.z),
          ],
          [
            Vector3(min.x, min.y, min.z),
            Vector3(min.x, min.y, max.z),
            Vector3(min.x, max.y, max.z),
            Vector3(min.x, max.y, min.z),
          ],
          [
            Vector3(max.x, min.y, min.z),
            Vector3(max.x, max.y, min.z),
            Vector3(max.x, max.y, max.z),
            Vector3(max.x, min.y, max.z),
          ],
        ];
      case PlacementGhostKind.path:
        final t = tile;
        if (t == null) return const [];
        final byTile = paths == null
            ? <(int, int), List<PathFootprint>>{
                t: pathFootprints(0, subtilesPerTile: grid.subtilesPerTile),
              }
            : previewPlaceFootprintsByTile(paths!, tx: t.$1, ty: t.$2);
        return [
          for (final entry in byTile.entries)
            ..._pathQuads(entry.key.$1, entry.key.$2, entry.value),
        ];
      case PlacementGhostKind.delete:
        final t = tile;
        if (t == null) return const [];
        final origin = grid.tileOrigin(t.$1, t.$2);
        final s = grid.tileSize;
        const y = 0.06;
        return [
          [
            Vector3(origin.x, y, origin.z),
            Vector3(origin.x + s, y, origin.z),
            Vector3(origin.x + s, y, origin.z + s),
            Vector3(origin.x, y, origin.z + s),
          ],
        ];
      case PlacementGhostKind.wall:
        final edge = wallEdge;
        if (edge == null) return const [];
        return [_fenceQuad(WallStore(grid: grid), edge)];
      case PlacementGhostKind.pathSplit:
        final edge = wallEdge;
        if (edge == null) return const [];
        final dummy = WallStore(grid: grid);
        final a = dummy.vertexWorld(edge.x0, edge.y0);
        final b = dummy.vertexWorld(edge.x1, edge.y1);
        const y = 0.08;
        const half = 0.18;
        if (edge.isVertical) {
          return [
            [
              Vector3(a.x - half, y, a.z),
              Vector3(a.x + half, y, a.z),
              Vector3(b.x + half, y, b.z),
              Vector3(b.x - half, y, b.z),
            ],
          ];
        }
        return [
          [
            Vector3(a.x, y, a.z - half),
            Vector3(b.x, y, b.z - half),
            Vector3(b.x, y, b.z + half),
            Vector3(a.x, y, a.z + half),
          ],
        ];
      case PlacementGhostKind.regionOpening:
        final edge = wallEdge;
        if (edge == null) return const [];
        final dummy = WallStore(grid: grid);
        final quads = <List<Vector3>>[];
        for (final (p, q) in wallCutRemnants(dummy, edge)) {
          quads.add([
            Vector3(p.x, 0, p.z),
            Vector3(q.x, 0, q.z),
            Vector3(q.x, kFenceHeight, q.z),
            Vector3(p.x, kFenceHeight, p.z),
          ]);
        }
        final pair = edge.separatedTiles;
        final store = paths;
        if (pair != null && store != null) {
          final outdoor = store.contains(pair.$1.$1, pair.$1.$2)
              ? pair.$1
              : store.contains(pair.$2.$1, pair.$2.$2)
                  ? pair.$2
                  : null;
          if (outdoor != null) {
            final toward = outdoor == pair.$1 ? pair.$2 : pair.$1;
            var mask = 0;
            if (toward.$1 == outdoor.$1 + 1) mask |= VolumeSide.east.maskBit;
            if (toward.$1 == outdoor.$1 - 1) mask |= VolumeSide.west.maskBit;
            if (toward.$2 == outdoor.$2 + 1) mask |= VolumeSide.south.maskBit;
            if (toward.$2 == outdoor.$2 - 1) mask |= VolumeSide.north.maskBit;
            quads.addAll(
              _pathQuads(
                outdoor.$1,
                outdoor.$2,
                pathStubFootprints(
                  mask,
                  subtilesPerTile: grid.subtilesPerTile,
                ),
              ),
            );
          }
        }
        return quads;
    }
  }

  List<List<Vector3>> _pathQuads(
    int tx,
    int ty,
    List<PathFootprint> pieces,
  ) {
    final origin = grid.tileOrigin(tx, ty);
    final s = grid.subtileSize;
    const y = 0.06;
    return [
      for (final p in pieces)
        [
          Vector3(
            origin.x + p.originXSubtiles * s,
            y,
            origin.z + p.originZSubtiles * s,
          ),
          Vector3(
            origin.x + (p.originXSubtiles + p.widthSubtiles) * s,
            y,
            origin.z + p.originZSubtiles * s,
          ),
          Vector3(
            origin.x + (p.originXSubtiles + p.widthSubtiles) * s,
            y,
            origin.z + (p.originZSubtiles + p.depthSubtiles) * s,
          ),
          Vector3(
            origin.x + p.originXSubtiles * s,
            y,
            origin.z + (p.originZSubtiles + p.depthSubtiles) * s,
          ),
        ],
    ];
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) => true;
}
