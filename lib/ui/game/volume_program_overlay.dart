import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/picking/focus_sticker.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_program.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

/// Projects 6×6 program papers onto volume floors.
class VolumeProgramOverlay extends StatelessWidget {
  const VolumeProgramOverlay({
    super.key,
    required this.programs,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.volumeId,
    this.selectedId,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
    this.draftKind,
  });

  final VolumeProgramStore programs;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final int? volumeId;
  final int? selectedId;
  final bool selectedInvalid;
  final List<Vector3>? draftCorners;
  final bool draftInvalid;
  final VolumeProgramKind? draftKind;

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
        painter: _ProgramPainter(
          programs: programs,
          volumes: volumes,
          camera: camera,
          viewport: viewport,
          volumeId: volumeId,
          selectedId: selectedId,
          selectedInvalid: selectedInvalid,
          draftCorners: draftCorners,
          draftInvalid: draftInvalid,
          draftKind: draftKind,
        ),
      ),
    );
  }
}

class _ProgramPainter extends CustomPainter {
  _ProgramPainter({
    required this.programs,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.volumeId,
    this.selectedId,
    this.selectedInvalid = false,
    this.draftCorners,
    this.draftInvalid = false,
    this.draftKind,
  });

  final VolumeProgramStore programs;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final int? volumeId;
  final int? selectedId;
  final bool selectedInvalid;
  final List<Vector3>? draftCorners;
  final bool draftInvalid;
  final VolumeProgramKind? draftKind;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stamp in programs.stamps) {
      if (volumeId != null && stamp.volumeId != volumeId) continue;
      if (draftCorners != null && stamp.id == selectedId) continue;
      VolumeCell? cell;
      for (final volume in volumes.visibleVolumes) {
        if (volume.id != stamp.volumeId) continue;
        cell = volume.cellAt(stamp.tx, stamp.ty);
        break;
      }
      if (cell == null) continue;
      final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
      final s = volumes.grid.subtileSize;
      final x0 = min.x + stamp.originU * s;
      final z0 = min.z + stamp.originV * s;
      final y = min.y + 0.06;
      final corners = [
        Vector3(x0, y, z0),
        Vector3(x0, y, z0 + stamp.height * s),
        Vector3(x0 + stamp.width * s, y, z0 + stamp.height * s),
        Vector3(x0 + stamp.width * s, y, z0),
      ];
      final pts = <Offset>[];
      for (final c in corners) {
        final p = camera.projectToScreen(c, viewport);
        if (p == null) {
          pts.clear();
          break;
        }
        pts.add(p);
      }
      if (pts.length < 4) continue;
      final invalid = stamp.id == selectedId && selectedInvalid;
      final fill = invalid
          ? kFocusStickerInvalid.withValues(alpha: 0.72)
          : Color(stamp.kind.paperArgb);
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()..color = fill,
      );
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()
          ..color = const Color(0x33000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final cx = (pts[0].dx + pts[2].dx) * 0.5;
      final cy = (pts[0].dy + pts[2].dy) * 0.5;
      final icon = stamp.kind == VolumeProgramKind.bedroom
          ? Icons.bed_outlined
          : Icons.weekend_outlined;
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 16,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: const Color(0xFF6A6A6A),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(cx - painter.width * 0.5, cy - painter.height * 0.5),
      );
      if (stamp.id == selectedId) {
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = invalid ? kFocusStickerInvalid : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }
    final draft = draftCorners;
    if (draft != null && draft.length >= 4) {
      final pts = <Offset>[];
      for (final c in draft) {
        final p = camera.projectToScreen(c, viewport);
        if (p == null) {
          pts.clear();
          break;
        }
        pts.add(p);
      }
      if (pts.length >= 4) {
        final fill = draftInvalid
            ? kFocusStickerInvalid.withValues(alpha: 0.72)
            : Color((draftKind ?? VolumeProgramKind.bedroom).paperArgb)
                .withValues(alpha: 0.72);
        canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = fill);
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..color = draftInvalid ? kFocusStickerInvalid : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProgramPainter oldDelegate) => true;
}
