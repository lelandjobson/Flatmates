import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'blueprint_board.dart';

/// Paper parked on the blueprint, plus the transform box while scaling.
class BlueprintBoardPainter extends CustomPainter {
  BlueprintBoardPainter({
    required this.camera,
    required this.pieces,
    required this.selected,
    this.marquee,
    this.transform,
    this.pivot,
    this.snap,
  });

  final PapercutCamera camera;
  final List<BoardPiece> pieces;
  final Set<String> selected;
  final Rect? marquee;
  final Rect? transform;
  final Offset? pivot;
  final Offset? snap;

  static const _selection = Color(0xFFFFFFFF);
  static const _overlay = Color(0xFFFFE14A);

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      _fillRing(
        canvas,
        size,
        piece.vertices,
        piece.color.withValues(alpha: 0.85),
      );
      for (final hole in piece.holes) {
        _fillRing(canvas, size, hole, const Color(0xFF1A1A2E));
      }
    }
    for (final piece in pieces) {
      if (!selected.contains(piece.id)) continue;
      _fillRing(canvas, size, piece.vertices, _overlay.withValues(alpha: 0.2));
      _strokeRing(canvas, size, piece.vertices, _selection, width: 2.5);
    }
    final box = transform;
    if (box != null) _paintBox(canvas, size, box);
    final mark = pivot ?? snap;
    if (mark != null) _paintDot(canvas, size, mark, pivot != null);
    final band = marquee;
    if (band != null) {
      canvas.drawRect(
        band,
        Paint()
          ..color = const Color(0x332196F3)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        band,
        Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _paintBox(Canvas canvas, Size size, Rect bounds) {
    final corners = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
    _strokeRing(canvas, size, corners, _selection, width: 1.4);
    final paint = Paint()..color = _selection;
    final line = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final handle in transformHandlePoints(bounds)) {
      final screen = _project(handle, size);
      if (screen == null) continue;
      final rect = Rect.fromCenter(center: screen, width: 10, height: 10);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, line);
    }
  }

  void _paintDot(Canvas canvas, Size size, Offset world, bool locked) {
    final screen = _project(world, size);
    if (screen == null) return;
    canvas.drawCircle(
      screen,
      locked ? 7 : 5,
      Paint()..color = locked ? _overlay : _selection,
    );
  }

  void _fillRing(Canvas canvas, Size size, List<Offset> ring, Color color) {
    final path = _path(ring, size);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokeRing(
    Canvas canvas,
    Size size,
    List<Offset> ring,
    Color color, {
    required double width,
  }) {
    final path = _path(ring, size);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path? _path(List<Offset> ring, Size size) {
    if (ring.length < 2) return null;
    final path = Path();
    var started = false;
    for (final point in ring) {
      final screen = _project(point, size);
      if (screen == null) continue;
      if (!started) {
        path.moveTo(screen.dx, screen.dy);
        started = true;
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    if (!started) return null;
    path.close();
    return path;
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  @override
  bool shouldRepaint(covariant BlueprintBoardPainter oldDelegate) => true;
}
