import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/path_database.dart';
import 'iso_camera.dart';
import 'iso_coordinate.dart';
import 'iso_painter.dart';
import 'path_geometry.dart';
import 'path_style.dart';

/// Renderable for paths with dotted line visualization
class PathRenderable implements IsoRenderable {
  PathRenderable({required this.path, this.assetOverrides = const {}});

  final PathEntry path;

  /// Map of coordinates to custom geometry from path assets
  final Map<IsoCoordinate, PathSegmentGeometry> assetOverrides;

  @override
  double get depth {
    // Paths render above ALL tiles by using the maximum tile depth + offset
    // Offset must be large enough to be above all tiles, but small enough to stay below assets
    if (path.coordinates.isEmpty) return 0.0;

    final maxDepth = path.coordinates
        .map((c) => c.depth)
        .reduce((a, b) => a > b ? a : b);

    // Add 0.0001 to put paths just above tiles (tiles use h * 0.001 for height)
    return maxDepth + 0.0001;
  }

  @override
  double getDepthForView(IsoViewDirection view) =>
      getDepthForPath(path, view);

  /// Depth for a path without allocating a [PathRenderable].
  /// Paths render just above tiles (tiles use h * 0.001 for height).
  static double getDepthForPath(PathEntry path, IsoViewDirection view) {
    if (path.coordinates.isEmpty) return 0.0;
    final maxDepth = path.coordinates
        .map((c) => c.getDepthForView(view))
        .reduce((a, b) => a > b ? a : b);
    return maxDepth + 0.0001;
  }

  @override
  void draw(Canvas canvas, IsoCamera camera, Size viewport) {
    drawPath(canvas, camera, viewport, path);
  }

  /// Draw a single path without allocating a [PathRenderable]. Use in hot
  /// paths (e.g. many paths per frame) to avoid per-path allocation.
  static void drawPath(
    Canvas canvas,
    IsoCamera camera,
    Size viewport,
    PathEntry path,
  ) {
    if (path.coordinates.isEmpty) return;

    final allPoints = path.coordinates
        .map((c) => c.toScreen(camera, viewport))
        .toList();

    if (allPoints.length >= 2) {
      _drawDottedLineStatic(canvas, allPoints, path.style);
      _drawGatherChevronsStatic(canvas, allPoints, path.style);
    }
  }

  /// Chevron spacing along the path (pixels). Points from gather target (end)
  /// toward source (start).
  static const double _chevronSpacing = 48.0;

  /// Chevron size (half-width of triangle)
  static const double _chevronSize = 6.0;

  static void _drawGatherChevronsStatic(
    Canvas canvas,
    List<Offset> points,
    PathStyle style,
  ) {
    if (points.length < 2) return;

    double totalLength = 0.0;
    final segmentLengths = <double>[];
    for (var i = 0; i < points.length - 1; i++) {
      final length = (points[i + 1] - points[i]).distance;
      segmentLengths.add(length);
      totalLength += length;
    }
    if (totalLength < _chevronSpacing * 2) return;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Place chevrons at intervals from end toward start (gather flow direction).
    // Distance from path end: 48, 96, 144, ... (skip very end/start)
    var distFromEnd = _chevronSpacing;
    while (distFromEnd < totalLength - _chevronSpacing * 0.5) {
      final distFromStart = totalLength - distFromEnd;
      final t = distFromStart / totalLength;
      final pos = _interpolateAlongPathStatic(
        points,
        segmentLengths,
        totalLength,
        t,
      );
      // Find segment and direction toward start
      var acc = 0.0;
      for (var i = 0; i < segmentLengths.length; i++) {
        if (acc + segmentLengths[i] >= distFromStart) {
          final pStart = points[i];
          final pEnd = points[i + 1];
          final segLen = segmentLengths[i];
          final dir = segLen > 0.001
              ? (pStart - pEnd) / segLen
              : Offset.zero;
          if (dir.distance > 0.001) {
            _drawChevronAt(canvas, pos, dir, paint);
          }
          break;
        }
        acc += segmentLengths[i];
      }
      distFromEnd += _chevronSpacing;
    }
  }

  static void _drawChevronAt(
    Canvas canvas,
    Offset center,
    Offset direction,
    Paint paint,
  ) {
    final len = direction.distance;
    if (len < 0.001) return;
    final u = direction / len;

    // Chevron: triangle pointing in direction u. Tip at center + u * size.
    final tip = center + u * _chevronSize;
    final base = center - u * _chevronSize;
    final perp = Offset(-u.dy, u.dx);
    final left = base + perp * (_chevronSize * 0.6);
    final right = base - perp * (_chevronSize * 0.6);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Draw a specific segment with custom style (for highlighting)
  void drawSegment(
    Canvas canvas,
    IsoCamera camera,
    Size viewport,
    int segmentIndex,
    PathStyle customStyle,
  ) {
    if (segmentIndex < 0 ||
        segmentIndex >= path.coordinates.length - 1 ||
        path.coordinates.isEmpty) {
      return;
    }

    final start = path.coordinates[segmentIndex].toScreen(camera, viewport);
    final end = path.coordinates[segmentIndex + 1].toScreen(camera, viewport);
    _drawDottedLine(canvas, [start, end], customStyle);
  }

  void _drawDottedLine(Canvas canvas, List<Offset> points, PathStyle style) {
    _drawDottedLineStatic(canvas, points, style);
  }

  /// Static implementation to avoid per-path [PathRenderable] allocation.
  static void _drawDottedLineStatic(
    Canvas canvas,
    List<Offset> points,
    PathStyle style,
  ) {
    if (points.length < 2) return;

    if (style.dotRadius * 2 >= style.dotSpacing) {
      _drawThickLineStatic(canvas, points, style);
      return;
    }

    double totalLength = 0.0;
    final segmentLengths = <double>[];

    for (var i = 0; i < points.length - 1; i++) {
      final length = (points[i + 1] - points[i]).distance;
      segmentLengths.add(length);
      totalLength += length;
    }

    if (totalLength == 0) return;

    final numDots = (totalLength / style.dotSpacing).floor() + 1;

    final paint = Paint()
      ..color = style.color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < numDots; i++) {
      final t = i / math.max(1, numDots - 1);
      final position = _interpolateAlongPathStatic(
        points,
        segmentLengths,
        totalLength,
        t,
      );
      canvas.drawCircle(position, style.dotRadius, paint);
    }
  }

  static void _drawThickLineStatic(
    Canvas canvas,
    List<Offset> points,
    PathStyle style,
  ) {
    final linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final paint = Paint()
      ..color = style.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.dotRadius * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, paint);
  }

  /// Draw a continuous thick line with rounded caps/joins through [points].
  void _drawThickLine(Canvas canvas, List<Offset> points, PathStyle style) {
    _drawThickLineStatic(canvas, points, style);
  }

  static Offset _interpolateAlongPathStatic(
    List<Offset> points,
    List<double> segmentLengths,
    double totalLength,
    double t,
  ) {
    if (points.length < 2) return points[0];
    if (t <= 0) return points[0];
    if (t >= 1) return points.last;

    final targetLength = t * totalLength;
    double accumulatedLength = 0.0;

    for (var i = 0; i < segmentLengths.length; i++) {
      final segmentLength = segmentLengths[i];

      if (accumulatedLength + segmentLength >= targetLength) {
        final segmentT = (targetLength - accumulatedLength) / segmentLength;
        return Offset.lerp(points[i], points[i + 1], segmentT)!;
      }

      accumulatedLength += segmentLength;
    }

    return points.last;
  }

  Offset _interpolateAlongPath(
    List<Offset> points,
    List<double> segmentLengths,
    double totalLength,
    double t,
  ) =>
      _interpolateAlongPathStatic(points, segmentLengths, totalLength, t);
}
