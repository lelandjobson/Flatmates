import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../debug/scene_paint_stats.dart';
import '../gameplay/paint/plane_shade_model.dart';
import '../gameplay/spawns/basement_spawn_mesh.dart';
import '../rendering/ground_occlusion.dart';
import '../rendering/scene/camera.dart';

/// True when triangle [a],[b],[c] (CCW) faces [cameraPosition].
///
/// Cut walls use this so only the hole-facing side is drawn; the map plane
/// is painted afterward and covers any remaining underground fragments.
bool landscapeCutWallFacesCamera(
  Vector3 a,
  Vector3 b,
  Vector3 c,
  Vector3 cameraPosition,
) {
  final normal = (b - a).cross(c - a);
  if (normal.length2 < 1e-16) return false;
  return normal.dot(cameraPosition - a) > 1e-8;
}

/// Drops collapsed corners so a slope-to-flat wall still has a triangle.
List<Vector3> landscapeCleanWallVerts(List<Vector3> verts) {
  final out = <Vector3>[];
  for (final p in verts) {
    if (out.isEmpty || out.last.distanceToSquared(p) > 1e-12) {
      out.add(p);
    }
  }
  if (out.length >= 2 && out.first.distanceToSquared(out.last) <= 1e-12) {
    out.removeLast();
  }
  return out;
}

bool landscapeCutWallVisible(List<Vector3> verts, Vector3 cameraPosition) {
  if (verts.length < 3) return false;
  for (var i = 1; i < verts.length - 1; i++) {
    if (landscapeCutWallFacesCamera(
      verts[0],
      verts[i],
      verts[i + 1],
      cameraPosition,
    )) {
      return true;
    }
  }
  return false;
}

/// Atlas modulate tint from [shade] for triangle [a]→[b]→[c].
///
/// [lift] mixes back toward white (0 = full shade, 1 = unlit ground).
Color landscapeFaceShadeColor(
  PlaneShadeModel? shade,
  Vector3 a,
  Vector3 b,
  Vector3 c, {
  double lift = 0,
}) {
  if (shade == null) return const Color(0xFFFFFFFF);
  final normal = (b - a).cross(c - a);
  if (normal.length2 < 1e-16) return const Color(0xFFFFFFFF);
  final shaded = shade.apply(const Color(0xFFFFFFFF), normal);
  if (lift <= 1e-6) return shaded;
  return Color.lerp(shaded, const Color(0xFFFFFFFF), lift.clamp(0.0, 1.0))!;
}

/// How much sloped ground is lifted toward unlit atlas (walls stay fully shaded).
const kLandscapeSlopeShadeLift = 0.55;

/// World X sampled on a vertical cut wall. Top ([y] = 0) is the ground seam;
/// going down steps into the neighboring tile, opposite the inward normal.
double landscapeCutWallSampleX(double seamX, double y, double inwardX) =>
    seamX + inwardX * y;

/// Draws a landscape atlas as a textured ground plane (XZ, Y=0) through [camera].
///
/// Uses a tessellated mesh so Flutter's affine UV interpolation does not create
/// the classic perspective "swim" / bow-tie warping of a single 4-vertex quad.
class LandscapePlanePainter extends CustomPainter {
  LandscapePlanePainter({
    required this.camera,
    required this.listenable,
    required this.image,
    required this.worldSize,
    required this.tilesSide,
    required this.pixelsPerTile,
    this.hoverWx,
    this.hoverWy,
    this.hoverBrushSize = 1,
    this.visibleTiles,
    this.omitTiles,
    this.omitFloorY,
    this.slopeTiles,
    this.cutDoor,
    this.clipMinX,
    this.clipMaxX,
    this.clipMinZ,
    this.clipMaxZ,
    this.hideGround = false,
    this.backgroundColor = const Color(0xFF101418),
    this.modulateColor,
    this.shade,
    this.paperTexture,
    this.paperRepeatWorld = 2.0,
  }) : super(repaint: listenable);

  final Camera camera;
  final Listenable listenable;
  final ui.Image? image;
  final double worldSize;
  final int tilesSide;
  final int pixelsPerTile;
  final int? hoverWx;
  final int? hoverWy;
  final int hoverBrushSize;

  /// When set, only these tiles (and their grid lines) are drawn.
  final Set<(int, int)>? visibleTiles;

  /// Tiles punched out of the ground plane (basement cut, etc.).
  final Set<(int, int)>? omitTiles;

  /// World Y of the punched floor at world Z. When set, omit tiles get
  /// atlas-textured side walls down to this height.
  final double Function(double worldZ)? omitFloorY;

  /// Tiles drawn as a sloped atlas surface at [omitFloorY] (basement ramp).
  final Set<(int, int)>? slopeTiles;

  /// Volume-colored facade with an open 2×4 door on the hole / bridge seam.
  final BasementCutDoorWall? cutDoor;

  /// Optional world-space XZ crop. Quads are clipped to this rectangle.
  final double? clipMinX;
  final double? clipMaxX;
  final double? clipMinZ;
  final double? clipMaxZ;

  /// When true, the ground plane is omitted (crop floor is above Y=0).
  final bool hideGround;

  final Color backgroundColor;

  /// Optional multiply tint (day → night). Applied on the textured draw so
  /// Impeller does not need a [ColorFiltered] saveLayer around the plane.
  final Color? modulateColor;

  /// Sun / face lighting for sloped ground and cut walls.
  final PlaneShadeModel? shade;

  /// World-locked repeating paper grain. Multiplied over the color atlas.
  final ui.Image? paperTexture;

  /// World units per one repeat of [paperTexture].
  final double paperRepeatWorld;

  static ui.Image? _atlasImage;
  static ui.ImageShader? _atlasShader;
  static ui.Image? _paperImage;
  static ui.ImageShader? _paperShader;

  static final Paint _imagePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static final Paint _paperPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium
    ..blendMode = BlendMode.multiply;

  static final Paint _bgPaint = Paint();

  static final Paint _gridPaint = Paint()
    ..color = const Color(0x338A8078)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _borderPaint = Paint()
    ..color = const Color(0x668A8078)
    ..strokeWidth = 1.25
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _hoverPaint = Paint()
    ..color = const Color(0xAA6B6358)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  ColorFilter? get _modulateFilter {
    final color = modulateColor;
    if (color == null || color == const Color(0xFFFFFFFF)) return null;
    return ColorFilter.mode(color, BlendMode.modulate);
  }

  static ui.ImageShader _shaderFor(ui.Image img) {
    final cached = _atlasShader;
    if (identical(_atlasImage, img) && cached != null) return cached;
    cached?.dispose();
    _atlasImage = img;
    return _atlasShader = ui.ImageShader(
      img,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    );
  }

  static ui.ImageShader _paperShaderFor(ui.Image img) {
    final cached = _paperShader;
    if (identical(_paperImage, img) && cached != null) return cached;
    cached?.dispose();
    _paperImage = img;
    return _paperShader = ui.ImageShader(
      img,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sw = Stopwatch()..start();
    Timeline.startSync('LandscapePlane');
    final filter = _modulateFilter;
    _bgPaint.colorFilter = filter;
    _imagePaint.colorFilter = filter;
    _paperPaint.colorFilter = filter;
    _gridPaint.colorFilter = filter;
    _borderPaint.colorFilter = filter;
    _hoverPaint.colorFilter = filter;
    try {
      canvas.drawRect(Offset.zero & size, _bgPaint..color = backgroundColor);

      final img = image;
      if (img == null || worldSize <= 0) return;

      final aspect = size.width / size.height;
      final mvp = camera.projectionMatrix(aspect) * camera.viewMatrix;
      final half = worldSize * 0.5;

      // Walls first so the ground plane covers faces that sit under the map.
      _drawOmitWalls(canvas, mvp, size, half, img);
      _drawSlopedTiles(canvas, mvp, size, half, img);
      final drawn = _tilesToDraw;
      if (drawn != null) {
        _drawVisibleTiles(canvas, mvp, size, half, img, drawn);
      } else {
        _drawTessellatedPlane(canvas, mvp, size, half, img);
      }
      _drawTileGrid(canvas, mvp, size, half);
      if (!hideGround) _drawHoverPixel(canvas, mvp, size, half);
    } finally {
      _bgPaint.colorFilter = null;
      _imagePaint.colorFilter = null;
      _imagePaint.shader = null;
      _paperPaint.colorFilter = null;
      _paperPaint.shader = null;
      _gridPaint.colorFilter = null;
      _borderPaint.colorFilter = null;
      _hoverPaint.colorFilter = null;
      Timeline.finishSync();
      PaintStatsProbe.landscape = ScenePaintStats(
        source: 'landscape',
        paintMs: sw.elapsedMicroseconds / 1000.0,
      );
    }
  }

  void _drawHoverPixel(Canvas canvas, Matrix4 mvp, Size size, double half) {
    final hx = hoverWx;
    final hy = hoverWy;
    if (hx == null || hy == null) return;
    final side = tilesSide * pixelsPerTile;
    if (hx < 0 || hy < 0 || hx >= side || hy >= side) return;

    final brush = hoverBrushSize.clamp(1, 25);
    final originX = hx - brush ~/ 2;
    final originY = hy - brush ~/ 2;
    final x0 = -half + originX;
    final z0 = -half + originY;
    final x1 = x0 + brush;
    final z1 = z0 + brush;
    final corners = <Vector3>[
      Vector3(x0, 0, z0),
      Vector3(x1, 0, z0),
      Vector3(x1, 0, z1),
      Vector3(x0, 0, z1),
    ];
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = _projectToScreen(corners[i], mvp, size);
      if (p == null) return;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _hoverPaint);
  }

  Set<(int, int)>? get _tilesToDraw {
    final omit = omitTiles;
    final visible = visibleTiles;
    if (visible != null) {
      if (omit == null || omit.isEmpty) return visible;
      return visible.difference(omit);
    }
    if (omit == null || omit.isEmpty) return null;
    final origin = -(tilesSide ~/ 2);
    return {
      for (var ty = origin; ty < origin + tilesSide; ty++)
        for (var tx = origin; tx < origin + tilesSide; tx++)
          if (!omit.contains((tx, ty))) (tx, ty),
    };
  }

  void _drawTessellatedPlane(
    Canvas canvas,
    Matrix4 mvp,
    Size size,
    double half,
    ui.Image img,
  ) {
    if (hideGround) return;
    final visible = visibleTiles;
    if (visible != null) {
      _drawVisibleTiles(canvas, mvp, size, half, img, visible);
      return;
    }
    // Enough subdivisions to keep affine UV error invisible while orbiting.
    // Prefer at least 2 segments per tile, capped for performance.
    final segments = math.max(tilesSide * 2, 24).clamp(1, 64);

    final tw = img.width.toDouble();
    final th = img.height.toDouble();
    final paper = paperTexture;
    final paperW = paper?.width.toDouble() ?? 0;
    final paperH = paper?.height.toDouble() ?? 0;
    final positions = <Offset>[];
    final texCoords = <Offset>[];
    final paperCoords = paper == null ? null : <Offset>[];

    Offset? project(double x, double z) =>
        _projectToScreen(Vector3(x, 0, z), mvp, size);

    for (var jz = 0; jz < segments; jz++) {
      final v0 = jz / segments;
      final v1 = (jz + 1) / segments;
      final z0 = -half + v0 * worldSize;
      final z1 = -half + v1 * worldSize;

      for (var ix = 0; ix < segments; ix++) {
        final u0 = ix / segments;
        final u1 = (ix + 1) / segments;
        final x0 = -half + u0 * worldSize;
        final x1 = -half + u1 * worldSize;

        final p00 = project(x0, z0);
        final p10 = project(x1, z0);
        final p11 = project(x1, z1);
        final p01 = project(x0, z1);
        if (p00 == null || p10 == null || p11 == null || p01 == null) {
          continue;
        }

        final t00 = Offset(u0 * tw, v0 * th);
        final t10 = Offset(u1 * tw, v0 * th);
        final t11 = Offset(u1 * tw, v1 * th);
        final t01 = Offset(u0 * tw, v1 * th);

        // Two triangles: (00,10,11) and (00,11,01)
        positions
          ..add(p00)
          ..add(p10)
          ..add(p11)
          ..add(p00)
          ..add(p11)
          ..add(p01);
        texCoords
          ..add(t00)
          ..add(t10)
          ..add(t11)
          ..add(t00)
          ..add(t11)
          ..add(t01);
        _appendPaperCoords(paperCoords, paperW, paperH, half, x0, x1, z0, z1);
      }
    }

    _drawAtlasAndPaper(canvas, img, positions, texCoords, paperCoords);
  }

  void _drawVisibleTiles(
    Canvas canvas,
    Matrix4 mvp,
    Size size,
    double half,
    ui.Image img,
    Set<(int, int)> visible,
  ) {
    if (visible.isEmpty) return;
    final tileWorld = worldSize / tilesSide;
    final tw = img.width.toDouble();
    final th = img.height.toDouble();
    final paper = paperTexture;
    final paperW = paper?.width.toDouble() ?? 0;
    final paperH = paper?.height.toDouble() ?? 0;
    const segs = 4;
    final positions = <Offset>[];
    final texCoords = <Offset>[];
    final paperCoords = paper == null ? null : <Offset>[];
    final cMinX = clipMinX;
    final cMaxX = clipMaxX;
    final cMinZ = clipMinZ;
    final cMaxZ = clipMaxZ;

    Offset? project(double x, double z) =>
        _projectToScreen(Vector3(x, 0, z), mvp, size);

    final origin = -(tilesSide ~/ 2);
    final last = origin + tilesSide - 1;
    for (final (tx, ty) in visible) {
      if (tx < origin || ty < origin || tx > last || ty > last) continue;
      var x0 = tx * tileWorld;
      var z0 = ty * tileWorld;
      var x1 = x0 + tileWorld;
      var z1 = z0 + tileWorld;
      if (cMinX != null) x0 = math.max(x0, cMinX);
      if (cMaxX != null) x1 = math.min(x1, cMaxX);
      if (cMinZ != null) z0 = math.max(z0, cMinZ);
      if (cMaxZ != null) z1 = math.min(z1, cMaxZ);
      if (x1 - x0 < 1e-6 || z1 - z0 < 1e-6) continue;
      final u0 = (x0 + half) / worldSize;
      final v0 = (z0 + half) / worldSize;
      final u1 = (x1 + half) / worldSize;
      final v1 = (z1 + half) / worldSize;
      for (var jz = 0; jz < segs; jz++) {
        final fv0 = jz / segs;
        final fv1 = (jz + 1) / segs;
        for (var ix = 0; ix < segs; ix++) {
          final fu0 = ix / segs;
          final fu1 = (ix + 1) / segs;
          final px0 = x0 + fu0 * (x1 - x0);
          final px1 = x0 + fu1 * (x1 - x0);
          final pz0 = z0 + fv0 * (z1 - z0);
          final pz1 = z0 + fv1 * (z1 - z0);
          final p00 = project(px0, pz0);
          final p10 = project(px1, pz0);
          final p11 = project(px1, pz1);
          final p01 = project(px0, pz1);
          if (p00 == null || p10 == null || p11 == null || p01 == null) {
            continue;
          }
          final t00 = Offset(
            (u0 + fu0 * (u1 - u0)) * tw,
            (v0 + fv0 * (v1 - v0)) * th,
          );
          final t10 = Offset(
            (u0 + fu1 * (u1 - u0)) * tw,
            (v0 + fv0 * (v1 - v0)) * th,
          );
          final t11 = Offset(
            (u0 + fu1 * (u1 - u0)) * tw,
            (v0 + fv1 * (v1 - v0)) * th,
          );
          final t01 = Offset(
            (u0 + fu0 * (u1 - u0)) * tw,
            (v0 + fv1 * (v1 - v0)) * th,
          );
          positions
            ..add(p00)
            ..add(p10)
            ..add(p11)
            ..add(p00)
            ..add(p11)
            ..add(p01);
          texCoords
            ..add(t00)
            ..add(t10)
            ..add(t11)
            ..add(t00)
            ..add(t11)
            ..add(t01);
          _appendPaperCoords(
            paperCoords,
            paperW,
            paperH,
            half,
            px0,
            px1,
            pz0,
            pz1,
          );
        }
      }
    }
    _drawAtlasAndPaper(canvas, img, positions, texCoords, paperCoords);
  }

  void _drawOmitWalls(
    Canvas canvas,
    Matrix4 mvp,
    Size size,
    double half,
    ui.Image img,
  ) {
    final omit = omitTiles;
    final floorYOf = omitFloorY;
    if (omit == null || omit.isEmpty || floorYOf == null || hideGround) return;
    final span = (slopeTiles == null || slopeTiles!.isEmpty) ? omit : slopeTiles!;
    final wallTiles =
        visibleTiles == null ? span : span.intersection(visibleTiles!);
    if (wallTiles.isEmpty) return;

    final tileWorld = worldSize / tilesSide;
    final hole = omit;
    final occlusion = GroundOcclusion(
      holeTiles: hole,
      tileSize: tileWorld,
    );
    final tw = img.width.toDouble();
    final th = img.height.toDouble();
    final paper = paperTexture;
    final paperW = paper?.width.toDouble() ?? 0;
    final paperH = paper?.height.toDouble() ?? 0;
    const segs = 4;
    final positions = <Offset>[];
    final texCoords = <Offset>[];
    final paperCoords = paper == null ? null : <Offset>[];
    final colors = shade == null ? null : <Color>[];

    Offset atlasUv(double sampleX, double z) => Offset(
          (sampleX + half) / worldSize * tw,
          (z + half) / worldSize * th,
        );

    void addTri(
      List<Vector3> poly,
      List<Offset> uvs,
      Color tint, [
      List<Offset>? grains,
    ]) {
      if (poly.length < 3) return;
      for (var i = 1; i < poly.length - 1; i++) {
        final p0 = _projectToScreen(poly[0], mvp, size);
        final p1 = _projectToScreen(poly[i], mvp, size);
        final p2 = _projectToScreen(poly[i + 1], mvp, size);
        if (p0 == null || p1 == null || p2 == null) continue;
        positions
          ..add(p0)
          ..add(p1)
          ..add(p2);
        texCoords
          ..add(uvs[0])
          ..add(uvs[i])
          ..add(uvs[i + 1]);
        if (paperCoords != null) {
          if (grains != null) {
            paperCoords
              ..add(grains[0])
              ..add(grains[i])
              ..add(grains[i + 1]);
          } else {
            paperCoords
              ..add(_paperUv(poly[0].x, poly[0].z, half, paperW, paperH))
              ..add(_paperUv(poly[i].x, poly[i].z, half, paperW, paperH))
              ..add(_paperUv(poly[i + 1].x, poly[i + 1].z, half, paperW, paperH));
          }
        }
        colors
          ?..add(tint)
          ..add(tint)
          ..add(tint);
      }
    }

    final cam = camera.position;

    void addWallQuad({
      required Vector3 a,
      required Vector3 b,
      required Vector3 c,
      required Vector3 d,
      required double seam,
      required double inward,
      required bool unfoldX,
      required bool clip,
    }) {
      var verts = landscapeCleanWallVerts([a, b, c, d]);
      if (!landscapeCutWallVisible(verts, cam)) return;
      if (clip) {
        verts = landscapeCleanWallVerts(
          clipFaceToVisible(camera, verts, occlusion),
        );
        if (verts.length < 3) return;
      }
      final uvs = <Offset>[];
      final grains = paper == null ? null : <Offset>[];
      for (final p in verts) {
        final sampleX = unfoldX
            ? landscapeCutWallSampleX(seam, p.y, inward)
            : p.x;
        final sampleZ = unfoldX
            ? p.z
            : landscapeCutWallSampleX(seam, p.y, inward);
        uvs.add(atlasUv(sampleX, sampleZ));
        grains?.add(_paperUv(sampleX, sampleZ, half, paperW, paperH));
      }
      addTri(
        verts,
        uvs,
        landscapeFaceShadeColor(shade, verts[0], verts[1], verts[2]),
        grains,
      );
    }

    for (final (tx, ty) in wallTiles) {
      final x0 = tx * tileWorld;
      final z0 = ty * tileWorld;
      final x1 = x0 + tileWorld;
      final z1 = z0 + tileWorld;
      final clip = !hole.contains((tx, ty));

      for (var i = 0; i < segs; i++) {
        final t0 = i / segs;
        final t1 = (i + 1) / segs;
        final za = z0 + t0 * (z1 - z0);
        final zb = z0 + t1 * (z1 - z0);
        final ya = floorYOf(za);
        final yb = floorYOf(zb);
        if (ya >= -1e-6 && yb >= -1e-6) continue;
        // West face: inward +X. Texture walks −X into the (−1, ty) tile.
        if (!span.contains((tx - 1, ty))) {
          addWallQuad(
            a: Vector3(x0, 0, za),
            b: Vector3(x0, 0, zb),
            c: Vector3(x0, yb, zb),
            d: Vector3(x0, ya, za),
            seam: x0,
            inward: 1,
            unfoldX: true,
            clip: clip,
          );
        }
        // East face: inward −X. Texture walks +X into the (1, ty) tile.
        if (!span.contains((tx + 1, ty))) {
          addWallQuad(
            a: Vector3(x1, 0, za),
            b: Vector3(x1, ya, za),
            c: Vector3(x1, yb, zb),
            d: Vector3(x1, 0, zb),
            seam: x1,
            inward: -1,
            unfoldX: true,
            clip: clip,
          );
        }
      }

      // Cap only at the far end of the span, not at the hole / bridge join.
      if (!span.contains((tx, ty - 1))) {
        final yN0 = floorYOf(z0);
        if (yN0 < -1e-6) {
          addWallQuad(
            a: Vector3(x0, 0, z0),
            b: Vector3(x0, yN0, z0),
            c: Vector3(x1, yN0, z0),
            d: Vector3(x1, 0, z0),
            seam: z0,
            inward: 1,
            unfoldX: false,
            clip: clip,
          );
        }
      }
    }

    _drawAtlasAndPaper(canvas, img, positions, texCoords, paperCoords, colors);
  }

  void _drawSlopedTiles(
    Canvas canvas,
    Matrix4 mvp,
    Size size,
    double half,
    ui.Image img,
  ) {
    final slope = slopeTiles;
    final floorYOf = omitFloorY;
    if (slope == null || slope.isEmpty || floorYOf == null || hideGround) {
      return;
    }
    final tiles = visibleTiles == null ? slope : slope.intersection(visibleTiles!);
    if (tiles.isEmpty) return;

    final tileWorld = worldSize / tilesSide;
    final hole = omitTiles ?? const <(int, int)>{};
    final door = cutDoor;
    final occlusion = GroundOcclusion(
      holeTiles: hole,
      tileSize: tileWorld,
      wallHole: door == null ? null : wallHoleOccluderFromDoor(door),
      groundHole: GroundHoleRect.fromTiles(hole, tileWorld),
    );
    final tw = img.width.toDouble();
    final th = img.height.toDouble();
    final paper = paperTexture;
    final paperW = paper?.width.toDouble() ?? 0;
    final paperH = paper?.height.toDouble() ?? 0;
    const segs = 4;
    final positions = <Offset>[];
    final texCoords = <Offset>[];
    final paperCoords = paper == null ? null : <Offset>[];
    final colors = shade == null ? null : <Color>[];

    void addTri(List<Vector3> poly, List<Offset> uvs, Color tint) {
      if (poly.length < 3) return;
      for (var i = 1; i < poly.length - 1; i++) {
        final p0 = _projectToScreen(poly[0], mvp, size);
        final p1 = _projectToScreen(poly[i], mvp, size);
        final p2 = _projectToScreen(poly[i + 1], mvp, size);
        if (p0 == null || p1 == null || p2 == null) continue;
        positions
          ..add(p0)
          ..add(p1)
          ..add(p2);
        texCoords
          ..add(uvs[0])
          ..add(uvs[i])
          ..add(uvs[i + 1]);
        if (paperCoords != null) {
          paperCoords
            ..add(_paperUv(poly[0].x, poly[0].z, half, paperW, paperH))
            ..add(_paperUv(poly[i].x, poly[i].z, half, paperW, paperH))
            ..add(_paperUv(poly[i + 1].x, poly[i + 1].z, half, paperW, paperH));
        }
        colors
          ?..add(tint)
          ..add(tint)
          ..add(tint);
      }
    }

    for (final (tx, ty) in tiles) {
      final x0 = tx * tileWorld;
      final z0 = ty * tileWorld;
      final x1 = x0 + tileWorld;
      final z1 = z0 + tileWorld;
      final u0 = (x0 + half) / worldSize * tw;
      final v0 = (z0 + half) / worldSize * th;
      final u1 = (x1 + half) / worldSize * tw;
      final v1 = (z1 + half) / worldSize * th;
      for (var jz = 0; jz < segs; jz++) {
        final fv0 = jz / segs;
        final fv1 = (jz + 1) / segs;
        for (var ix = 0; ix < segs; ix++) {
          final fu0 = ix / segs;
          final fu1 = (ix + 1) / segs;
          final px0 = x0 + fu0 * (x1 - x0);
          final px1 = x0 + fu1 * (x1 - x0);
          final pz0 = z0 + fv0 * (z1 - z0);
          final pz1 = z0 + fv1 * (z1 - z0);
          final verts = [
            Vector3(px0, floorYOf(pz0), pz0),
            Vector3(px1, floorYOf(pz0), pz0),
            Vector3(px1, floorYOf(pz1), pz1),
            Vector3(px0, floorYOf(pz1), pz1),
          ];
          final uvs = [
            Offset(u0 + fu0 * (u1 - u0), v0 + fv0 * (v1 - v0)),
            Offset(u0 + fu1 * (u1 - u0), v0 + fv0 * (v1 - v0)),
            Offset(u0 + fu1 * (u1 - u0), v0 + fv1 * (v1 - v0)),
            Offset(u0 + fu0 * (u1 - u0), v0 + fv1 * (v1 - v0)),
          ];
          final parts = hole.contains((tx, ty))
              ? <List<Vector3>>[verts]
              : clipFaceToVisibleParts(camera, verts, occlusion);
          if (parts.isEmpty) continue;
          final tint = landscapeFaceShadeColor(
            shade,
            verts[0],
            verts[1],
            verts[2],
            lift: kLandscapeSlopeShadeLift,
          );
          for (final clipped in parts) {
            if (clipped.length < 3) continue;
            if (identical(clipped, verts) || clipped.length == 4) {
              addTri(clipped, uvs, tint);
              continue;
            }
            final clippedUvs = [
              for (final p in clipped)
                Offset(
                  u0 + ((p.x - x0) / (x1 - x0)).clamp(0.0, 1.0) * (u1 - u0),
                  v0 + ((p.z - z0) / (z1 - z0)).clamp(0.0, 1.0) * (v1 - v0),
                ),
            ];
            addTri(clipped, clippedUvs, tint);
          }
        }
      }
    }

    _drawAtlasAndPaper(canvas, img, positions, texCoords, paperCoords, colors);
  }

  void _appendPaperCoords(
    List<Offset>? paperCoords,
    double paperW,
    double paperH,
    double half,
    double x0,
    double x1,
    double z0,
    double z1,
  ) {
    if (paperCoords == null) return;
    final p00 = _paperUv(x0, z0, half, paperW, paperH);
    final p10 = _paperUv(x1, z0, half, paperW, paperH);
    final p11 = _paperUv(x1, z1, half, paperW, paperH);
    final p01 = _paperUv(x0, z1, half, paperW, paperH);
    paperCoords
      ..add(p00)
      ..add(p10)
      ..add(p11)
      ..add(p00)
      ..add(p11)
      ..add(p01);
  }

  Offset _paperUv(double x, double z, double half, double pw, double ph) {
    final repeat = paperRepeatWorld;
    if (repeat <= 1e-6) return Offset.zero;
    return Offset((x + half) / repeat * pw, (z + half) / repeat * ph);
  }

  void _drawAtlasAndPaper(
    Canvas canvas,
    ui.Image img,
    List<Offset> positions,
    List<Offset> texCoords,
    List<Offset>? paperCoords, [
    List<Color>? colors,
  ]) {
    if (positions.isEmpty) return;
    _imagePaint.shader = _shaderFor(img);
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: texCoords,
        colors: colors,
      ),
      colors == null ? BlendMode.srcOver : BlendMode.modulate,
      _imagePaint,
    );

    final paper = paperTexture;
    if (paper == null || paperCoords == null || paperCoords.isEmpty) return;
    _paperPaint.shader = _paperShaderFor(paper);
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: paperCoords,
      ),
      BlendMode.srcOver,
      _paperPaint,
    );
  }

  void _drawTileGrid(Canvas canvas, Matrix4 mvp, Size size, double half) {
    if (hideGround) return;
    final n = tilesSide.clamp(1, 512);
    final tileWorld = pixelsPerTile.toDouble().clamp(1.0, worldSize);
    final visible = visibleTiles;
    final path = Path();

    void line(Vector3 a, Vector3 b) {
      final pa = _projectToScreen(a, mvp, size);
      final pb = _projectToScreen(b, mvp, size);
      if (pa == null || pb == null) return;
      path.moveTo(pa.dx, pa.dy);
      path.lineTo(pb.dx, pb.dy);
    }

    if (visible != null) {
      final omit = omitTiles;
      for (final (tx, ty) in visible) {
        if (omit != null && omit.contains((tx, ty))) continue;
        var x0 = tx * tileWorld;
        var z0 = ty * tileWorld;
        var x1 = x0 + tileWorld;
        var z1 = z0 + tileWorld;
        if (clipMinX != null) x0 = math.max(x0, clipMinX!);
        if (clipMaxX != null) x1 = math.min(x1, clipMaxX!);
        if (clipMinZ != null) z0 = math.max(z0, clipMinZ!);
        if (clipMaxZ != null) z1 = math.min(z1, clipMaxZ!);
        if (x1 - x0 < 1e-6 || z1 - z0 < 1e-6) continue;
        line(Vector3(x0, 0, z0), Vector3(x1, 0, z0));
        line(Vector3(x1, 0, z0), Vector3(x1, 0, z1));
        line(Vector3(x1, 0, z1), Vector3(x0, 0, z1));
        line(Vector3(x0, 0, z1), Vector3(x0, 0, z0));
      }
      canvas.drawPath(path, _gridPaint);
      return;
    }

    for (var i = 0; i <= n; i++) {
      final x = -half + i * tileWorld;
      line(Vector3(x, 0, -half), Vector3(x, 0, half));
      final z = -half + i * tileWorld;
      line(Vector3(-half, 0, z), Vector3(half, 0, z));
    }

    canvas.drawPath(path, _gridPaint);

    final border = Path();
    final corners = <Vector3>[
      Vector3(-half, 0, -half),
      Vector3(half, 0, -half),
      Vector3(half, 0, half),
      Vector3(-half, 0, half),
    ];
    for (var i = 0; i < corners.length; i++) {
      final p = _projectToScreen(corners[i], mvp, size);
      if (p == null) return;
      if (i == 0) {
        border.moveTo(p.dx, p.dy);
      } else {
        border.lineTo(p.dx, p.dy);
      }
    }
    border.close();
    canvas.drawPath(border, _borderPaint);
  }

  static Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
    final clip = _transformPosition(mvp, worldPos);
    if (!_vector4IsFinite(clip) || clip.w < 1e-3) return null;
    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;
    final screenX = (ndcX * 0.5 + 0.5) * size.width;
    final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
    if (!screenX.isFinite || !screenY.isFinite) return null;
    return Offset(screenX, screenY);
  }

  static Vector4 _transformPosition(Matrix4 m, Vector3 v) {
    final r = Vector4(v.x, v.y, v.z, 1);
    m.transform(r);
    return r;
  }

  static bool _vector4IsFinite(Vector4 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite;

  @override
  bool shouldRepaint(covariant LandscapePlanePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.worldSize != worldSize ||
        oldDelegate.tilesSide != tilesSide ||
        oldDelegate.pixelsPerTile != pixelsPerTile ||
        oldDelegate.hoverWx != hoverWx ||
        oldDelegate.hoverWy != hoverWy ||
        oldDelegate.hoverBrushSize != hoverBrushSize ||
        oldDelegate.visibleTiles != visibleTiles ||
        oldDelegate.omitTiles != omitTiles ||
        oldDelegate.slopeTiles != slopeTiles ||
        oldDelegate.cutDoor != cutDoor ||
        oldDelegate.clipMinX != clipMinX ||
        oldDelegate.clipMaxX != clipMaxX ||
        oldDelegate.clipMinZ != clipMinZ ||
        oldDelegate.clipMaxZ != clipMaxZ ||
        oldDelegate.hideGround != hideGround ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.modulateColor != modulateColor ||
        oldDelegate.shade != shade ||
        oldDelegate.paperTexture != paperTexture ||
        oldDelegate.paperRepeatWorld != paperRepeatWorld ||
        oldDelegate.camera != camera ||
        oldDelegate.listenable != listenable;
  }
}
