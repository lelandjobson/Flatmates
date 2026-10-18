import 'package:flutter/material.dart';

/// One edge of the hologram as drawn, fading in or out.
class HologramEdgeView {
  const HologramEdgeView({
    required this.a,
    required this.b,
    required this.fold,
    required this.opacity,
  });

  final Offset a;
  final Offset b;
  final bool fold;
  final double opacity;
}

/// The hologram: the unfolded blueprint of the selected faces in glowing
/// white. Desk point `p` lands on screen at `origin + p * scale`.
class HologramPainter extends CustomPainter {
  const HologramPainter({
    required this.edges,
    required this.faces,
    required this.origin,
    required this.scale,
    this.faceOpacity = 1,
    this.contrast = 0,
  });

  final List<HologramEdgeView> edges;

  /// Face outlines on the desk, washed faintly so the net reads as a sheet.
  final List<List<Offset>> faces;
  final Offset origin;
  final double scale;
  final double faceOpacity;

  /// 0–1: how much darker the shadow under each line is, so the lines still
  /// read over light paper on the desk.
  final double contrast;

  Offset _screen(Offset p) => origin + p * scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (faceOpacity > 0) {
      final wash = Paint()
        ..color = Colors.white.withValues(alpha: 0.05 * faceOpacity);
      for (final ring in faces) {
        if (ring.length < 3) continue;
        final path = Path()..addPolygon([for (final p in ring) _screen(p)], true);
        canvas.drawPath(path, wash);
      }
    }
    final glow = Paint()
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
          ..color = Colors.white.withValues(alpha: 0.38 * t);
        _dashed(canvas, a, b, core);
        continue;
      }
      glow
        ..strokeWidth = 9
        ..color = Colors.white.withValues(alpha: 0.32 * t);
      canvas.drawLine(a, b, glow);
      shade.color = Colors.black.withValues(alpha: (0.22 + 0.3 * contrast) * t);
      canvas.drawLine(a, b, shade);
      core
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: 0.95 * t);
      canvas.drawLine(a, b, core);
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
      old.faceOpacity != faceOpacity ||
      old.contrast != contrast;
}
