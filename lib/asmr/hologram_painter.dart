import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asmr_lens.dart';

/// One edge of the hologram as drawn, fading in or out.
class HologramEdgeView {
  const HologramEdgeView({
    required this.a,
    required this.b,
    required this.fold,
    required this.opacity,
    this.color,
  });

  final Offset a;
  final Offset b;
  final bool fold;
  final double opacity;

  /// How well the cut along this edge was judged. Null draws the edge in
  /// the painter's own colors.
  final Color? color;
}

/// The hologram: the unfolded blueprint of the selected faces. Desk point
/// `p` lands on screen at `origin + p * scale`, turned clockwise by [angle]. Edges stay [line] and [glow],
/// white by default. A craft group colors [vertex] circles on the corners.
class HologramPainter extends CustomPainter {
  const HologramPainter({
    required this.edges,
    required this.faces,
    required this.origin,
    required this.scale,
    this.angle = 0,
    this.lens,
    this.faceOpacity = 1,
    this.contrast = 0,
    this.line = const Color(0xFFFFFFFF),
    this.glow = const Color(0xFFFFFFFF),
    this.vertex = const Color(0x00000000),
    this.inkOpacity = 1,
  });

  final List<HologramEdgeView> edges;

  /// Face outlines on the desk, washed faintly so the net reads as a sheet.
  final List<List<Offset>> faces;
  final Offset origin;
  final double scale;
  final double angle;

  /// Pitched cut-mode view. Null leaves the net flat on the desk.
  final AsmrCutLens? lens;
  final double faceOpacity;

  /// 0–1: how much darker the shadow under each line is, so the lines still
  /// read over light paper on the desk.
  final double contrast;

  /// The blueprint stroke, and the halo around edges that are off the paper.
  final Color line;
  final Color glow;

  /// Filled circles on the blueprint's corners. Nothing is drawn at alpha 0.
  final Color vertex;

  /// Fades the lines and the face wash together.
  final double inkOpacity;

  Offset _screen(Offset p) {
    final flat = angle == 0
        ? origin + p * scale
        : origin +
              Offset(
                    math.cos(angle) * p.dx - math.sin(angle) * p.dy,
                    math.sin(angle) * p.dx + math.cos(angle) * p.dy,
                  ) *
                  scale;
    final view = lens;
    if (view == null || view.isOverhead) return flat;
    return view.project(flat);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (inkOpacity <= 0) return;
    if (faceOpacity > 0) {
      final wash = Paint()
        ..color = line.withValues(alpha: 0.05 * faceOpacity * inkOpacity);
      for (final ring in faces) {
        if (ring.length < 3) continue;
        final path = Path()
          ..addPolygon([for (final p in ring) _screen(p)], true);
        canvas.drawPath(path, wash);
      }
    }
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final edge in edges) {
      final t = Curves.easeOut.transform(edge.opacity.clamp(0.0, 1.0));
      if (t <= 0) continue;
      final a = _screen(edge.a);
      final b = _screen(edge.b);
      if (edge.fold) {
        core
          ..strokeWidth = 1.2
          ..color = line.withValues(alpha: 0.38 * t * inkOpacity);
        _dashed(canvas, a, b, core);
        continue;
      }
      final judged = edge.color;
      halo
        ..strokeWidth = 9
        ..color = (judged ?? glow).withValues(
          alpha: (judged == null ? 0.45 : 0.6) * t * inkOpacity,
        );
      canvas.drawLine(a, b, halo);
      shade.color = Colors.black.withValues(alpha: (0.22 + 0.3 * contrast) * t);
      canvas.drawLine(a, b, shade);
      core
        ..strokeWidth = 1.8
        ..color = (judged ?? line).withValues(alpha: 0.95 * t * inkOpacity);
      canvas.drawLine(a, b, core);
    }
    _paintVertices(canvas);
  }

  /// One circle per corner, so a shared vertex of several faces is drawn once.
  void _paintVertices(Canvas canvas) {
    if (vertex.a == 0) return;
    final seen = <Offset>[];
    final fill = Paint()..color = vertex;
    for (final ring in faces) {
      for (final point in ring) {
        var duplicate = false;
        for (final have in seen) {
          if ((have - point).distance < 1e-3) {
            duplicate = true;
            break;
          }
        }
        if (duplicate) continue;
        seen.add(point);
        canvas.drawCircle(_screen(point), 4.5, fill);
      }
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final dir = delta / length;
    var at = 0.0;
    while (at < length) {
      final stop = (at + 6).clamp(0.0, length);
      canvas.drawLine(a + dir * at, a + dir * stop, paint);
      at = stop + 5;
    }
  }

  @override
  bool shouldRepaint(covariant HologramPainter old) =>
      old.edges != edges ||
      old.faces != faces ||
      old.origin != origin ||
      old.scale != scale ||
      old.angle != angle ||
      old.lens != lens ||
      old.faceOpacity != faceOpacity ||
      old.contrast != contrast ||
      old.line != line ||
      old.glow != glow ||
      old.vertex != vertex ||
      old.inkOpacity != inkOpacity;
}
