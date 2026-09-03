import 'package:flutter/material.dart';

import '../../gameplay/outlines/outline_edges.dart';
import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/volumes/volume_outline.dart';
import '../../rendering/scene/camera.dart';

export '../../gameplay/outlines/outline_paint.dart' show kWorldOutlineColor;

/// Camera-facing outer creases of volumes, drawn on top of the 3D scene.
class VolumeOutlineOverlay extends StatelessWidget {
  const VolumeOutlineOverlay({
    super.key,
    this.volumes,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.color = kWorldOutlineColor,
    this.edgeOpacity,
  });

  final VolumeOutlineStore? volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final Color color;
  final double Function(OutlineEdge edge)? edgeOpacity;

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
          camera: camera,
          viewport: viewport,
          color: color,
          edgeOpacity: edgeOpacity,
        ),
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.volumes,
    required this.camera,
    required this.viewport,
    required this.color,
    this.edgeOpacity,
  });

  final VolumeOutlineStore? volumes;
  final Camera camera;
  final Size viewport;
  final Color color;
  final double Function(OutlineEdge edge)? edgeOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final volumes = this.volumes;
    if (volumes == null) return;
    paintOutlineEdges(
      canvas: canvas,
      edges: volumes.edges,
      camera: camera,
      viewport: viewport,
      color: color,
      opacityFor: edgeOpacity,
    );
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter oldDelegate) => true;
}
