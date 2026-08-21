import 'package:flutter/material.dart';

import '../../gameplay/volumes/volume_door.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

const _kDoorOutline = Color(0xFF455A64);
const _kDoorStroke = 2.8;

/// Outer outline of each volume door (not per-subtile edges).
class VolumeDoorOverlay extends StatelessWidget {
  const VolumeDoorOverlay({
    super.key,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
  });

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
        painter: _DoorOutlinePainter(
          volumes: volumes,
          camera: camera,
          viewport: viewport,
          tileVisible: tileVisible,
        ),
      ),
    );
  }
}

class _DoorOutlinePainter extends CustomPainter {
  _DoorOutlinePainter({
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.tileVisible,
  });

  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kDoorOutline
      ..strokeWidth = _kDoorStroke
      ..strokeJoin = StrokeJoin.miter
      ..style = PaintingStyle.stroke;
    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        final visible = tileVisible;
        if (visible != null && !visible(cell.tx, cell.ty)) continue;
        for (final door in exteriorDoors(volume, cell)) {
          final corners = doorWorldCorners(
            grid: volumes.grid,
            tx: cell.tx,
            ty: cell.ty,
            box: cell.box,
            door: door,
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
          canvas.drawPath(Path()..addPolygon(pts, true), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DoorOutlinePainter oldDelegate) => true;
}
