import 'package:flutter/material.dart';

import '../../geometry/prefabs/prefab_factory.dart';
import '../../user/friend_provider.dart';

/// Iso 45° corner thumbnail of a friend's face / body.
class FriendPortrait extends StatelessWidget {
  const FriendPortrait({
    super.key,
    required this.friend,
    this.size = 44,
    this.selected = false,
  });

  final Friend friend;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF141414),
          border: Border.all(
            color: selected
                ? Color.lerp(friend.color, Colors.white, 0.35)!
                : friend.color.withValues(alpha: 0.7),
            width: selected ? 2.2 : 1.2,
          ),
        ),
        child: ClipOval(
          child: CustomPaint(
            painter: _PortraitPainter(friend: friend),
          ),
        ),
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter({required this.friend});

  final Friend friend;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.58;
    final s = size.width * 0.28;
    final fill = Paint()..color = friend.color;
    final edge = Paint()
      ..color = Color.lerp(friend.color, Colors.black, 0.35)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    switch (friend.geometryType) {
      case GeometryPrefabs.cone:
        _cone(canvas, cx, cy, s, fill, edge);
      case GeometryPrefabs.frog:
        _frog(canvas, cx, cy, s, fill, edge);
      default:
        _cube(canvas, cx, cy, s, fill, edge);
    }
    _eyes(canvas, cx, cy - s * 0.15, s);
  }

  void _cube(
    Canvas canvas,
    double cx,
    double cy,
    double s,
    Paint fill,
    Paint edge,
  ) {
    final top = Offset(cx, cy - s * 0.85);
    final right = Offset(cx + s * 0.95, cy - s * 0.15);
    final bottom = Offset(cx, cy + s * 0.55);
    final left = Offset(cx - s * 0.95, cy - s * 0.15);
    final topR = Offset(cx + s * 0.95, cy - s * 0.85);
    final topL = Offset(cx - s * 0.95, cy - s * 0.85);
    // Approximate iso cube from the 45° corner.
    final topFace = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo((top.dx + right.dx) * 0.5, top.dy - s * 0.18)
      ..lineTo(right.dx, right.dy - s * 0.7)
      ..lineTo(cx, cy - s * 0.35)
      ..close();
    final rightFace = Path()
      ..moveTo(cx, cy - s * 0.35)
      ..lineTo(right.dx, right.dy - s * 0.7)
      ..lineTo(right.dx, bottom.dy - s * 0.15)
      ..lineTo(bottom.dx, bottom.dy)
      ..close();
    final leftFace = Path()
      ..moveTo(cx, cy - s * 0.35)
      ..lineTo(left.dx, left.dy - s * 0.7)
      ..lineTo(left.dx, bottom.dy - s * 0.15)
      ..lineTo(bottom.dx, bottom.dy)
      ..close();
    canvas.drawPath(leftFace, fill);
    canvas.drawPath(
      rightFace,
      Paint()..color = Color.lerp(friend.color, Colors.black, 0.18)!,
    );
    canvas.drawPath(
      topFace,
      Paint()..color = Color.lerp(friend.color, Colors.white, 0.22)!,
    );
    canvas.drawPath(leftFace, edge);
    canvas.drawPath(rightFace, edge);
    canvas.drawPath(topFace, edge);
    canvas.drawLine(topL, left, edge);
    canvas.drawLine(topR, right, edge);
  }

  void _cone(
    Canvas canvas,
    double cx,
    double cy,
    double s,
    Paint fill,
    Paint edge,
  ) {
    final path = Path()
      ..moveTo(cx, cy - s * 1.05)
      ..lineTo(cx + s * 0.85, cy + s * 0.45)
      ..lineTo(cx - s * 0.85, cy + s * 0.45)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, edge);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + s * 0.45),
        width: s * 1.7,
        height: s * 0.45,
      ),
      Paint()..color = Color.lerp(friend.color, Colors.black, 0.2)!,
    );
  }

  void _frog(
    Canvas canvas,
    double cx,
    double cy,
    double s,
    Paint fill,
    Paint edge,
  ) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 2.1, height: s * 1.7),
      fill,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: s * 2.1, height: s * 1.7),
      edge,
    );
    canvas.drawCircle(Offset(cx - s * 0.55, cy - s * 0.55), s * 0.32, fill);
    canvas.drawCircle(Offset(cx + s * 0.55, cy - s * 0.55), s * 0.32, fill);
  }

  void _eyes(Canvas canvas, double cx, double cy, double s) {
    final white = Paint()..color = Colors.white;
    final gap = s * 0.42;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - gap, cy),
        width: s * 0.38,
        height: s * 0.46,
      ),
      white,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + gap, cy),
        width: s * 0.38,
        height: s * 0.46,
      ),
      white,
    );
  }

  @override
  bool shouldRepaint(covariant _PortraitPainter oldDelegate) =>
      oldDelegate.friend != friend;
}
