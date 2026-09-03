import 'package:flutter/material.dart';

import '../../gameplay/outlines/outline_edges.dart';
import '../../gameplay/paths/path_outline.dart';
import '../../gameplay/volumes/volume_outline.dart';
import '../../rendering/scene/camera.dart';

const kWorldOutlineColor = Color(0xB3808080);

/// Camera-facing outer creases of volumes and path paper.
class VolumeOutlineOverlay extends StatelessWidget {
  const VolumeOutlineOverlay({
    super.key,
    this.volumes,
    this.paths,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.color = kWorldOutlineColor,
  });

  final VolumeOutlineStore? volumes;
  final PathOutlineStore? paths;
  final Camera camera;
  final Size viewport;
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
        painter: _OutlinePainter(
          volumes: volumes,
          paths: paths,
          camera: camera,
          viewport: viewport,
          color: color,
        ),
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.volumes,
    required this.paths,
    required this.camera,
    required this.viewport,
    required this.color,
  });

  final VolumeOutlineStore? volumes;
  final PathOutlineStore? paths;
  final Camera camera;
  final Size viewport;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final eye = camera.position;
    void drawAll(Iterable<OutlineEdge> edges) {
      for (final edge in edges) {
        if (!outlineEdgeVisible(edge, eye)) continue;
        final a = camera.projectToScreen(edge.a, viewport);
        final b = camera.projectToScreen(edge.b, viewport);
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, stroke);
      }
    }

    final volumes = this.volumes;
    if (volumes != null) drawAll(volumes.edges);
    final paths = this.paths;
    if (paths != null) drawAll(paths.edges);
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter oldDelegate) => true;
}
