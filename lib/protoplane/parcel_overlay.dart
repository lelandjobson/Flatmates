import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../rendering/scene/camera.dart';
import 'parcels.dart';

/// Screen-projected lots share the terrain's world-space parcel grid.
class ParcelPainter extends CustomPainter {
  ParcelPainter({
    required this.parcels,
    required this.available,
    required this.camera,
    required this.shopping,
    required this.hovered,
    required Listenable repaint,
  }) : super(repaint: repaint);
  final WorldParcels parcels;
  final Set<ParcelId> available;
  final Camera camera;
  final bool shopping;
  final ParcelId? hovered;

  @override
  void paint(Canvas canvas, Size size) {
    if (!shopping) return;
    Offset? label;
    for (final id in available) {
      final bounds = parcels.bounds(id);
      final corners =
          [
                bounds.topLeft,
                bounds.topRight,
                bounds.bottomRight,
                bounds.bottomLeft,
              ]
              .map(
                (p) => camera.projectToScreen(Vector3(p.dx, .015, -p.dy), size),
              )
              .toList();
      if (corners.any((p) => p == null)) continue;
      final path = Path()..addPolygon(corners.cast<Offset>(), true);
      final owned = parcels.purchased.contains(id);
      final selected = id == hovered;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 1
          ..color = selected
              ? const Color(0xffffd477)
              : owned
              ? const Color(0x887be3ab)
              : const Color(0x668e9bb7),
      );
      if (selected) {
        label = camera.projectToScreen(
          Vector3(bounds.center.dx, .02, -bounds.center.dy),
          size,
        );
      }
    }
    if (label == null || hovered == null) return;
    final owned = parcels.purchased.contains(hovered);
    final text = TextPainter(
      text: TextSpan(
        text: owned ? 'Owned' : '\$${parcels.price}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 32);
    final x = (label.dx - text.width / 2).clamp(
      16.0,
      (size.width - text.width - 16).clamp(16.0, double.infinity),
    );
    final y = (label.dy - text.height - 20).clamp(
      16.0,
      (size.height - text.height - 16).clamp(16.0, double.infinity),
    );
    final rect = Rect.fromLTWH(
      x - 10,
      y - 7,
      text.width + 20,
      text.height + 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = const Color(0xee172033),
    );
    text.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant ParcelPainter oldDelegate) => true;
}
