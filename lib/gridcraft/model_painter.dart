import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'folded_model.dart';
import 'painter.dart' show kCriterionMetColor;

/// Blueprint ink, shared by the sheet and the model.
const Color kBlueprintInk = Color(0xFF1565C0);

/// A placed paper piece that has not wrapped, already in world space.
class LoosePaper {
  const LoosePaper({
    required this.ring,
    required this.color,
    this.ink = const [],
  });

  final List<Vector3> ring;
  final Color color;
  final List<(Vector3, Vector3)> ink;
}

/// The folded model: ghost faces, paper on them, marks, focus, and glows.
/// Faces are drawn back to front.
class ModelPainter extends CustomPainter {
  ModelPainter({
    required this.camera,
    required this.model,
    this.ghostPoses = const {},
    this.ghostOpacity = 1,
    this.marks = const [],
    this.paperPoses = const {},
    this.paperColors = const {},
    this.loose = const [],
    this.focusFace,
    this.glow = const {},
    this.complete = 0,
  });

  final PapercutCamera camera;
  final FoldedModel model;

  /// Ghost face poses. Faces not listed sit at [ModelFace.toWorld].
  final Map<int, Matrix4> ghostPoses;
  final double ghostOpacity;

  /// Parallel to [FoldedModel.faces]. Empty draws no marks.
  final List<FaceMark> marks;

  /// Faces covered by wrapped paper, at their current wrap pose.
  final Map<int, Matrix4> paperPoses;
  final Map<int, Color> paperColors;
  final List<LoosePaper> loose;
  final int? focusFace;

  /// Face index to 0–1 match glow.
  final Map<int, double> glow;

  /// 0–1 stand-in glow once every island is wrapped.
  final double complete;

  @override
  void paint(Canvas canvas, Size size) {
    final view = camera.camera.viewMatrix;
    final eye = camera.camera.position;
    final items = <_Item>[];
    for (var i = 0; i < model.faces.length; i++) {
      final paper = paperPoses[i];
      final pose = paper ?? ghostPoses[i] ?? model.faces[i].toWorld;
      final ring = model.faces[i].worldRing(pose);
      items.add(
        _Item(
          depth: _depth(view, ring),
          paint: () => paper == null
              ? _paintGhost(canvas, size, i, pose, ring, eye)
              : _paintPaper(canvas, size, i, pose, ring, eye),
        ),
      );
    }
    for (final piece in loose) {
      items.add(
        _Item(
          depth: _depth(view, piece.ring),
          paint: () => _paintLoose(canvas, size, piece),
        ),
      );
    }
    items.sort((a, b) => a.depth.compareTo(b.depth));
    for (final item in items) {
      item.paint();
    }

    for (final entry in glow.entries) {
      if (entry.value <= 0) continue;
      final pose = paperPoses[entry.key] ?? ghostPoses[entry.key];
      final ring = model.faces[entry.key].worldRing(pose);
      final t = entry.value.clamp(0.0, 1.0);
      _fill(canvas, size, ring, kCriterionMetColor.withValues(alpha: 0.22 * t));
      _stroke(
        canvas,
        size,
        ring,
        kCriterionMetColor.withValues(alpha: 0.75 * t),
        width: 3 + 5 * t,
      );
    }
    if (complete > 0) {
      final t = complete.clamp(0.0, 1.0);
      for (var i = 0; i < model.faces.length; i++) {
        final pose = paperPoses[i] ?? ghostPoses[i];
        _stroke(
          canvas,
          size,
          model.faces[i].worldRing(pose),
          kCriterionMetColor.withValues(alpha: 0.45 * t),
          width: 8,
        );
      }
    }
    final focus = focusFace;
    if (focus != null && focus >= 0 && focus < model.faces.length) {
      final ring = model.faces[focus].worldRing(
        paperPoses[focus] ?? ghostPoses[focus],
      );
      _stroke(canvas, size, ring, const Color(0x66FFFFFF), width: 6);
      _stroke(canvas, size, ring, const Color(0xFFFFD54F), width: 2);
    }
  }

  void _paintGhost(
    Canvas canvas,
    Size size,
    int face,
    Matrix4 pose,
    List<Vector3> ring,
    Vector3 eye,
  ) {
    if (ghostOpacity <= 0) return;
    final facing = _facing(face, pose, ring, eye);
    final shade = 0.55 + 0.45 * facing.abs();
    _fill(
      canvas,
      size,
      ring,
      kBlueprintInk.withValues(alpha: (0.06 + 0.10 * shade) * ghostOpacity),
    );
    _edges(
      canvas,
      size,
      face,
      ring,
      kBlueprintInk.withValues(alpha: 0.85 * ghostOpacity),
      width: 1.6,
    );
    if (facing > 0) _mark(canvas, size, face, pose, ghostOpacity);
  }

  void _paintPaper(
    Canvas canvas,
    Size size,
    int face,
    Matrix4 pose,
    List<Vector3> ring,
    Vector3 eye,
  ) {
    final facing = _facing(face, pose, ring, eye);
    final base = paperColors[face] ?? const Color(0xFFFFF3B0);
    final shade = 0.72 + 0.28 * facing.abs();
    _fill(canvas, size, ring, Color.lerp(Colors.black, base, shade)!);
    _edges(canvas, size, face, ring, kBlueprintInk, width: 1.8);
    _stroke(
      canvas,
      size,
      ring,
      const Color(0xFF1A1A2E).withValues(alpha: 0.5),
      width: 1,
      close: true,
    );
    if (facing > 0) _mark(canvas, size, face, pose, 1);
  }

  void _paintLoose(Canvas canvas, Size size, LoosePaper piece) {
    _fill(canvas, size, piece.ring, piece.color);
    for (final (a, b) in piece.ink) {
      _stroke(canvas, size, [a, b], kBlueprintInk, width: 1.6);
    }
    _stroke(
      canvas,
      size,
      piece.ring,
      const Color(0xFF1A1A2E),
      width: 1.5,
      close: true,
    );
  }

  void _edges(
    Canvas canvas,
    Size size,
    int face,
    List<Vector3> ring,
    Color color, {
    required double width,
  }) {
    final folds = model.foldEdges[face];
    for (var e = 0; e < ring.length; e++) {
      final a = ring[e];
      final b = ring[(e + 1) % ring.length];
      _stroke(
        canvas,
        size,
        [a, b],
        color,
        width: width,
        dashed: e < folds.length && folds[e],
      );
    }
  }

  void _mark(Canvas canvas, Size size, int face, Matrix4 pose, double opacity) {
    if (face >= marks.length) return;
    final modelFace = model.faces[face];
    paintFaceMark(
      canvas,
      marks[face],
      (point) =>
          camera.camera.projectToScreen(modelFace.world(point, pose), size),
      opacity: opacity,
    );
  }

  /// Signed cosine between the outward normal and the view direction.
  double _facing(int face, Matrix4 pose, List<Vector3> ring, Vector3 eye) {
    final side = model.outwardSides[face];
    final normal = pose.getRotation().transformed(Vector3(0, 0, side));
    final center = Vector3.zero();
    for (final point in ring) {
      center.add(point);
    }
    center.scale(1 / ring.length);
    final toEye = eye - center;
    if (toEye.length2 < 1e-12 || normal.length2 < 1e-12) return 0;
    return normal.normalized().dot(toEye.normalized());
  }

  double _depth(Matrix4 view, List<Vector3> ring) {
    var sum = 0.0;
    for (final point in ring) {
      sum += view.transformed3(point).z;
    }
    return ring.isEmpty ? 0 : sum / ring.length;
  }

  void _fill(Canvas canvas, Size size, List<Vector3> ring, Color color) {
    final path = _path(size, ring);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = color);
  }

  void _stroke(
    Canvas canvas,
    Size size,
    List<Vector3> points,
    Color color, {
    required double width,
    bool close = true,
    bool dashed = false,
  }) {
    final projected = [
      for (final point in points) camera.camera.projectToScreen(point, size),
    ];
    if (projected.any((point) => point == null) || projected.length < 2) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final screen = projected.cast<Offset>();
    if (!dashed) {
      final path = Path()..moveTo(screen.first.dx, screen.first.dy);
      for (final point in screen.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (close && screen.length > 2) path.close();
      canvas.drawPath(path, paint);
      return;
    }
    for (var i = 0; i < screen.length - 1; i++) {
      _dash(canvas, screen[i], screen[i + 1], paint);
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final dir = delta / length;
    var traveled = 0.0;
    while (traveled < length) {
      final stop = math.min(traveled + 7, length);
      canvas.drawLine(a + dir * traveled, a + dir * stop, paint);
      traveled = stop + 5;
    }
  }

  Path? _path(Size size, List<Vector3> ring) {
    final projected = [
      for (final point in ring) camera.camera.projectToScreen(point, size),
    ];
    if (projected.length < 3 || projected.any((point) => point == null)) {
      return null;
    }
    final screen = projected.cast<Offset>();
    final path = Path()..moveTo(screen.first.dx, screen.first.dy);
    for (final point in screen.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant ModelPainter oldDelegate) => true;
}

class _Item {
  const _Item({required this.depth, required this.paint});

  final double depth;
  final VoidCallback paint;
}

/// Letter at the face center with an up arrow above it. [project] takes level
/// coordinates to the screen, so the glyph lies in whatever plane it maps to.
void paintFaceMark(
  Canvas canvas,
  FaceMark mark,
  Offset? Function(Offset point) project, {
  Color color = kBlueprintInk,
  double opacity = 1,
}) {
  if (opacity <= 0) return;
  final unit = (mark.size * 0.28).clamp(0.3, 1.2);
  final up = mark.up.distance < 1e-9
      ? const Offset(0, 1)
      : mark.up / mark.up.distance;
  final center = project(mark.center);
  final above = project(mark.center + up * unit);
  final tail = project(mark.center + up * (unit * 0.85));
  final tip = project(mark.center + up * (unit * 1.9));
  if (center == null || above == null || tail == null || tip == null) return;
  final pixels = (above - center).distance;
  if (pixels < 3) return;
  final ink = color.withValues(alpha: color.a * opacity);
  final text = TextPainter(
    text: TextSpan(
      text: mark.label,
      style: TextStyle(
        color: ink,
        fontSize: (pixels * 1.15).clamp(7.0, 26.0),
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, center - Offset(text.width / 2, text.height / 2));

  final paint = Paint()
    ..color = ink
    ..strokeWidth = (pixels * 0.12).clamp(1.2, 2.6)
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(tail, tip, paint);
  final delta = tip - tail;
  final length = delta.distance;
  if (length < 2) return;
  final dir = delta / length;
  final normal = Offset(-dir.dy, dir.dx);
  final head = math.min(length * 0.45, 9.0);
  final base = tip - dir * head;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (base + normal * head * 0.55).dx,
        (base + normal * head * 0.55).dy,
      )
      ..lineTo(
        (base - normal * head * 0.55).dx,
        (base - normal * head * 0.55).dy,
      )
      ..close(),
    Paint()..color = ink,
  );
}
