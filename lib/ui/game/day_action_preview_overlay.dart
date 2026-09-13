import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/flatmates/day_action.dart';
import '../../gameplay/flatmates/day_action_store.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';

/// Gradient action-tile fills plus arrowed hops for the selected day plan.
class DayActionPreviewOverlay extends StatelessWidget {
  const DayActionPreviewOverlay({
    super.key,
    required this.plan,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.validTiles = const {},
    this.pickingTile = false,
    this.listenable,
  });

  final FlatmateDayPlan plan;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Set<(int, int)> validTiles;
  final bool pickingTile;
  final Listenable? listenable;

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
        painter: _PreviewPainter(
          plan: plan,
          grid: grid,
          camera: camera,
          viewport: viewport,
          validTiles: validTiles,
          pickingTile: pickingTile,
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({
    required this.plan,
    required this.grid,
    required this.camera,
    required this.viewport,
    required this.validTiles,
    required this.pickingTile,
  });

  final FlatmateDayPlan plan;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Set<(int, int)> validTiles;
  final bool pickingTile;

  static const _lift = 0.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (pickingTile) {
      final wash = Paint()
        ..color = const Color(0x33FFE08A)
        ..style = PaintingStyle.fill;
      for (final tile in validTiles) {
        final quad = _tileQuad(tile);
        if (quad == null) continue;
        canvas.drawPath(quad, wash);
      }
    }

    for (var i = 0; i < plan.slots.length; i++) {
      final tile = plan.slots[i].tile;
      if (tile == null) continue;
      final quad = _tileQuad(tile);
      if (quad == null) continue;
      final color = dayProgressColor(i, count: plan.slots.length);
      canvas.drawPath(
        quad,
        Paint()
          ..color = color.withValues(alpha: 0.32)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        quad,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    for (var i = 0; i < plan.hops.length; i++) {
      final hop = plan.hops[i];
      if (hop == null || hop.length < 2) continue;
      final color = dayProgressColor(i, count: plan.slots.length);
      _drawHop(canvas, hop, color);
    }
  }

  Path? _tileQuad((int, int) tile) {
    final origin = grid.tileOrigin(tile.$1, tile.$2);
    final s = grid.tileSize;
    final corners = [
      Vector3(origin.x, _lift, origin.z),
      Vector3(origin.x + s, _lift, origin.z),
      Vector3(origin.x + s, _lift, origin.z + s),
      Vector3(origin.x, _lift, origin.z + s),
    ];
    final pts = <Offset>[];
    for (final c in corners) {
      final screen = camera.projectToScreen(c, viewport);
      if (screen == null) return null;
      pts.add(screen);
    }
    return Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();
  }

  void _drawHop(Canvas canvas, List<(int, int)> tiles, Color color) {
    final pts = <Offset>[];
    for (final tile in tiles) {
      final c = grid.tileCenter(tile.$1, tile.$2);
      final screen = camera.projectToScreen(
        Vector3(c.x, _lift, c.z),
        viewport,
      );
      if (screen != null) pts.add(screen);
    }
    if (pts.length < 2) return;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < pts.length - 1; i++) {
      canvas.drawLine(pts[i], pts[i + 1], stroke);
      _arrow(canvas, pts[i], pts[i + 1], color);
    }
  }

  void _arrow(Canvas canvas, Offset a, Offset b, Color color) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 8) return;
    final ux = dx / len;
    final uy = dy / len;
    final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
    final side = Offset(-uy, ux);
    const head = 7.0;
    final path = Path()
      ..moveTo(mid.dx + ux * head, mid.dy + uy * head)
      ..lineTo(mid.dx - ux * 3 + side.dx * 5, mid.dy - uy * 3 + side.dy * 5)
      ..lineTo(mid.dx - ux * 3 - side.dx * 5, mid.dy - uy * 3 - side.dy * 5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) => true;
}