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

/// Step that keeps unit dots at least about 7px apart.
double unitGridStride({
  required double spacing,
  required double pixelsPerUnit,
}) {
  if (spacing <= 0) return spacing;
  var stride = spacing;
  final pixels = pixelsPerUnit.abs();
  if (pixels < 1e-6) return stride;
  while (pixels * (stride / spacing) < 7 && stride < spacing * 128) {
    stride *= 2;
  }
  return stride;
}

/// Lattice points covering [bounds]. Each coordinate is a multiple of [stride].
List<Offset> unitGridPoints(Rect bounds, double stride) {
  if (stride <= 0) return const [];
  final i0 = (bounds.left / stride).floor();
  final i1 = (bounds.right / stride).ceil();
  final j0 = (bounds.top / stride).floor();
  final j1 = (bounds.bottom / stride).ceil();
  final points = <Offset>[];
  for (var i = i0; i <= i1; i++) {
    for (var j = j0; j <= j1; j++) {
      points.add(Offset(i * stride, j * stride));
    }
  }
  return points;
}

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
    _paintUnitGrid(canvas, size);
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

  /// Crafting-view dot grid: one dot per unit, behind the sheet.
  void _paintUnitGrid(Canvas canvas, Size size) {
    final spacing = step.gridSpacing;
    if (spacing <= 0 || size.width < 2 || size.height < 2) return;
    final bounds = _visiblePlane(size);
    if (bounds == null) return;
    final origin = _project(Offset.zero, size);
    final neighbor = _project(Offset(spacing, 0), size);
    final pixels = origin == null || neighbor == null
        ? 12.0
        : (neighbor - origin).distance;
    var stride = unitGridStride(spacing: spacing, pixelsPerUnit: pixels);
    while (stride < spacing * 128) {
      final cols = (bounds.width / stride).ceil() + 3;
      final rows = (bounds.height / stride).ceil() + 3;
      final gap = pixels * (stride / spacing);
      if (gap >= 7 && cols * rows <= 4000) break;
      stride *= 2;
    }

    const dotRadius = 1.35;
    final dot = Paint()
      ..color = Colors.grey.shade400.withValues(alpha: 0.55);
    Offset? originScreen;
    for (final world in unitGridPoints(bounds, stride)) {
      final screen = _project(world, size);
      if (screen == null || !_onScreen(screen, size)) continue;
      if (world.distance < 1e-6) {
        originScreen = screen;
        continue;
      }
      canvas.drawCircle(screen, dotRadius, dot);
    }
    if (originScreen == null) return;
    canvas.drawCircle(
      originScreen,
      4.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      originScreen,
      3.6,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  Rect? _visiblePlane(Size size) {
    final corners = <Offset>[];
    for (final screen in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ]) {
      final world = camera.planePoint(screen, size);
      if (world == null) return null;
      corners.add(world);
    }
    var minX = corners.first.dx;
    var maxX = corners.first.dx;
    var minY = corners.first.dy;
    var maxY = corners.first.dy;
    for (final corner in corners) {
      minX = math.min(minX, corner.dx);
      maxX = math.max(maxX, corner.dx);
      minY = math.min(minY, corner.dy);
      maxY = math.max(maxY, corner.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _onScreen(Offset screen, Size size) {
    return screen.dx >= -4 &&
        screen.dy >= -4 &&
        screen.dx <= size.width + 4 &&
        screen.dy <= size.height + 4;
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
