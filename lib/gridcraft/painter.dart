import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/polygon_union.dart';
import '../papercut/camera.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'celebrate.dart';
import 'fold.dart';
import 'rules.dart';
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
    this.pickedPiece,
    this.ghostCuts = const [],
    this.blockedCuts = const [],
    this.ghostSeparation,
    this.fillShapes = false,
    this.draft = const [],
    this.picked = const {},
    this.marquee,
    this.marqueeCross = false,
    this.gatheredColors = const {},
    this.nextNumber = 1,
    this.failure,
    this.failureFlash = 0,
    this.darkness = false,
    this.lightOrigin,
    this.lightDirection,
    this.lightThrow,
    this.foldLine,
    this.foldBend,
    this.foldBendT = 1,
    this.collisionLeft = const [],
    this.celebrations = const [],
    this.celebrateSeconds = 0,
    this.lit = const [],
    this.clearedRings = const {},
  });

  final PapercutCamera camera;
  final GridStep step;
  final PapercutSheet sheet;
  final ScissorMarch? march;
  final double flash;
  final double? rulerX;
  final bool showRuler;
  final Set<int> selected;

  /// Paper piece the select tool is holding. Drawn on top of the sheet outline.
  final int? pickedPiece;
  final List<(Offset, Offset)> ghostCuts;
  final List<(Offset, Offset)> blockedCuts;

  /// Editor draws polygons as filled paper and skips the sheet fill.
  final bool fillShapes;
  final List<Offset> draft;

  /// Rule widgets the editor has selected.
  final Set<RulePick> picked;

  /// Screen-space drag rectangle. Dashed when [marqueeCross] is set.
  final Rect? marquee;
  final bool marqueeCross;

  /// Color gems already collected. They are not drawn.
  final Set<int> gatheredColors;

  /// Number gems below this have been taken and are not drawn.
  final int nextNumber;

  /// Entity flashing red because it caused a failure.
  final FailureCue? failure;

  /// 0–1 progress of the failure flash. The painter pulses red across it.
  final double failureFlash;

  final bool darkness;
  final Offset? lightOrigin;
  final Offset? lightDirection;
  final double? lightThrow;

  /// Folder crease preview, in the same space as the drawn sheet.
  final (Offset, Offset)? foldLine;

  /// Joint index swinging onto the sheet, with [foldBendT] in 0–1.
  final int? foldBend;
  final double foldBendT;

  /// Remaining piece-tool collisions, parallel to blueprint pieces.
  final List<int?> collisionLeft;

  /// In-progress light-ups and leftover bursts.
  final List<CelebrationPlayback> celebrations;

  /// Seconds into the celebration clock.
  final double celebrateSeconds;

  /// Completed pieces that stay filled green after their light-up.
  final List<CelebrationPlayback> lit;

  /// Blueprint rings already cut out. Their outlines are not drawn.
  final Set<int> clearedRings;

  /// Display nudge for the piece the blade is cutting. Overrides ownership
  /// when another piece's model outline still contains that point.
  final Offset? ghostSeparation;

  @override
  void paint(Canvas canvas, Size size) {
    _paintUnitGrid(canvas, size);
    if (fillShapes) _paintPaperFrame(canvas, size);
    if (!fillShapes) {
      final order = [for (var i = 0; i < sheet.pieces.length; i++) i]..sort((
        a,
        b,
      ) {
        final depthA = foldDepth(
          polygonCentroid(sheet.pieces[a].vertices),
          sheet.folds,
        );
        final depthB = foldDepth(
          polygonCentroid(sheet.pieces[b].vertices),
          sheet.folds,
        );
        return depthA.compareTo(depthB);
      });
      for (final index in order) {
        final piece = sheet.pieces[index];
        if (_bursting(piece.id)) continue;
        _fillDisplayed(canvas, size, piece, const Color(0xFFFFF3B0));
        _stroke(
          canvas,
          size,
          _shownRing(piece.vertices, piece.separation),
          const Color(0xFF1A1A2E),
          width: 1.5,
          close: true,
        );
      }
      final picked = pickedPiece;
      if (picked != null && picked >= 0 && picked < sheet.pieces.length) {
        final piece = sheet.pieces[picked];
        _stroke(
          canvas,
          size,
          _moved(piece.vertices, piece.separation),
          const Color(0xE6FFFFFF),
          width: 2.5,
          close: true,
        );
      }
    }
    _paintBlueprint(canvas, size);
    _paintDraft(canvas, size);
    _paintRules(canvas, size);
    for (final stroke in sheet.cutStrokes) {
      for (final piece in sheet.pieces) {
        if (_bursting(piece.id)) continue;
        for (final mark in cutMarksOnPiece(stroke, piece)) {
          _stroke(
            canvas,
            size,
            [for (final point in mark) _seen(point) + piece.separation],
            const Color(0xFF000000),
            width: 1.25,
          );
        }
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
    final ink = Color.fromRGBO(102, 187, 106, 0.35 + 0.65 * flash);
    for (final preview in ghostCuts) {
      final shown = _shiftSegment(preview.$1, preview.$2);
      _stroke(canvas, size, [shown.$1, shown.$2], ink, width: 4);
      final terminal = _project(shown.$2, size);
      if (terminal != null) _paintTerminal(canvas, terminal, ink);
    }
    final blocked = const Color(0xFFE53935);
    for (final preview in blockedCuts) {
      final shown = _shiftSegment(preview.$1, preview.$2);
      _stroke(canvas, size, [shown.$1, shown.$2], blocked, width: 4);
      final terminal = _project(shown.$2, size);
      if (terminal != null) _paintTerminal(canvas, terminal, blocked);
    }
    _paintScores(canvas, size);
    _paintMarks(canvas, size);
    _paintFoldLine(canvas, size);
    _paintNoFold(canvas, size);
    if (darkness && !fillShapes) _paintDarkness(canvas, size);
    _paintCelebration(canvas, size);
    _paintMarquee(canvas);
  }

  Offset _seen(Offset point) => displayPoint(
    point,
    sheet.folds,
    bend: foldBend,
    bendT: foldBendT,
  );

  bool _bursting(String id) {
    for (final play in lit) {
      if (play.pieceId == id) return true;
    }
    for (final play in celebrations) {
      if (play.pieceId != id) continue;
      if (play.local(celebrateSeconds) >= Celebration.fillSeconds) return true;
    }
    return false;
  }

  void _paintCelebration(Canvas canvas, Size size) {
    for (final play in lit) {
      _paintSolidFill(
        canvas,
        size,
        play.celebration,
        play.anchor,
        1,
        play.fillColors,
      );
    }
    for (final play in celebrations) {
      final local = play.local(celebrateSeconds);
      if (local < 0) continue;
      final celebration = play.celebration;
      final shift = play.anchor;
      if (!play.burst) {
        final fill = (local / Celebration.fillSeconds).clamp(0.0, 1.0);
        _paintSolidFill(
          canvas,
          size,
          celebration,
          shift,
          fill,
          play.fillColors,
        );
        continue;
      }
      final burst =
          local - Celebration.fillSeconds - Celebration.holdSeconds;
      if (burst < 0) {
        final fill = (local / Celebration.fillSeconds).clamp(0.0, 1.0);
        _paintSolidFill(
          canvas,
          size,
          celebration,
          shift,
          fill,
          play.fillColors,
        );
        continue;
      }
      if (celebration.cells.isEmpty || burst > Celebration.burstSeconds) {
        continue;
      }
      _paintSparks(canvas, size, play, burst);
    }
  }

  void _paintSparks(
    Canvas canvas,
    Size size,
    CelebrationPlayback play,
    double burst,
  ) {
    final celebration = play.celebration;
    final shift = play.anchor;
    final life = (burst / Celebration.burstSeconds).clamp(0.0, 1.0);
    final sparks = Path();
    final streaks = Path();
    for (final cell in celebration.cells) {
      final speed = celebration.gridSpacing * 3.2 * cell.reach;
      final now = sparkPosition(cell, burst, speed: speed);
      final earlier = sparkPosition(
        cell,
        math.max(0, burst - 0.045),
        speed: speed,
      );
      final head = _project(_seen(now) + shift, size);
      final tail = _project(_seen(earlier) + shift, size);
      if (head == null) continue;
      final edge = _project(
        _seen(now) + shift + Offset(celebration.cellSize, 0),
        size,
      );
      final radius = edge == null
          ? 2.0
          : math.max(0.8, (edge - head).distance * 0.55 * (1 - life));
      sparks.addOval(Rect.fromCircle(center: head, radius: radius));
      if (tail != null) {
        streaks.moveTo(tail.dx, tail.dy);
        streaks.lineTo(head.dx, head.dy);
      }
    }
    final ends = play.sparkColors;
    final color = Color.lerp(ends[0], ends[1], life)!.withValues(alpha: 1 - life);
    canvas.drawPath(
      streaks,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(sparks, Paint()..color = color);
  }

  void _paintSolidFill(
    Canvas canvas,
    Size size,
    Celebration celebration,
    Offset shift,
    double t,
    List<Color> colors,
  ) {
    if (celebration.ring.length < 3 || t <= 0) return;
    final shown = [for (final point in celebration.ring) _seen(point) + shift];
    final centroid = polygonCentroid(shown);
    List<Offset> grown(List<Offset> ring) => [
      for (final point in ring) Offset.lerp(centroid, point, t)!,
    ];
    final path = _path(grown(shown), size, close: true);
    if (path == null) return;
    for (final hole in celebration.holes) {
      final holePath = _path(
        grown([for (final point in hole) _seen(point) + shift]),
        size,
        close: true,
      );
      if (holePath != null) path.addPath(holePath, Offset.zero);
    }
    path.fillType = PathFillType.evenOdd;
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.bottomRight,
          colors,
        ),
    );
  }

  double get _failurePulse {
    if (failure == null || failureFlash <= 0) return 0;
    return math.sin(failureFlash * math.pi * 3).abs();
  }

  void _paintBlueprint(Canvas canvas, Size size) {
    for (var i = 0; i < step.polygons.length; i++) {
      if (clearedRings.contains(i)) continue;
      final ring = step.polygons[i];
      if (ring.length < 2) continue;
      final selectedPolygon = selected.contains(i);
      final closedRing = step.isRingClosed(i);
      if (fillShapes && closedRing) {
        _fill(canvas, size, ring, const Color(0xFFFFF3B0));
      }
      final styles = step.edgeStyleOf(i);
      final edges = step.edgeCountOf(i);
      for (var edge = 0; edge < edges; edge++) {
        final a = ring[edge];
        final b = ring[(edge + 1) % ring.length];
        final penciled = styles[edge] == EdgeStyle.penciled;
        final back = !fillShapes && showingBack(a, sheet.folds);
        final failing =
            failure?.kind == FailureKind.piece && failure?.index == i;
        final pulse = failing ? _failurePulse : 0.0;
        final color = pulse > 0
            ? Color.lerp(
                const Color(0xFF1565C0),
                const Color(0xFFFF1744),
                pulse,
              )!
            : selectedPolygon
            ? const Color(0xFFFFD54F)
            : back
            ? const Color(0x881565C0)
            : const Color(0xFF1565C0);
        final width = pulse > 0
            ? 2.0 + 4 * pulse
            : (selectedPolygon ? 3.0 : 2.0);
        if (penciled) {
          _paintFoldMark(canvas, size, a, b, color, width);
        } else {
          for (final shown in _ownedSegments(a, b)) {
            _stroke(canvas, size, [shown.$1, shown.$2], color, width: width);
          }
        }
      }
      final budget = i < collisionLeft.length
          ? collisionLeft[i]
          : step.collisionOf(i);
      if (budget != null) {
        final at = collisionAnchor(ring);
        _paintCount(
          canvas,
          size,
          at,
          budget,
          shift: fillShapes ? Offset.zero : markSeparation(at, sheet.pieces),
        );
      }
    }
  }

  /// A fold mark. Player creases are black. Puzzle fold lines use the outline
  /// color. Dashes are measured from the world origin, then carried with the
  /// piece, so a split line keeps one pattern.
  void _paintFoldMark(
    Canvas canvas,
    Size size,
    Offset a,
    Offset b,
    Color color,
    double width,
  ) {
    void paint(Offset from, Offset to, Offset shift) {
      for (final dash in globalDashSegments(
        from,
        to,
        spacing: step.gridSpacing,
      )) {
        _stroke(
          canvas,
          size,
          [_seen(dash.$1) + shift, _seen(dash.$2) + shift],
          color,
          width: width,
        );
      }
    }

    if (fillShapes || sheet.pieces.isEmpty) {
      paint(a, b, Offset.zero);
      return;
    }
    for (final piece in sheet.pieces) {
      if (_bursting(piece.id)) continue;
      for (final part in segmentOnPiece(a, b, piece)) {
        paint(part.$1, part.$2, piece.separation);
      }
    }
  }

  /// Blueprint edges clipped onto each paper piece. The editor draws the
  /// authored ring, because it has no cut sheet.
  List<(Offset, Offset)> _ownedSegments(Offset a, Offset b) {
    if (fillShapes || sheet.pieces.isEmpty) {
      final shown = _shiftSegment(_seen(a), _seen(b));
      return [(shown.$1, shown.$2)];
    }
    final placed = <(Offset, Offset)>[];
    for (final piece in sheet.pieces) {
      if (_bursting(piece.id)) continue;
      for (final part in segmentOnPiece(a, b, piece)) {
        placed.add((
          _seen(part.$1) + piece.separation,
          _seen(part.$2) + piece.separation,
        ));
      }
    }
    return placed;
  }

  void _paintCount(
    Canvas canvas,
    Size size,
    Offset at,
    int count, {
    Offset shift = Offset.zero,
  }) {
    final screen = _project(_seen(at) + shift, size);
    if (screen == null) return;
    final painter = TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          color: Color(0xFF0D47A1),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      screen - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintScores(Canvas canvas, Size size) {
    const ink = Color(0xFF000000);
    for (final score in sheet.scores) {
      _paintFoldMark(canvas, size, score.a, score.b, ink, 1.25);
    }
    for (final joint in sheet.folds) {
      if (joint.facing == FoldFacing.unfolded) continue;
      _paintFoldMark(canvas, size, joint.a, joint.b, ink, 1.25);
    }
  }

  void _paintMarks(Canvas canvas, Size size) {
    for (final mark in sheet.marks) {
      final shown = [
        for (final point in mark.points) _seen(point),
      ];
      _stroke(canvas, size, shown, const Color(0xFF5D4037), width: 1.5);
    }
  }

  void _paintFoldLine(Canvas canvas, Size size) {
    final line = foldLine;
    if (line == null) return;
    _paintFoldMark(
      canvas,
      size,
      line.$1,
      line.$2,
      const Color(0xFFFFB74D),
      2,
    );
  }

  void _paintNoFold(Canvas canvas, Size size) {
    for (final zone in step.permutation.noFold) {
      if (zone.length < 3) continue;
      _fill(canvas, size, zone, const Color(0x33E53935));
    }
  }

  void _paintDarkness(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = const Color(0xE6000000));
    final origin = lightOrigin;
    final direction = lightDirection;
    final reach = lightThrow;
    if (origin != null &&
        direction != null &&
        reach != null &&
        reach > 0 &&
        direction.distance > 1e-6) {
      final ray = direction / direction.distance;
      final tip = origin + ray * reach;
      final left = origin + _turn(ray, flashlightHalfAngle) * reach;
      final right = origin + _turn(ray, -flashlightHalfAngle) * reach;
      final apex = _project(origin, size);
      final far = _project(tip, size);
      final leftScreen = _project(left, size);
      final rightScreen = _project(right, size);
      if (apex != null &&
          far != null &&
          leftScreen != null &&
          rightScreen != null) {
        final path = Path()
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(leftScreen.dx, leftScreen.dy)
          ..lineTo(far.dx, far.dy)
          ..lineTo(rightScreen.dx, rightScreen.dy)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..blendMode = BlendMode.dstOut
            ..shader = ui.Gradient.linear(
              apex,
              far,
              const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            ),
        );
      }
    }
    canvas.restore();
  }

  Offset _turn(Offset vector, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(vector.dx * c - vector.dy * s, vector.dx * s + vector.dy * c);
  }

  void _paintPaperFrame(Canvas canvas, Size size) {
    final paper = step.paper;
    if (paper.width < 1e-6 && paper.height < 1e-6) return;
    final ring = [
      paper.topLeft,
      paper.topRight,
      paper.bottomRight,
      paper.bottomLeft,
    ];
    _fill(canvas, size, ring, const Color(0x33FFF3B0));
    _stroke(
      canvas,
      size,
      ring,
      const Color(0xAAFFFFFF),
      width: 1.6,
      close: true,
    );
  }

  void _paintDraft(Canvas canvas, Size size) {
    if (draft.length < 2) {
      if (draft.length == 1) {
        final screen = _project(draft.first, size);
        if (screen != null) {
          canvas.drawCircle(
            screen,
            4,
            Paint()..color = const Color(0xFFFFD54F),
          );
        }
      }
      return;
    }
    _stroke(canvas, size, draft, const Color(0xFFFFD54F), width: 2);
    for (final point in draft) {
      final screen = _project(point, size);
      if (screen == null) continue;
      canvas.drawCircle(screen, 3.5, Paint()..color = const Color(0xFFFFD54F));
    }
  }

  void _paintRules(Canvas canvas, Size size) {
    final rules = step.rules;
    if (rules.isEmpty) return;
    for (var i = 0; i < rules.seams.length; i++) {
      final edge = _shiftedEdge(rules.seams[i]);
      final on = _markOn(RuleKind.seam, i);
      _stroke(
        canvas,
        size,
        [edge.a, edge.b],
        on ? const Color(0xFFFFD54F) : const Color(0xFFFF8A65),
        width: on ? 5 : 3,
        dashed: true,
      );
    }
    for (var i = 0; i < rules.arrows.length; i++) {
      _paintArrow(
        canvas,
        size,
        _shiftedEdge(rules.arrows[i]),
        selected: _markOn(RuleKind.arrow, i),
      );
    }
    for (var i = 0; i < rules.docks.length; i++) {
      final screen = _project(_shifted(rules.docks[i]), size);
      if (screen == null) continue;
      if (_markOn(RuleKind.dock, i)) _markHalo(canvas, screen);
      _paintDiamond(canvas, screen, const Color(0xFF80DEEA));
    }
    for (var i = 0; i < rules.links.length; i++) {
      final mark = rules.links[i];
      final screen = _project(_shifted(mark.point), size);
      if (screen == null) continue;
      if (_markOn(RuleKind.link, i)) _markHalo(canvas, screen);
      final color = kRulePalette[mark.pair.abs() % kRulePalette.length];
      canvas.drawCircle(screen, 7, Paint()..color = color);
      canvas.drawCircle(
        screen,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
      _paintLabel(canvas, screen, '${mark.pair}');
    }
    for (var i = 0; i < rules.colors.length; i++) {
      if (gatheredColors.contains(i)) continue;
      final mark = rules.colors[i];
      final screen = _project(_shifted(mark.point), size);
      if (screen == null) continue;
      if (_markOn(RuleKind.color, i)) _markHalo(canvas, screen);
      final index = mark.color.clamp(0, kRulePalette.length - 1).toInt();
      final failing =
          failure?.kind == FailureKind.color && failure?.index == i;
      final pulse = failing ? _failurePulse : 0.0;
      final color = Color.lerp(
        kRulePalette[index],
        const Color(0xFFFF1744),
        pulse,
      )!;
      final radius = 6.5 + 5 * pulse;
      canvas.drawCircle(screen, radius, Paint()..color = color);
      canvas.drawCircle(
        screen,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = pulse > 0 ? const Color(0xFFFF1744) : Colors.white,
      );
    }
    for (var i = 0; i < rules.numbers.length; i++) {
      final mark = rules.numbers[i];
      if (mark.number < nextNumber) continue;
      final screen = _project(_shifted(mark.point), size);
      if (screen == null) continue;
      if (_markOn(RuleKind.number, i)) _markHalo(canvas, screen, radius: 12);
      final failing =
          failure?.kind == FailureKind.number && failure?.index == i;
      final pulse = failing ? _failurePulse : 0.0;
      final fill = Color.lerp(
        const Color(0xFF1A1A2E),
        const Color(0xFFFF1744),
        pulse,
      )!;
      final side = 14.0 + 6 * pulse;
      canvas.drawRect(
        Rect.fromCenter(center: screen, width: side, height: side),
        Paint()..color = fill,
      );
      canvas.drawRect(
        Rect.fromCenter(center: screen, width: side, height: side),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = pulse > 0 ? const Color(0xFFFF1744) : Colors.white,
      );
      _paintLabel(canvas, screen, '${mark.number}');
    }
    for (var i = 0; i < rules.forbidden.length; i++) {
      final screen = _project(_shifted(rules.forbidden[i]), size);
      if (screen == null) continue;
      if (_markOn(RuleKind.forbidden, i)) _markHalo(canvas, screen, radius: 11);
      _paintTerminal(canvas, screen, const Color(0xFFEF5350));
    }
  }

  Offset _shifted(Offset point) => point + markSeparation(point, sheet.pieces);

  GridEdge _shiftedEdge(GridEdge edge) {
    final shift = markSeparation(
      Offset((edge.a.dx + edge.b.dx) / 2, (edge.a.dy + edge.b.dy) / 2),
      sheet.pieces,
    );
    if (shift == Offset.zero) return edge;
    return GridEdge(edge.a + shift, edge.b + shift);
  }

  bool _markOn(RuleKind kind, int index) =>
      picked.contains(RulePick(kind, index));

  void _markHalo(Canvas canvas, Offset screen, {double radius = 13}) {
    canvas.drawCircle(
      screen,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD54F),
    );
  }

  void _paintMarquee(Canvas canvas) {
    final rect = marquee;
    if (rect == null || rect.width < 1 && rect.height < 1) return;
    canvas.drawRect(rect, Paint()..color = const Color(0x33FFFFFF));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    if (!marqueeCross) {
      canvas.drawRect(rect, paint);
      return;
    }
    const dash = 6.0;
    const gap = 4.0;
    final sides = [
      (rect.topLeft, rect.topRight),
      (rect.topRight, rect.bottomRight),
      (rect.bottomRight, rect.bottomLeft),
      (rect.bottomLeft, rect.topLeft),
    ];
    for (final (a, b) in sides) {
      final delta = b - a;
      final length = delta.distance;
      if (length < 1e-6) continue;
      final dir = delta / length;
      var traveled = 0.0;
      while (traveled < length) {
        final end = math.min(traveled + dash, length);
        canvas.drawLine(a + dir * traveled, a + dir * end, paint);
        traveled += dash + gap;
      }
    }
  }

  void _paintArrow(
    Canvas canvas,
    Size size,
    GridEdge edge, {
    bool selected = false,
  }) {
    final a = _project(edge.a, size);
    final b = _project(edge.b, size);
    if (a == null || b == null) return;
    if (selected) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
    final paint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    final delta = b - a;
    final len = delta.distance;
    if (len < 4) return;
    final dir = delta / len;
    final normal = Offset(-dir.dy, dir.dx);
    final tip = b;
    final base = b - dir * 9;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * 4.5).dx, (base + normal * 4.5).dy)
      ..lineTo((base - normal * 4.5).dx, (base - normal * 4.5).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFD54F));
  }

  void _paintDiamond(Canvas canvas, Offset screen, Color color) {
    final path = Path()
      ..moveTo(screen.dx, screen.dy - 7)
      ..lineTo(screen.dx + 6, screen.dy)
      ..lineTo(screen.dx, screen.dy + 7)
      ..lineTo(screen.dx - 6, screen.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintLabel(Canvas canvas, Offset screen, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      screen - Offset(painter.width / 2, painter.height / 2),
    );
  }

  /// Green X at the far end of a preview, in screen pixels.
  void _paintTerminal(Canvas canvas, Offset screen, Color color) {
    const arm = 7.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      screen + const Offset(-arm, -arm),
      screen + const Offset(arm, arm),
      paint,
    );
    canvas.drawLine(
      screen + const Offset(-arm, arm),
      screen + const Offset(arm, -arm),
      paint,
    );
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
    final dot = Paint()..color = Colors.grey.shade400.withValues(alpha: 0.55);
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

  void _fillDisplayed(Canvas canvas, Size size, PapercutPiece piece, Color color) {
    final path = _path(
      _shownRing(piece.vertices, piece.separation),
      size,
      close: true,
    );
    if (path == null) return;
    for (final hole in piece.holes) {
      final holePath = _path(
        _shownRing(hole, piece.separation),
        size,
        close: true,
      );
      if (holePath != null) path.addPath(holePath, Offset.zero);
    }
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = color);
  }

  List<Offset> _shownRing(List<Offset> ring, Offset shift) {
    return _moved(
      displayRing(ring, sheet.folds, bend: foldBend, bendT: foldBendT),
      shift,
    );
  }

  List<Offset> _moved(List<Offset> ring, Offset shift) {
    if (shift == Offset.zero) return ring;
    return [for (final point in ring) point + shift];
  }

  List<List<Offset>> _onEachOwner(List<Offset> stroke) {
    if (stroke.isEmpty) return const [];
    final shifted = <List<Offset>>[];
    for (final piece in sheet.pieces) {
      for (final mark in cutMarksOnPiece(stroke, piece)) {
        shifted.add(_moved(mark, piece.separation));
      }
    }
    if (shifted.isEmpty) shifted.add(stroke);
    return shifted;
  }

  (Offset, Offset) _shiftSegment(Offset a, Offset b) {
    final shift = ghostSeparation;
    if (shift != null) return (a + shift, b + shift);
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
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  @override
  bool shouldRepaint(covariant GridPuzzlePainter oldDelegate) => true;
}
