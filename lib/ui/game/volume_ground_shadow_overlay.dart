import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../gameplay/paint/ground_shadow_model.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

/// Batched ground-plane shadows for volume AABBs. One path, one blur.
class VolumeGroundShadowOverlay extends StatelessWidget {
  const VolumeGroundShadowOverlay({
    super.key,
    required this.volumes,
    required this.camera,
    required this.viewport,
    required this.model,
    this.listenable,
    this.tileVisible,
  });

  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final GroundShadowModel model;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  Widget build(BuildContext context) {
    if (model.mode == GroundShadowMode.off) {
      return const SizedBox.shrink();
    }
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
        painter: _GroundShadowPainter(
          volumes: volumes,
          camera: camera,
          viewport: viewport,
          model: model,
          tileVisible: tileVisible,
        ),
      ),
    );
  }
}

class _GroundShadowPainter extends CustomPainter {
  _GroundShadowPainter({
    required this.volumes,
    required this.camera,
    required this.viewport,
    required this.model,
    this.tileVisible,
  });

  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final GroundShadowModel model;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    final path = Path();
    var added = false;
    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        final visible = tileVisible;
        if (visible != null && !visible(cell.tx, cell.ty)) continue;
        final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
        final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
        final world = model.polygon(min, max);
        if (world.length < 3) continue;
        final screen = <Offset>[];
        var ok = true;
        for (final p in world) {
          final s = camera.projectToScreen(p, viewport);
          if (s == null) {
            ok = false;
            break;
          }
          screen.add(s);
        }
        if (!ok || screen.length < 3) continue;
        path.addPolygon(screen, true);
        added = true;
      }
    }
    if (!added) return;

    final paint = Paint()
      ..color = model.color.withValues(
        alpha: (model.color.a * model.opacity.clamp(0.0, 1.0)).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.fill;
    final sigma = model.blurSigma;
    if (sigma > 0.05) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GroundShadowPainter oldDelegate) => true;
}
