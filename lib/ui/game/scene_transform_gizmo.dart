import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/gizmo/gizmo_target.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';
import 'volume_transform_gizmo.dart';

const kSceneGizmoStemOut = 1.5;
const _kHandleVisual = 16.0;
const _kHandleHit = 44.0;

enum SceneGizmoAxis { posX, posY, posZ }

extension SceneGizmoAxisX on SceneGizmoAxis {
  Vector3 get direction => switch (this) {
        SceneGizmoAxis.posX => Vector3(1, 0, 0),
        SceneGizmoAxis.posY => Vector3(0, 1, 0),
        SceneGizmoAxis.posZ => Vector3(0, 0, 1),
      };

  Color get color => switch (this) {
        SceneGizmoAxis.posX => const Color(0xFFE57373),
        SceneGizmoAxis.posY => const Color(0xFF81C784),
        SceneGizmoAxis.posZ => const Color(0xFF64B5F6),
      };
}

/// Axis translate handles for the current [GizmoTarget].
class SceneTransformGizmo extends StatelessWidget {
  const SceneTransformGizmo({
    super.key,
    required this.target,
    required this.camera,
    required this.viewport,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final GizmoTarget target;
  final Camera camera;
  final Size viewport;
  final void Function(SceneGizmoAxis axis, Offset global) onDragStart;
  final void Function(SceneGizmoAxis axis, Offset global) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final center = target.worldCenter;
    final stems = <(Offset, Offset, Color)>[];
    final handles = <Widget>[];

    for (final axis in SceneGizmoAxis.values) {
      if (axis == SceneGizmoAxis.posY && !target.allowsVertical) continue;
      final tip = center + axis.direction * kSceneGizmoStemOut;
      final a = camera.projectToScreen(center, viewport);
      final b = camera.projectToScreen(tip, viewport);
      if (a != null && b != null) {
        stems.add((a, b, axis.color));
      }
      handles.add(
        ProjectedWorldAnchor(
          camera: camera,
          viewport: viewport,
          world: tip,
          size: const Size(_kHandleHit, _kHandleHit),
          child: _HandleKnob(
            color: axis.color,
            onPanStart: (details) => onDragStart(axis, details.globalPosition),
            onPanUpdate: (details) => onDragUpdate(axis, details.globalPosition),
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
  bool shouldRepaint(covariant _HandleStemPainter oldDelegate) =>
      oldDelegate.stems != stems;
}

/// Re-export so gizmo drag code can share the volume handle math.
double? sceneAxisDragDelta({
  required Camera camera,
  required Size viewport,
  required Offset screen,
  required Vector3 axis,
  required Vector3 planePoint,
  required Vector3 startHit,
}) {
  return axisDragDelta(
    camera: camera,
    viewport: viewport,
    screen: screen,
    axis: axis,
    planePoint: planePoint,
    startHit: startHit,
  );
}
