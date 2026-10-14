import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../flatgram/flatgram_models.dart';
import '../flatgram/flatgram_painter.dart';
import 'tilewalk_models.dart';
import 'tilewalk_projector.dart';
import 'tilewalk_rules.dart';

/// Screen-space piece badge. Radius stays fixed so the shape survives the camera.
class TilewalkIconMark {
  const TilewalkIconMark({
    required this.pieceId,
    required this.center,
    required this.piece,
    required this.turns,
    required this.pickup,
    required this.locked,
    required this.selected,
  });

  static const double radius = 20;

  final String pieceId;
  final Offset center;
  final FlatgramPiece piece;
  final int turns;
  final bool pickup;
  final bool locked;
  final bool selected;

  bool contains(Offset point) => (point - center).distance <= radius + 2;
}

List<TilewalkIconMark> tilewalkIconMarks({
  required TilewalkProjector projector,
  required TilewalkSession session,
  String? selectedPieceId,
  String? hiddenPieceId,
  PlacedPiece? ghost,
}) {
  final placed = <TilewalkIconMark>[];

  void addPlaced(PlacedPiece item, {required bool selected}) {
    final piece = session.piece(item.pieceId);
    final cells = piece.transformedCells(item.anchor, item.turns);
    final center = _centroid(projector, cells);
    final locked = cells.contains(session.cube);
    placed.add(
      TilewalkIconMark(
        pieceId: item.pieceId,
        center: center,
        piece: piece,
        turns: item.turns,
        pickup: false,
        locked: locked,
        selected: selected,
      ),
    );
  }

  for (final item in session.placed) {
    if (item.pieceId == hiddenPieceId) continue;
    addPlaced(item, selected: item.pieceId == selectedPieceId);
  }
  if (ghost != null) {
    addPlaced(ghost, selected: true);
  }

  final marks = List<TilewalkIconMark>.of(placed);
  for (final pickup in session.pickups) {
    var center = projector.project(
      pickup.cell.x + 0.5,
      pickup.cell.y + 0.5,
      0.22,
    );
    for (final other in placed) {
      if ((other.center - center).distance < 48) {
        center = center + const Offset(0, -48);
      }
    }
    final piece = session.piece(pickup.pieceId);
    marks.add(
      TilewalkIconMark(
        pieceId: pickup.pieceId,
        center: center,
        piece: piece,
        turns: 0,
        pickup: true,
        locked: false,
        selected: false,
      ),
    );
  }
  return marks;
}

Offset _centroid(TilewalkProjector projector, List<GridPoint> cells) {
  var x = 0.0;
  var y = 0.0;
  for (final cell in cells) {
    x += cell.x + 0.5;
    y += cell.y + 0.5;
  }
  final n = math.max(cells.length, 1);
  return projector.project(x / n, y / n, 0.22);
}

class TilewalkPainter extends CustomPainter {
  TilewalkPainter({
    required this.session,
    required this.projector,
    required this.cubeX,
    required this.cubeY,
    this.selectedPieceId,
    this.hiddenPieceId,
    this.ghost,
    this.ghostValid = false,
    this.doorPulse = 0,
  });

  final TilewalkSession session;
  final TilewalkProjector projector;
  final double cubeX;
  final double cubeY;
  final String? selectedPieceId;
  final String? hiddenPieceId;
  final PlacedPiece? ghost;
  final bool ghostValid;
  final double doorPulse;

  static const double _slab = 0.18;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDots(canvas);
    _paintOpenCells(canvas);
    _paintShadow(canvas);

    final faces = <_Face>[];
    for (final item in session.placed) {
      if (item.pieceId == hiddenPieceId) continue;
      final piece = session.piece(item.pieceId);
      _slabs(
        faces,
        piece.transformedCells(item.anchor, item.turns),
        piece.defaultColor,
        lifted: item.pieceId == selectedPieceId,
      );
    }
    if (ghost != null) {
      final piece = session.piece(ghost!.pieceId);
      final color = ghostValid
          ? piece.defaultColor
          : const Color(0xFFE57373);
      _slabs(
        faces,
        piece.transformedCells(ghost!.anchor, ghost!.turns),
        color,
        alpha: 0.62,
      );
    }
    _cube(faces);
    if (showDoor(session)) _door(faces);

    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      canvas.drawPath(face.path, Paint()..color = face.color);
    }

    final marks = tilewalkIconMarks(
      projector: projector,
      session: session,
      selectedPieceId: selectedPieceId,
      hiddenPieceId: hiddenPieceId,
      ghost: ghost,
    );
    for (final mark in marks) {
      _paintIcon(canvas, mark);
    }
  }

  void _paintDots(Canvas canvas) {
    final bounds = session.puzzle.bounds;
    final paint = Paint()..color = FlatgramPainter.fadedWhite;
    final minX = bounds.left.floor() - 2;
    final maxX = bounds.right.ceil() + 2;
    final minY = bounds.top.floor() - 2;
    final maxY = bounds.bottom.ceil() + 2;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final point = projector.project(x.toDouble(), y.toDouble(), 0);
        canvas.drawCircle(point, 1.7, paint);
      }
    }
  }

  void _paintOpenCells(Canvas canvas) {
    final covered = coveredCells(session);
    final hidden = hiddenPieceId;
    if (hidden != null) {
      final placed = session.placementOf(hidden);
      if (placed != null) {
        covered.removeAll(
          session.piece(hidden).transformedCells(placed.anchor, placed.turns),
        );
      }
    }
    final fill = Paint()..color = const Color(0x14FFFFFF);
    final stroke = Paint()
      ..color = FlatgramPainter.fadedWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final cell in session.puzzle.cells) {
      if (covered.contains(cell)) continue;
      final path = Path();
      final corners = <Offset>[
        projector.project(cell.x.toDouble(), cell.y.toDouble(), 0.02),
        projector.project(cell.x + 1.0, cell.y.toDouble(), 0.02),
        projector.project(cell.x + 1.0, cell.y + 1.0, 0.02),
        projector.project(cell.x.toDouble(), cell.y + 1.0, 0.02),
      ];
      path.moveTo(corners.first.dx, corners.first.dy);
      for (final corner in corners.skip(1)) {
        path.lineTo(corner.dx, corner.dy);
      }
      path.close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  void _paintShadow(Canvas canvas) {
    final feet = projector.project(cubeX + 0.5, cubeY + 0.62, _slab);
    canvas.drawOval(
      Rect.fromCenter(center: feet, width: 22, height: 9),
      Paint()..color = const Color(0x66000000),
    );
  }

  void _slabs(
    List<_Face> faces,
    List<GridPoint> cells,
    Color color, {
    bool lifted = false,
    double alpha = 1,
  }) {
    if (cells.isEmpty) return;
    final set = cells.toSet();
    const inset = 0.045;
    final top = _shade(color, Colors.white, lifted ? 0.28 : 0.14, alpha);
    final south = _shade(color, Colors.white, 0.04, alpha);
    final north = _shade(color, Colors.black, 0.42, alpha);
    final east = _shade(color, Colors.black, 0.2, alpha);
    final west = _shade(color, Colors.black, 0.32, alpha);

    for (final cell in set) {
      final hasWest = set.contains(GridPoint(cell.x - 1, cell.y));
      final hasEast = set.contains(GridPoint(cell.x + 1, cell.y));
      final hasNorth = set.contains(GridPoint(cell.x, cell.y - 1));
      final hasSouth = set.contains(GridPoint(cell.x, cell.y + 1));
      final x0 = hasWest ? cell.x.toDouble() : cell.x + inset;
      final x1 = hasEast ? cell.x + 1.0 : cell.x + 1.0 - inset;
      final y0 = hasNorth ? cell.y.toDouble() : cell.y + inset;
      final y1 = hasSouth ? cell.y + 1.0 : cell.y + 1.0 - inset;
      _quad(faces, [
        (x0, y0, _slab),
        (x1, y0, _slab),
        (x1, y1, _slab),
        (x0, y1, _slab),
      ], top);
      if (!hasNorth) {
        _quad(faces, [
          (x0, y0, 0),
          (x1, y0, 0),
          (x1, y0, _slab),
          (x0, y0, _slab),
        ], north);
      }
      if (!hasSouth) {
        _quad(faces, [
          (x0, y1, 0),
          (x1, y1, 0),
          (x1, y1, _slab),
          (x0, y1, _slab),
        ], south);
      }
      if (!hasWest) {
        _quad(faces, [
          (x0, y0, 0),
          (x0, y1, 0),
          (x0, y1, _slab),
          (x0, y0, _slab),
        ], west);
      }
      if (!hasEast) {
        _quad(faces, [
          (x1, y0, 0),
          (x1, y1, 0),
          (x1, y1, _slab),
          (x1, y0, _slab),
        ], east);
      }
    }
  }

  void _cube(List<_Face> faces) {
    _box(
      faces,
      cubeX + 0.22,
      cubeY + 0.22,
      _slab,
      cubeX + 0.78,
      cubeY + 0.78,
      _slab + 0.56,
      const Color(0xFFF4F0E6),
    );
  }

  void _door(List<_Face> faces) {
    final exit = session.puzzle.exitCell;
    final x = exit.x.toDouble();
    final y = exit.y.toDouble();
    final wood = Color.lerp(
      const Color(0xFFB08968),
      const Color(0xFFFFD54F),
      doorPulse * 0.35,
    )!;
    _box(faces, x + 0.16, y + 0.04, _slab, x + 0.30, y + 0.22, _slab + 1.05, wood);
    _box(faces, x + 0.70, y + 0.04, _slab, x + 0.84, y + 0.22, _slab + 1.05, wood);
    _box(faces, x + 0.16, y + 0.04, _slab + 0.8, x + 0.84, y + 0.22, _slab + 1.05, wood);
    _quad(faces, [
      (x + 0.30, y + 0.23, _slab + 0.02),
      (x + 0.70, y + 0.23, _slab + 0.02),
      (x + 0.70, y + 0.23, _slab + 0.8),
      (x + 0.30, y + 0.23, _slab + 0.8),
    ], const Color(0xFF140E0C));
  }

  void _box(
    List<_Face> faces,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    Color color,
  ) {
    final top = _shade(color, Colors.white, 0.2, 1);
    final south = _shade(color, Colors.white, 0.05, 1);
    final north = _shade(color, Colors.black, 0.4, 1);
    final east = _shade(color, Colors.black, 0.18, 1);
    final west = _shade(color, Colors.black, 0.3, 1);
    _quad(faces, [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], top);
    _quad(faces, [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], south);
    _quad(faces, [(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)], north);
    _quad(faces, [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], east);
    _quad(faces, [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], west);
  }

  void _quad(List<_Face> faces, List<(double, double, double)> corners, Color color) {
    final path = Path();
    var depth = 0.0;
    for (var i = 0; i < corners.length; i++) {
      final (x, y, z) = corners[i];
      final point = projector.project(x, y, z);
      depth += projector.depth(x, y, z);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    faces.add(_Face(depth / corners.length, path, color));
  }

  void _paintIcon(Canvas canvas, TilewalkIconMark mark) {
    final center = mark.center;
    canvas.drawCircle(center, TilewalkIconMark.radius, Paint()..color = const Color(0xF0161B28));

    final bounds = mark.piece.localBounds(mark.turns);
    final cells = mark.piece.transformedCells(GridPoint.zero, mark.turns);
    final cellPx =
        (TilewalkIconMark.radius * 1.45) /
        math.max(bounds.width, bounds.height);
    final origin = Offset(
      center.dx - (bounds.left + bounds.width / 2) * cellPx,
      center.dy - (bounds.top + bounds.height / 2) * cellPx,
    );
    final fill = Paint()..color = mark.piece.defaultColor;
    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        origin.dx + cell.x * cellPx + 0.7,
        origin.dy + cell.y * cellPx + 0.7,
        math.max(cellPx - 1.4, 1),
        math.max(cellPx - 1.4, 1),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
    }

    final ring = mark.selected
        ? const Color(0xFFFFC107)
        : mark.pickup
            ? Colors.white
            : mark.locked
                ? const Color(0x66FFFFFF)
                : mark.piece.defaultColor;
    canvas.drawCircle(
      center,
      TilewalkIconMark.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = mark.selected || mark.pickup ? 2.4 : 1.6
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(covariant TilewalkPainter oldDelegate) => true;
}

class _Face {
  _Face(this.depth, this.path, this.color);
  final double depth;
  final Path path;
  final Color color;
}

Color _shade(Color color, Color toward, double amount, double alpha) {
  return Color.lerp(color, toward, amount)!.withValues(alpha: alpha);
}
