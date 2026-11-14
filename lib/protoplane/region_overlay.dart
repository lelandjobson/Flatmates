import 'package:flutter/rendering.dart';
import '../rendering/scene/camera.dart';
import 'models.dart';
import 'pencil.dart';
import 'programs.dart';
import 'region_workspace.dart';

class RegionOverlayPainter extends CustomPainter {
  RegionOverlayPainter({
    required this.workspace,
    required this.camera,
    this.preview,
    this.hover,
    this.fading = const {},
    this.fade = 0,
    this.fadeColor = lightPencilColor,
  });
  final RegionWorkspace workspace;
  final Camera camera;
  final ProgramEvaluation? preview;
  final LightRegion? hover;
  final Map<RegionSurface, List<PencilSegment>> fading;
  final double fade;
  final Color fadeColor;

  @override
  void paint(Canvas canvas, Size size) {
    Offset? project(CraftPlane p, Offset v) =>
        camera.projectToScreen(p.point(v, .009), size);
    Path outline(CraftPlane p, Iterable<List<Offset>> rings) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in rings) {
        final points = ring.map((v) => project(p, v)).toList();
        if (points.isEmpty || points.any((v) => v == null)) continue;
        path.moveTo(points.first!.dx, points.first!.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point!.dx, point.dy);
        }
        path.close();
      }
      return path;
    }

    final target = preview?.target ?? hover;
    if (target != null) {
      final plane =
          preview?.surface.frame ?? workspace.surfaces[target.surfaceId]?.frame;
      if (plane != null) {
        final color = preview?.issue == null
            ? lightPencilColor
            : const Color(0xffff5353);
        final path = outline(plane, target.geometry.rings);
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: .17));
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: .7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    void lines(
      CraftPlane plane,
      Iterable<PencilSegment> segments,
      double opacity, [
      Color color = lightPencilColor,
    ]) {
      final path = Path();
      for (final s in segments) {
        final a = project(plane, s.a), b = project(plane, s.b);
        if (a == null || b == null) continue;
        path.moveTo(a.dx, a.dy);
        path.lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .4 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 11
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final entry in workspace.lines.entries) {
      final plane = workspace.surfaces[entry.key]?.frame;
      if (plane != null) lines(plane, entry.value, 1);
    }
    for (final entry in fading.entries) {
      lines(entry.key.frame, entry.value, fade, fadeColor);
    }
  }

  @override
  bool shouldRepaint(RegionOverlayPainter oldDelegate) => true;
}
