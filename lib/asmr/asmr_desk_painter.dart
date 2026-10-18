import 'package:flutter/material.dart';

import 'asmr_mapping.dart';
import 'asmr_net.dart';
import 'asmr_paper.dart';
import 'asmr_piece.dart';

/// The 2D crafting desk, and the last stop of the 3D view's gradient.
const Color kAsmrDeskColor = Color(0xFF14152A);

/// The top of the 3D view's gradient.
const Color kAsmrSkyColor = Color(0xFF2B2D4A);

const Color _kGroove = Color(0xFF2A2440);

/// The desk: paper pieces with their prints, scores, and the cut under way.
/// Desk point `p` lands on screen at `origin + p * scale`.
class AsmrDeskPainter extends CustomPainter {
  const AsmrDeskPainter({
    required this.pieces,
    required this.tiles,
    required this.origin,
    required this.scale,
    this.selectedId,
    this.selectedOutline = 0,
    this.flash = const {},
    this.stroke,
    this.knifeTip,
    this.finger,
    this.rotateHandle,
    this.blueprint,
    this.shadowThrow = 10,
    this.shadowSpread = 8,
    this.shadowColor = const Color(0x73000000),
  });

  final List<AsmrPiece> pieces;
  final AsmrPaperTiles tiles;
  final Offset origin;
  final double scale;
  final String? selectedId;
  final double selectedOutline;

  /// Piece id to 0–1: a white ring flashing round a piece just cut free.
  final Map<String, double> flash;

  /// The exacto cut under way, on the desk.
  final List<Offset>? stroke;

  /// Where the blade cuts, and the finger holding it, on screen.
  final Offset? knifeTip;
  final Offset? finger;

  /// The selected piece's rotate handle, on screen.
  final Offset? rotateHandle;

  /// The hologram on the desk. Pieces on its outer edge cast [shadowColor].
  final AsmrNet? blueprint;

  /// How far that shadow is offset, in screen pixels, down and a little right.
  final double shadowThrow;

  /// How soft that shadow is, in screen pixels.
  final double shadowSpread;

  /// The shadow's color, alpha included.
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kAsmrDeskColor);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final px = 1 / scale;
    final net = blueprint;
    final onEdge = <String>{
      if (net != null)
        for (final piece in pieces)
          if (onBlueprintEdge(piece, net)) piece.id,
    };
    for (final piece in pieces) {
      if (!onEdge.contains(piece.id)) {
        _paintPiece(canvas, piece, px, contactShadow: true);
      }
    }
    for (final piece in pieces) {
      if (!onEdge.contains(piece.id)) continue;
      _paintEdgeShadow(canvas, piece, px);
      _paintPiece(canvas, piece, px, contactShadow: false);
    }

    final cut = stroke;
    if (cut != null && cut.length >= 2) {
      final path = _polyline(cut);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * px
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _kGroove.withValues(alpha: 0.85),
      );
      canvas.save();
      canvas.translate(0.6 * px, 0.8 * px);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * px
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.45),
      );
      canvas.restore();
    }
    canvas.restore();

    final handle = rotateHandle;
    if (handle != null && selectedOutline > 0) {
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
      final arc = Rect.fromCircle(center: handle, radius: 6);
      canvas.drawArc(
        arc,
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

    final hand = finger;
    final tip = knifeTip;
    if (hand != null && tip != null && (hand - tip).distance > 1) {
      canvas.drawCircle(
        hand,
        22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.25),
      );
      canvas.drawLine(
        hand + (tip - hand) / (tip - hand).distance * 22,
        tip + (hand - tip) / (hand - tip).distance * 9,
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.25),
      );
    }
    if (tip != null) _crosshair(canvas, tip);
  }

  /// Down and a little to the right, the way the shadow is thrown.
  static const Offset _shadowDir = Offset(0.330, 0.944);

  void _paintEdgeShadow(Canvas canvas, AsmrPiece piece, double px) {
    if (shadowColor.a == 0) return;
    final throwPx = shadowThrow.clamp(0.0, 80.0);
    final spreadPx = shadowSpread.clamp(0.0, 80.0);
    canvas.save();
    canvas.translate(_shadowDir.dx * throwPx * px, _shadowDir.dy * throwPx * px);
    canvas.transform(piece.pose.storage);
    canvas.drawPath(
      piece.localPath,
      Paint()
        ..color = shadowColor
        ..maskFilter = spreadPx > 0.05
            ? MaskFilter.blur(BlurStyle.normal, spreadPx * px)
            : null,
    );
    canvas.restore();
  }

  void _paintPiece(
    Canvas canvas,
    AsmrPiece piece,
    double px, {
    required bool contactShadow,
  }) {
    final path = piece.localPath;
    if (piece.liberated && contactShadow) {
      canvas.save();
      canvas.translate(1.6 * px, 2.8 * px);
      canvas.transform(piece.pose.storage);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * px),
      );
      canvas.restore();
    }
    canvas.save();
    canvas.transform(piece.pose.storage);
    canvas.drawPath(path, tiles.paint(piece.paper));
    if (piece.scores.isNotEmpty) {
      canvas.save();
      canvas.clipPath(path);
      final groove = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 * px
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _kGroove.withValues(alpha: 0.6);
      for (final score in piece.scores) {
        canvas.drawPath(_polyline(score), groove);
      }
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = _kGroove.withValues(alpha: 0.45),
    );
    final ring = flash[piece.id] ?? 0;
    if (ring > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (2 + 5 * ring) * px
          ..color = Colors.white.withValues(alpha: 0.85 * ring)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (2 * ring + 0.5) * px,
          ),
      );
    }
    if (piece.id == selectedId && selectedOutline > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * px
          ..color = Colors.white.withValues(alpha: 0.95 * selectedOutline),
      );
    }
    canvas.restore();
  }

  void _crosshair(Canvas canvas, Offset at) {
    for (final (width, color) in [
      (3.2, Colors.black.withValues(alpha: 0.45)),
      (1.4, Colors.white),
    ]) {
      final paint = Paint()
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color;
      const gap = 3.0;
      const reach = 9.0;
      canvas.drawLine(at + const Offset(-reach, 0), at + const Offset(-gap, 0), paint);
      canvas.drawLine(at + const Offset(gap, 0), at + const Offset(reach, 0), paint);
      canvas.drawLine(at + const Offset(0, -reach), at + const Offset(0, -gap), paint);
      canvas.drawLine(at + const Offset(0, gap), at + const Offset(0, reach), paint);
    }
    canvas.drawCircle(at, 1.3, Paint()..color = const Color(0xFFFF5A5F));
  }

  static Path _polyline(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant AsmrDeskPainter old) => true;
}
