import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume.dart';
import '../../gameplay/walls/wall_edge.dart';
import '../../gameplay/walls/wall_mesh.dart';
import '../../gameplay/walls/wall_store.dart';
import '../../rendering/scene/camera.dart';

enum PlacementGhostKind { volume, path, wall }

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
    this.listenable,
    this.color = const Color(0x99B3E5FC),
  });

  final PlacementGhostKind kind;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final (int, int)? tile;
  final WallEdge? wallEdge;
  final Listenable? listenable;
  final Color color;

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
          color: color,
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
    required this.color,
  });

  final PlacementGhostKind kind;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final (int, int)? tile;
  final WallEdge? wallEdge;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;

    for (final quad in _quads()) {
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
        ];
      case PlacementGhostKind.path:
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
        final dummy = WallStore(grid: grid);
        final a = dummy.vertexWorld(edge.x0, edge.y0);
        final b = dummy.vertexWorld(edge.x1, edge.y1);
        return [
          [
            Vector3(a.x, 0, a.z),
            Vector3(b.x, 0, b.z),
            Vector3(b.x, kFenceHeight, b.z),
            Vector3(a.x, kFenceHeight, a.z),
          ],
        ];
    }
  }

  @override
  bool shouldRepaint(covariant _GhostPainter oldDelegate) => true;
}
