import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen pixels across the straight edge, edge line to edge line.
const double kStraightEdgeThickness = 50;

/// Screen pixels within which the exacto's blade is drawn onto an edge.
const double kStraightEdgeSnap = 10;

/// A double-edged parallel rule held to the screen, not the desk. [anchor]
/// is a point on its middle line, and [angle] turns its edges from
/// horizontal. Both edges cut straight and stop cuts.
class AsmrStraightEdge {
  const AsmrStraightEdge({
    required this.anchor,
    this.angle = 0,
    this.thickness = kStraightEdgeThickness,
  });

  final Offset anchor;
  final double angle;
  final double thickness;

  double get half => thickness / 2;

  /// Along the edges.
  Offset get direction => Offset(math.cos(angle), math.sin(angle));

  /// Across the edges, toward the side that is down when [angle] is 0.
  Offset get normal => Offset(-math.sin(angle), math.cos(angle));

  AsmrStraightEdge copyWith({Offset? anchor, double? angle}) =>
      AsmrStraightEdge(
        anchor: anchor ?? this.anchor,
        angle: angle ?? this.angle,
        thickness: thickness,
      );

  /// Screen pixels from the middle line, positive on the [normal] side.
  double across(Offset p) {
    final d = p - anchor;
    return d.dx * normal.dx + d.dy * normal.dy;
  }

  bool contains(Offset p) => across(p).abs() <= half;

  /// +1 or -1: the side of the rule [p] is on, or nearest to inside it.
  int sideOf(Offset p) => across(p) >= 0 ? 1 : -1;

  /// [p] kept on [side]: inside the rule it is pushed out to that edge.
  /// Within [snap] of the edge it is drawn onto it, so a blade slides
  /// along it.
  Offset hold(Offset p, int side, {double snap = 0}) {
    final d = across(p);
    if (side > 0 && d < half + snap) return p + normal * (half - d);
    if (side < 0 && d > -half - snap) return p + normal * (-half - d);
    return p;
  }

  /// The rotate handle: just outside the edge, across from [screenCenter].
  Offset rotateHandle(Offset screenCenter) =>
      nearestOnMiddle(screenCenter) + normal * (half + 28);

  /// The point on the middle line nearest [p].
  Offset nearestOnMiddle(Offset p) {
    final d = p - anchor;
    return anchor + direction * (d.dx * direction.dx + d.dy * direction.dy);
  }

  /// How far the line through [a] and [b] can run from [a] before it meets
  /// the rule, as line parameters: 0 at [a], 1 at [b]. Unbounded where it
  /// does not meet it, and on both sides when [a] is inside the rule.
  (double, double) lineLimits(Offset a, Offset b) {
    final along = (b - a).dx * normal.dx + (b - a).dy * normal.dy;
    if (along.abs() < 1e-9 || contains(a)) {
      return (double.negativeInfinity, double.infinity);
    }
    final start = across(a);
    final t0 = (-half - start) / along;
    final t1 = (half - start) / along;
    final near = math.min(t0, t1);
    final far = math.max(t0, t1);
    if (near >= 0) return (double.negativeInfinity, near);
    return (far, double.infinity);
  }
}

const Color _kBody = Color(0xFF3B3D46);

/// Draws the straight edge right across the screen, moved [fly] pixels
/// along its normal while it flies in or out.
class AsmrStraightEdgePainter extends CustomPainter {
  const AsmrStraightEdgePainter({
    required this.edge,
    this.fly = 0,
    this.handle,
    this.pressed = false,
    this.body = _kBody,
    this.bodyOpacity = 1,
  });

  final AsmrStraightEdge edge;
  final double fly;

  /// The rule's color, and how much of it shows.
  final Color body;
  final double bodyOpacity;

  Color _body(double alpha) => body.withValues(alpha: alpha * bodyOpacity);

  /// The rotate handle, on screen, or null to hide it.
  final Offset? handle;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.longestSide * 2 + 200;
    final half = edge.half;
    final at = edge.anchor + edge.normal * fly;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(edge.angle);
    final body = Rect.fromLTRB(-reach, -half, reach, half);
    canvas.drawRect(
      body.shift(const Offset(0, 4)).inflate(1),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_body(0.96), _body(pressed ? 0.62 : 0.5), _body(0.96)],
          stops: const [0, 0.5, 1],
        ).createShader(body),
    );
    final line = Paint()
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.92 * bodyOpacity);
    canvas.drawLine(Offset(-reach, -half), Offset(reach, -half), line);
    canvas.drawLine(Offset(-reach, half), Offset(reach, half), line);
    final inner = Paint()
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawLine(
      Offset(-reach, -half + 1.5),
      Offset(reach, -half + 1.5),
      inner,
    );
    canvas.drawLine(
      Offset(-reach, half - 1.5),
      Offset(reach, half - 1.5),
      inner,
    );
    canvas.restore();

    final knob = handle;
    if (knob == null) return;
    final center = knob + edge.normal * fly;
    canvas.drawCircle(
      center,
      13,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      center,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9 * bodyOpacity),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 6),
      -2.6,
      4.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9 * bodyOpacity),
    );
  }

  @override
  bool shouldRepaint(covariant AsmrStraightEdgePainter old) =>
      old.edge != edge ||
      old.fly != fly ||
      old.handle != handle ||
      old.pressed != pressed ||
      old.body != body ||
      old.bodyOpacity != bodyOpacity;
}
