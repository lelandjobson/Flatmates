import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'flatgram_constraints.dart';
import 'flatgram_models.dart';
import 'flatgram_puzzles.dart';

class _GridSegment {
  const _GridSegment(this.from, this.to);
  final GridPoint from;
  final GridPoint to;
}

/// Helper that builds a continuous, smoothly rounded outer polygon Path
/// for any orthogonal polyomino cell arrangement.
Path buildPolyominoPath(
  List<GridPoint> cells,
  double cellSize, {
  Offset origin = Offset.zero,
  double cornerRadius = 5.0,
  double inset = 0.0,
}) {
  if (cells.isEmpty) return Path();

  final cellSet = cells.toSet();

  // 1. Collect all directed boundary edges (clockwise around exterior)
  final boundarySegments = <_GridSegment>[];
  for (final c in cellSet) {
    // Top
    if (!cellSet.contains(GridPoint(c.x, c.y - 1))) {
      boundarySegments.add(
        _GridSegment(GridPoint(c.x, c.y), GridPoint(c.x + 1, c.y)),
      );
    }
    // Right
    if (!cellSet.contains(GridPoint(c.x + 1, c.y))) {
      boundarySegments.add(
        _GridSegment(GridPoint(c.x + 1, c.y), GridPoint(c.x + 1, c.y + 1)),
      );
    }
    // Bottom
    if (!cellSet.contains(GridPoint(c.x, c.y + 1))) {
      boundarySegments.add(
        _GridSegment(GridPoint(c.x + 1, c.y + 1), GridPoint(c.x, c.y + 1)),
      );
    }
    // Left
    if (!cellSet.contains(GridPoint(c.x - 1, c.y))) {
      boundarySegments.add(
        _GridSegment(GridPoint(c.x, c.y + 1), GridPoint(c.x, c.y)),
      );
    }
  }

  if (boundarySegments.isEmpty) return Path();

  // 2. Build adjacency map
  final adj = <GridPoint, List<GridPoint>>{};
  for (final seg in boundarySegments) {
    adj.putIfAbsent(seg.from, () => []).add(seg.to);
  }

  final path = Path();

  // 3. Trace all closed boundary loops (handles both single & disconnected components)
  while (adj.isNotEmpty) {
    // Find start point with minimum X, then minimum Y among remaining edges
    GridPoint? start;
    for (final from in adj.keys) {
      final candidates = adj[from];
      if (candidates == null || candidates.isEmpty) continue;
      if (start == null ||
          from.x < start.x ||
          (from.x == start.x && from.y < start.y)) {
        start = from;
      }
    }
    if (start == null) break;

    final loop = <GridPoint>[];
    var curr = start;
    GridPoint? prev;
    final visitedEdges = <(GridPoint, GridPoint)>{};

    while (true) {
      loop.add(curr);
      final nextCandidates = adj[curr];
      if (nextCandidates == null || nextCandidates.isEmpty) break;

      GridPoint next;
      if (nextCandidates.length == 1) {
        next = nextCandidates.first;
      } else {
        final inDir = prev == null ? const GridPoint(0, -1) : (curr - prev);
        next = _pickClockwiseNext(curr, inDir, nextCandidates);
      }

      final edgeKey = (curr, next);
      if (visitedEdges.contains(edgeKey)) break;
      visitedEdges.add(edgeKey);

      nextCandidates.remove(next);
      if (nextCandidates.isEmpty) {
        adj.remove(curr);
      }
      prev = curr;
      curr = next;

      if (curr == start) break;
    }

    adj.removeWhere((key, value) => value.isEmpty);

    if (loop.length < 3) continue;

    // 4. Simplify collinear points
    final simplified = <GridPoint>[];
    for (var i = 0; i < loop.length; i++) {
      final pPrev = loop[(i - 1 + loop.length) % loop.length];
      final pCurr = loop[i];
      final pNext = loop[(i + 1) % loop.length];
      final d1 = pCurr - pPrev;
      final d2 = pNext - pCurr;
      // Skip if collinear in the same direction
      if (d1.x * d2.y - d1.y * d2.x == 0 && (d1.x * d2.x + d1.y * d2.y) > 0) {
        continue;
      }
      simplified.add(pCurr);
    }

    if (simplified.length < 3) continue;

    // 5. Generate points (applying inward offset if requested)
    final n = simplified.length;
    final points = <Offset>[];

    for (var i = 0; i < n; i++) {
      final pPrev = simplified[(i - 1 + n) % n];
      final pCurr = simplified[i];
      final pNext = simplified[(i + 1) % n];

      final screenCurr = Offset(
        origin.dx + pCurr.x * cellSize,
        origin.dy + pCurr.y * cellSize,
      );

      if (inset <= 0.0) {
        points.add(screenCurr);
      } else {
        final v1 = pCurr - pPrev;
        final v2 = pNext - pCurr;
        final len1 = math.sqrt((v1.x * v1.x + v1.y * v1.y).toDouble());
        final len2 = math.sqrt((v2.x * v2.x + v2.y * v2.y).toDouble());

        // Inward normals (90 deg clockwise in screen coordinates where +Y is down):
        final n1 = Offset(-v1.y / len1, v1.x / len1);
        final n2 = Offset(-v2.y / len2, v2.x / len2);

        final offsetPoint = screenCurr + (n1 + n2) * inset;
        points.add(offsetPoint);
      }
    }

    // 6. Generate smooth path with rounded corners
    final m = points.length;
    for (var i = 0; i < m; i++) {
      final pPrev = points[(i - 1 + m) % m];
      final pCurr = points[i];
      final pNext = points[(i + 1) % m];

      final v1 = pPrev == pCurr ? Offset.zero : pCurr - pPrev;
      final v2 = pCurr == pNext ? Offset.zero : pNext - pCurr;
      final len1 = v1.distance;
      final len2 = v2.distance;
      if (len1 < 1e-4 || len2 < 1e-4) continue;

      final cr = math.min(cornerRadius, math.min(len1, len2) / 2);
      final pStart = pCurr - (v1 / len1) * cr;
      final pEnd = pCurr + (v2 / len2) * cr;

      if (i == 0) {
        path.moveTo(pStart.dx, pStart.dy);
      } else {
        path.lineTo(pStart.dx, pStart.dy);
      }
      path.quadraticBezierTo(pCurr.dx, pCurr.dy, pEnd.dx, pEnd.dy);
    }

    path.close();
  }

  return path;
}

GridPoint _pickClockwiseNext(
  GridPoint curr,
  GridPoint inDir,
  List<GridPoint> candidates,
) {
  final inAngle = math.atan2(inDir.y.toDouble(), inDir.x.toDouble());
  var bestDiff = double.infinity;
  var bestChoice = candidates.first;

  for (final c in candidates) {
    final outDir = c - curr;
    final outAngle = math.atan2(outDir.y.toDouble(), outDir.x.toDouble());
    var diff = outAngle - inAngle;
    while (diff <= 0) {
      diff += 2 * math.pi;
    }
    if (diff < bestDiff) {
      bestDiff = diff;
      bestChoice = c;
    }
  }

  return bestChoice;
}

/// Computes the centermost tile within any region's set of cells.
GridPoint findCentermostCell(Set<GridPoint> cells) {
  if (cells.isEmpty) return GridPoint.zero;
  if (cells.length == 1) return cells.first;

  double sumX = 0;
  double sumY = 0;
  for (final c in cells) {
    sumX += c.x;
    sumY += c.y;
  }
  final avgX = sumX / cells.length;
  final avgY = sumY / cells.length;

  GridPoint bestCell = cells.first;
  double bestDistSq = double.infinity;

  final sortedCells = cells.toList()
    ..sort((a, b) {
      if (a.y != b.y) return a.y.compareTo(b.y);
      return a.x.compareTo(b.x);
    });

  for (final c in sortedCells) {
    final dx = c.x - avgX;
    final dy = c.y - avgY;
    final distSq = dx * dx + dy * dy;
    if (distSq < bestDistSq - 1e-6) {
      bestDistSq = distSq;
      bestCell = c;
    }
  }

  return bestCell;
}

/// Custom painter for Flatgram game board, subregions, pieces, badges, and dot grid.
class FlatgramPainter extends CustomPainter {
  FlatgramPainter({
    required this.board,
    required this.placedPieces,
    required this.pieceCatalog,
    required this.constraints,
    this.evaluation,
    this.selectedPieceId,
    this.dragPiece,
    this.dragAnchor,
    this.dragVisualAnchor,
    this.dragScreenPos,
    this.cellSize = 56.0,
    this.boardOffset = Offset.zero,
    this.pulseValue = 0.0,
    this.rotatingPieceId,
    this.rotationAngle = 0.0,
  });

  final FlatgramBoard board;
  final List<PlacedPiece> placedPieces;
  final Map<String, FlatgramPiece> pieceCatalog;
  final List<FlatgramConstraint> constraints;
  final FlatgramEvaluation? evaluation;
  final String? selectedPieceId;

  final FlatgramPiece? dragPiece;
  final GridPoint? dragAnchor;
  final Offset? dragVisualAnchor;
  final Offset? dragScreenPos;

  final double cellSize;
  final Offset boardOffset;
  final double pulseValue;
  final String? rotatingPieceId;
  final double rotationAngle;

  /// Faded white used for both background dot grid and puzzle boundary outline.
  static const Color fadedWhite = Color(0x40FFFFFF);

  /// Default opacity for continuous tangram piece tiles (50% translucent so underlying regions/dots are visible).
  static const double pieceOpacity = 0.50;

  /// Inward offset in pixels for subregion boundaries to avoid overlapping adjacent regions.
  static const double regionInset = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDotGrid(canvas, size);
    _paintBoardOutline(canvas);
    _paintSubregions(canvas);
    _paintRegionIndicators(canvas);
    _paintPlacedPieces(canvas);
    _paintSnapPreview(canvas);
    _paintSelectionGlow(canvas);
    _paintDragPiece(canvas);
  }

  Offset cellToScreen(GridPoint cell) {
    return Offset(
      boardOffset.dx + cell.x * cellSize,
      boardOffset.dy + cell.y * cellSize,
    );
  }

  Rect cellToRect(GridPoint cell) {
    final origin = cellToScreen(cell);
    return Rect.fromLTWH(origin.dx, origin.dy, cellSize, cellSize);
  }

  // 1. Dot Grid background matching mixed crafting
  // Dots correspond to corners of grid squares; a grid square corresponds
  // to a tile square on a piece or in the puzzle.
  void _paintDotGrid(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = fadedWhite
      ..style = PaintingStyle.fill;

    const dotRadius = 1.4;

    final minCol = ((0 - boardOffset.dx) / cellSize).floor() - 1;
    final maxCol = ((size.width - boardOffset.dx) / cellSize).ceil() + 1;
    final minRow = ((0 - boardOffset.dy) / cellSize).floor() - 1;
    final maxRow = ((size.height - boardOffset.dy) / cellSize).ceil() + 1;

    for (var col = minCol; col <= maxCol; col++) {
      final x = boardOffset.dx + col * cellSize;
      for (var row = minRow; row <= maxRow; row++) {
        final y = boardOffset.dy + row * cellSize;
        canvas.drawCircle(
          Offset(x, y),
          dotRadius,
          dotPaint,
        );
      }
    }
  }

  // 2. Puzzle outline in the same faded white as the dot grid.
  // No flat color fill covering the board, so grid dots remain visible inside the puzzle.
  void _paintBoardOutline(Canvas canvas) {
    final boardPath = buildPolyominoPath(
      board.cells.toList(),
      cellSize,
      origin: boardOffset,
      cornerRadius: 6.0,
    );

    // Outer contour of the puzzle in faded white
    canvas.drawPath(
      boardPath,
      Paint()
        ..color = fadedWhite
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // 3. Subregions with constraints rendered as thick colored outlines instead of fills
  void _paintSubregions(Canvas canvas) {
    for (final region in board.regions) {
      final hasConstraint = constraints.any(
        (c) => c.params['regionId'] == region.id,
      );
      if (!hasConstraint && region.badgeLabel == null) continue;

      final regionPath = buildPolyominoPath(
        region.cells.toList(),
        cellSize,
        origin: boardOffset,
        cornerRadius: 4.0,
        inset: regionInset,
      );

      // Thick colored outline in pastel color (no fill), offset inward so adjacent regions do not overlap
      canvas.drawPath(
        regionPath,
        Paint()
          ..color = region.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  // 3b. Simple colored number or equals sign at the centermost tile of each region with value constraint
  void _paintRegionIndicators(Canvas canvas) {
    for (final region in board.regions) {
      FlatgramConstraint? regionConstraint;
      for (final c in constraints) {
        if (c.params['regionId'] == region.id) {
          regionConstraint = c;
          break;
        }
      }

      String? label;
      if (regionConstraint != null) {
        if (regionConstraint.type == 'region_equal') {
          label = '=';
        } else if (regionConstraint.type == 'region_sum') {
          label = '${regionConstraint.params['target']}';
        } else if (regionConstraint.badgeLabel != null) {
          label = regionConstraint.badgeLabel;
        }
      } else if (region.badgeLabel != null) {
        label = region.badgeLabel;
      }

      if (label == null) continue;

      final centerCell = findCentermostCell(region.cells);
      final cellCenter = Offset(
        boardOffset.dx + (centerCell.x + 0.5) * cellSize,
        boardOffset.dy + (centerCell.y + 0.5) * cellSize,
      );

      // Colored numbers using the region's pastel color
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: region.color,
            fontSize: cellSize * 0.48,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          cellCenter.dx - textPainter.width / 2,
          cellCenter.dy - textPainter.height / 2,
        ),
      );
    }
  }

  // 4. Placed continuous tangram pieces
  void _paintPlacedPieces(Canvas canvas) {
    for (final placed in placedPieces) {
      if (dragPiece != null && dragPiece!.id == placed.pieceId) {
        continue;
      }
      final piece = pieceCatalog[placed.pieceId];
      if (piece == null) continue;

      final isRotating = placed.pieceId == rotatingPieceId;
      final extraAngle = isRotating ? rotationAngle : 0.0;

      _paintContinuousTangramPiece(
        canvas: canvas,
        piece: piece,
        anchor: placed.anchor,
        turns: placed.turns,
        extraAngle: extraAngle,
      );
    }
  }

  void _paintContinuousTangramPiece({
    required Canvas canvas,
    required FlatgramPiece piece,
    required GridPoint anchor,
    required int turns,
    double extraAngle = 0.0,
    double opacity = 1.0,
  }) {
    final transformedCells = piece.transformedCells(anchor, turns);
    final origin = boardOffset;
    final path = buildPolyominoPath(
      transformedCells,
      cellSize,
      origin: origin,
      cornerRadius: 6.0,
    );

    final pivot = Offset(
      origin.dx + (anchor.x + 0.5) * cellSize,
      origin.dy + (anchor.y + 0.5) * cellSize,
    );

    if (extraAngle != 0.0) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(extraAngle);
      canvas.translate(-pivot.dx, -pivot.dy);
    }

    final isLightPiece = piece.defaultColor.computeLuminance() > 0.45;

    // 1. Drop shadow (softened for translucent material)
    canvas.drawPath(
      path.shift(const Offset(2.0, 3.0)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );

    // 2. Continuous tangram fill (50% opacity so colored regions & grid dots below are visible)
    canvas.drawPath(
      path,
      Paint()
        ..color = piece.defaultColor.withValues(alpha: pieceOpacity * opacity)
        ..style = PaintingStyle.fill,
    );

    // 3. Inner bevel stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
            .withValues(alpha: (isLightPiece ? 0.70 : 0.35) * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // 4. Outer crisp boundary stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = (isLightPiece ? const Color(0xFF64748B) : Colors.black)
            .withValues(alpha: (isLightPiece ? 0.65 : 0.50) * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // 5. Paint numbers on cells that have a value
    for (final localCell in piece.cells) {
      final val = piece.cellValues[localCell];
      if (val == null) continue;

      final tCell = anchor + localCell.rotateClockwise(turns);
      final cellCenter = Offset(
        origin.dx + tCell.x * cellSize + cellSize / 2,
        origin.dy + tCell.y * cellSize + cellSize / 2,
      );

      _paintCellNumber(
        canvas: canvas,
        center: cellCenter,
        value: val,
        textColor: isLightPiece ? FlatgramPalette.tangramPieceNumber : Colors.white,
        isLightPiece: isLightPiece,
        counterAngle: extraAngle != 0.0 ? -extraAngle : 0.0,
        opacity: opacity,
      );
    }

    if (extraAngle != 0.0) {
      canvas.restore();
    }
  }

  void _paintCellNumber({
    required Canvas canvas,
    required Offset center,
    required int value,
    Color textColor = FlatgramPalette.tangramPieceNumber,
    bool isLightPiece = true,
    double counterAngle = 0.0,
    double opacity = 1.0,
  }) {
    if (counterAngle != 0.0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(counterAngle);
      canvas.translate(-center.dx, -center.dy);
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(
          color: textColor.withValues(alpha: opacity),
          fontSize: cellSize * 0.40,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    if (counterAngle != 0.0) {
      canvas.restore();
    }
  }

  // 5. Real-time drag snap shadow preview
  void _paintSnapPreview(Canvas canvas) {
    if (dragPiece == null || dragAnchor == null) return;

    final transformedCells =
        dragPiece!.transformedCells(dragAnchor!, dragPiece!.turns);

    final path = buildPolyominoPath(
      transformedCells,
      cellSize,
      origin: boardOffset,
      cornerRadius: 6.0,
    );

    final previewFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final previewBorder = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawPath(path, previewFill);
    canvas.drawPath(path, previewBorder);
  }

  // 6. Selected piece continuous glow border
  void _paintSelectionGlow(Canvas canvas) {
    if (selectedPieceId == null) return;
    if (dragPiece != null && dragPiece!.id == selectedPieceId) return;

    PlacedPiece? targetPlaced;
    for (final p in placedPieces) {
      if (p.pieceId == selectedPieceId) {
        targetPlaced = p;
        break;
      }
    }
    if (targetPlaced == null) return;
    final piece = pieceCatalog[targetPlaced.pieceId];
    if (piece == null) return;

    final transformedCells =
        piece.transformedCells(targetPlaced.anchor, targetPlaced.turns);

    final path = buildPolyominoPath(
      transformedCells,
      cellSize,
      origin: boardOffset,
      cornerRadius: 6.0,
    );

    final glowPaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(
        alpha: 0.75 + 0.25 * math.sin(pulseValue * math.pi * 2),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final isRotating = targetPlaced.pieceId == rotatingPieceId;
    final extraAngle = isRotating ? rotationAngle : 0.0;

    if (extraAngle != 0.0) {
      final pivot = Offset(
        boardOffset.dx + (targetPlaced.anchor.x + 0.5) * cellSize,
        boardOffset.dy + (targetPlaced.anchor.y + 0.5) * cellSize,
      );
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(extraAngle);
      canvas.translate(-pivot.dx, -pivot.dy);
    }

    canvas.drawPath(path, glowPaint);

    if (extraAngle != 0.0) {
      canvas.restore();
    }
  }

  // 7. Piece currently being dragged under cursor/finger
  void _paintDragPiece(Canvas canvas) {
    final anchorOffset = dragVisualAnchor ?? dragScreenPos;
    if (dragPiece == null || anchorOffset == null) return;

    final turns = dragPiece!.turns;
    final localCells = dragPiece!.transformedCells(GridPoint.zero, turns);

    final path = buildPolyominoPath(
      localCells,
      cellSize,
      origin: anchorOffset,
      cornerRadius: 6.0,
    );

    // Drag shadow
    canvas.drawPath(
      path.shift(const Offset(3.0, 5.0)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );

    final isLightPiece = dragPiece!.defaultColor.computeLuminance() > 0.45;

    // Continuous tangram body (50% opacity)
    canvas.drawPath(
      path,
      Paint()
        ..color = dragPiece!.defaultColor.withValues(alpha: pieceOpacity)
        ..style = PaintingStyle.fill,
    );

    // Inner bevel stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
            .withValues(alpha: isLightPiece ? 0.70 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Outer crisp boundary stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = (isLightPiece ? const Color(0xFF64748B) : Colors.black)
            .withValues(alpha: isLightPiece ? 0.65 : 0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Numbers
    for (final localCell in dragPiece!.cells) {
      final val = dragPiece!.cellValues[localCell];
      if (val == null) continue;

      final tCell = localCell.rotateClockwise(turns);
      final cellCenter = Offset(
        anchorOffset.dx + tCell.x * cellSize + cellSize / 2,
        anchorOffset.dy + tCell.y * cellSize + cellSize / 2,
      );

      _paintCellNumber(
        canvas: canvas,
        center: cellCenter,
        value: val,
        textColor: isLightPiece ? FlatgramPalette.tangramPieceNumber : Colors.white,
        isLightPiece: isLightPiece,
        opacity: 0.95,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FlatgramPainter oldDelegate) {
    return true;
  }
}

/// Mini painter for drawing continuous tangram pieces inside tray cards.
class TrayPiecePainter extends CustomPainter {
  TrayPiecePainter({required this.piece, required this.turns});

  final FlatgramPiece piece;
  final int turns;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = piece.localBounds(turns);
    final pieceW = bounds.width;
    final pieceH = bounds.height;

    final cellPixels = math.min(
      size.width / math.max(pieceW, 1.0),
      size.height / math.max(pieceH, 1.0),
    ) * 0.90;

    final originX =
        (size.width - pieceW * cellPixels) / 2 - bounds.left * cellPixels;
    final originY =
        (size.height - pieceH * cellPixels) / 2 - bounds.top * cellPixels;

    final transformedCells = piece.transformedCells(GridPoint.zero, turns);
    final path = buildPolyominoPath(
      transformedCells,
      cellPixels,
      origin: Offset(originX, originY),
      cornerRadius: 4.0,
    );

    // Shadow
    canvas.drawPath(
      path.shift(const Offset(1, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    final isLight = piece.defaultColor.computeLuminance() > 0.45;

    // Continuous body
    canvas.drawPath(
      path,
      Paint()
        ..color = piece.defaultColor
        ..style = PaintingStyle.fill,
    );

    // Bevel stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = isLight
            ? const Color(0xFF64748B).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Numbers
    for (final localCell in piece.cells) {
      final val = piece.cellValues[localCell];
      if (val == null) continue;

      final tCell = localCell.rotateClockwise(turns);
      final center = Offset(
        originX + tCell.x * cellPixels + cellPixels / 2,
        originY + tCell.y * cellPixels + cellPixels / 2,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(
            color: isLight ? FlatgramPalette.tangramPieceNumber : Colors.white,
            fontSize: cellPixels * 0.40,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrayPiecePainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.piece != piece;
}
