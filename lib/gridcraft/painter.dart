import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry_2d.dart';
import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/camera.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'scissor.dart';

class GridPuzzlePainter extends CustomPainter {
  GridPuzzlePainter({
    required this.camera,
    required this.step,
    required this.sheet,
    required this.march,
    required this.flash,
    required this.rulerX,
    required this.showRuler,
    required this.selected,
    required this.painted,
    required this.ghostCells,
    this.ghostCut,
  });

  final PapercutCamera camera;
  final GridStep step;
  final PapercutSheet sheet;
  final ScissorMarch? march;
  final double flash;
  final double? rulerX;
  final bool showRuler;
  final Set<int> selected;
  final Set<(int, int)> painted;
  final Set<(int, int)> ghostCells;
  final (Offset, Offset)? ghostCut;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in sheet.pieces) {
      _fillPiece(canvas, size, piece, const Color(0xFFFFF3B0));
      _stroke(
        canvas,
        size,
        _moved(piece.vertices, piece.separation),
        const Color(0xFF1A1A2E),
        width: 1.5,
        close: true,
      );
    }
    for (var i = 0; i < step.polygons.length; i++) {
      final selectedPolygon = selected.contains(i);
      for (final ring in _polygonOnPieces(step.polygons[i])) {
        _stroke(
          canvas,
          size,
          ring,
          selectedPolygon ? const Color(0xFFFFD54F) : const Color(0xFF1565C0),
          width: selectedPolygon ? 3 : 2,
          close: true,
        );
      }
    }
    for (final cell in ghostCells) {
      if (painted.contains(cell)) continue;
      final spacing = step.gridSpacing;
      final x = cell.$1 * spacing;
      final y = cell.$2 * spacing;
      _fill(canvas, size, [
        Offset(x, y),
        Offset(x + spacing, y),
        Offset(x + spacing, y + spacing),
        Offset(x, y + spacing),
      ], const Color(0x5567BB6A));
    }
    for (final cell in painted) {
      final spacing = step.gridSpacing;
      final x = cell.$1 * spacing;
      final y = cell.$2 * spacing;
      _fill(canvas, size, [
        Offset(x, y),
        Offset(x + spacing, y),
        Offset(x + spacing, y + spacing),
        Offset(x, y + spacing),
      ], const Color(0x8867BB6A));
    }
    for (final stroke in sheet.cutStrokes) {
      for (final shifted in _onEachOwner(stroke)) {
        _stroke(canvas, size, shifted, const Color(0xFF000000), width: 2.5);
      }
    }
    for (final crease in sheet.creases) {
      for (final shifted in _onEachOwner([crease.a, crease.b])) {
        _stroke(
          canvas,
          size,
          shifted,
          const Color(0xFFE53935),
          width: 2,
          dashed: true,
        );
      }
    }
    if (showRuler && rulerX != null) {
      for (final piece in sheet.pieces) {
        if (!_crossesX(piece.vertices, rulerX!)) continue;
        final shift = piece.separation;
        final top = piece.vertices.map((point) => point.dy).reduce(math.min);
        final bottom = piece.vertices.map((point) => point.dy).reduce(math.max);
        _stroke(
          canvas,
          size,
          [
            Offset(rulerX! + shift.dx, top + shift.dy),
            Offset(rulerX! + shift.dx, bottom + shift.dy),
          ],
          const Color(0xFFFFD54F),
          width: 2,
        );
      }
    }
    final preview = ghostCut;
    if (preview != null) {
      final shown = _shiftSegment(preview.$1, preview.$2);
      _stroke(
        canvas,
        size,
        [shown.$1, shown.$2],
        Color.fromRGBO(102, 187, 106, 0.35 + 0.65 * flash),
        width: 4,
      );
    }
  }

  void _fillPiece(Canvas canvas, Size size, PapercutPiece piece, Color color) {
    final path = _path(_moved(piece.vertices, piece.separation), size, close: true);
    if (path == null) return;
    for (final hole in piece.holes) {
      final holePath = _path(_moved(hole, piece.separation), size, close: true);
      if (holePath != null) path.addPath(holePath, Offset.zero);
    }
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = color);
  }

  List<Offset> _moved(List<Offset> ring, Offset shift) {
    if (shift == Offset.zero) return ring;
    return [for (final point in ring) point + shift];
  }

  List<List<Offset>> _polygonOnPieces(List<Offset> polygon) {
    final drawn = <List<Offset>>[];
    for (final piece in sheet.pieces) {
      if (piece.vertices.length < 3) continue;
      final hits = polygonIntersection(
        Polygon2D.simple(polygon),
        Polygon2D.simple(piece.vertices),
      );
      if (hits.isEmpty) {
        final centroid = polygonCentroid(polygon);
        if (ownsPoint(piece.vertices, centroid)) {
          drawn.add(_moved(polygon, piece.separation));
        }
        continue;
      }
      for (final hit in hits) {
        if (hit.exterior.points.length < 3) continue;
        drawn.add(_moved(hit.exterior.points, piece.separation));
      }
    }
    if (drawn.isEmpty) drawn.add(polygon);
    return drawn;
  }

  List<List<Offset>> _onEachOwner(List<Offset> stroke) {
    if (stroke.isEmpty) return const [];
    final mid = stroke[stroke.length ~/ 2];
    final shifted = <List<Offset>>[];
    for (final piece in sheet.pieces) {
      if (!ownsPoint(piece.vertices, mid)) continue;
      shifted.add(_moved(stroke, piece.separation));
    }
    if (shifted.isEmpty) shifted.add(stroke);
    return shifted;
  }

  (Offset, Offset) _shiftSegment(Offset a, Offset b) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    for (final piece in sheet.pieces) {
      if (!ownsPoint(piece.vertices, mid) && !ownsPoint(piece.vertices, a)) {
        continue;
      }
      return (a + piece.separation, b + piece.separation);
    }
    return (a, b);
  }

  bool _crossesX(List<Offset> ring, double x) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    for (final point in ring) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
    }
    return x >= minX - 1e-3 && x <= maxX + 1e-3;
  }

  void _fill(Canvas canvas, Size size, List<Offset> ring, Color color) {
    final path = _path(ring, size, close: true);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = color);
  }

  void _stroke(
    Canvas canvas,
    Size size,
    List<Offset> ring,
    Color color, {
    required double width,
    bool close = false,
    bool dashed = false,
  }) {
    final projected = [
      for (final point in ring) _project(point, size),
    ].whereType<Offset>().toList();
    if (projected.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      final path = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (final point in projected.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (close) path.close();
      canvas.drawPath(path, paint);
      return;
    }
    for (var i = 0; i < projected.length - 1; i++) {
      final a = projected[i];
      final b = projected[i + 1];
      final delta = b - a;
      final len = delta.distance;
      if (len < 1) continue;
      final dir = delta / len;
      var traveled = 0.0;
      while (traveled < len) {
        final stop = math.min(traveled + 8, len);
        canvas.drawLine(a + dir * traveled, a + dir * stop, paint);
        traveled = stop + 6;
      }
    }
  }

  Path? _path(List<Offset> ring, Size size, {required bool close}) {
    final projected = [
      for (final point in ring) _project(point, size),
    ].whereType<Offset>().toList();
    if (projected.length < 3) return null;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) path.close();
    return path;
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(
      Vector3(point.dx, point.dy, 0),
      size,
    );
  }

  @override
  bool shouldRepaint(covariant GridPuzzlePainter oldDelegate) => true;
}
