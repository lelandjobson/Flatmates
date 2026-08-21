import 'package:flutter/material.dart';

import '../../gameplay/paint/face_paint_store.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

/// Projects painted volume-face subtles into screen space.
class VolumeFacePaintOverlay extends StatelessWidget {
  const VolumeFacePaintOverlay({
    super.key,
    required this.store,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
  });

  final FacePaintStore store;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;

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
        painter: _FacePaintPainter(
          store: store,
          volumes: volumes,
          camera: camera,
          viewport: viewport,
          tileVisible: tileVisible,
        ),
      ),
    );
  }
}

class _FacePaintPainter extends CustomPainter {
  _FacePaintPainter({
    required this.store,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.tileVisible,
  });

  final FacePaintStore store;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in store.canvases.entries) {
      final key = entry.key;
      final faceCanvas = entry.value;
      VolumeCell? cell;
      for (final volume in volumes.visibleVolumes) {
        if (volume.id != key.volumeId) continue;
        cell = volume.cellAt(key.tx, key.ty);
        break;
      }
      if (cell == null) continue;
      final visible = tileVisible;
      if (visible != null && !visible(key.tx, key.ty)) continue;

      for (var y = 0; y < faceCanvas.height; y++) {
        for (var x = 0; x < faceCanvas.width; x++) {
          final color = faceCanvas.colorAt(x, y);
          if (color == null) continue;
          final corners = FacePaintStore.pixelCorners(
            u: x,
            v: y,
            grid: volumes.grid,
            cell: cell,
            face: key.face,
          );
          final pts = <Offset>[];
          var ok = true;
          for (final c in corners) {
            final p = camera.projectToScreen(c, viewport);
            if (p == null) {
              ok = false;
              break;
            }
            pts.add(p);
          }
          if (!ok || pts.length < 3) continue;
          final path = Path()..addPolygon(pts, true);
          canvas.drawPath(path, Paint()..color = color.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FacePaintPainter oldDelegate) => true;
}
