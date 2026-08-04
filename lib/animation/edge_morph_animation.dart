import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Represents a single edge that can be morphed
class MorphableEdge {
  const MorphableEdge({
    required this.start,
    required this.end,
    this.color = Colors.cyanAccent,
    this.thickness = 1.5,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double thickness;

  /// Get the center point of this edge
  Offset get center => Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

  /// Get the length of this edge
  double get length {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Get the angle of this edge (in radians)
  double get angle => math.atan2(end.dy - start.dy, end.dx - start.dx);

  /// Lerp between two edges
  static MorphableEdge lerp(MorphableEdge a, MorphableEdge b, double t) {
    return MorphableEdge(
      start: Offset.lerp(a.start, b.start, t)!,
      end: Offset.lerp(a.end, b.end, t)!,
      color: Color.lerp(a.color, b.color, t)!,
      thickness: lerpDouble(a.thickness, b.thickness, t)!,
    );
  }

  /// Create a copy with different properties
  MorphableEdge copyWith({
    Offset? start,
    Offset? end,
    Color? color,
    double? thickness,
  }) {
    return MorphableEdge(
      start: start ?? this.start,
      end: end ?? this.end,
      color: color ?? this.color,
      thickness: thickness ?? this.thickness,
    );
  }

  @override
  String toString() => 'MorphableEdge($start -> $end)';
}

/// Style configuration for edge morphing
class EdgeMorphStyle {
  const EdgeMorphStyle({
    this.color = Colors.cyanAccent,
    this.thickness = 1.5,
    this.glowColor,
    this.glowThickness = 3.0,
    this.glowOpacity = 0.4,
  });

  final Color color;
  final double thickness;
  final Color? glowColor;
  final double glowThickness;
  final double glowOpacity;

  /// Get the glow color (defaults to main color)
  Color get effectiveGlowColor => glowColor ?? color;

  /// Lerp between two styles
  static EdgeMorphStyle lerp(EdgeMorphStyle a, EdgeMorphStyle b, double t) {
    return EdgeMorphStyle(
      color: Color.lerp(a.color, b.color, t)!,
      thickness: lerpDouble(a.thickness, b.thickness, t)!,
      glowColor: Color.lerp(a.effectiveGlowColor, b.effectiveGlowColor, t),
      glowThickness: lerpDouble(a.glowThickness, b.glowThickness, t)!,
      glowOpacity: lerpDouble(a.glowOpacity, b.glowOpacity, t)!,
    );
  }

  EdgeMorphStyle copyWith({
    Color? color,
    double? thickness,
    Color? glowColor,
    double? glowThickness,
    double? glowOpacity,
  }) {
    return EdgeMorphStyle(
      color: color ?? this.color,
      thickness: thickness ?? this.thickness,
      glowColor: glowColor ?? this.glowColor,
      glowThickness: glowThickness ?? this.glowThickness,
      glowOpacity: glowOpacity ?? this.glowOpacity,
    );
  }
}

/// A paired set of edges for morphing (source -> target)
class EdgeMorphPair {
  const EdgeMorphPair({required this.source, required this.target});

  final MorphableEdge source;
  final MorphableEdge target;

  /// Get the interpolated edge at time t (0 = source, 1 = target)
  MorphableEdge lerp(double t) => MorphableEdge.lerp(source, target, t);
}

/// Algorithm for matching source edges to target edges
enum EdgeMatchingStrategy {
  /// Match by index order (simple, fast)
  sequential,

  /// Match by proximity of edge centers
  proximity,

  /// Match by angle similarity
  angle,

  /// Combined proximity and angle matching
  combined,
}

/// Callback type for providing edges dynamically (supports camera changes)
typedef EdgeProvider = List<MorphableEdge> Function();

/// Controller for edge morphing animations
///
/// This is a reusable animation controller that morphs between two sets of edges.
/// It handles:
/// - Different edge counts (duplicating/merging as needed)
/// - Smooth interpolation of position, color, and thickness
/// - Configurable easing curves
/// - Dynamic edge updates (edges follow objects during camera pan)
class EdgeMorphController extends ChangeNotifier {
  EdgeMorphController({
    required TickerProvider vsync,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.easeOut,
    this.matchingStrategy = EdgeMatchingStrategy.proximity,
  }) : _vsync = vsync;

  final TickerProvider _vsync;
  final Duration duration;
  final Curve curve;
  final EdgeMatchingStrategy matchingStrategy;

  AnimationController? _animationController;
  Animation<double>? _animation;

  // Static edge pairs (for non-dynamic mode)
  List<EdgeMorphPair> _morphPairs = [];

  // Dynamic edge providers (for camera-following mode)
  EdgeProvider? _sourceProvider;
  EdgeProvider? _targetProvider;
  bool _useDynamicEdges = false;
  bool _preserveEdgeOrder = false; // For tile-to-tile morphs

  EdgeMorphStyle _sourceStyle = const EdgeMorphStyle();
  EdgeMorphStyle _targetStyle = const EdgeMorphStyle();

  bool _isAnimating = false;
  VoidCallback? _onComplete;

  /// Whether the animation is currently running
  bool get isAnimating => _isAnimating;

  /// Current animation progress (0-1)
  double get progress => _animation?.value ?? 0.0;

  /// Current interpolated edges
  List<MorphableEdge> get currentEdges {
    if (!_isAnimating) return [];

    final t = curve.transform(progress);

    if (_useDynamicEdges &&
        _sourceProvider != null &&
        _targetProvider != null) {
      // Recalculate edges from providers each frame (for camera following)
      final sourceEdges = _sourceProvider!();
      final targetEdges = _targetProvider!();

      // Use sequential matching for preserved edge order (tile-to-tile)
      // Otherwise use the configured matching strategy
      final pairs = _preserveEdgeOrder
          ? _matchSequentialDirect(sourceEdges, targetEdges)
          : _matchEdges(sourceEdges, targetEdges);
      return pairs.map((pair) => pair.lerp(t)).toList();
    }

    if (_morphPairs.isEmpty) return [];
    return _morphPairs.map((pair) => pair.lerp(t)).toList();
  }

  /// Direct sequential matching without normalization - preserves edge order
  /// Used for tile-to-tile morphs where edge positions should be preserved
  List<EdgeMorphPair> _matchSequentialDirect(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    if (source.isEmpty && target.isEmpty) return [];

    // Handle empty cases
    if (source.isEmpty) {
      final center = _computeCenter(target);
      return target.map((t) {
        return EdgeMorphPair(
          source: MorphableEdge(
            start: center,
            end: center,
            color: t.color.withOpacity(0),
            thickness: 0,
          ),
          target: t,
        );
      }).toList();
    }

    if (target.isEmpty) {
      final center = _computeCenter(source);
      return source.map((s) {
        return EdgeMorphPair(
          source: s,
          target: MorphableEdge(
            start: center,
            end: center,
            color: s.color.withOpacity(0),
            thickness: 0,
          ),
        );
      }).toList();
    }

    // Direct 1:1 matching by index (preserves edge order)
    final count = math.max(source.length, target.length);
    final pairs = <EdgeMorphPair>[];

    for (var i = 0; i < count; i++) {
      final srcEdge = source[i % source.length];
      final tgtEdge = target[i % target.length];
      pairs.add(EdgeMorphPair(source: srcEdge, target: tgtEdge));
    }

    return pairs;
  }

  /// Current interpolated style
  EdgeMorphStyle get currentStyle {
    final t = curve.transform(progress);
    return EdgeMorphStyle.lerp(_sourceStyle, _targetStyle, t);
  }

  /// Start morphing from source edges to target edges (static mode)
  void morphTo({
    required List<MorphableEdge> sourceEdges,
    required List<MorphableEdge> targetEdges,
    EdgeMorphStyle? sourceStyle,
    EdgeMorphStyle? targetStyle,
    VoidCallback? onComplete,
  }) {
    // Store styles
    _sourceStyle = sourceStyle ?? const EdgeMorphStyle();
    _targetStyle = targetStyle ?? const EdgeMorphStyle();
    _onComplete = onComplete;
    _useDynamicEdges = false;
    _sourceProvider = null;
    _targetProvider = null;

    // Match edges
    _morphPairs = _matchEdges(sourceEdges, targetEdges);

    _startAnimation();
  }

  /// Start morphing with dynamic edge providers (edges recalculated each frame)
  /// This allows edges to follow objects during camera pan/zoom
  ///
  /// Set [preserveEdgeOrder] to true for tile-to-tile morphs where edge
  /// positions should be preserved (top-left stays top-left, etc.)
  void morphToDynamic({
    required EdgeProvider sourceProvider,
    required EdgeProvider targetProvider,
    EdgeMorphStyle? sourceStyle,
    EdgeMorphStyle? targetStyle,
    VoidCallback? onComplete,
    bool preserveEdgeOrder = false,
  }) {
    // Store styles
    _sourceStyle = sourceStyle ?? const EdgeMorphStyle();
    _targetStyle = targetStyle ?? const EdgeMorphStyle();
    _onComplete = onComplete;
    _useDynamicEdges = true;
    _preserveEdgeOrder = preserveEdgeOrder;
    _sourceProvider = sourceProvider;
    _targetProvider = targetProvider;
    _morphPairs = []; // Not used in dynamic mode

    _startAnimation();
  }

  void _startAnimation() {
    // Create animation controller
    _animationController?.dispose();
    _animationController = AnimationController(
      vsync: _vsync,
      duration: duration,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController!, curve: curve));

    _animationController!.addListener(_handleAnimationTick);
    _animationController!.addStatusListener(_handleAnimationStatus);

    _isAnimating = true;
    notifyListeners();

    _animationController!.forward();
  }

  /// Match source edges to target edges based on the matching strategy
  List<EdgeMorphPair> _matchEdges(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    if (source.isEmpty && target.isEmpty) return [];

    // Handle empty cases
    if (source.isEmpty) {
      // Collapse from center to target edges
      final center = _computeCenter(target);
      return target.map((t) {
        return EdgeMorphPair(
          source: MorphableEdge(
            start: center,
            end: center,
            color: t.color.withOpacity(0),
            thickness: 0,
          ),
          target: t,
        );
      }).toList();
    }

    if (target.isEmpty) {
      // Collapse source edges to center
      final center = _computeCenter(source);
      return source.map((s) {
        return EdgeMorphPair(
          source: s,
          target: MorphableEdge(
            start: center,
            end: center,
            color: s.color.withOpacity(0),
            thickness: 0,
          ),
        );
      }).toList();
    }

    // Normalize edge counts
    final maxCount = math.max(source.length, target.length);
    final normalizedSource = _normalizeEdgeCount(source, maxCount);
    final normalizedTarget = _normalizeEdgeCount(target, maxCount);

    // Match based on strategy
    switch (matchingStrategy) {
      case EdgeMatchingStrategy.sequential:
        return _matchSequential(normalizedSource, normalizedTarget);
      case EdgeMatchingStrategy.proximity:
        return _matchByProximity(normalizedSource, normalizedTarget);
      case EdgeMatchingStrategy.angle:
        return _matchByAngle(normalizedSource, normalizedTarget);
      case EdgeMatchingStrategy.combined:
        return _matchCombined(normalizedSource, normalizedTarget);
    }
  }

  /// Compute the center point of a set of edges
  Offset _computeCenter(List<MorphableEdge> edges) {
    if (edges.isEmpty) return Offset.zero;

    double sumX = 0, sumY = 0;
    for (final edge in edges) {
      sumX += edge.center.dx;
      sumY += edge.center.dy;
    }
    return Offset(sumX / edges.length, sumY / edges.length);
  }

  /// Normalize edge count by duplicating or distributing edges
  List<MorphableEdge> _normalizeEdgeCount(
    List<MorphableEdge> edges,
    int targetCount,
  ) {
    if (edges.length == targetCount) return edges;

    if (edges.length < targetCount) {
      // Need to duplicate edges
      final result = <MorphableEdge>[];
      for (var i = 0; i < targetCount; i++) {
        // Distribute evenly across source edges
        final sourceIndex = (i * edges.length) ~/ targetCount;
        result.add(edges[sourceIndex]);
      }
      return result;
    } else {
      // More source edges than needed - just take what we need
      // (the remaining will converge to the same targets)
      return edges;
    }
  }

  /// Simple sequential matching
  List<EdgeMorphPair> _matchSequential(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    final count = math.min(source.length, target.length);
    return List.generate(count, (i) {
      return EdgeMorphPair(source: source[i], target: target[i]);
    });
  }

  /// Match edges by proximity (closest centers)
  List<EdgeMorphPair> _matchByProximity(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    // Sort both by distance from combined center for consistent ordering
    final allEdges = [...source, ...target];
    final center = _computeCenter(allEdges);

    final sortedSource = List<MorphableEdge>.from(source)
      ..sort((a, b) {
        final distA = (a.center - center).distance;
        final distB = (b.center - center).distance;
        return distA.compareTo(distB);
      });

    final sortedTarget = List<MorphableEdge>.from(target)
      ..sort((a, b) {
        final distA = (a.center - center).distance;
        final distB = (b.center - center).distance;
        return distA.compareTo(distB);
      });

    return _matchSequential(sortedSource, sortedTarget);
  }

  /// Match edges by angle from center
  List<EdgeMorphPair> _matchByAngle(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    final allEdges = [...source, ...target];
    final center = _computeCenter(allEdges);

    double angleFromCenter(MorphableEdge edge) {
      return math.atan2(edge.center.dy - center.dy, edge.center.dx - center.dx);
    }

    final sortedSource = List<MorphableEdge>.from(source)
      ..sort((a, b) => angleFromCenter(a).compareTo(angleFromCenter(b)));

    final sortedTarget = List<MorphableEdge>.from(target)
      ..sort((a, b) => angleFromCenter(a).compareTo(angleFromCenter(b)));

    return _matchSequential(sortedSource, sortedTarget);
  }

  /// Combined proximity and angle matching
  List<EdgeMorphPair> _matchCombined(
    List<MorphableEdge> source,
    List<MorphableEdge> target,
  ) {
    // Use a greedy algorithm: for each source edge, find the closest
    // unmatched target edge
    final availableTargets = List<MorphableEdge>.from(target);
    final pairs = <EdgeMorphPair>[];

    for (final src in source) {
      if (availableTargets.isEmpty) break;

      // Find closest target by center distance
      var bestIndex = 0;
      var bestDistance = double.infinity;

      for (var i = 0; i < availableTargets.length; i++) {
        final dist = (src.center - availableTargets[i].center).distance;
        if (dist < bestDistance) {
          bestDistance = dist;
          bestIndex = i;
        }
      }

      pairs.add(
        EdgeMorphPair(source: src, target: availableTargets[bestIndex]),
      );

      availableTargets.removeAt(bestIndex);
    }

    // If there are remaining targets, pair them with the closest source
    for (final remaining in availableTargets) {
      if (source.isEmpty) {
        pairs.add(
          EdgeMorphPair(
            source: MorphableEdge(
              start: remaining.center,
              end: remaining.center,
              color: remaining.color.withOpacity(0),
              thickness: 0,
            ),
            target: remaining,
          ),
        );
      } else {
        // Find closest source
        var closestSource = source.first;
        var closestDist = double.infinity;
        for (final src in source) {
          final dist = (src.center - remaining.center).distance;
          if (dist < closestDist) {
            closestDist = dist;
            closestSource = src;
          }
        }
        pairs.add(EdgeMorphPair(source: closestSource, target: remaining));
      }
    }

    return pairs;
  }

  void _handleAnimationTick() {
    notifyListeners();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _isAnimating = false;
      notifyListeners();
      _onComplete?.call();
    }
  }

  /// Stop the current animation
  void stop() {
    _animationController?.stop();
    _isAnimating = false;
    notifyListeners();
  }

  /// Reset the animation
  void reset() {
    _animationController?.reset();
    _morphPairs = [];
    _isAnimating = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _animationController?.removeListener(_handleAnimationTick);
    _animationController?.dispose();
    super.dispose();
  }
}

/// Custom painter that draws morphing edges
class EdgeMorphPainter extends CustomPainter {
  EdgeMorphPainter({required this.controller}) : super(repaint: controller);

  final EdgeMorphController controller;

  @override
  void paint(Canvas canvas, Size size) {
    // Only draw while animating - stop drawing once complete
    if (!controller.isAnimating) return;

    final edges = controller.currentEdges;
    final style = controller.currentStyle;

    // Draw glow layer first
    final glowPaint = Paint()
      ..color = style.effectiveGlowColor.withOpacity(style.glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.glowThickness
      ..strokeCap = StrokeCap.round;

    for (final edge in edges) {
      canvas.drawLine(edge.start, edge.end, glowPaint);
    }

    // Draw main edges
    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final edge in edges) {
      mainPaint
        ..color = edge.color
        ..strokeWidth = edge.thickness;
      canvas.drawLine(edge.start, edge.end, mainPaint);
    }
  }

  @override
  bool shouldRepaint(EdgeMorphPainter oldDelegate) {
    return controller != oldDelegate.controller;
  }
}

/// Widget that displays morphing edges
class EdgeMorphWidget extends StatelessWidget {
  const EdgeMorphWidget({super.key, required this.controller, this.child});

  final EdgeMorphController controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: EdgeMorphPainter(controller: controller),
      child: child,
    );
  }
}

/// Extension to create MorphableEdge from offset pairs
extension MorphableEdgeListExtension on List<(Offset, Offset)> {
  /// Convert a list of offset pairs to morphable edges
  List<MorphableEdge> toMorphableEdges({
    Color color = Colors.cyanAccent,
    double thickness = 1.5,
  }) {
    return map(
      (pair) => MorphableEdge(
        start: pair.$1,
        end: pair.$2,
        color: color,
        thickness: thickness,
      ),
    ).toList();
  }
}
