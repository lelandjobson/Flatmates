import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/viewers/focus_crop.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';
import 'volume_transform_gizmo.dart';

const _kCropColor = Color(0xFF80DEEA);
const _kCropYColor = Color(0xFFFFFFFF);

/// Wireframe crop AABB plus axis handles, matching volume transform grabs.
class CropBoxGizmo extends StatelessWidget {
  const CropBoxGizmo({
    super.key,
    required this.crop,
    required this.grid,
    required this.camera,
    required this.viewport,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final FocusCrop crop;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final void Function(CropHandle handle, Offset global) onDragStart;
  final void Function(CropHandle handle, Offset global) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final min = crop.worldMin(grid);
    final max = crop.worldMax(grid);
    final stems = <(Offset, Offset, Color)>[];
    final handles = <Widget>[];

    for (final handle in CropHandle.values) {
      final face = crop.faceCenter(grid, handle);
      final color = handle.isHeight ? _kCropYColor : _kCropColor;
      final tip = face + handle.axis * kVolumeHandleStemOut;
      final a = camera.projectToScreen(face, viewport);
      final b = camera.projectToScreen(tip, viewport);
      if (a != null && b != null) {
        stems.add((a, b, color));
      }
      handles.add(
        ProjectedWorldAnchor(
          camera: camera,
          viewport: viewport,
          world: tip,
          size: const Size(44, 44),
          child: _CropHandleKnob(
            color: color,
            onPanStart: (details) => onDragStart(handle, details.globalPosition),
            onPanUpdate: (details) =>
                onDragUpdate(handle, details.globalPosition),
            onPanEnd: onDragEnd,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: viewport,
            painter: _CropBoxPainter(
              camera: camera,
              viewport: viewport,
              min: min,
              max: max,
              stems: stems,
            ),
          ),
        ),
        ...handles,
      ],
    );
  }
}

class _CropHandleKnob extends StatelessWidget {
  const _CropHandleKnob({
    required this.color,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final Color color;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: (_) => onPanEnd(),
      onPanCancel: onPanEnd,
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropBoxPainter extends CustomPainter {
  _CropBoxPainter({
    required this.camera,
    required this.viewport,
    required this.min,
    required this.max,
    required this.stems,
  });

  final Camera camera;
  final Size viewport;
  final Vector3 min;
  final Vector3 max;
  final List<(Offset, Offset, Color)> stems;

  @override
  void paint(Canvas canvas, Size size) {
    Offset? p(double x, double y, double z) =>
        camera.projectToScreen(Vector3(x, y, z), viewport);

    final corners = [
      p(min.x, min.y, min.z),
      p(max.x, min.y, min.z),
      p(min.x, min.y, max.z),
      p(max.x, min.y, max.z),
      p(min.x, max.y, min.z),
      p(max.x, max.y, min.z),
      p(min.x, max.y, max.z),
      p(max.x, max.y, max.z),
    ];
    const edges = [
      (0, 1),
      (1, 3),
      (3, 2),
      (2, 0),
      (4, 5),
      (5, 7),
      (7, 6),
      (6, 4),
      (0, 4),
      (1, 5),
      (2, 6),
      (3, 7),
    ];
    final line = Paint()
      ..color = _kCropColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final (a, b) in edges) {
      final pa = corners[a];
      final pb = corners[b];
      if (pa == null || pb == null) continue;
      canvas.drawLine(pa, pb, line);
    }
    for (final (a, b, color) in stems) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropBoxPainter oldDelegate) =>
      oldDelegate.min != min ||
      oldDelegate.max != max ||
      oldDelegate.camera != camera ||
      oldDelegate.viewport != viewport;
}
