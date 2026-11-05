import 'dart:convert';
import 'dart:ui';
import '../landscape/color_texture_catalog.dart';
import 'package:vector_math/vector_math_64.dart';
import '../geometry/geometry.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/planar_texture.dart';
import 'harvest.dart';
import 'models.dart';
import 'appearance.dart';
import 'layered_terrain.dart';
import 'geometry.dart' as planar;
import 'crumpled_paper.dart';

/// Like GameView's LandscapeGenerator/landscape painter, bake material into an
/// atlas and submit textured ground. Only changed slots rasterize again; camera,
/// hover and draft changes reuse the image. Polygons remain the harvest truth.
class HarvestMeshCache {
  static const renderVersion = 4;
  static const tilePixels = 128, gutter = 1, columns = 16;
  static const slotPixels = tilePixels + gutter * 2;
  final atlas = PlanarTextureAtlas();
  final Map<String, (String, Geometry, PlanarTexture)> _tiles = {};
  int rasterizedTiles = 0, crumpleBakes = 0;
  CrumpledPaperResources? _crumpleResources;
  FragmentShader? _crumpleShader;
  int _crumpleRevision = 0;
  double _foldStrength = 1, _foldScale = 1, _bakedShadow = 1;
  double _foldDensity = 1;
  FoldDistribution _foldDistribution = FoldDistribution.pockets;

  void setCrumpledPaper(CrumpledPaperResources? resources) {
    if (identical(resources, _crumpleResources)) return;
    _crumpleShader?.dispose();
    _crumpleResources = resources;
    _crumpleShader = resources?.program.fragmentShader();
    _crumpleShader?.setImageSampler(0, resources!.image);
    _crumpleRevision++;
  }

  void configureCrumple({
    required double strength,
    required double scale,
    required double shadow,
    double density = 1,
    FoldDistribution distribution = FoldDistribution.pockets,
  }) {
    if (_foldStrength == strength &&
        _foldScale == scale &&
        _bakedShadow == shadow &&
        _foldDensity == density &&
        _foldDistribution == distribution) {
      return;
    }
    _foldStrength = strength;
    _foldScale = scale;
    _bakedShadow = shadow;
    _foldDensity = density;
    _foldDistribution = distribution;
    _crumpleRevision++;
  }

  final Map<String, (TerrainSheet, Object, Mesh)> _walls = {};
  int rebuiltWalls = 0;
  Iterable<Mesh> walls(LayeredTerrain terrain) sync* {
    for (final sheet in terrain.sheets) {
      if (sheet.material == PaperMaterial.graphite) {
        for (final tile in terrain.tiles.values.where(
          (t) => identical(t.sheet, sheet),
        )) {
          final key = terrain.wallSignature(tile.id);
          final old = _walls[tile.id];
          if (old != null && identical(old.$1, sheet) && old.$2 == key) {
            if (old.$3.geometry.faces.isNotEmpty) yield old.$3;
            continue;
          }
          final vertices = <Vector3>[], faces = <List<int>>[];
          bool contains(Offset world) {
            final x = world.dx.floor(), y = world.dy.floor();
            final neighbor = TerrainTile(sheet, x, y);
            return terrain
                .remainingInTile(neighbor.id)
                .any(
                  (r) => r.contains(world - neighbor.origin, boundary: false),
                );
          }

          for (final region in terrain.remainingInTile(tile.id)) {
            for (final ring in region.rings) {
              for (var i = 0; i < ring.length; i++) {
                final a = ring[i] + tile.origin,
                    b = ring[(i + 1) % ring.length] + tile.origin;
                final delta = b - a;
                if (delta.distance < planar.geometryEpsilon) continue;
                final normal =
                    Offset(-delta.dy, delta.dx) / delta.distance * .00001;
                final mid = (a + b) / 2;
                final left = contains(mid + normal),
                    right = contains(mid - normal);
                if (left == right) continue; // internal slab or tile seam
                Vector3 point(Offset p, double z) => Vector3(p.dx, z, -p.dy);
                final points = [
                  point(a, sheet.elevation),
                  point(b, sheet.elevation),
                  point(b, sheet.elevation - sheet.thickness),
                  point(a, sheet.elevation - sheet.thickness),
                ];
                final start = vertices.length;
                vertices.addAll(left ? points.reversed : points);
                faces.add(List.generate(4, (i) => start + i));
              }
            }
          }
          final mesh = Mesh(
            id: 'terrain-wall-${tile.id}',
            name: 'Graphite edges',
            groundPlane: true,
            geometry: Geometry(
              id: 'terrain-wall-${tile.id}',
              name: 'Graphite edges',
              vertices: vertices,
              faces: faces,
            ),
            material: MaterialModel(
              color: sheet.material.base,
              doubleSided: false,
              strokeEdges: false,
            ),
          );
          _walls[tile.id] = (sheet, key, mesh);
          rebuiltWalls++;
          if (faces.isNotEmpty) yield mesh;
        }
        continue;
      }
      final old = _walls[sheet.id];
      if (old != null && identical(old.$1, sheet) && old.$2 == sheet.revision) {
        yield old.$3;
        continue;
      }
      final vertices = <Vector3>[], faces = <List<int>>[];
      void face(List<Vector3> points) {
        final start = vertices.length;
        vertices.addAll(points);
        faces.add(List.generate(points.length, (i) => start + i));
      }

      Vector3 point(Offset p, double height) => Vector3(p.dx, height, -p.dy);
      for (final r in sheet.remaining) {
        for (final originalRing in r.rings) {
          final signed = List.generate(
            originalRing.length,
            (i) =>
                originalRing[i].dx *
                    originalRing[(i + 1) % originalRing.length].dy -
                originalRing[(i + 1) % originalRing.length].dx *
                    originalRing[i].dy,
          ).fold<double>(0, (a, b) => a + b);
          final outer = identical(originalRing, r.outer);
          final ring = (outer == (signed > 0))
              ? originalRing
              : originalRing.reversed.toList();
          for (var i = 0; i < ring.length; i++) {
            final a = ring[i], b = ring[(i + 1) % ring.length];
            face(
              [
                point(a, sheet.elevation),
                point(b, sheet.elevation),
                point(b, sheet.elevation - sheet.thickness),
                point(a, sheet.elevation - sheet.thickness),
              ].reversed.toList(),
            );
          }
        }
        for (final triangle in r.triangles) {
          final points = triangle
              .map((p) => point(p, sheet.elevation - sheet.thickness))
              .toList();
          if ((points[1] - points[0]).cross(points[2] - points[0]).y > 0) {
            face(points.reversed.toList());
          } else {
            face(points);
          }
        }
      }
      final mesh = Mesh(
        id: 'terrain-wall-${sheet.id}',
        name: sheet.material.label,
        groundPlane: true,
        geometry: Geometry(
          id: 'terrain-wall-${sheet.id}',
          name: 'Sheet edges',
          vertices: vertices,
          faces: faces,
        ),
        material: MaterialModel(
          color: sheet.material.base,
          doubleSided: false,
          strokeEdges: false,
        ),
      );
      _walls[sheet.id] = (sheet, sheet.revision, mesh);
      rebuiltWalls++;
      yield mesh;
    }
  }

  String _styleKey = '';
  double _grainRepeat = ColorTextureCatalog.whiteRepeatWorld;
  void configureStyle({
    required SurfaceAppearance fill,
    required SurfaceAppearance grain,
    required double strength,
    required double repeat,
  }) {
    final key = jsonEncode([fill.toJson(), grain.toJson(), strength, repeat]);
    if (key == _styleKey) return;
    _styleKey = key;
    if (repeat != _grainRepeat) {
      final image = _paperImage;
      setPaperTexture(null);
      _grainRepeat = repeat;
      setPaperTexture(image);
    }
    _tiles.clear();
  }

  ImageShader? _paperGrain;
  Image? _paperImage;
  void setPaperTexture(Image? image) {
    if (identical(image, _paperImage)) return;
    _paperGrain?.dispose();
    _paperImage = image;
    _paperGrain = image == null
        ? null
        : ImageShader(
            image,
            TileMode.repeated,
            TileMode.repeated,
            (Matrix4.identity()
                  ..setEntry(0, 0, _grainRepeat / image.width)
                  ..setEntry(1, 1, _grainRepeat / image.height))
                .storage,
          );
    _tiles.clear();
  }

  void dispose() {
    _crumpleShader?.dispose();
    _crumpleShader = null;
    _crumpleResources = null;
    _paperGrain?.dispose();
    _paperGrain = null;
    _paperImage = null;
    atlas.dispose();
    _walls.clear();
    _tiles.clear();
  }

  void synchronize(Iterable<CraftPlane> planes, PaperLandscape landscape) {
    PictureRecorder? recorder;
    Canvas? canvas;
    final temporary = <Image>[];
    for (final plane in planes.where((p) => p.id.startsWith('ground-'))) {
      final naturalWhite =
          landscape.terrain.tiles[plane.id]?.sheet.material ==
          PaperMaterial.paperWhite;
      final crumpleKey = naturalWhite ? _crumpleRevision : 0;
      final key =
          '$renderVersion/$crumpleKey/${landscape.terrain.signature(plane.id)}/${PaperLandscape.generationVersion}/${landscape.seed}/${jsonEncode(plane.region.toJson())}/${plane.origin}/${plane.u}/${plane.v}';
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

      final visiblePaper = Path();
      void face(
        List<Offset> points,
        Color color,
        double depth, [
        PaperMaterial? material,
      ]) {
        final start = vertices.length;
        vertices.addAll(points.map((p) => plane.point(p, depth)));
        faces.add(List.generate(points.length, (i) => start + i));
        colors.add(color);
        final path = Path()..addPolygon(points, true);
        visiblePaper.addPath(path, Offset.zero);
        tileCanvas.drawPath(
          path,
          Paint()
            ..color = color
            ..isAntiAlias = false,
        );
      }

      // Retain exact fallback geometry for near-plane clipping and debug views.
      for (final patch in landscape.remaining(plane)) {
        face(patch.region.outer, patch.color.base, .001);
      }

      // Fold shading belongs to natural white-paper terrain, never its material
      // globally: placed sheets, graphite and cork keep their existing finish.
      if (naturalWhite &&
          _crumpleShader != null &&
          _foldStrength > 0 &&
          _foldDensity > 0) {
        final shader = _crumpleShader!;
        final base = PaperMaterial.paperWhite.base;
        // Stable phase per world; shared coordinates guarantee seam continuity.
        final phase = (landscape.seed & 1023) / 256.0;
        final uniforms = [
          plane.origin.x + phase,
          -plane.origin.z + phase,
          _foldScale,
          _foldStrength,
          _bakedShadow,
          base.r,
          base.g,
          base.b,
          _foldDensity,
          _foldDistribution.index.toDouble(),
        ];
        for (var i = 0; i < uniforms.length; i++) {
          shader.setFloat(i, uniforms[i]);
        }
        tileCanvas.save();
        tileCanvas.clipPath(visiblePaper, doAntiAlias: false);
        tileCanvas.drawRect(box, Paint()..shader = shader);
        tileCanvas.restore();
        crumpleBakes++;
      }
      final layerMaterial = landscape.terrain.tiles[plane.id]?.sheet.material;
      final grain = layerMaterial == PaperMaterial.graphite
          ? null
          : _paperGrain;
      final strength = (layerMaterial == PaperMaterial.cork ? .16 : .10);
      if (grain != null && strength > 0) {
        // World-aligned coordinates keep grain continuous across tile seams.
        final origin = Offset(plane.origin.x, -plane.origin.z);
        tileCanvas.save();
        tileCanvas.clipPath(visiblePaper, doAntiAlias: false);
        tileCanvas.translate(-origin.dx, -origin.dy);
        tileCanvas.drawRect(
          box.shift(origin),
          Paint()
            ..shader = grain
            ..blendMode = BlendMode.multiply
            ..color = Color.fromRGBO(255, 255, 255, strength),
        );
        tileCanvas.restore();
      }
      final picture = tileRecorder.endRecording();
      final image = picture.toImageSync(tilePixels, tilePixels);
      picture.dispose();
      temporary.add(image);
      rasterizedTiles++;
      final paint = Paint()
        ..blendMode = BlendMode.src
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
          depthSorted: true,
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
