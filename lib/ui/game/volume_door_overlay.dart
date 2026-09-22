import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/outlines/applique_outline.dart';
import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/picking/focus_sticker.dart';
import '../../gameplay/viewers/world_plane.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_applique.dart';
import '../../gameplay/volumes/volume_door.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

const _kDoorStroke = 2.8;

/// Door appliques (path-colored paper) plus focus-view selection / drag preview.
class VolumeDoorOverlay extends StatelessWidget {
  const VolumeDoorOverlay({
    super.key,
    required this.volumes,
    required this.appliques,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
    this.faceHidden,
    this.interiorRevealed,
    this.selectedVolumeId,
    this.selectedTx,
    this.selectedTy,
    this.selectedSide,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
  });

  final VolumeStore volumes;
  final VolumeAppliqueStore appliques;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;
  final bool Function(int tx, int ty, VolumeFace face)? faceHidden;
  final bool Function(int tx, int ty)? interiorRevealed;
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
        painter: _DoorAppliquePainter(
          volumes: volumes,
          appliques: appliques,
          camera: camera,
          viewport: viewport,
          tileVisible: tileVisible,
          faceHidden: faceHidden,
          interiorRevealed: interiorRevealed,
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

class _DoorAppliquePainter extends CustomPainter {
  _DoorAppliquePainter({
    required this.volumes,
    required this.appliques,
    required this.camera,
    required this.viewport,
    this.tileVisible,
    this.faceHidden,
    this.interiorRevealed,
    this.selectedVolumeId,
    this.selectedTx,
    this.selectedTy,
    this.selectedSide,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
  });

  final VolumeStore volumes;
  final VolumeAppliqueStore appliques;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;
  final bool Function(int tx, int ty, VolumeFace face)? faceHidden;
  final bool Function(int tx, int ty)? interiorRevealed;
  final int? selectedVolumeId;
  final int? selectedTx;
  final int? selectedTy;
  final VolumeSide? selectedSide;
  final bool selectedInvalid;
  final List<Vector3>? draftCorners;
  final bool draftInvalid;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = List<VolumeApplique>.from(appliques.items)
      ..sort((a, b) {
        final layer = a.layer.compareTo(b.layer);
        if (layer != 0) return layer;
        return a.id.compareTo(b.id);
      });
    final papers = visibleAppliquePapers(
      appliques: ordered,
      volumes: volumes,
      camera: camera.position,
      tileVisible: tileVisible,
      faceHidden: faceHidden,
      interiorRevealed: interiorRevealed,
    );
    for (final paper in papers) {
      final piece = paper.piece;
      final selected = piece.kind == VolumeAppliqueKind.door &&
          piece.volumeId == selectedVolumeId &&
          piece.tx == selectedTx &&
          piece.ty == selectedTy &&
          piece.side == selectedSide;
      if (selected && draftCorners != null) continue;
      final pts = _project(paper.corners);
      if (pts == null) continue;
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()..color = piece.color,
      );
      if (selected) {
        if (selectedInvalid) {
          canvas.drawPath(
            Path()..addPolygon(pts, true),
            Paint()..color = kFocusStickerInvalid.withValues(alpha: 0.55),
          );
        }
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = selectedInvalid ? kFocusStickerInvalid : Colors.white
            ..strokeWidth = _kDoorStroke
            ..style = PaintingStyle.stroke,
        );
      }
    }
    _paintAppliqueOutlines(canvas);
    final draft = draftCorners;
    final draftFace = selectedSide?.volumeFace;
    if (draft != null &&
        (draftFace == null ||
            doorFacesCamera(
              face: draftFace,
              corners: draft,
              cameraPosition: camera.position,
            ))) {
      final pts = _project(draft);
      if (pts != null) {
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = (draftInvalid ? kFocusStickerInvalid : kDoorAppliqueColor)
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

  void _paintAppliqueOutlines(Canvas canvas) {
    if (appliques.items.isEmpty) return;
    final edges = buildAppliqueOutline(
      appliques: appliques.items,
      volumes: volumes,
      camera: camera.position,
      tileVisible: tileVisible,
      faceHidden: faceHidden,
      interiorRevealed: interiorRevealed,
    );
    if (edges.isEmpty) return;
    paintOutlineEdges(
      canvas: canvas,
      edges: edges,
      camera: camera,
      viewport: viewport,
      color: kAppliqueOutlineColor,
      strokeWidth: kAppliqueOutlineStrokeWidth,
    );
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
  bool shouldRepaint(covariant _DoorAppliquePainter oldDelegate) => true;
}
