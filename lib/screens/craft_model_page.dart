import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/blueprint.dart';
import '../gridcraft/cube_blueprint.dart';

/// Drag-to-orbit view of the folded cube.
///
/// The projection matches the craft editor fold pane: yaw around Y, then
/// pitch, then perspective. Faces of the selected blueprint step draw solid.
/// Faces of any other step draw dim. A blueprint that is not the cube net
/// draws no solid.
class CraftModelPage extends StatefulWidget {
  const CraftModelPage({
    super.key,
    required this.blueprint,
    required this.stepIndex,
  });

  final GridBlueprint blueprint;
  final int stepIndex;

  @override
  State<CraftModelPage> createState() => _CraftModelPageState();
}

class _CraftModelPageState extends State<CraftModelPage> {
  double _yaw = 0.6;
  double _pitch = 0.45;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF12141A),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _yaw += details.delta.dx * 0.01;
            _pitch = (_pitch + details.delta.dy * 0.01).clamp(-1.2, 1.2);
          });
        },
        child: CustomPaint(
          painter: _CubePainter(
            faces: foldedCube(widget.blueprint),
            stepIndex: widget.stepIndex,
            yaw: _yaw,
            pitch: _pitch,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _CubePainter extends CustomPainter {
  _CubePainter({
    required this.faces,
    required this.stepIndex,
    required this.yaw,
    required this.pitch,
  });

  final List<CubeFace>? faces;
  final int stepIndex;
  final double yaw;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final model = faces;
    if (model == null || model.isEmpty) return;
    final points = [for (final face in model) ...face.corners];
    final bounds = _bounds(points);
    final center = bounds.center;
    final radius = math.max(bounds.radius, 1.0);
    final ordered = [...model]
      ..sort((a, b) {
        final depthA = _faceDepth(a, center, radius);
        final depthB = _faceDepth(b, center, radius);
        return depthB.compareTo(depthA);
      });
    for (final face in ordered) {
      final ring = <Offset>[];
      for (final corner in face.corners) {
        final screen = _project(corner, size, center, radius);
        if (screen == null) continue;
        ring.add(screen);
      }
      if (ring.length < 3) continue;
      final solid = face.stepIndex == stepIndex;
      final path = Path()..addPolygon(ring, true);
      canvas.drawPath(
        path,
        Paint()
          ..color = solid ? const Color(0xFF8EAECE) : const Color(0x478EAECE)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = solid ? const Color(0xFFE8EEF4) : const Color(0x66E8EEF4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) {
    return old.yaw != yaw ||
        old.pitch != pitch ||
        old.stepIndex != stepIndex ||
        old.faces != faces;
  }

  double _faceDepth(CubeFace face, Vector3 center, double radius) {
    var sum = 0.0;
    for (final corner in face.corners) {
      sum += _depth(corner, center, radius);
    }
    return sum / face.corners.length;
  }

  double _depth(Vector3 point, Vector3 center, double radius) {
    final rel = point - center;
    final sy = math.sin(yaw);
    final cy = math.cos(yaw);
    final z1 = rel.x * sy + rel.z * cy;
    final sx = math.sin(pitch);
    final cx = math.cos(pitch);
    final z2 = rel.y * sx + z1 * cx;
    return z2 + radius * 3;
  }

  Offset? _project(Vector3 point, Size size, Vector3 center, double radius) {
    final rel = point - center;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final x1 = rel.x * cy - rel.z * sy;
    final z1 = rel.x * sy + rel.z * cy;
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);
    final y2 = rel.y * cx - z1 * sx;
    final z2 = rel.y * sx + z1 * cx;
    final depth = z2 + radius * 3;
    if (depth < 1) return null;
    final scale = size.shortestSide * 0.38 / radius;
    return Offset(
      size.width / 2 + x1 * scale * (radius * 2.2) / depth,
      size.height / 2 - y2 * scale * (radius * 2.2) / depth,
    );
  }
}

class _Bounds {
  _Bounds(this.center, this.radius);

  final Vector3 center;
  final double radius;
}

_Bounds _bounds(List<Vector3> points) {
  var minX = double.infinity;
  var minY = double.infinity;
  var minZ = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var maxZ = -double.infinity;
  for (final point in points) {
    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    minZ = math.min(minZ, point.z);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
    maxZ = math.max(maxZ, point.z);
  }
  final center = Vector3(
    (minX + maxX) / 2,
    (minY + maxY) / 2,
    (minZ + maxZ) / 2,
  );
  var radius = 1.0;
  for (final point in points) {
    radius = math.max(radius, (point - center).length);
  }
  return _Bounds(center, radius);
}
