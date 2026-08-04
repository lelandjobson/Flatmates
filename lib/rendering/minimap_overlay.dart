import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../geometry/geometry.dart';

class UnfoldedFaceMinimap extends StatelessWidget {
  const UnfoldedFaceMinimap({
    super.key,
    required this.geometry,
    required this.highlightedFaceIndex,
    required this.size,
    this.onFaceTap,
    this.hiddenFaceIndices = const {},
  });

  final Geometry geometry;
  final int highlightedFaceIndex;
  final double size;
  final ValueChanged<int>? onFaceTap;

  /// Face indices (in the unfolded geometry) to hide from display and
  /// interaction. Used to suppress ceiling/roof faces in inside mode.
  final Set<int> hiddenFaceIndices;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actualSize = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : size,
            constraints.maxHeight.isFinite ? constraints.maxHeight : size,
          );
          final projection = _MinimapProjection(
            geometry: geometry,
            size: actualSize,
            hiddenFaceIndices: hiddenFaceIndices,
          ).project();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onFaceTap == null
                ? null
                : (details) {
                    final faceIndex = projection.hitTest(details.localPosition);
                    if (faceIndex != null) {
                      onFaceTap!(faceIndex);
                    }
                  },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _UnfoldedFacePainter(
                    faces: projection.faces,
                    highlightedFaceIndex: highlightedFaceIndex,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProjectedFaceSet {
  const _ProjectedFaceSet(this.faces);

  final List<_ProjectedFace> faces;

  int? hitTest(Offset position) {
    for (final face in faces) {
      if (face.path.contains(position)) {
        return face.index;
      }
    }
    return null;
  }
}

class _ProjectedFace {
  _ProjectedFace({required this.index, required this.path});

  final int index;
  final Path path;
}

class _MinimapProjection {
  const _MinimapProjection({
    required this.geometry,
    required this.size,
    this.hiddenFaceIndices = const {},
  });

  final Geometry geometry;
  final Size size;
  final Set<int> hiddenFaceIndices;

  _ProjectedFaceSet project() {
    final projected = _projectVertices(geometry.vertices);
    if (projected.isEmpty || geometry.faces.isEmpty) {
      return const _ProjectedFaceSet(<_ProjectedFace>[]);
    }

    // Compute bounds only from visible faces so hidden faces don't waste space.
    final visibleProjected = <Offset>[];
    for (var i = 0; i < geometry.faces.length; i++) {
      if (hiddenFaceIndices.contains(i)) continue;
      for (final vi in geometry.faces[i]) {
        if (vi >= 0 && vi < projected.length) {
          visibleProjected.add(projected[vi]);
        }
      }
    }
    if (visibleProjected.isEmpty) {
      return const _ProjectedFaceSet(<_ProjectedFace>[]);
    }

    final bounds = _boundsFromOffsets(visibleProjected);
    final margin = 12.0;
    final contentWidth = math.max(1.0, size.width - margin * 2);
    final contentHeight = math.max(1.0, size.height - margin * 2);
    final boundsWidth = math.max(1e-3, bounds.width);
    final boundsHeight = math.max(1e-3, bounds.height);
    final scale = math.min(
      contentWidth / boundsWidth,
      contentHeight / boundsHeight,
    );
    final dx = (size.width - boundsWidth * scale) / 2 - bounds.left * scale;
    final dy = (size.height - boundsHeight * scale) / 2 - bounds.top * scale;

    final faces = <_ProjectedFace>[];
    for (var faceIndex = 0; faceIndex < geometry.faces.length; faceIndex++) {
      if (hiddenFaceIndices.contains(faceIndex)) continue;
      final face = geometry.faces[faceIndex];
      if (face.isEmpty) continue;
      final path = Path();
      var isFirst = true;
      var vertexCount = 0;
      for (final vertexIndex in face) {
        if (vertexIndex < 0 || vertexIndex >= projected.length) {
          continue;
        }
        final projectedPoint = projected[vertexIndex];
        final canvasPoint = Offset(
          projectedPoint.dx * scale + dx,
          projectedPoint.dy * scale + dy,
        );
        if (isFirst) {
          path.moveTo(canvasPoint.dx, canvasPoint.dy);
          isFirst = false;
        } else {
          path.lineTo(canvasPoint.dx, canvasPoint.dy);
        }
        vertexCount++;
      }
      if (vertexCount < 3) {
        continue;
      }
      path.close();
      faces.add(_ProjectedFace(index: faceIndex, path: path));
    }

    return _ProjectedFaceSet(faces);
  }
}

class _UnfoldedFacePainter extends CustomPainter {
  const _UnfoldedFacePainter({
    required this.faces,
    required this.highlightedFaceIndex,
  });

  final List<_ProjectedFace> faces;
  final int highlightedFaceIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) {
      return;
    }

    final baseFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final baseStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.35);
    final highlightStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = Colors.redAccent;

    for (final face in faces) {
      canvas.drawPath(face.path, baseFill);
      final isHighlighted = face.index == highlightedFaceIndex;
      canvas.drawPath(face.path, isHighlighted ? highlightStroke : baseStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _UnfoldedFacePainter oldDelegate) {
    return oldDelegate.highlightedFaceIndex != highlightedFaceIndex ||
        oldDelegate.faces != faces;
  }
}

List<Offset> _projectVertices(List<Vector3> vertices) {
  if (vertices.isEmpty) {
    return const <Offset>[];
  }
  return List<Offset>.generate(vertices.length, (index) {
    final vertex = vertices[index];
    return Offset(vertex.x, vertex.z);
  }, growable: false);
}

Rect _boundsFromOffsets(List<Offset> points) {
  if (points.isEmpty) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  var minX = points.first.dx;
  var minY = points.first.dy;
  var maxX = points.first.dx;
  var maxY = points.first.dy;
  for (final point in points) {
    if (point.dx < minX) minX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy > maxY) maxY = point.dy;
  }
  final width = math.max(1e-3, maxX - minX);
  final height = math.max(1e-3, maxY - minY);
  return Rect.fromLTWH(minX, minY, width, height);
}
