import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/picking/focus_sticker.dart';
import '../../gameplay/volumes/volume.dart';
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
    this.selectedVolumeId,
    this.selectedTx,
    this.selectedTy,
    this.selectedSide,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
  });

  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;
  final int? selectedVolumeId;
  final int? selectedTx;
  final int? selectedTy;
  final VolumeSide? selectedSide;
  final bool selectedInvalid;
  final List<Vector3>? draftCorners;
  final bool draftInvalid;

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
          selectedVolumeId: selectedVolumeId,
          selectedTx: selectedTx,
          selectedTy: selectedTy,
          selectedSide: selectedSide,
          selectedInvalid: selectedInvalid,
          draftCorners: draftCorners,
          draftInvalid: draftInvalid,
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
    this.selectedVolumeId,
    this.selectedTx,
    this.selectedTy,
    this.selectedSide,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
  });

  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;
  final int? selectedVolumeId;
  final int? selectedTx;
  final int? selectedTy;
  final VolumeSide? selectedSide;
  final bool selectedInvalid;
  final List<Vector3>? draftCorners;
  final bool draftInvalid;

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
          final pts = _project(doorWorldCorners(
            grid: volumes.grid,
            tx: cell.tx,
            ty: cell.ty,
            box: cell.box,
            door: door,
          ));
          if (pts == null) continue;
          final selected = volume.id == selectedVolumeId &&
              cell.tx == selectedTx &&
              cell.ty == selectedTy &&
              door.side == selectedSide;
          if (selected && draftCorners != null) continue;
          if (selected && selectedInvalid) {
            canvas.drawPath(
              Path()..addPolygon(pts, true),
              Paint()..color = kFocusStickerInvalid.withValues(alpha: 0.55),
            );
          }
          canvas.drawPath(
            Path()..addPolygon(pts, true),
            selected
                ? (Paint()
                  ..color = selectedInvalid ? kFocusStickerInvalid : Colors.white
                  ..strokeWidth = _kDoorStroke
                  ..style = PaintingStyle.stroke)
                : paint,
          );
        }
      }
    }
    final draft = draftCorners;
    if (draft != null) {
      final pts = _project(draft);
      if (pts != null) {
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = (draftInvalid ? kFocusStickerInvalid : const Color(0xFFF7F7F2))
                .withValues(alpha: 0.7),
        );
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = draftInvalid ? kFocusStickerInvalid : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kDoorStroke,
        );
      }
    }
  }

  List<Offset>? _project(List<Vector3> corners) {
    final pts = <Offset>[];
    for (final c in corners) {
      final p = camera.projectToScreen(c, viewport);
      if (p == null) return null;
      pts.add(p);
    }
    if (pts.length < 3) return null;
    return pts;
  }

  @override
  bool shouldRepaint(covariant _DoorOutlinePainter oldDelegate) => true;
}
