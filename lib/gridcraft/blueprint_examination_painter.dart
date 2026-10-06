import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import '../ui/dimension_chrome.dart';
import 'blueprint.dart';
import 'dimension_measure.dart';
import 'fold.dart';

const Color _blueprintInk = Color(0xFF1565C0);
const Color _gridInk = Color(0x47FFFFFF);
const Color _toolInk = Color(0xFFFFFFFF);
const Color _labelFree = Color(0xFFB0B0B0);

/// Left ruler, and the vertices that share its world Y.
const Color kDimensionLeft = Color(0xFFFFEB3B);

/// Bottom ruler, and the vertices that share its world X.
const Color kDimensionBottom = Color(0xFF42A5F5);

/// Colinear vertex marks. Two axes at one vertex stack, blue then yellow.
const double kDimensionDotOpacity = 0.5;

Color dimensionAxisColor(DimensionAxis axis) {
  return axis == DimensionAxis.vertical ? kDimensionLeft : kDimensionBottom;
}

/// Outlines, the grid inside each blueprint piece, snap guides, and locked
/// dimensions. The screen rulers are [DimensionChromePainter].
class BlueprintExaminationPainter extends CustomPainter {
  BlueprintExaminationPainter({
    required this.camera,
    required this.step,
    required this.locked,
    required this.guides,
  });

  final PapercutCamera camera;
  final GridStep step;
  final List<LockedDimension> locked;
  final List<SnapGuide> guides;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrids(canvas, size);
    _paintOutlines(canvas, size);
    _paintGuides(canvas, size);
    _paintLocked(canvas, size);
  }

  void _paintGrids(Canvas canvas, Size size) {
    for (final ring in step.closedPolygons) {
      if (ring.length < 3) continue;
      for (final segment in paperGridSegments(
        ring: ring,
        holes: const [],
        spacing: step.gridSpacing,
      )) {
        _stroke(canvas, size, [segment.$1, segment.$2], _gridInk, width: 0.7);
      }
    }
  }

  void _paintOutlines(Canvas canvas, Size size) {
    for (var i = 0; i < step.polygons.length; i++) {
      final ring = step.polygons[i];
      if (ring.length < 2) continue;
      final styles = step.edgeStyleOf(i);
      final edges = step.edgeCountOf(i);
      for (var edge = 0; edge < edges; edge++) {
        final a = ring[edge];
        final b = ring[(edge + 1) % ring.length];
        final penciled = styles[edge] == EdgeStyle.penciled;
        if (penciled) {
          for (final dash in globalDashSegments(
            a,
            b,
            spacing: step.gridSpacing * foldDashScale,
          )) {
            _stroke(canvas, size, [dash.$1, dash.$2], _blueprintInk, width: 2);
          }
        } else {
          _stroke(canvas, size, [a, b], _blueprintInk, width: 2);
        }
      }
    }
  }

  void _paintGuides(Canvas canvas, Size size) {
    final dots = {
      DimensionAxis.horizontal: <Offset>{},
      DimensionAxis.vertical: <Offset>{},
    };
    for (final guide in guides) {
      final color = dimensionAxisColor(guide.axis);
      final along = _screenAlong(guide, size);
      if (along != null) {
        final scan = Paint()
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 1;
        if (guide.axis == DimensionAxis.horizontal) {
          canvas.drawLine(Offset(along, 0), Offset(along, size.height), scan);
        } else {
          canvas.drawLine(Offset(0, along), Offset(size.width, along), scan);
        }
      }
      for (final vertex in step.vertices) {
        if ((axisCoordinate(guide.axis, vertex) - guide.world).abs() >
            kDimensionColinearEpsilon) {
          continue;
        }
        final screen = _project(vertex, size);
        if (screen == null) continue;
        dots[guide.axis]!.add(screen);
      }
    }
    _paintDots(canvas, dots[DimensionAxis.horizontal]!, kDimensionBottom);
    _paintDots(canvas, dots[DimensionAxis.vertical]!, kDimensionLeft);
  }

  void _paintDots(Canvas canvas, Set<Offset> dots, Color color) {
    final paint = Paint()..color = color.withValues(alpha: kDimensionDotOpacity);
    for (final screen in dots) {
      canvas.drawCircle(screen, kDimensionMarkWidth / 2, paint);
    }
  }

  void _paintLocked(Canvas canvas, Size size) {
    for (final dimension in locked) {
      final ends = dimensionEndpoints(dimension);
      final a = _project(ends.$1, size);
      final b = _project(ends.$2, size);
      if (a == null || b == null) continue;
      paintDimensionMark(
        canvas,
        a: a,
        b: b,
        aStuck: true,
        bStuck: true,
        label: formatDimensionCells(
          dimensionCells(dimension.low, dimension.high, step.gridSpacing),
        ),
        axis: dimension.axis,
      );
    }
  }

  double? _screenAlong(SnapGuide guide, Size size) {
    final cross = guide.axis == DimensionAxis.horizontal
        ? camera.lookAt.dy
        : camera.lookAt.dx;
    final world = guide.axis == DimensionAxis.horizontal
        ? Offset(guide.world, cross)
        : Offset(cross, guide.world);
    final screen = _project(world, size);
    if (screen == null) return null;
    return axisCoordinate(guide.axis, screen);
  }

  void _stroke(
    Canvas canvas,
    Size size,
    List<Offset> world,
    Color color, {
    required double width,
  }) {
    if (world.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < world.length - 1; i++) {
      final a = _project(world[i], size);
      final b = _project(world[i + 1], size);
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, paint);
    }
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  @override
  bool shouldRepaint(covariant BlueprintExaminationPainter oldDelegate) => true;
}

/// The two screen-space rulers. Locked copies are painted with the blueprint.
class DimensionChromePainter extends CustomPainter {
  DimensionChromePainter({
    required this.chrome,
    required this.horizontal,
    required this.vertical,
    required this.horizontalLabel,
    required this.verticalLabel,
  });

  final DimensionChrome chrome;
  final DimensionRuler horizontal;
  final DimensionRuler vertical;
  final String horizontalLabel;
  final String verticalLabel;

  @override
  void paint(Canvas canvas, Size size) {
    _paintRuler(canvas, chrome.horizontal, horizontal, horizontalLabel);
    _paintRuler(canvas, chrome.vertical, vertical, verticalLabel);
  }

  void _paintRuler(
    Canvas canvas,
    DimensionTrack track,
    DimensionRuler ruler,
    String label,
  ) {
    canvas.drawLine(
      track.start,
      track.end,
      Paint()
        ..color = _toolInk
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    final a = track.at(ruler.grabs[0].fraction);
    final b = track.at(ruler.grabs[1].fraction);
    if (ruler.bothStuck) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = _toolInk
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    paintDimensionPip(canvas, a, track.axis);
    paintDimensionPip(canvas, b, track.axis);
    paintDimensionLabel(
      canvas,
      a: a,
      b: b,
      label: label,
      axis: track.axis,
      emphasis: ruler.bothStuck,
    );
  }

  @override
  bool shouldRepaint(covariant DimensionChromePainter oldDelegate) => true;
}

/// Line, grabs, and the length between them. Used for a locked dimension.
void paintDimensionMark(
  Canvas canvas, {
  required Offset a,
  required Offset b,
  required bool aStuck,
  required bool bStuck,
  required String label,
  required DimensionAxis axis,
}) {
  canvas.drawLine(
    a,
    b,
    Paint()
      ..color = _toolInk
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round,
  );
  paintDimensionPip(canvas, a, axis);
  paintDimensionPip(canvas, b, axis);
  paintDimensionLabel(
    canvas,
    a: a,
    b: b,
    label: label,
    axis: axis,
    emphasis: aStuck && bStuck,
  );
}

void paintDimensionPip(Canvas canvas, Offset at, DimensionAxis axis) {
  final path = Path()
    ..addPolygon(
      dimensionCropMark(
        at: at,
        toward: dimensionWidgetMarkDirection(axis),
        scale: kDimensionWidgetMarkScale,
      ),
      true,
    );
  canvas.drawPath(path, Paint()..color = _toolInk);
}

void paintDimensionLabel(
  Canvas canvas, {
  required Offset a,
  required Offset b,
  required String label,
  required DimensionAxis axis,
  required bool emphasis,
}) {
  if (label.isEmpty) return;
  final mid = Offset.lerp(a, b, 0.5)!;
  final anchor = axis == DimensionAxis.horizontal
      ? mid + const Offset(0, -16)
      : mid + const Offset(16, 0);
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: emphasis ? _toolInk : _labelFree,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  painter.layout();
  painter.paint(canvas, anchor - Offset(painter.width / 2, painter.height / 2));
}
