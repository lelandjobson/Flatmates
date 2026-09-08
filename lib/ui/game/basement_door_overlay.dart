import 'package:flutter/material.dart';

import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/spawns/basement_spawn_mesh.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/ground_occlusion.dart';
import '../../rendering/scene/camera.dart';

/// Open-door outlines on the basement facade. Wall fill is path-colored.
class BasementDoorOverlay extends StatelessWidget {
  const BasementDoorOverlay({
    super.key,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.groundOcclusion,
  });

  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final GroundOcclusion? groundOcclusion;

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
        painter: _BasementDoorPainter(
          grid: grid,
          camera: camera,
          viewport: viewport,
          groundOcclusion: groundOcclusion,
        ),
      ),
    );
  }
}

class _BasementDoorPainter extends CustomPainter {
  _BasementDoorPainter({
    required this.grid,
    required this.camera,
    required this.viewport,
    this.groundOcclusion,
  });

  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final GroundOcclusion? groundOcclusion;

  @override
  void paint(Canvas canvas, Size size) {
    paintOutlineEdges(
      canvas: canvas,
      edges: basementDoorWallOutline(grid),
      camera: camera,
      viewport: viewport,
      groundOcclusion: groundOcclusion,
    );
    paintOutlineEdges(
      canvas: canvas,
      edges: basementDoorPaperOutline(grid),
      camera: camera,
      viewport: viewport,
      color: kAppliqueOutlineColor,
      strokeWidth: kAppliqueOutlineStrokeWidth,
      groundOcclusion: groundOcclusion,
    );
  }

  @override
  bool shouldRepaint(covariant _BasementDoorPainter oldDelegate) => true;
}
