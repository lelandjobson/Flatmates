import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../gameplay/paint/face_applique_atlas.dart';
import '../../gameplay/paint/face_paint_store.dart';
import '../../gameplay/viewers/world_plane.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_solid.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';

/// One textured applique quad per baked face. Map 3d leaves this off.
class VolumeFacePaintOverlay extends StatelessWidget {
  const VolumeFacePaintOverlay({
    super.key,
    required this.atlas,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
  });

  final FaceAppliqueAtlas atlas;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  Widget build(BuildContext context) {
    final extra = this.listenable;
    final listenable =
        extra == null ? atlas : Listenable.merge([extra, atlas]);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => IgnorePointer(
        child: CustomPaint(
          size: viewport,
          painter: _FaceAppliquePainter(
            atlas: atlas,
            volumes: volumes,
            camera: camera,
            viewport: viewport,
            tileVisible: tileVisible,
          ),
        ),
      ),
    );
  }
}

class _FaceAppliquePainter extends CustomPainter {
  _FaceAppliquePainter({
    required this.atlas,
    required this.volumes,
    required this.camera,
    required this.viewport,
    this.tileVisible,
  });

  final FaceAppliqueAtlas atlas;
  final VolumeStore volumes;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    final quads = <_TexturedQuad>[];
    for (final slot in atlas.slots) {
      final key = slot.key.face;
      if (key == null) continue;
      Volume? owner;
      VolumeCell? cell;
      for (final volume in volumes.visibleVolumes) {
        if (volume.id != key.volumeId) continue;
        owner = volume;
        cell = volume.cellAt(key.tx, key.ty);
        break;
      }
      if (owner == null || cell == null) continue;
      final solid = resolveVolumeSolid(owner, volumes.grid);
      if (solid.isFaceFullyInternal(key.tx, key.ty, key.face)) continue;
      final visible = tileVisible;
      if (visible != null && !visible(key.tx, key.ty)) continue;

      final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
      final faceNormal = key.face.worldNormal;
      final origin = key.face.originAndNormal(min, max).$1;
      final toCamera = camera.position - origin;
      if (faceNormal.dot(toCamera) <= 1e-6) continue;

      final corners = FacePaintStore.faceCorners(
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
      if (!ok || pts.length < 4) continue;
      quads.add(
        _TexturedQuad(
          points: pts,
          image: slot.image,
          src: slot.rect,
          depth: depth / corners.length,
        ),
      );
    }
    quads.sort((a, b) => b.depth.compareTo(a.depth));
    for (final quad in quads) {
      _drawTexturedQuad(canvas, quad);
    }
  }

  void _drawTexturedQuad(Canvas canvas, _TexturedQuad quad) {
    final img = quad.image;
    final src = quad.src;
    final tw = src.width;
    final th = src.height;
    final t00 = Offset(src.left, src.top);
    final t10 = Offset(src.left + tw, src.top);
    final t11 = Offset(src.left + tw, src.top + th);
    final t01 = Offset(src.left, src.top + th);
    final p00 = quad.points[0];
    final p01 = quad.points[1];
    final p11 = quad.points[2];
    final p10 = quad.points[3];
    final paint = Paint()
      ..shader = ui.ImageShader(
        img,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      )
      ..filterQuality = FilterQuality.none;
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangles,
        [p00, p10, p11, p00, p11, p01],
        textureCoordinates: [t00, t10, t11, t00, t11, t01],
      ),
      BlendMode.srcOver,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceAppliquePainter oldDelegate) => true;
}

class _TexturedQuad {
  const _TexturedQuad({
    required this.points,
    required this.image,
    required this.src,
    required this.depth,
  });

  final List<Offset> points;
  final ui.Image image;
  final Rect src;
  final double depth;
}
