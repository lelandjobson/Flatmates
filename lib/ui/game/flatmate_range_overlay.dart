import 'package:flutter/material.dart';

import '../../gameplay/flatmates/flatmate_range.dart';
import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';

const kFlatmateRangeOutsideDim = Color(0x99050810);

/// Dash-dotted Chebyshev range square around a bedroom home tile.
class FlatmateRangeOverlay extends StatelessWidget {
  const FlatmateRangeOverlay({
    super.key,
    required this.home,
    required this.color,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.listenable,
  });

  final (int, int) home;
  final Color color;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _RangePainter(
          home: home,
          color: color,
          grid: grid,
          camera: camera,
          viewport: viewport,
        ),
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter({
    required this.home,
    required this.color,
    required this.grid,
    required this.camera,
    required this.viewport,
  });

  final (int, int) home;
  final Color color;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;

  static const _lift = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = flatmateRangeWorldCorners(
      home,
      tileSize: grid.tileSize,
      y: _lift,
    );
    final pts = [
      for (final corner in corners)
        camera.projectToScreen(corner, viewport),
    ];
    final quad = [
      for (final pt in pts)
        if (pt != null) pt,
    ];
    final dim = flatmateRangeOutsidePath(viewport: size, quad: quad);
    if (dim != null) {
      canvas.drawPath(
        dim,
        Paint()
          ..color = kFlatmateRangeOutsideDim
          ..style = PaintingStyle.fill,
      );
    }
    final stroke = Paint()
      ..color = Color.lerp(color, const Color(0xFFF4F4F4), 0.4)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      if (a == null || b == null) continue;
      paintDashedLine(
        canvas,
        a,
        b,
        stroke,
        dashLength: 10,
        gapLength: 5,
        dashDot: true,
        dotLength: 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RangePainter oldDelegate) => true;
}