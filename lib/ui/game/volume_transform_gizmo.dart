import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';

const kVolumeHandleStemOut = 1.2;
const _kHandleVisual = 16.0;
const _kHandleHit = 44.0;

class VolumeTransformGizmo extends StatelessWidget {
  const VolumeTransformGizmo({
    super.key,
    required this.store,
    required this.camera,
    required this.viewport,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final VolumeStore store;
  final Camera camera;
  final Size viewport;
  final void Function(VolumeCell cell, VolumeHandle handle, Offset global)
      onDragStart;
  final void Function(VolumeCell cell, VolumeHandle handle, Offset global)
      onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final volume = store.draftVolume;
    if (volume == null) return const SizedBox.shrink();

    final stems = <(Offset, Offset, Color)>[];
    final handles = <Widget>[];

    for (final facet in volume.exteriorFacets()) {
      final cell = facet.cell;
      final handle = facet.handle;
      final face = cell.box.faceCenter(store.grid, cell.tx, cell.ty, handle);
      final tip = face + handle.axis * kVolumeHandleStemOut;
      final a = camera.projectToScreen(face, viewport);
      final b = camera.projectToScreen(tip, viewport);
      final color = handle.isHeight ? Colors.white : const Color(0xFFFFD54F);
      if (a != null && b != null) {
        stems.add((a, b, color));
      }
      handles.add(
        ProjectedWorldAnchor(
          camera: camera,
          viewport: viewport,
          world: tip,
          size: const Size(_kHandleHit, _kHandleHit),
          child: _HandleKnob(
            color: color,
            onPanStart: (details) =>
                onDragStart(cell, handle, details.globalPosition),
            onPanUpdate: (details) =>
                onDragUpdate(cell, handle, details.globalPosition),
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
            painter: _HandleStemPainter(stems: stems),
          ),
        ),
        ...handles,
      ],
    );
  }
}

/// Converts a screen drag into a world-axis delta using a camera-facing drag plane.
double? axisDragDelta({
  required Camera camera,
  required Size viewport,
  required Offset screen,
  required Vector3 axis,
  required Vector3 planePoint,
  required Vector3 startHit,
}) {
  final ray = camera.unprojectRay(screen, viewport);
  if (ray == null) return null;
  var planeN = axis.cross(camera.forward.cross(axis));
  if (planeN.length2 < 1e-8) {
    planeN = Vector3.copy(camera.up);
  }
  planeN.normalize();
  final hit = Camera.intersectPlane(ray: ray, point: planePoint, normal: planeN);
  if (hit == null) return null;
  return (hit - startHit).dot(axis);
}

class _HandleKnob extends StatelessWidget {
  const _HandleKnob({
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
          width: _kHandleVisual,
          height: _kHandleVisual,
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

class _HandleStemPainter extends CustomPainter {
  _HandleStemPainter({required this.stems});

  final List<(Offset, Offset, Color)> stems;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (a, b, color) in stems) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandleStemPainter oldDelegate) => true;
}
