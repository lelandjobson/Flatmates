import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'craft_plane.dart';
import 'folded_model.dart';
import 'painter.dart' show kCriterionMetColor;

/// Blueprint ink, shared by the sheet and the model.
const Color kBlueprintInk = Color(0xFF1565C0);

/// Fill on the face under the reticle, ready to take paper.
const Color kPreselectColor = Color(0xFFFF9F43);

/// Ghost faces show their decals this faintly, as where paper wraps to.
const double _kGhostDecalOpacity = 0.35;

/// A placed paper piece that has not wrapped, already in world space.
/// [decals] are in coordinates of [plane], the face it lies on.
class LoosePaper {
  const LoosePaper({
    required this.ring,
    required this.color,
    this.ink = const [],
    this.plane,
    this.decals = const [],
  });

  final List<Vector3> ring;
  final Color color;
  final List<(Vector3, Vector3)> ink;
  final CraftPlane? plane;
  final List<Decal> decals;
}

/// The folded model: ghost faces, paper on them, decals, focus, and glows.
/// Faces are drawn back to front.
class ModelPainter extends CustomPainter {
  ModelPainter({
    required this.camera,
    required this.model,
    this.ghostPoses = const {},
    this.ghostOpacity = 1,
    this.decals = const [],
    this.paperPoses = const {},
    this.paperColors = const {},
    this.loose = const [],
    this.highlight = const {},
    this.desk,
    this.deskHighlight = 0,
    this.glow = const {},
    this.complete = 0,
  });

  final PapercutCamera camera;
  final FoldedModel model;

  /// Ghost face poses. Faces not listed sit at [ModelFace.toWorld].
  final Map<int, Matrix4> ghostPoses;
  final double ghostOpacity;

  /// Drawn on their [Decal.face]: in full on wrapped paper, faintly on the
  /// ghost.
  final List<Decal> decals;

  /// Faces covered by wrapped paper, at their current wrap pose.
  final Map<int, Matrix4> paperPoses;
  final Map<int, Color> paperColors;
  final List<LoosePaper> loose;

  /// Face index to 0–1 preselect fill.
  final Map<int, double> highlight;

  /// The desk on the world sheet, under the model. Null draws none.
  final Rect? desk;

  /// 0–1 preselect fill on [desk].
  final double deskHighlight;

  /// Face index to 0–1 match glow.
  final Map<int, double> glow;

  /// 0–1 stand-in glow once every island is wrapped.
  final double complete;

  @override
  void paint(Canvas canvas, Size size) {
    final view = camera.camera.viewMatrix;
    final eye = camera.camera.position;
    _paintDesk(canvas, size);
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

    for (final entry in highlight.entries) {
      if (entry.value <= 0 || entry.key < 0) continue;
      if (entry.key >= model.faces.length) continue;
      final pose = paperPoses[entry.key] ?? ghostPoses[entry.key];
      final t = Curves.easeOut.transform(entry.value.clamp(0.0, 1.0));
      _fill(
        canvas,
        size,
        model.faces[entry.key].worldRing(pose),
        kPreselectColor.withValues(alpha: 0.34 * t),
      );
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
  }

  void _paintDesk(Canvas canvas, Size size) {
    final rect = desk;
    if (rect == null) return;
    final ring = [
      Vector3(rect.left, rect.top, 0),
      Vector3(rect.right, rect.top, 0),
      Vector3(rect.right, rect.bottom, 0),
      Vector3(rect.left, rect.bottom, 0),
    ];
    _fill(canvas, size, ring, Colors.white.withValues(alpha: 0.035));
    final t = Curves.easeOut.transform(deskHighlight.clamp(0.0, 1.0));
    if (t > 0) {
      _fill(canvas, size, ring, kPreselectColor.withValues(alpha: 0.22 * t));
    }
    _stroke(
      canvas,
      size,
      ring,
      Colors.white.withValues(alpha: 0.22 + 0.2 * t),
      width: 1.5,
    );
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
    if (facing > 0) {
      _decals(canvas, size, face, pose, _kGhostDecalOpacity * ghostOpacity);
    }
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
    if (facing > 0) _decals(canvas, size, face, pose, 1);
  }

  void _paintLoose(Canvas canvas, Size size, LoosePaper piece) {
    _fill(canvas, size, piece.ring, piece.color);
    for (final (a, b) in piece.ink) {
      _stroke(canvas, size, [a, b], kBlueprintInk, width: 1.6);
    }
    final plane = piece.plane;
    if (plane != null) {
      for (final decal in piece.decals) {
        paintDecal(
          canvas,
          decal,
          (point) => camera.camera.projectToScreen(plane.world(point), size),
        );
      }
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

  void _decals(
    Canvas canvas,
    Size size,
    int face,
    Matrix4 pose,
    double opacity,
  ) {
    final modelFace = model.faces[face];
    for (final decal in decals) {
      if (decal.face != face) continue;
      paintDecal(
        canvas,
        decal,
        (point) =>
            camera.camera.projectToScreen(modelFace.world(point, pose), size),
        opacity: opacity,
      );
    }
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

/// Letter height over the decal's [Decal.size].
const double _kDecalHeight = 0.55;

/// Layout size of the glyph before it is mapped into the plane.
const double _kDecalFont = 64;

/// [decal]'s letter lying flat in the plane [project] maps level coordinates
/// into, upright along [Decal.up]. Seen from the back of that plane it is
/// flipped to read forwards.
void paintDecal(
  Canvas canvas,
  Decal decal,
  Offset? Function(Offset point) project, {
  Color color = kBlueprintInk,
  double opacity = 1,
}) {
  if (opacity <= 0) return;
  final height = decal.size * _kDecalHeight;
  final up = decal.up.distance < 1e-9
      ? const Offset(0, 1)
      : decal.up / decal.up.distance;
  final right = Offset(up.dy, -up.dx);
  final center = project(decal.center);
  final across = project(decal.center + right * height);
  final below = project(decal.center - up * height);
  if (center == null || across == null || below == null) return;
  var ex = across - center;
  final ey = below - center;
  if (ey.distance < 4) return;
  if (ex.dx * ey.dy - ex.dy * ey.dx < 0) ex = -ex;
  final text = TextPainter(
    text: TextSpan(
      text: decal.label,
      style: TextStyle(
        color: color.withValues(alpha: color.a * opacity),
        fontSize: _kDecalFont,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.transform(
    Float64List.fromList([
      ex.dx / _kDecalFont,
      ex.dy / _kDecalFont,
      0,
      0,
      ey.dx / _kDecalFont,
      ey.dy / _kDecalFont,
      0,
      0,
      0,
      0,
      1,
      0,
      center.dx,
      center.dy,
      0,
      1,
    ]),
  );
  text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
  canvas.restore();
}
