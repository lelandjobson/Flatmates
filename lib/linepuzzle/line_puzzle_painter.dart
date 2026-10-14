import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../gridcraft/rules.dart';
import '../papercut/camera.dart';
import 'line_puzzle_models.dart';

const Color kLinePaper = Color(0xFFF4EFE4);
const Color kLineInk = Color(0xFF1A1A2E);
const Color kLineCut = Color(0xFF1B5E20);
const Color kLineFold = Color(0xFFFFB74D);
const Color kLineFail = Color(0xFFFF1744);

Offset? lineProject(PapercutCamera camera, Offset point, Size size) {
  return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
}

Color lineToolColor(LineTool tool) =>
    tool == LineTool.fold ? kLineFold : kLineCut;

Color linePaperTint(int? colorIndex) {
  if (colorIndex == null) return kLinePaper;
  final index = colorIndex.clamp(0, kRulePalette.length - 1);
  return Color.lerp(kLinePaper, kRulePalette[index], 0.46)!;
}

class LinePuzzlePainter extends CustomPainter {
  LinePuzzlePainter({
    required this.session,
    required this.camera,
    required this.failureFlash,
    this.tip,
  });

  final LineSession session;
  final PapercutCamera camera;
  final double failureFlash;

  /// Open end of the tool line, in world cells. Null sits on the last dot.
  final Offset? tip;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF12141C),
    );
    final unit = _unit(size);
    if (unit < 1) return;
    _paintPaper(canvas, size);
    _paintLattice(canvas, size, unit);
    _paintRegions(canvas, size, unit);
    _paintFlippers(canvas, size, unit);
    _paintDots(canvas, size, unit, onPath: false);
    _paintPath(canvas, size, unit);
    _paintDots(canvas, size, unit, onPath: true);
    _paintMarks(canvas, size, unit);
    _paintHead(canvas, size, unit);
  }

  double _unit(Size size) {
    final origin = session.puzzle.bounds.rect.center;
    final a = lineProject(camera, origin, size);
    final b = lineProject(camera, origin + const Offset(1, 0), size);
    if (a == null || b == null) return 0;
    return (b - a).distance;
  }

  Offset? _at(Offset point, Size size) => lineProject(camera, point, size);

  void _paintPaper(Canvas canvas, Size size) {
    final rect = session.puzzle.bounds.rect;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final screen = _at(corners[i], size);
      if (screen == null) return;
      if (i == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = linePaperTint(session.paperColor));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFD9D0C2),
    );
  }

  void _paintLattice(Canvas canvas, Size size, double unit) {
    final bounds = session.puzzle.bounds;
    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = math.max(1.0, unit * 0.035);
    for (var x = bounds.left; x <= bounds.right; x++) {
      for (var y = bounds.top; y <= bounds.bottom; y++) {
        final here = LinePoint(x, y);
        if (!session.puzzle.hasDot(here)) continue;
        final from = _at(here.offset, size);
        if (from == null) continue;
        final east = LinePoint(x + 1, y);
        if (x < bounds.right && session.puzzle.hasDot(east)) {
          final to = _at(east.offset, size);
          if (to != null) canvas.drawLine(from, to, paint);
        }
        final north = LinePoint(x, y + 1);
        if (y < bounds.bottom && session.puzzle.hasDot(north)) {
          final to = _at(north.offset, size);
          if (to != null) canvas.drawLine(from, to, paint);
        }
      }
    }
  }

  void _paintRegions(Canvas canvas, Size size, double unit) {
    final pulse = failureFlash <= 0
        ? 0.0
        : math.sin(failureFlash * math.pi * 3).abs();
    for (var i = 0; i < session.puzzle.regions.length; i++) {
      final region = session.puzzle.regions[i];
      final path = _ringPath(region.ring, size);
      if (path == null) continue;
      final failing = session.failure?.regionIndex == i;
      final solved = session.solvedBorders.contains(i);
      Color fill = const Color(0x00000000);
      if (failing && pulse > 0) {
        fill = kLineFail.withValues(alpha: 0.18 + 0.55 * pulse);
      } else if (solved) {
        final tint = region.color == null
            ? const Color(0xFF2E7D32)
            : kRulePalette[region.color!.clamp(0, kRulePalette.length - 1)];
        fill = tint.withValues(alpha: 0.22);
      } else {
        fill = const Color(0x0A1A1A2E);
      }
      canvas.drawPath(path, Paint()..color = fill);
      final ink = failing ? Color.lerp(kLineInk, kLineFail, pulse)! : kLineInk;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              math.max(1.6, unit * 0.07) + (failing ? 2.4 * pulse : 0)
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
    }
  }

  void _paintFlippers(Canvas canvas, Size size, double unit) {
    final side = unit * 0.58;
    for (final flip in session.puzzle.flippers) {
      final screen = _at(flip.at.offset, size);
      if (screen == null) continue;
      final color = kRulePalette[flip.color.clamp(0, kRulePalette.length - 1)];
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: screen, width: side, height: side),
        Radius.circular(side * 0.18),
      );
      final active = session.paperColor == flip.color;
      canvas.drawRRect(rect, Paint()..color = color);
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2.4 : 1.4
          ..color = active ? Colors.white : const Color(0xFFF7F4EE),
      );
    }
  }

  void _paintDots(
    Canvas canvas,
    Size size,
    double unit, {
    required bool onPath,
  }) {
    final bounds = session.puzzle.bounds;
    final normal = math.max(2.2, unit * 0.11);
    final hollow = math.max(4.0, unit * 0.2);
    for (var x = bounds.left; x <= bounds.right; x++) {
      for (var y = bounds.top; y <= bounds.bottom; y++) {
        final point = LinePoint(x, y);
        if (!session.puzzle.hasDot(point)) continue;
        if (session.puzzle.flipperColor(point) != null) continue;
        final uses = _uses(point);
        final budget = session.puzzle.budget(point);
        final doubled = budget > 1;
        final screen = _at(point.offset, size);
        if (screen == null) continue;
        if (!onPath && doubled && uses == 0) {
          canvas.drawCircle(
            screen,
            hollow,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.6, unit * 0.06)
              ..color = kLineInk,
          );
        } else if (!onPath && !doubled && uses == 0) {
          canvas.drawCircle(screen, normal, Paint()..color = kLineInk);
        } else if (onPath && doubled && uses == 1) {
          canvas.drawCircle(screen, normal * 1.15, Paint()..color = kLineInk);
        }
      }
    }
  }

  void _paintPath(Canvas canvas, Size size, double unit) {
    final width = (unit * 0.26).clamp(3.5, 14.0);
    final strokes = session.strokes;
    for (var i = 0; i < strokes.length; i++) {
      final screens = _screens(strokes[i].points, size);
      if (i == strokes.length - 1) {
        final end = tip;
        if (end != null) {
          final screen = _at(end, size);
          if (screen != null &&
              (screens.isEmpty || (screens.last - screen).distance > 0.5)) {
            screens.add(screen);
          }
        }
      }
      _stroke(canvas, screens, lineToolColor(strokes[i].tool), width);
    }
  }

  void _paintMarks(Canvas canvas, Size size, double unit) {
    final pulse = failureFlash <= 0
        ? 0.0
        : math.sin(failureFlash * math.pi * 3).abs();
    for (var i = 0; i < session.puzzle.regions.length; i++) {
      final region = session.puzzle.regions[i];
      final anchor = lineRegionAnchor(region.ring);
      final screen = _at(anchor, size);
      if (screen == null) continue;
      final failing = session.failure?.regionIndex == i && pulse > 0;
      var cursor = screen;
      if (region.order != null) {
        _paintNumber(canvas, cursor, unit, region.order!, failing: failing);
        cursor = cursor + Offset(0, unit * 0.42);
      }
      if (region.color != null) {
        _paintColorMark(canvas, cursor, unit, region.color!, failing: failing);
      }
    }
  }

  void _paintNumber(
    Canvas canvas,
    Offset center,
    double unit,
    int number, {
    required bool failing,
  }) {
    final side = math.max(14.0, unit * 0.62) + (failing ? 4 : 0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: side, height: side),
      Radius.circular(side * 0.2),
    );
    final fill = failing ? Color.lerp(kLineInk, kLineFail, 0.85)! : kLineInk;
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = failing ? kLineFail : Colors.white,
    );
    _label(
      canvas,
      center,
      '$number',
      math.max(11.0, side * 0.55),
      Colors.white,
    );
  }

  void _paintColorMark(
    Canvas canvas,
    Offset center,
    double unit,
    int color, {
    required bool failing,
  }) {
    final side = math.max(10.0, unit * 0.36) + (failing ? 3 : 0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: side, height: side),
      Radius.circular(3),
    );
    final fill = failing
        ? kLineFail
        : kRulePalette[color.clamp(0, kRulePalette.length - 1)];
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white,
    );
  }

  void _paintHead(Canvas canvas, Size size, double unit) {
    final at = tip ?? session.head?.offset;
    if (at == null) return;
    final screen = _at(at, size);
    if (screen == null) return;
    final radius = math.max(4.0, unit * 0.16);
    canvas.drawCircle(screen, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      screen,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = lineToolColor(session.tool),
    );
  }

  Path? _ringPath(List<LinePoint> ring, Size size) {
    final path = Path();
    for (var i = 0; i < ring.length; i++) {
      final screen = _at(ring[i].offset, size);
      if (screen == null) return null;
      if (i == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    path.close();
    return path;
  }

  List<Offset> _screens(List<LinePoint> points, Size size) {
    final projected = <Offset>[];
    for (final point in points) {
      final screen = _at(point.offset, size);
      if (screen != null) projected.add(screen);
    }
    return projected;
  }

  void _stroke(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final style = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path,
      style
        ..strokeWidth = width + 3.2
        ..color = const Color(0xFFF7F4EE),
    );
    canvas.drawPath(
      path,
      style
        ..strokeWidth = width
        ..color = color,
    );
  }

  void _label(
    Canvas canvas,
    Offset center,
    String text,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  int _uses(LinePoint point) {
    var count = 0;
    for (final stroke in session.strokes) {
      for (final dot in stroke.points) {
        if (dot == point) count++;
      }
    }
    return count;
  }

  @override
  bool shouldRepaint(LinePuzzlePainter oldDelegate) => true;
}
