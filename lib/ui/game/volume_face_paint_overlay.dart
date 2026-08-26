import 'package:flutter/material.dart';

import '../../gameplay/paint/face_paint_store.dart';
import '../../gameplay/paint/plane_grain_model.dart';
import '../../gameplay/paint/plane_shade_model.dart';
import '../../gameplay/viewers/world_plane.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import '../../theme/world_theme.dart';

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
    this.shade,
    this.grain,
    this.theme,
  });

  final FacePaintStore store;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;
  final PlaneShadeModel? shade;
  final PlaneGrainModel? grain;
  final WorldTheme? theme;

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
          shade: shade,
          grain: grain,
          theme: theme,
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
    this.shade,
    this.grain,
    this.theme,
  });

  final FacePaintStore store;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;
  final PlaneShadeModel? shade;
  final PlaneGrainModel? grain;
  final WorldTheme? theme;

  @override
  void paint(Canvas canvas, Size size) {
    final quads = <_PaintedQuad>[];
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

      final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
      final faceNormal = key.face.worldNormal;
      final origin = key.face.originAndNormal(min, max).$1;
      final toCamera = camera.position - origin;
      if (faceNormal.dot(toCamera) <= 1e-6) continue;

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
          var depth = 0.0;
          for (final c in corners) {
            final p = camera.projectToScreen(c, viewport);
            if (p == null) {
              ok = false;
              break;
            }
            pts.add(p);
            depth += (c - camera.position).length2;
          }
          if (!ok || pts.length < 3) continue;
          final shade = this.shade;
          final paper = theme?.paper(color) ?? color.color;
          var painted = shade == null
              ? paper
              : shade.apply(paper, faceNormal);
          final grain = this.grain;
          if (grain != null) {
            painted = grain.apply(
              painted,
              tx: key.tx,
              ty: key.ty,
              u: x,
              v: y,
              faceIndex: key.face.index,
            );
          }
          quads.add(
            _PaintedQuad(
              points: pts,
              color: painted,
              depth: depth / corners.length,
            ),
          );
        }
      }
    }
    quads.sort((a, b) => b.depth.compareTo(a.depth));
    for (final quad in quads) {
      canvas.drawPath(Path()..addPolygon(quad.points, true), Paint()..color = quad.color);
    }
  }

  @override
  bool shouldRepaint(covariant _FacePaintPainter oldDelegate) => true;
}

class _PaintedQuad {
  const _PaintedQuad({
    required this.points,
    required this.color,
    required this.depth,
  });

  final List<Offset> points;
  final Color color;
  final double depth;
}
