import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'dynamic_grid.dart';

/// Tangram fills, the repeated grid, the blueprint outline, and the finger circle.
///
/// The blueprint is drawn after the grid so its white outline sits on top.
class DynamicGridPainter extends CustomPainter {
  DynamicGridPainter({
    required this.camera,
    required this.lattice,
    required this.pieces,
    required this.graph,
    required this.view,
    required this.editing,
    required this.stroke,
    required this.flashRings,
    required this.illegal,
    required this.pulse,
    this.blueprint = const [],
    this.failingBlueprint,
    this.failureFlash = 0,
    this.selectedId,
    this.showCursor = false,
  });

  final PapercutCamera camera;
  final TangramLattice? lattice;
  final List<TangramPiece> pieces;
  final DynamicGridGraph graph;
  final Rect view;
  final bool editing;
  final String? selectedId;
  final List<Offset> stroke;

  /// Faces a finished cut would create. They flash until the finger lifts.
  final List<List<Offset>> flashRings;
  final List<List<Offset>> blueprint;
  final int? failingBlueprint;
  final double failureFlash;
  final bool illegal;
  final double pulse;
  final bool showCursor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintFills(canvas, size);
    _paintGraph(canvas, size);
    _paintBlueprint(canvas, size);
    _paintFlash(canvas, size);
    if (selectedId != null) _paintSelection(canvas, size);
    if (stroke.length >= 2) _paintStroke(canvas, size);
    if (showCursor && stroke.isNotEmpty) {
      _paintCursor(canvas, size, stroke.last);
    }
  }

  void _paintFills(Canvas canvas, Size size) {
    final lattice = this.lattice;
    if (lattice == null) return;
    for (final cell in lattice.cellsCovering(view)) {
      final shift = lattice.shift(cell.$1, cell.$2);
      final source = cell.$1 == 0 && cell.$2 == 0;
      final alpha = editing && source
          ? 0.5
          : (editing ? 0.18 : (source ? 0.16 : 0.07));
      for (final piece in pieces) {
        _paintPiece(
          canvas,
          size,
          piece,
          shift,
          piece.color.withValues(alpha: alpha),
        );
      }
    }
  }

  void _paintPiece(
    Canvas canvas,
    Size size,
    TangramPiece piece,
    Offset shift,
    Color color,
  ) {
    if (piece.kind == TangramKind.circle) {
      final samples = sampleArc(
        piece.anchor + shift,
        kTangramModule / 2,
        0,
        math.pi * 2,
      );
      _fill(canvas, size, samples, color);
      return;
    }
    final ring = [for (final point in tangramRing(piece)) point + shift];
    _fill(canvas, size, ring, color);
  }

  void _paintGraph(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8E8E98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final link in graph.links) {
      final a = _project(graph.vertices[link.$1], size);
      final b = _project(graph.vertices[link.$2], size);
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, paint);
    }
  }

  void _paintBlueprint(Canvas canvas, Size size) {
    final pulse = failureFlash <= 0
        ? 0.0
        : math.sin(failureFlash * math.pi * 3).abs();
    for (var i = 0; i < blueprint.length; i++) {
      final ring = blueprint[i];
      if (ring.length < 2) continue;
      final failing = failingBlueprint == i && pulse > 0;
      final color = failing
          ? Color.lerp(const Color(0xFFFFFFFF), const Color(0xFFFF1744), pulse)!
          : const Color(0xFFFFFFFF);
      _strokeRing(
        canvas,
        size,
        ring,
        color,
        width: failing ? 2.5 + 3 * pulse : 2.5,
        close: ring.length >= 3,
      );
    }
  }

  void _paintFlash(Canvas canvas, Size size) {
    if (flashRings.isEmpty) return;
    final color = const Color(0xFFFFFFFF).withValues(alpha: 0.28 + 0.5 * pulse);
    for (final ring in flashRings) {
      _fill(canvas, size, ring, color);
    }
  }

  void _paintSelection(Canvas canvas, Size size) {
    final lattice = this.lattice;
    TangramPiece? piece;
    for (final candidate in pieces) {
      if (candidate.id == selectedId) piece = candidate;
    }
    if (piece == null || lattice == null) return;
    for (final cell in lattice.cellsCovering(view)) {
      final shift = lattice.shift(cell.$1, cell.$2);
      final ring = piece.kind == TangramKind.circle
          ? sampleArc(piece.anchor + shift, kTangramModule / 2, 0, math.pi * 2)
          : [for (final point in tangramRing(piece)) point + shift];
      _strokeRing(
        canvas,
        size,
        ring,
        const Color(0xFFFFFFFF),
        width: 2.5,
        close: true,
      );
    }
  }

  void _paintStroke(Canvas canvas, Size size) {
    final hot = illegal ? (0.45 + 0.55 * pulse) : 1.0;
    final glow = illegal
        ? const Color(0xFFFF1744).withValues(alpha: 0.85 * hot)
        : const Color(0xFF69F0AE).withValues(alpha: 0.9);
    _strokeRing(canvas, size, stroke, glow, width: 14, blur: 8);
    _strokeRing(
      canvas,
      size,
      stroke,
      illegal ? const Color(0xFFFF8A80) : const Color(0xFFE8FFF3),
      width: 5,
    );
  }

  void _paintCursor(Canvas canvas, Size size, Offset world) {
    final screen = _project(world, size);
    if (screen == null) return;
    canvas.drawCircle(screen, 26, Paint()..color = const Color(0x55FFFFFF));
    canvas.drawCircle(
      screen,
      26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFFFFF),
    );
  }

  void _fill(Canvas canvas, Size size, List<Offset> ring, Color color) {
    final path = _path(ring, size, close: true);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokeRing(
    Canvas canvas,
    Size size,
    List<Offset> ring,
    Color color, {
    required double width,
    bool close = false,
    double blur = 0,
  }) {
    final path = _path(ring, size, close: close);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = blur > 0
            ? MaskFilter.blur(BlurStyle.normal, blur)
            : null,
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
  bool shouldRepaint(covariant DynamicGridPainter oldDelegate) => true;
}
