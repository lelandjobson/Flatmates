import 'dart:convert';
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';
import '../geometry/geometry.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/planar_texture.dart';
import 'harvest.dart';
import 'geometry.dart';
import 'meshes.dart';
import 'models.dart';

/// Like GameView's LandscapeGenerator/landscape painter, bake material into an
/// atlas and submit textured ground. Only changed slots rasterize again; camera,
/// hover and draft changes reuse the image. Polygons remain the harvest truth.
class HarvestMeshCache {
  static const tilePixels = 256, gutter = 1, columns = 8;
  static const slotPixels = tilePixels + gutter * 2;
  final atlas = PlanarTextureAtlas();
  final Map<String, (String, Geometry, PlanarTexture)> _tiles = {};
  int rasterizedTiles = 0;

  void dispose() {
    atlas.dispose();
    _tiles.clear();
  }

  void synchronize(Iterable<CraftPlane> planes, PaperLandscape landscape) {
    PictureRecorder? recorder;
    Canvas? canvas;
    final temporary = <Image>[];
    for (final plane in planes.where((p) => p.id.startsWith('ground-'))) {
      final key =
          '${PaperLandscape.generationVersion}/${landscape.seed}/${jsonEncode(plane.region.toJson())}/${jsonEncode(landscape.depleted(plane.id).map((r) => r.toJson()).toList())}/${plane.origin}/${plane.u}/${plane.v}';
      final cached = _tiles[plane.id];
      if (cached != null && cached.$1 == key) continue;
      if (recorder == null) {
        recorder = PictureRecorder();
        canvas = Canvas(recorder);
        if (atlas.image != null) {
          canvas.drawImage(atlas.image!, Offset.zero, Paint());
        }
      }
      final index = cached == null
          ? _tiles.length
          : ((cached.$3.source.top - gutter) / slotPixels).round() * columns +
                ((cached.$3.source.left - gutter) / slotPixels).round();
      final left = (index % columns) * slotPixels.toDouble() + gutter;
      final top = (index ~/ columns) * slotPixels.toDouble() + gutter;
      final source = Rect.fromLTWH(
        left,
        top,
        tilePixels.toDouble(),
        tilePixels.toDouble(),
      );
      final vertices = <Vector3>[], faces = <List<int>>[], colors = <Color>[];
      final tileRecorder = PictureRecorder();
      final tileCanvas = Canvas(tileRecorder);
      final box = plane.region.bounds;
      tileCanvas.scale(tilePixels / box.width, tilePixels / box.height);
      tileCanvas.translate(-box.left, -box.top);
      // Fully opaque backing also overwrites any previous contents of the slot.
      tileCanvas.drawRect(box, Paint()..color = const Color(0xff777a72));
      void face(List<Offset> points, Color color, double depth) {
        final start = vertices.length;
        vertices.addAll(points.map((p) => plane.point(p, depth)));
        faces.add(List.generate(points.length, (i) => start + i));
        colors.add(color);
        tileCanvas.drawPath(
          Path()..addPolygon(points, true),
          Paint()
            ..color = color
            ..isAntiAlias = false,
        );
      }

      // Retain exact fallback geometry for near-plane clipping and debug views.
      final cuts = landscape.depleted(plane.id);
      if (cuts.isNotEmpty) {
        for (final cell in slabs([
          plane.region,
          ...cuts,
        ], (p) => plane.region.contains(p) && cuts.any((r) => r.contains(p)))) {
          face(cell, const Color(0xff777a72), 0);
        }
      }
      for (final patch in landscape.remaining(plane)) {
        final base = paperColors[patch.color]!;
        final tint = Color.lerp(
          base,
          patch.grain < 0 ? const Color(0xff384539) : const Color(0xfffffff0),
          patch.grain.abs(),
        )!;
        face(patch.region.outer, tint, .001);
      }
      final picture = tileRecorder.endRecording();
      final image = picture.toImageSync(tilePixels, tilePixels);
      picture.dispose();
      temporary.add(image);
      rasterizedTiles++;
      final paint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false;
      final full = Rect.fromLTWH(
        0,
        0,
        tilePixels.toDouble(),
        tilePixels.toDouble(),
      );
      canvas!.drawImageRect(image, full, source, paint);
      // Duplicate border texels into gutters, including corners, so bilinear
      // filtering cannot sample the neighboring slot at a ground-tile seam.
      for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
          if (x == 0 && y == 0) continue;
          final sx = x < 0
              ? 0.0
              : x > 0
              ? tilePixels - 1.0
              : 0.0;
          final sy = y < 0
              ? 0.0
              : y > 0
              ? tilePixels - 1.0
              : 0.0;
          final width = x == 0 ? tilePixels.toDouble() : 1.0;
          final height = y == 0 ? tilePixels.toDouble() : 1.0;
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(sx, sy, width, height),
            Rect.fromLTWH(
              x < 0
                  ? left - gutter
                  : x > 0
                  ? source.right
                  : left,
              y < 0
                  ? top - gutter
                  : y > 0
                  ? source.bottom
                  : top,
              x == 0 ? width : gutter.toDouble(),
              y == 0 ? height : gutter.toDouble(),
            ),
            paint,
          );
        }
      }
      _tiles[plane.id] = (
        key,
        Geometry(
          id: plane.id,
          name: 'Natural paper',
          vertices: vertices,
          faces: faces,
          faceColors: colors,
          colorSeed: 42,
        ),
        PlanarTexture(
          origin: plane.origin + plane.normal * .001,
          u: plane.u,
          v: plane.v,
          bounds: box,
          source: source,
          atlas: atlas,
        ),
      );
    }
    if (recorder != null) {
      final picture = recorder.endRecording();
      atlas.replace(
        picture.toImageSync(
          columns * slotPixels,
          ((_tiles.length + columns - 1) ~/ columns) * slotPixels,
        ),
      );
      picture.dispose();
      for (final image in temporary) {
        image.dispose();
      }
    }
  }

  Mesh mesh(CraftPlane plane, PaperLandscape landscape) {
    synchronize([plane], landscape);
    final cached = _tiles[plane.id]!;
    return Mesh(
      id: plane.id,
      name: 'Natural paper',
      groundPlane: true,
      geometry: cached.$2,
      planarTexture: cached.$3,
      material: MaterialModel(
        color: const Color(0xff777a72),
        perFaceColors: cached.$2.faceColors,
        exactPerFaceColors: true,
        doubleSided: true,
        strokeEdges: false,
      ),
    );
  }
}
