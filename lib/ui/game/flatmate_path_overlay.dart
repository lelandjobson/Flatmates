import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Dashed ground polyline for a pending or active flatmate walk.
class FlatmatePathOverlay extends StatelessWidget {
  const FlatmatePathOverlay({
    super.key,
    required this.tiles,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.color = const Color(0xE6FFFFFF),
    this.listenable,
  });

  final List<(int, int)> tiles;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Color color;
  final Scene? listenable;

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
    if (tiles.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _PathPainter(
          tiles: tiles,
          grid: grid,
          camera: camera,
          viewport: viewport,
          color: color,
        ),
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.tiles,
    required this.grid,
    required this.camera,
    required this.viewport,
    required this.color,
  });

  final List<(int, int)> tiles;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Color color;

  static const _lift = 0.18;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = <Offset>[];
    for (final tile in tiles) {
      final c = grid.tileCenter(tile.$1, tile.$2);
      final screen = camera.projectToScreen(
        Vector3(c.x, _lift, c.z),
        viewport,
      );
      if (screen != null) projected.add(screen);
    }
    if (projected.length < 2) return;

    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    _drawDashed(canvas, projected, line);

    final node = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final p in projected) {
      canvas.drawCircle(p, 3.5, node);
    }
  }

  void _drawDashed(Canvas canvas, List<Offset> pts, Paint paint) {
    const dash = 9.0;
    const gap = 5.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-3) continue;
      final ux = dx / len;
      final uy = dy / len;
      var t = 0.0;
      var draw = true;
      while (t < len) {
        final next = math.min(t + (draw ? dash : gap), len);
        if (draw) {
          canvas.drawLine(
            Offset(a.dx + ux * t, a.dy + uy * t),
            Offset(a.dx + ux * next, a.dy + uy * next),
            paint,
          );
        }
        t = next;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter oldDelegate) => true;
}
