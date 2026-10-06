import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import '../papercut/paper.dart';
import 'fold.dart';
import 'mixed_craft.dart';
import 'painter.dart';
import 'scissor.dart';

/// Crafting lattice, paper, and the candidate cut or crease.
class MixedCraftPainter extends CustomPainter {
  MixedCraftPainter({
    required this.camera,
    required this.area,
    required this.grids,
    required this.view,
    required this.background,
    this.hoverKey,
    this.segment,
    this.segmentGlows = false,
    this.foldSegment = false,
    this.marquee,
    this.marqueeCross = false,
    this.flutterSheetId,
    this.flutterJoint,
    this.flutterBendT = 0,
  });

  final PapercutCamera camera;
  final MixedCraftArea area;

  /// Dot-lattice opacities keyed by crafting grid scale.
  final Map<int, double> grids;
  final Rect view;
  final String? hoverKey;
  final (Offset, Offset)? segment;
  final bool segmentGlows;
  final bool foldSegment;
  final Rect? marquee;
  final bool marqueeCross;

  /// Temporary joint for a crease flutter. It is not stored on the sheet.
  final String? flutterSheetId;
  final FoldJoint? flutterJoint;

  /// 0 is flat, and the twitch peaks near [creaseBendFraction].
  final double flutterBendT;

  /// Screen color behind the paper. Cuts are painted in it so a slit reads
  /// as the backdrop showing through.
  final Color background;

  static const _selectionLine = Color(0xFFFFFFFF);
  static const _overlay = Color(0xFFFFE14A);

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    for (final sheet in area.sheets) {
      final pose = _pose(sheet);
      for (final piece in sheet.paper.pieces) {
        final key = mixedPieceKey(sheet.id, piece.id);
        if (area.hidden.contains(key)) continue;
        final ring = shownRing(
          piece.vertices,
          piece.separation,
          pose.folds,
          pieceId: piece.id,
          bend: pose.bend,
          bendT: pose.bendT,
        );
        _paintPaper(
          canvas,
          size,
          ring,
          piece.color,
          onFill: (path) => _paintPaperGrid(
            canvas,
            size,
            path,
            piece,
            pose.folds,
            bend: pose.bend,
            bendT: pose.bendT,
          ),
        );
      }
    }
    _paintCreases(canvas, size);
    for (final sheet in area.sheets) {
      final pose = _pose(sheet);
      for (final piece in sheet.paper.pieces) {
        final key = mixedPieceKey(sheet.id, piece.id);
        if (area.hidden.contains(key)) continue;
        final selected = area.selected.contains(key);
        final hover = key == hoverKey;
        if (!selected && !hover) continue;
        final ring = shownRing(
          piece.vertices,
          piece.separation,
          pose.folds,
          pieceId: piece.id,
          bend: pose.bend,
          bendT: pose.bendT,
        );
        if (selected) {
          _fill(canvas, size, ring, _overlay.withValues(alpha: 0.2));
        }
        _stroke(canvas, size, ring, _selectionLine, width: 2.5, close: true);
      }
    }
    for (final sheet in area.sheets) {
      for (final piece in sheet.paper.pieces) {
        final key = mixedPieceKey(sheet.id, piece.id);
        if (area.hidden.contains(key)) continue;
        _paintCutMarks(canvas, size, piece, sheet, _pose(sheet));
      }
    }
    final line = segment;
    if (line != null) _paintSegment(canvas, size, line.$1, line.$2);
    final box = marquee;
    if (box != null) _paintMarquee(canvas, box);
  }

  void _paintGrid(Canvas canvas, Size size) {
    if (grids.isEmpty || view.width < 1 || view.height < 1) return;
    final layers = grids.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final layer in layers) {
      _paintDots(canvas, size, layer.key, layer.value);
    }
    _paintOrigin(canvas, size);
  }

  /// Dots at the lattice intersections of [scale], matching the crafting view.
  void _paintDots(Canvas canvas, Size size, int scale, double opacity) {
    if (opacity <= 0.001 || scale <= 0) return;
    final spacing = scale.toDouble();
    final origin = _project(Offset.zero, size);
    final neighbor = _project(Offset(spacing, 0), size);
    final pixels = origin == null || neighbor == null
        ? 12.0
        : (neighbor - origin).distance;
    var stride = unitGridStride(spacing: spacing, pixelsPerUnit: pixels);
    while (stride < spacing * 128) {
      final cols = (view.width / stride).ceil() + 3;
      final rows = (view.height / stride).ceil() + 3;
      final gap = pixels * (stride / spacing);
      if (gap >= 7 && cols * rows <= 4000) break;
      stride *= 2;
    }
    final paint = Paint()
      ..color = Colors.grey.shade400.withValues(alpha: 0.55 * opacity);
    for (final world in unitGridPoints(view, stride)) {
      if (world.distance < 1e-6) continue;
      final screen = _project(world, size);
      if (screen == null || !_onScreen(screen, size)) continue;
      canvas.drawCircle(screen, 1.35, paint);
    }
  }

  void _paintOrigin(Canvas canvas, Size size) {
    final screen = _project(Offset.zero, size);
    if (screen == null || !_onScreen(screen, size)) return;
    canvas.drawCircle(
      screen,
      4.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      screen,
      3.6,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  bool _onScreen(Offset screen, Size size) {
    return screen.dx >= -4 &&
        screen.dy >= -4 &&
        screen.dx <= size.width + 4 &&
        screen.dy <= size.height + 4;
  }

  void _paintPaper(
    Canvas canvas,
    Size size,
    List<Offset> ring,
    Color color, {
    void Function(Path path)? onFill,
  }) {
    final path = _path(ring, size, close: true);
    if (path == null) return;
    final shadow = path.shift(const Offset(2, 2));
    canvas.drawPath(shadow, Paint()..color = const Color(0x14000000));
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
    onFill?.call(path);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xBFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Light lattice on the sheet, clipped to the face. Each entry of [grids]
  /// is one spacing, so a scale fade draws the outgoing and incoming lines
  /// together, the same way the dots behind the paper do.
  ({List<FoldJoint> folds, int? bend, double bendT}) _pose(MixedSheet sheet) {
    final joint = flutterJoint;
    if (joint == null || flutterSheetId != sheet.id) {
      return (folds: sheet.paper.folds, bend: null, bendT: 1);
    }
    return (
      folds: [...sheet.paper.folds, joint],
      bend: sheet.paper.folds.length,
      bendT: flutterBendT,
    );
  }

  void _paintPaperGrid(
    Canvas canvas,
    Size size,
    Path clip,
    PapercutPiece piece,
    List<FoldJoint> folds, {
    int? bend,
    double bendT = 1,
  }) {
    if (grids.isEmpty) return;
    canvas.save();
    canvas.clipPath(clip);
    final layers = grids.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final layer in layers) {
      if (layer.value <= 0.001 || layer.key <= 0) continue;
      final ink = const Color(
        0xFF000000,
      ).withValues(alpha: 0.12 * layer.value);
      final segments = paperGridSegments(
        ring: piece.vertices,
        holes: piece.holes,
        spacing: layer.key.toDouble(),
      );
      for (final segment in segments) {
        final a =
            displayPoint(
              segment.$1,
              folds,
              pieceId: piece.id,
              bend: bend,
              bendT: bendT,
            ) +
            piece.separation;
        final b =
            displayPoint(
              segment.$2,
              folds,
              pieceId: piece.id,
              bend: bend,
              bendT: bendT,
            ) +
            piece.separation;
        _stroke(canvas, size, [a, b], ink, width: 0.6);
      }
    }
    canvas.restore();
  }

  void _paintCutMarks(
    Canvas canvas,
    Size size,
    PapercutPiece piece,
    MixedSheet sheet,
    ({List<FoldJoint> folds, int? bend, double bendT}) pose,
  ) {
    for (final stroke in sheet.paper.cutStrokes) {
      for (final mark in cutMarksOnPiece(stroke, piece)) {
        _stroke(
          canvas,
          size,
          [
            for (final point in mark)
              displayPoint(
                point,
                pose.folds,
                pieceId: piece.id,
                bend: pose.bend,
                bendT: pose.bendT,
              ) +
                  piece.separation,
          ],
          background,
          width: 1.25,
        );
      }
    }
  }

  void _paintCreases(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5C6BC0)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final sheet in area.sheets) {
      for (final score in sheet.paper.scores) {
        final a = _project(score.a, size);
        final b = _project(score.b, size);
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, paint);
      }
      for (final joint in sheet.paper.folds) {
        if (joint.facing == FoldFacing.unfolded) continue;
        final a = _project(displayPoint(joint.a, sheet.paper.folds), size);
        final b = _project(displayPoint(joint.b, sheet.paper.folds), size);
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, paint);
      }
    }
  }

  void _paintSegment(Canvas canvas, Size size, Offset a, Offset b) {
    final color = foldSegment ? const Color(0xFFFFB74D) : background;
    final width = foldSegment && segmentGlows ? 4.0 : 3.0;
    _stroke(canvas, size, [a, b], color, width: width);
  }

  void _paintMarquee(Canvas canvas, Rect box) {
    final paint = Paint()
      ..color = marqueeCross ? const Color(0xFF42A5F5) : const Color(0xFF66BB6A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(box, paint);
    canvas.drawRect(
      box,
      Paint()
        ..color = paint.color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
  }

  void _fill(Canvas canvas, Size size, List<Offset> ring, Color color) {
    final path = _path(ring, size, close: true);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = color);
  }

  void _stroke(
    Canvas canvas,
    Size size,
    List<Offset> ring,
    Color color, {
    required double width,
    bool close = false,
  }) {
    final path = _path(ring, size, close: close);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  Path? _path(List<Offset> ring, Size size, {required bool close}) {
    final projected = <Offset>[];
    for (final point in ring) {
      final screen = _project(point, size);
      if (screen == null) return null;
      projected.add(screen);
    }
    if (projected.length < 2) return null;
    if (close && projected.length < 3) return null;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) path.close();
    return path;
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  @override
  bool shouldRepaint(covariant MixedCraftPainter oldDelegate) => true;
}
