import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// A morphable polygon represented as an ordered list of points
class MorphablePolygon {
  MorphablePolygon({
    required this.points,
    this.color = Colors.cyanAccent,
    this.thickness = 1.5,
  });

  final List<Offset> points;
  final Color color;
  final double thickness;

  /// Calculate the centroid (center of mass) of the polygon
  Offset get centroid {
    if (points.isEmpty) return Offset.zero;
    double sumX = 0, sumY = 0;
    for (final p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    return Offset(sumX / points.length, sumY / points.length);
  }

  /// Get the angle of each point relative to the centroid
  /// Returns list of (angle, pointIndex) sorted by angle
  List<(double angle, int index)> getPointAngles() {
    final center = centroid;
    final angles = <(double, int)>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      // Angle from positive Y axis (up), clockwise
      final angle = math.atan2(p.dx - center.dx, -(p.dy - center.dy));
      angles.add((angle, i));
    }
    // Sort by angle
    angles.sort((a, b) => a.$1.compareTo(b.$1));
    return angles;
  }

  /// Create a copy with more points by subdividing edges
  MorphablePolygon withPointCount(int targetCount) {
    if (points.length >= targetCount) return this;
    if (points.isEmpty) return this;

    final result = List<Offset>.from(points);

    // Distribute new points evenly along the edges
    while (result.length < targetCount) {
      // Find the longest edge and split it
      var longestIndex = 0;
      var longestLength = 0.0;

      for (var i = 0; i < result.length; i++) {
        final next = (i + 1) % result.length;
        final length = (result[next] - result[i]).distance;
        if (length > longestLength) {
          longestLength = length;
          longestIndex = i;
        }
      }

      // Insert midpoint
      final p1 = result[longestIndex];
      final p2 = result[(longestIndex + 1) % result.length];
      final midpoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      result.insert(longestIndex + 1, midpoint);
    }

    return MorphablePolygon(points: result, color: color, thickness: thickness);
  }

  /// Find where a ray from centroid at given angle intersects the polygon boundary
  Offset? findRayIntersection(double angle) {
    if (points.length < 3) return null;

    final center = centroid;
    // Direction from angle (measured from +Y axis clockwise)
    final dirX = math.sin(angle);
    final dirY = -math.cos(angle);

    // Ray: center + t * dir, t >= 0
    Offset? bestPoint;
    double bestT = double.infinity;

    for (var i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];

      // Line segment: p1 + s * (p2 - p1), s in [0, 1]
      // Solve: center + t * dir = p1 + s * (p2 - p1)
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;

      final denom = dirX * dy - dirY * dx;
      if (denom.abs() < 1e-10) continue; // Parallel

      final t = ((p1.dx - center.dx) * dy - (p1.dy - center.dy) * dx) / denom;
      final s =
          ((p1.dx - center.dx) * dirY - (p1.dy - center.dy) * dirX) / denom;

      if (t > 0 && s >= 0 && s <= 1 && t < bestT) {
        bestT = t;
        bestPoint = Offset(center.dx + t * dirX, center.dy + t * dirY);
      }
    }

    return bestPoint;
  }

  @override
  String toString() => 'MorphablePolygon(${points.length} points)';
}

/// Matches points between two polygons for smooth morphing
class PolygonMatcher {
  /// Match points between source and target polygons
  /// Returns two new polygons with the same number of points, matched by angle
  static (MorphablePolygon source, MorphablePolygon target) matchPolygons(
    MorphablePolygon source,
    MorphablePolygon target,
  ) {
    if (source.points.isEmpty && target.points.isEmpty) {
      return (source, target);
    }

    // Handle empty cases
    if (source.points.isEmpty) {
      final center = target.centroid;
      return (
        MorphablePolygon(
          points: List.filled(target.points.length, center),
          color: source.color,
          thickness: source.thickness,
        ),
        target,
      );
    }

    if (target.points.isEmpty) {
      final center = source.centroid;
      return (
        source,
        MorphablePolygon(
          points: List.filled(source.points.length, center),
          color: target.color,
          thickness: target.thickness,
        ),
      );
    }

    // Get point count and normalize
    final maxCount = math.max(source.points.length, target.points.length);

    // Add points to the smaller polygon by ray intersection
    final normalizedSource = _normalizePolygon(source, target, maxCount);
    final normalizedTarget = _normalizePolygon(target, source, maxCount);

    // Now reorder points to match by angle
    final matchedSource = _reorderByAngle(normalizedSource, normalizedTarget);

    return (matchedSource, normalizedTarget);
  }

  /// Normalize a polygon to have the target count of points
  /// Uses ray intersection to add points at angles from the other polygon
  static MorphablePolygon _normalizePolygon(
    MorphablePolygon polygon,
    MorphablePolygon reference,
    int targetCount,
  ) {
    if (polygon.points.length >= targetCount) {
      // Just use existing points (might need to drop some)
      return MorphablePolygon(
        points: polygon.points.take(targetCount).toList(),
        color: polygon.color,
        thickness: polygon.thickness,
      );
    }

    // Need to add points
    // First, get angles of all points in reference polygon
    final referenceAngles = reference.getPointAngles();

    // Get existing angles in our polygon
    final center = polygon.centroid;
    final existingAngles = <double>{};
    for (final p in polygon.points) {
      final angle = math.atan2(p.dx - center.dx, -(p.dy - center.dy));
      existingAngles.add(angle);
    }

    // Start with existing points
    final result = List<Offset>.from(polygon.points);

    // Add points at angles from reference that we don't have
    for (final (angle, _) in referenceAngles) {
      if (result.length >= targetCount) break;

      // Check if we already have a point close to this angle
      bool hasClose = false;
      for (final existingAngle in existingAngles) {
        if ((existingAngle - angle).abs() < 0.1) {
          hasClose = true;
          break;
        }
      }

      if (!hasClose) {
        // Find intersection point at this angle
        final intersection = polygon.findRayIntersection(angle);
        if (intersection != null) {
          result.add(intersection);
          existingAngles.add(angle);
        }
      }
    }

    // If we still need more points, subdivide edges
    while (result.length < targetCount) {
      // Find longest edge
      var longestIdx = 0;
      var longestLen = 0.0;
      for (var i = 0; i < result.length; i++) {
        final len = (result[(i + 1) % result.length] - result[i]).distance;
        if (len > longestLen) {
          longestLen = len;
          longestIdx = i;
        }
      }
      // Insert midpoint
      final mid = Offset(
        (result[longestIdx].dx + result[(longestIdx + 1) % result.length].dx) /
            2,
        (result[longestIdx].dy + result[(longestIdx + 1) % result.length].dy) /
            2,
      );
      result.insert(longestIdx + 1, mid);
    }

    return MorphablePolygon(
      points: result,
      color: polygon.color,
      thickness: polygon.thickness,
    );
  }

  /// Reorder source polygon points to best match target polygon points by angle.
  /// Preserves winding order by finding the best rotation offset (and checking reversal).
  static MorphablePolygon _reorderByAngle(
    MorphablePolygon source,
    MorphablePolygon target,
  ) {
    if (source.points.length != target.points.length) {
      return source; // Can't match if different counts
    }

    final n = source.points.length;
    if (n == 0) return source;

    final sourceCenter = source.centroid;
    final targetCenter = target.centroid;

    // Calculate angle from centroid for each point
    double getAngle(Offset point, Offset center) {
      return math.atan2(point.dx - center.dx, -(point.dy - center.dy));
    }

    final targetAngles = target.points
        .map((p) => getAngle(p, targetCenter))
        .toList();

    // Try both forward and reversed source orderings
    // This handles different winding directions (CW vs CCW)

    List<Offset> bestOrder = source.points;
    double bestScore = double.infinity;

    for (final reversed in [false, true]) {
      final srcPoints = reversed
          ? source.points.reversed.toList()
          : source.points;
      final srcCenter = sourceCenter; // Centroid is the same either way
      final srcAngles = srcPoints.map((p) => getAngle(p, srcCenter)).toList();

      // Try each rotation offset
      for (var offset = 0; offset < n; offset++) {
        double totalDist = 0;

        for (var i = 0; i < n; i++) {
          final srcIdx = (i + offset) % n;
          // Calculate angular difference
          var angleDiff = (srcAngles[srcIdx] - targetAngles[i]).abs();
          if (angleDiff > math.pi) angleDiff = 2 * math.pi - angleDiff;
          totalDist += angleDiff;
        }

        if (totalDist < bestScore) {
          bestScore = totalDist;
          // Build the reordered list
          bestOrder = List.generate(n, (i) => srcPoints[(i + offset) % n]);
        }
      }
    }

    return MorphablePolygon(
      points: bestOrder,
      color: source.color,
      thickness: source.thickness,
    );
  }
}

/// Lerp between two matched polygons
MorphablePolygon lerpPolygon(MorphablePolygon a, MorphablePolygon b, double t) {
  if (a.points.length != b.points.length) {
    // Fallback: use the target if counts don't match
    return t < 0.5 ? a : b;
  }

  final lerpedPoints = <Offset>[];
  for (var i = 0; i < a.points.length; i++) {
    lerpedPoints.add(Offset.lerp(a.points[i], b.points[i], t)!);
  }

  return MorphablePolygon(
    points: lerpedPoints,
    color: Color.lerp(a.color, b.color, t)!,
    thickness: lerpDouble(a.thickness, b.thickness, t)!,
  );
}

/// Style for polygon morph
class PolygonMorphStyle {
  const PolygonMorphStyle({
    this.color = Colors.cyanAccent,
    this.thickness = 2.0,
    this.glowColor,
    this.glowThickness = 4.0,
    this.glowOpacity = 0.4,
  });

  final Color color;
  final double thickness;
  final Color? glowColor;
  final double glowThickness;
  final double glowOpacity;

  Color get effectiveGlowColor => glowColor ?? color;

  static PolygonMorphStyle lerp(
    PolygonMorphStyle a,
    PolygonMorphStyle b,
    double t,
  ) {
    return PolygonMorphStyle(
      color: Color.lerp(a.color, b.color, t)!,
      thickness: lerpDouble(a.thickness, b.thickness, t)!,
      glowColor: Color.lerp(a.effectiveGlowColor, b.effectiveGlowColor, t),
      glowThickness: lerpDouble(a.glowThickness, b.glowThickness, t)!,
      glowOpacity: lerpDouble(a.glowOpacity, b.glowOpacity, t)!,
    );
  }
}

/// Provider type for dynamic polygon updates
typedef PolygonProvider = MorphablePolygon Function();

/// Controller for polygon morphing animations
class PolygonMorphController extends ChangeNotifier {
  PolygonMorphController({
    required TickerProvider vsync,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOut,
  }) : _vsync = vsync;

  final TickerProvider _vsync;
  final Duration duration;
  final Curve curve;

  AnimationController? _animationController;
  Animation<double>? _animation;

  // Matched polygons for morphing
  MorphablePolygon? _sourcePolygon;
  MorphablePolygon? _targetPolygon;

  // Dynamic providers
  PolygonProvider? _sourceProvider;
  PolygonProvider? _targetProvider;
  bool _useDynamic = false;

  PolygonMorphStyle _sourceStyle = const PolygonMorphStyle();
  PolygonMorphStyle _targetStyle = const PolygonMorphStyle();

  bool _isAnimating = false;
  VoidCallback? _onComplete;

  bool get isAnimating => _isAnimating;
  double get progress => _animation?.value ?? 0.0;

  /// Current interpolated polygon
  MorphablePolygon? get currentPolygon {
    if (!_isAnimating) return null;

    final t = curve.transform(progress);

    if (_useDynamic && _sourceProvider != null && _targetProvider != null) {
      // Recalculate from providers each frame
      final source = _sourceProvider!();
      final target = _targetProvider!();
      final (matched1, matched2) = PolygonMatcher.matchPolygons(source, target);
      return lerpPolygon(matched1, matched2, t);
    }

    if (_sourcePolygon == null || _targetPolygon == null) return null;
    return lerpPolygon(_sourcePolygon!, _targetPolygon!, t);
  }

  /// Current interpolated style
  PolygonMorphStyle get currentStyle {
    final t = curve.transform(progress);
    return PolygonMorphStyle.lerp(_sourceStyle, _targetStyle, t);
  }

  /// Start morphing between two static polygons
  void morphTo({
    required MorphablePolygon sourcePolygon,
    required MorphablePolygon targetPolygon,
    PolygonMorphStyle? sourceStyle,
    PolygonMorphStyle? targetStyle,
    VoidCallback? onComplete,
  }) {
    _sourceStyle = sourceStyle ?? const PolygonMorphStyle();
    _targetStyle = targetStyle ?? const PolygonMorphStyle();
    _onComplete = onComplete;
    _useDynamic = false;
    _sourceProvider = null;
    _targetProvider = null;

    // Match polygons
    final (matched1, matched2) = PolygonMatcher.matchPolygons(
      sourcePolygon,
      targetPolygon,
    );
    _sourcePolygon = matched1;
    _targetPolygon = matched2;

    _startAnimation();
  }

  /// Start morphing with dynamic polygon providers
  void morphToDynamic({
    required PolygonProvider sourceProvider,
    required PolygonProvider targetProvider,
    PolygonMorphStyle? sourceStyle,
    PolygonMorphStyle? targetStyle,
    VoidCallback? onComplete,
  }) {
    _sourceStyle = sourceStyle ?? const PolygonMorphStyle();
    _targetStyle = targetStyle ?? const PolygonMorphStyle();
    _onComplete = onComplete;
    _useDynamic = true;
    _sourceProvider = sourceProvider;
    _targetProvider = targetProvider;
    _sourcePolygon = null;
    _targetPolygon = null;

    _startAnimation();
  }

  void _startAnimation() {
    _animationController?.dispose();
    _animationController = AnimationController(
      vsync: _vsync,
      duration: duration,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController!, curve: curve));

    _animationController!.addListener(_handleTick);
    _animationController!.addStatusListener(_handleStatus);

    _isAnimating = true;
    notifyListeners();

    _animationController!.forward();
  }

  void _handleTick() => notifyListeners();

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _isAnimating = false;
      notifyListeners();
      _onComplete?.call();
    }
  }

  void stop() {
    _animationController?.stop();
    _isAnimating = false;
    notifyListeners();
  }

  void reset() {
    _animationController?.reset();
    _sourcePolygon = null;
    _targetPolygon = null;
    _isAnimating = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _animationController?.removeListener(_handleTick);
    _animationController?.dispose();
    super.dispose();
  }
}

/// Custom painter for polygon morph
class PolygonMorphPainter extends CustomPainter {
  PolygonMorphPainter({required this.controller}) : super(repaint: controller);

  final PolygonMorphController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isAnimating) return;

    final polygon = controller.currentPolygon;
    if (polygon == null || polygon.points.length < 2) return;

    final style = controller.currentStyle;

    // Build path
    final path = Path();
    path.moveTo(polygon.points[0].dx, polygon.points[0].dy);
    for (var i = 1; i < polygon.points.length; i++) {
      path.lineTo(polygon.points[i].dx, polygon.points[i].dy);
    }
    path.close();

    // Draw glow
    final glowPaint = Paint()
      ..color = style.effectiveGlowColor.withOpacity(style.glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.glowThickness
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glowPaint);

    // Draw main stroke
    final mainPaint = Paint()
      ..color = polygon.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygon.thickness
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, mainPaint);
  }

  @override
  bool shouldRepaint(PolygonMorphPainter oldDelegate) {
    return controller != oldDelegate.controller;
  }
}

/// Widget for polygon morph animation
class PolygonMorphWidget extends StatelessWidget {
  const PolygonMorphWidget({super.key, required this.controller, this.child});

  final PolygonMorphController controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PolygonMorphPainter(controller: controller),
      child: child,
    );
  }
}
