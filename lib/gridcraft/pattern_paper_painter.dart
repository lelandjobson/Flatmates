import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import '../papercut/paper.dart';
import 'folded_model.dart';
import 'model_painter.dart' show kPreselectColor;
import 'wrap_cut.dart';

/// Pattern paper is see-through: the fill at this opacity, and its pattern
/// in the paper's own color at [kPatternLineOpacity], just showing over it.
const double kPatternFillOpacity = 0.4;
const double kPatternLineOpacity = 0.22;

/// Paper off the face being worked on, so fills read across fold lines.
const double kOffFaceOpacity = 0.8;

/// Paper between the camera and the face being worked on, on top of
/// [kOffFaceOpacity].
const double kObstructingOpacity = 0.35;

/// Pattern paper lifts this far off a model face, in grid units.
const double kPatternLift = 0.04;

/// A cut glows red, and a dot of it marks where the cut started.
const Color kCutColor = Color(0xFFFF3B30);

/// A pattern cell that lines up with the face under it fades in this much
/// toward this green, opaque.
const Color kAlignedCellColor = Color(0xFF34C759);
const double kAlignedCellTint = 0.6;

/// Paper shading: a fixed light from above, in front, and to the left, so
/// paper facing different ways reads as different shades.
final Vector3 _kPaperLight = Vector3(-0.35, -0.5, 0.8).normalized();
const double _kPaperShadeDark = 0.8;

/// [color] lit by the paper light on a face whose outward normal is
/// [normal].
Color shadePaper(Color color, Vector3 normal) {
  if (normal.length2 < 1e-12) return color;
  final lambert = normal.normalized().dot(_kPaperLight);
  final shade = _kPaperShadeDark + (1 - _kPaperShadeDark) * (lambert + 1) / 2;
  return Color.lerp(Colors.black, color, shade)!.withValues(alpha: color.a);
}

/// [paper] filled as pattern paper with [lines] across it, all in screen
/// coordinates. [opaque] paper, wrapped onto the model, hides what is under
/// it.
void paintPatternPaper(
  Canvas canvas, {
  required Path paper,
  required Color color,
  Iterable<(Offset, Offset)> lines = const [],
  double opacity = 1,
  double lineWidth = 1.3,
  bool opaque = false,
}) {
  if (opacity <= 0) return;
  canvas.drawPath(
    paper,
    Paint()
      ..color = color.withValues(
        alpha: (opaque ? 1 : kPatternFillOpacity) * opacity,
      ),
  );
  canvas.save();
  canvas.clipPath(paper);
  paintPatternLines(canvas, lines, color, opacity: opacity, opaque: opaque);
  canvas.restore();
  canvas.drawPath(
    paper,
    Paint()
      ..color = Color.lerp(
        color,
        Colors.black,
        0.35,
      )!.withValues(alpha: 0.7 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
}

/// Pattern [lines] on paper of [color]. On [opaque] paper they are inked a
/// shade darker, as the paper's own color would not show.
void paintPatternLines(
  Canvas canvas,
  Iterable<(Offset, Offset)> lines,
  Color color, {
  double opacity = 1,
  double lineWidth = 1.3,
  bool opaque = false,
}) {
  final ink = Paint()
    ..color = opaque
        ? Color.lerp(color, Colors.black, 0.3)!.withValues(alpha: 0.5 * opacity)
        : color.withValues(alpha: kPatternLineOpacity * opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth;
  for (final (a, b) in lines) {
    canvas.drawLine(a, b, ink);
  }
}

/// The white outline of selected paper.
void paintSelectedOutline(Canvas canvas, Path paper, {double opacity = 1}) {
  canvas.drawPath(
    paper,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Screen path of [rings] carried by [toWorld], even-odd so holes stay open.
/// Null when a point falls behind the camera.
Path? projectedRings(
  PapercutCamera camera,
  Size size,
  Iterable<List<Offset>> rings,
  Vector3 Function(Offset point) toWorld,
) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final ring in rings) {
    if (ring.length < 3) continue;
    final first = camera.camera.projectToScreen(toWorld(ring.first), size);
    if (first == null) return null;
    path.moveTo(first.dx, first.dy);
    for (final point in ring.skip(1)) {
      final at = camera.camera.projectToScreen(toWorld(point), size);
      if (at == null) return null;
      path.lineTo(at.dx, at.dy);
    }
    path.close();
  }
  return path;
}

/// 0–1 glow of next-cut dot [index] of [count] at [turn] through one cycle.
/// The dots light in order: [index] starts at [index] / [count] of the
/// cycle and fades in, then out.
double nextDotPulse(int index, int count, double turn) {
  if (count <= 0 || index < 0 || index >= count) return 0;
  var phase = (turn - index / count) % 1.0;
  if (phase < 0) phase += 1;
  const window = 0.28;
  if (phase >= window) return 0;
  return math.sin(math.pi * phase / window);
}

/// Pattern paper being cut on the model: [piece] laid out by [cut]'s flaps,
/// each fold turned by [foldScale] of the way.
class WrapPaperLayer {
  const WrapPaperLayer({
    required this.cut,
    required this.piece,
    this.foldScale,
    this.path = const [],
    this.starts = const [],
    this.aimedStart,
    this.next = const [],
    this.outline = 0,
    this.opacity = 1,
    this.opaque = false,
    this.aligned = false,
  });

  final WrapCut cut;
  final PapercutPiece piece;
  final double Function(int fold)? foldScale;

  /// The cut so far, in paper coordinates.
  final List<Offset> path;

  /// Suggested places to set the blade, ringed, and where a tap would set
  /// it now, as the cut's start dot. Paper coordinates.
  final List<Offset> starts;
  final Offset? aimedStart;

  /// Where the blade can go next, dotted on the flap it would end on, in
  /// paper coordinates. A [travel] there cuts nothing, and its dot is
  /// fainter. [pulse] is 0–1, a circle fading in and out at the dot.
  final List<({Offset at, int flap, bool travel, double pulse})> next;

  /// 0–1: how far the white selection outline has faded in.
  final double outline;

  /// Scales the whole layer, as it fades into what replaces it.
  final double opacity;

  /// True when this paper lies on the model as a wrap: opaque, hiding the
  /// face under it.
  final bool opaque;

  /// Fill the pattern cells that line up with the face under them, as far
  /// as [WrapCutPainter.alignedFade] has faded them in.
  final bool aligned;
}

/// Draws [layers] flap by flap, back to front. Each flap is the paper inside
/// its half-planes, in that flap's plane.
class WrapCutPainter extends CustomPainter {
  WrapCutPainter({
    required this.camera,
    required this.model,
    required this.layers,
    this.currentFace,
    this.onFace = const {},
    this.focusFade = 0,
    this.coveredFaces = const {},
    this.alignedFade = const {},
    this.foldLine,
    this.foldAim,
    this.foldEdge,
    this.foldEdgeGlow = 0,
  });

  final PapercutCamera camera;
  final FoldedModel model;
  final List<WrapPaperLayer> layers;

  /// The face being worked on: the blade's, else the selected paper's.
  final int? currentFace;

  /// Face index to 0–1, easing toward 1 on [currentFace].
  final Map<int, double> onFace;

  /// 0–1: how far off-face paper has faded. 0 with no face worked on.
  final double focusFade;

  /// Faces already wrapped, which take no aligned-cell fill.
  final Set<int> coveredFaces;

  /// Face index to 0–1: how far its aligned cell has faded in.
  final Map<int, double> alignedFade;

  /// The fold tool's line on screen while dragged, and the model edge, in
  /// the world, it would fold over.
  final (Offset, Offset)? foldLine;
  final (Vector3, Vector3)? foldAim;

  /// The model edge the paper last folded over, glowing [foldEdgeGlow], 0–1.
  final (Vector3, Vector3)? foldEdge;
  final double foldEdgeGlow;

  @override
  void paint(Canvas canvas, Size size) {
    if (foldAim case final edge?) _paintFoldEdge(canvas, size, edge, 0.45);
    if (foldEdge case final edge? when foldEdgeGlow > 0) {
      _paintFoldEdge(canvas, size, edge, foldEdgeGlow.clamp(0.0, 1.0));
    }
    if (foldLine case (final a, final b)) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      _dash(canvas, a, b, paint);
      canvas.drawCircle(a, 3, paint);
      canvas.drawCircle(b, 3, paint);
    }
  }

  /// The paper of [layers], one entry per flap, for the model's back-to-front
  /// pass. Depth is the view-space center of the paper actually on that
  /// flap, not the flap's clip window: the window reaches past the sheet,
  /// and while a fold swings that center travels through the model. A flap
  /// swung toward the camera stays just in front of the flap it left, and
  /// one swung away stays just behind it, while a flap clearly farther away
  /// keeps its own depth so a front face can cover it.
  void addSheets(
    Canvas canvas,
    Size size,
    void Function(double depth, VoidCallback paint) add,
  ) {
    final view = camera.camera.viewMatrix;
    final eye = camera.camera.position;
    final current = currentFace;
    for (final layer in layers) {
      final cut = layer.cut;
      final dots = <int, List<Offset>>{};
      final rings = <int, List<Offset>>{};
      for (final point in [?_cutStart(layer), ?layer.aimedStart]) {
        (dots[cut.bladeFlap(point)] ??= []).add(point);
      }
      for (final point in layer.starts) {
        if (layer.aimedStart case final aimed?
            when (aimed - point).distance < 1e-6) {
          continue;
        }
        (rings[cut.bladeFlap(point)] ??= []).add(point);
      }
      final next = <int, List<(Offset, bool, double)>>{};
      for (final step in layer.next) {
        (next[step.flap] ??= []).add((step.at, step.travel, step.pulse));
      }
      final drawn = <int, _FlapSheet>{};
      for (var f = 0; f < cut.flaps.length; f++) {
        final window = cut.flapWindow(f);
        if (window.length < 3) continue;
        final ring = clipByHalfPlanes(layer.piece.vertices, cut.flaps[f].sides);
        if (ring.length < 3) continue;
        final toWorld = cut.flapToWorld(f, scale: layer.foldScale);
        final normal = cut.flapNormal(f, scale: layer.foldScale);
        final lift = normal.scaled(kPatternLift);
        Vector3 world(Offset point) =>
            toWorld.transformed3(Vector3(point.dx, point.dy, 0))..add(lift);
        final middle = Vector3.zero();
        for (final point in ring) {
          middle.add(world(point));
        }
        middle.scale(1 / ring.length);
        final face = cut.flaps[f].face;
        var obstructing = 1.0;
        if (current != null && current < model.faces.length) {
          final ahead = (middle - model.worldCenter(current)).dot(
            model.outwardNormal(current),
          );
          if (ahead > 0.1) obstructing = kObstructingOpacity;
        }
        final opacity =
            layer.opacity *
            obstructing *
            (1 - (1 - kOffFaceOpacity) * focusFade * (1 - (onFace[face] ?? 0)));
        final green = alignedFade[face] ?? 0;
        final cell = layer.aligned && green > 0 && !coveredFaces.contains(face)
            ? alignedCell(cut, f)
            : null;
        drawn[f] = _FlapSheet(
          depth: view.transformed3(middle).z,
          at: middle,
          normal: normal,
          parent: cut.flaps[f].parent,
          paint: () => _paintFlap(
            canvas,
            size,
            layer,
            window,
            world,
            shadePaper(layer.piece.color, normal),
            opacity,
            cell == null
                ? null
                : (
                    cell,
                    Curves.easeOut.transform(green) *
                        obstructing *
                        layer.opacity,
                  ),
            outline: f == 0 ? layer.outline : 0,
            opaque: layer.opaque,
            dots: dots[f] ?? const [],
            rings: rings[f] ?? const [],
            next: next[f] ?? const [],
          ),
        );
      }
      final order = drawn.keys.toList()..sort();
      for (final f in order) {
        final sheet = drawn[f]!;
        final under = sheet.parent == null ? null : drawn[sheet.parent!];
        if (under != null) {
          final side = (sheet.at - under.at).dot(under.normal);
          final eyeSide = (eye - under.at).dot(under.normal);
          if (side.abs() > 1e-4 &&
              eyeSide.abs() > 1e-4 &&
              (sheet.depth - under.depth).abs() < 0.5) {
            sheet.depth = side.sign == eyeSide.sign
                ? math.max(sheet.depth, under.depth) + 1e-3
                : math.min(sheet.depth, under.depth) - 1e-3;
          }
        }
        add(sheet.depth, sheet.paint);
      }
    }
  }

  /// A model edge glowing orange at [glow], 0–1.
  void _paintFoldEdge(
    Canvas canvas,
    Size size,
    (Vector3, Vector3) edge,
    double glow,
  ) {
    final a = camera.camera.projectToScreen(edge.$1, size);
    final b = camera.camera.projectToScreen(edge.$2, size);
    if (a == null || b == null) return;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = kPreselectColor.withValues(alpha: 0.5 * glow)
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = kPreselectColor.withValues(alpha: glow)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintFlap(
    Canvas canvas,
    Size size,
    WrapPaperLayer layer,
    List<Offset> window,
    Vector3 Function(Offset point) world,
    Color color,
    double opacity,
    (List<Offset>, double)? cell, {
    double outline = 0,
    bool opaque = false,
    List<Offset> dots = const [],
    List<Offset> rings = const [],
    List<(Offset, bool, double)> next = const [],
  }) {
    final clip = projectedRings(camera, size, [window], world);
    final paper = projectedRings(camera, size, [
      layer.piece.vertices,
      ...layer.piece.holes,
    ], world);
    if (clip == null || paper == null) return;
    Offset? screen(Offset point) =>
        camera.camera.projectToScreen(world(point), size);
    final lines = <(Offset, Offset)>[];
    for (final (a, b) in layer.cut.lines) {
      final p = screen(a);
      final q = screen(b);
      if (p != null && q != null) lines.add((p, q));
    }
    canvas.save();
    canvas.clipPath(clip);
    paintPatternPaper(
      canvas,
      paper: paper,
      color: color,
      lines: lines,
      opacity: opacity,
      opaque: opaque,
    );
    if (cell != null) {
      final (ring, alpha) = cell;
      final green = projectedRings(camera, size, [ring], world);
      if (green != null) {
        final tint = Color.lerp(color, kAlignedCellColor, kAlignedCellTint)!;
        canvas.drawPath(green, Paint()..color = tint.withValues(alpha: alpha));
        canvas.save();
        canvas.clipPath(green);
        paintPatternLines(canvas, lines, tint, opacity: alpha, opaque: true);
        canvas.restore();
      }
    }
    _paintCut(canvas, layer, screen, opacity);
    canvas.restore();
    if (outline > 0) {
      paintSelectedOutline(canvas, paper, opacity: opacity * outline);
    }
    for (final point in rings) {
      _paintStartRing(canvas, screen(point), opacity);
    }
    for (final (point, travel, pulse) in next) {
      _paintNext(canvas, screen(point), opacity * (travel ? 0.5 : 1), pulse);
    }
    for (final point in dots) {
      _paintStart(canvas, screen(point), opacity);
    }
  }

  /// A ring of the cut's glow where a cut can start.
  void _paintStartRing(Canvas canvas, Offset? at, double opacity) {
    if (at == null) return;
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = kCutColor.withValues(alpha: 0.35 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = kCutColor.withValues(alpha: 0.9 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// A small dot of the cut's glow where a tap takes the blade next, and a
  /// circle at [pulse], 0–1, fading in and out around it.
  void _paintNext(Canvas canvas, Offset? at, double opacity, double pulse) {
    if (at == null) return;
    if (pulse > 0) {
      canvas.drawCircle(
        at,
        18,
        Paint()
          ..color = kCutColor.withValues(alpha: 0.7 * opacity * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = kCutColor.withValues(alpha: 0.4 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      at,
      4,
      Paint()..color = kCutColor.withValues(alpha: 0.9 * opacity),
    );
  }

  /// Where [layer]'s cut starts: its first stretch that cuts, or the blade
  /// before any stroke. Null while the blade has only traveled.
  Offset? _cutStart(WrapPaperLayer layer) {
    final path = layer.path;
    if (path.length == 1) return path.first;
    for (var i = 0; i < path.length - 1; i++) {
      if (!layer.cut.travels(i)) return path[i];
    }
    return null;
  }

  /// Where the blade traveled without cutting.
  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length < 1) return;
    final along = (b - a) / length;
    for (var at = 0.0; at < length; at += 10) {
      canvas.drawLine(
        a + along * at,
        a + along * math.min(at + 5, length),
        paint,
      );
    }
  }

  /// A dot of the cut's glow where it started.
  void _paintStart(Canvas canvas, Offset? at, double opacity) {
    if (at == null) return;
    canvas.drawCircle(
      at,
      9,
      Paint()
        ..color = kCutColor.withValues(alpha: 0.5 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      at,
      5.5,
      Paint()..color = kCutColor.withValues(alpha: opacity),
    );
    canvas.drawCircle(
      at,
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.85 * opacity),
    );
  }

  void _paintCut(
    Canvas canvas,
    WrapPaperLayer layer,
    Offset? Function(Offset point) screen,
    double opacity,
  ) {
    final path = layer.path;
    if (path.length < 2) return;
    final segments = <(Offset, Offset)>[];
    final travel = Paint()
      ..color = kCutColor.withValues(alpha: 0.7 * opacity)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < path.length - 1; i++) {
      final a = screen(path[i]);
      final b = screen(path[i + 1]);
      if (a == null || b == null) continue;
      if (layer.cut.travels(i)) {
        _dash(canvas, a, b, travel);
      } else {
        segments.add((a, b));
      }
    }
    final glow = Paint()
      ..color = kCutColor.withValues(alpha: 0.45 * opacity)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (final (a, b) in segments) {
      canvas.drawLine(a, b, glow);
    }
    final line = Paint()
      ..color = kCutColor.withValues(alpha: opacity)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in segments) {
      canvas.drawLine(a, b, line);
    }
  }

  @override
  bool shouldRepaint(covariant WrapCutPainter oldDelegate) => true;
}

/// One flap in the model's back-to-front pass.
class _FlapSheet {
  _FlapSheet({
    required this.depth,
    required this.at,
    required this.normal,
    required this.parent,
    required this.paint,
  });

  double depth;
  final Vector3 at;
  final Vector3 normal;
  final int? parent;
  final VoidCallback paint;
}
