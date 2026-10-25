import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../asmr/hologram_painter.dart';
import '../gridcraft/fold.dart';
import '../gridcraft/painter.dart' show unitGridPoints, unitGridStride;
import '../papercut/paper.dart';
import 'bench_paper.dart';
import 'craft_theme.dart';

const Color _kSelected = Color(0xFF4FC3F7);
const Color _kCrease = Color(0xFFFFD54F);
const Color _kUnfold = Color(0xFF80DEEA);

/// How thick a cut reads on screen. A finished slit is the theme's desk, so
/// it looks like the background showing through the paper. A cut still being
/// drawn is red.
const double _kCutWidth = 5;
const Color _kLiveCut = Color(0xFFE53935);

/// A stretch of the blueprint that lies on paper, in desk units. [ink] is
/// the inverse of that sheet's visible color, the pip color at full strength.
/// A [fold] stays dashed, the same as the glowing fold line off the paper.
class PencilSpan {
  const PencilSpan(this.a, this.b, this.ink, {this.fold = false});

  final Offset a;
  final Offset b;
  final Color ink;
  final bool fold;
}

/// Splits the blueprint [edges] into the parts on bare desk and the parts
/// lying on [papers]. An edge along a sheet's border counts as on the sheet,
/// so the guide there is a pencil line instead of the glowing outline.
({List<HologramEdgeView> bare, List<PencilSpan> pencil}) splitCraftGuide(
  List<HologramEdgeView> edges,
  List<BenchPaper> papers,
) {
  final bare = <HologramEdgeView>[];
  final pencil = <PencilSpan>[];
  for (final edge in edges) {
    final marks = _segmentMarks(edge.a, edge.b, papers);
    final dir = edge.b - edge.a;
    final len = dir.distance;
    final normal = len < 1e-9
        ? Offset.zero
        : Offset(-dir.dy / len, dir.dx / len);
    double? runStart;
    Color? runInk;
    void flush(double t) {
      final start = runStart;
      if (start == null || t - start < 1e-5) {
        runStart = null;
        runInk = null;
        return;
      }
      final a = Offset.lerp(edge.a, edge.b, start)!;
      final b = Offset.lerp(edge.a, edge.b, t)!;
      final ink = runInk;
      if (ink == null) {
        bare.add(
          HologramEdgeView(a: a, b: b, fold: edge.fold, opacity: edge.opacity),
        );
      } else {
        pencil.add(PencilSpan(a, b, ink, fold: edge.fold));
      }
      runStart = null;
      runInk = null;
    }

    for (var i = 0; i < marks.length - 1; i++) {
      final t0 = marks[i];
      final t1 = marks[i + 1];
      if (t1 - t0 < 1e-5) continue;
      final mid = Offset.lerp(edge.a, edge.b, (t0 + t1) / 2)!;
      final ink = _inkNear(papers, mid, normal);
      if (runStart != null && ink != runInk) flush(t0);
      runStart ??= t0;
      runInk = ink;
    }
    flush(marks.last);
  }
  return (bare: bare, pencil: pencil);
}

/// 0 at [a], 1 at [b], wherever the segment meets a sheet's outline or hole.
/// Cramer's rule, as in Boost.Geometry's `cartesian_segments`.
List<double> _segmentMarks(Offset a, Offset b, List<BenchPaper> papers) {
  final dir = b - a;
  final marks = <double>[0, 1];
  void add(double t) {
    if (t < -1e-6 || t > 1 + 1e-6) return;
    final clamped = t.clamp(0.0, 1.0);
    for (final have in marks) {
      if ((have - clamped).abs() < 1e-6) return;
    }
    marks.add(clamped);
  }

  for (final paper in papers) {
    for (final piece in paper.sheet.pieces) {
      final loops = [
        paper.drawnRing(piece),
        for (final hole in piece.holes) paper.drawnRing(piece, ring: hole),
      ];
      for (final ring in loops) {
        for (var i = 0; i < ring.length; i++) {
          final c = ring[i];
          final edge = ring[(i + 1) % ring.length] - c;
          final denom = dir.dx * edge.dy - dir.dy * edge.dx;
          if (denom.abs() < 1e-12) continue;
          final w = c - a;
          final t = (w.dx * edge.dy - w.dy * edge.dx) / denom;
          final u = (w.dx * dir.dy - w.dy * dir.dx) / denom;
          if (u >= -1e-9 && u <= 1 + 1e-9) add(t);
        }
      }
    }
  }
  marks.sort();
  return marks;
}

/// The pip color of the top sheet at [point], or just beside it when the
/// point sits on the sheet's border.
Color? _inkNear(List<BenchPaper> papers, Offset point, Offset normal) {
  final samples = [
    point,
    if (normal != Offset.zero) ...[
      point + normal * 0.02,
      point - normal * 0.02,
    ],
  ];
  for (final paper in papers.reversed) {
    for (final sample in samples) {
      final ink = _inkOf(paper, sample);
      if (ink != null) return ink;
    }
  }
  return null;
}

Color? _inkOf(BenchPaper paper, Offset desk) {
  if (!paper.contains(desk)) return null;
  final index = topPieceIndex(paper.toLocal(desk), paper.sheet);
  if (index < 0) return null;
  final piece = paper.sheet.pieces[index];
  final back = showingBack(
    paper.toLocal(desk),
    paper.sheet.folds,
    pieceId: piece.id,
  );
  return _inverseOf(paperSideColor(piece, back: back));
}

/// The opposite of [paper], so a mark in it reads on that sheet.
Color _inverseOf(Color paper) => Color.from(
  alpha: 1,
  red: 1 - paper.r,
  green: 1 - paper.g,
  blue: 1 - paper.b,
);

/// A fold of paper [paper] still swinging over: joint [joint], [t] of the
/// way from flat to landed.
typedef BenchBend = ({String paper, int joint, double t});

/// The craft room bench: the dot grid, the paper with its folds, and the
/// previews of the tool in hand, in the colors of [theme]. Desk point `p`
/// lands on screen at `origin + p * scale`.
class CraftBenchPainter extends CustomPainter {
  CraftBenchPainter({
    required this.papers,
    required this.origin,
    required this.scale,
    this.theme = kCraftNoneTheme,
    this.paperGridOpacity = kPaperGridOpacity,
    this.selectedIds = const {},
    this.selectedOutline = 0,
    this.flash = const {},
    this.bend,
    this.stroke,
    this.cuts = const [],
    this.crease,
    this.flap,
    this.unfold,
    this.snap,
    this.island = const [],
    this.islandColor = Colors.white,
    this.pencil = const [],
    this.rotateHandle,
    this.background = true,
  });

  final List<BenchPaper> papers;
  final Offset origin;
  final double scale;

  /// The open group's theme, or the null group's.
  final CraftTheme theme;

  /// Opacity of the grid dots drawn on the paper, from 0 to 1.
  final double paperGridOpacity;
  final Set<String> selectedIds;
  final double selectedOutline;
  final Map<String, double> flash;
  final BenchBend? bend;

  /// The exacto's stroke so far, on the desk.
  final List<Offset>? stroke;

  /// Straight cut or scissors previews, on the desk.
  final List<(Offset, Offset)> cuts;

  /// The folder's crease and a point on the side that folds, on the desk.
  final (Offset, Offset)? crease;
  final Offset? flap;

  /// The crease a tap would open, on the desk.
  final (Offset, Offset)? unfold;

  /// Where the tool has snapped to, on the desk.
  final Offset? snap;

  /// Faces of the net island Arrange holds, on the desk.
  final List<List<Offset>> island;
  final Color islandColor;

  /// Blueprint edges where they lie on paper, in the pip color.
  final List<PencilSpan> pencil;

  /// The selected paper's turn handle, on screen.
  final Offset? rotateHandle;

  /// Fills the desk with [theme]'s desk color first. Off when whatever is
  /// under the bench should show between the papers.
  final bool background;

  Offset _screen(Offset desk) => origin + desk * scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..color = theme.desk);
    }
    _paintGrid(canvas, size);
    for (final paper in papers) {
      _paintPaper(canvas, paper);
    }
    _paintPencil(canvas);
    for (final paper in papers) {
      _paintSlits(canvas, paper);
    }
    _paintIsland(canvas);
    _paintPreviews(canvas);
    _paintHandle(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (scale <= 0) return;
    final stride = unitGridStride(spacing: kBenchGrid, pixelsPerUnit: scale);
    final view = Rect.fromPoints(
      (Offset.zero - origin) / scale,
      (Offset(size.width, size.height) - origin) / scale,
    );
    final dot = Paint()..color = theme.dot;
    final major = Paint()..color = theme.majorDot;
    for (final point in unitGridPoints(view, stride)) {
      final i = (point.dx / kBenchGrid).round();
      final j = (point.dy / kBenchGrid).round();
      final big = i % 5 == 0 && j % 5 == 0;
      canvas.drawCircle(_screen(point), big ? 1.6 : 1.1, big ? major : dot);
    }
  }

  Path _path(List<Offset> ring, List<List<Offset>> holes) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final loop in [ring, ...holes]) {
      if (loop.length < 3) continue;
      path.addPolygon([for (final p in loop) _screen(p)], true);
    }
    return path;
  }

  void _paintPaper(Canvas canvas, BenchPaper paper) {
    final folds = paper.sheet.folds;
    final swing = bend?.paper == paper.id ? bend : null;
    final pieces = [...paper.sheet.pieces]
      ..sort(
        (a, b) => foldDepth(
          _middle(a),
          folds,
          pieceId: a.id,
        ).compareTo(foldDepth(_middle(b), folds, pieceId: b.id)),
      );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.28);
    final selected = selectedIds.contains(paper.id) && selectedOutline > 0;
    final glow = flash[paper.id] ?? 0;
    for (final piece in pieces) {
      final ring = paper.drawnRing(
        piece,
        bend: swing?.joint,
        bendT: swing?.t ?? 1,
      );
      final holes = [
        for (final hole in piece.holes)
          paper.drawnRing(
            piece,
            ring: hole,
            bend: swing?.joint,
            bendT: swing?.t ?? 1,
          ),
      ];
      final path = _path(ring, holes);
      canvas.drawPath(
        path.shift(const Offset(1.5, 2.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      final back = showingBack(
        _middle(piece),
        folds,
        pieceId: piece.id,
        bend: swing?.joint,
        bendT: swing?.t ?? 1,
      );
      final side = paperSideColor(piece, back: back);
      canvas.drawPath(path, Paint()..color = side);
      if (paper.shade > 0) {
        canvas.drawPath(
          path,
          Paint()..color = Colors.black.withValues(alpha: paper.shade),
        );
      }
      canvas.drawPath(path, outline);
      canvas.save();
      canvas.clipPath(path);
      _paintPaperGrid(
        canvas,
        ring,
        _inverseOf(side).withValues(alpha: paperGridOpacity.clamp(0.0, 1.0)),
      );
      canvas.restore();
      if (selected) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = _kSelected.withValues(alpha: selectedOutline),
        );
      }
      if (glow > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
            ..color = Colors.white.withValues(alpha: 0.8 * glow),
        );
      }
    }
  }

  void _paintSlits(Canvas canvas, BenchPaper paper) {
    final folds = paper.sheet.folds;
    for (final line in paper.slits) {
      if (line.length < 2) continue;
      _paintCut(canvas, [
        for (final p in line) _screen(paper.toDesk(displayPoint(p, folds))),
      ], theme.desk);
    }
  }

  void _paintPencil(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final tinted = theme.line != kCraftNoneTheme.line;
    for (final span in pencil) {
      paint.color = tinted ? theme.line : span.ink;
      final a = _screen(span.a);
      final b = _screen(span.b);
      if (span.fold) {
        _dashed(canvas, a, b, paint, on: 6, gap: 5);
      } else {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  /// The bench's dot grid, drawn on a sheet in [ink] so it reads there.
  void _paintPaperGrid(Canvas canvas, List<Offset> ring, Color ink) {
    if (scale <= 0 || ring.isEmpty) return;
    var box = Rect.fromPoints(ring.first, ring.first);
    for (final point in ring.skip(1)) {
      box = box.expandToInclude(Rect.fromPoints(point, point));
    }
    final stride = unitGridStride(spacing: kBenchGrid, pixelsPerUnit: scale);
    final paint = Paint()..color = ink;
    for (final point in unitGridPoints(box.inflate(stride), stride)) {
      final i = (point.dx / kBenchGrid).round();
      final j = (point.dy / kBenchGrid).round();
      final big = i % 5 == 0 && j % 5 == 0;
      canvas.drawCircle(_screen(point), big ? 2.2 : 1.6, paint);
    }
  }

  Paint _cutLine(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kCutWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  void _paintCut(Canvas canvas, List<Offset> points, Color color) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, _cutLine(color));
  }

  Offset _middle(PapercutPiece piece) {
    final ring = piece.vertices;
    if (ring.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final p in ring) {
      sum += p;
    }
    return sum / ring.length.toDouble();
  }

  void _paintIsland(Canvas canvas) {
    if (island.isEmpty) return;
    final fill = Paint()..color = islandColor.withValues(alpha: 0.12);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = islandColor.withValues(alpha: 0.9);
    for (final ring in island) {
      final path = _path(ring, const []);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }
  }

  void _paintPreviews(Canvas canvas) {
    for (final (a, b) in cuts) {
      _paintCut(canvas, [_screen(a), _screen(b)], _kLiveCut);
      canvas.drawCircle(_screen(b), _kCutWidth / 2, Paint()..color = _kLiveCut);
    }
    final line = stroke;
    if (line != null && line.length >= 2) {
      _paintCut(canvas, [for (final p in line) _screen(p)], _kLiveCut);
    }
    final fold = crease;
    if (fold != null) {
      _dashed(
        canvas,
        _screen(fold.$1),
        _screen(fold.$2),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = _kCrease,
      );
      final side = flap;
      if (side != null) {
        canvas.drawCircle(
          _screen(side),
          4,
          Paint()..color = _kCrease.withValues(alpha: 0.8),
        );
      }
    }
    final open = unfold;
    if (open != null) {
      _dashed(
        canvas,
        _screen(open.$1),
        _screen(open.$2),
        Paint()
          ..strokeWidth = 2
          ..color = _kUnfold,
      );
    }
    final point = snap;
    if (point != null) {
      canvas.drawCircle(
        _screen(point),
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  void _paintHandle(Canvas canvas) {
    final handle = rotateHandle;
    if (handle == null || selectedOutline <= 0) return;
    final a = selectedOutline;
    canvas.drawCircle(
      handle,
      13,
      Paint()..color = Colors.black.withValues(alpha: 0.35 * a),
    );
    canvas.drawCircle(
      handle,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9 * a),
    );
    canvas.drawArc(
      Rect.fromCircle(center: handle, radius: 6),
      -2.6,
      4.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9 * a),
    );
  }

  void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double on = 7,
    double gap = 5,
  }) {
    final delta = b - a;
    final length = delta.distance;
    if (length < 1) return;
    final dir = delta / length;
    var at = 0.0;
    while (at < length) {
      final stop = math.min(at + on, length);
      canvas.drawLine(a + dir * at, a + dir * stop, paint);
      at = stop + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CraftBenchPainter old) => true;
}
