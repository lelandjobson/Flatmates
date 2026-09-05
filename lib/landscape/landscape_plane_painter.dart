import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../debug/scene_paint_stats.dart';
import '../rendering/scene/camera.dart';

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
    this.clipMinX,
    this.clipMaxX,
    this.clipMinZ,
    this.clipMaxZ,
    this.hideGround = false,
    this.backgroundColor = const Color(0xFF101418),
    this.modulateColor,
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

      _drawTessellatedPlane(canvas, mvp, size, half, img);
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

    for (final (tx, ty) in visible) {
      if (tx < 0 || ty < 0 || tx >= tilesSide || ty >= tilesSide) continue;
      var x0 = -half + tx * tileWorld;
      var z0 = -half + ty * tileWorld;
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
    List<Offset>? paperCoords,
  ) {
    if (positions.isEmpty) return;
    _imagePaint.shader = _shaderFor(img);
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: texCoords,
      ),
      BlendMode.srcOver,
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
      for (final (tx, ty) in visible) {
        var x0 = -half + tx * tileWorld;
        var z0 = -half + ty * tileWorld;
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
        oldDelegate.clipMinX != clipMinX ||
        oldDelegate.clipMaxX != clipMaxX ||
        oldDelegate.clipMinZ != clipMinZ ||
        oldDelegate.clipMaxZ != clipMaxZ ||
        oldDelegate.hideGround != hideGround ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.modulateColor != modulateColor ||
        oldDelegate.paperTexture != paperTexture ||
        oldDelegate.paperRepeatWorld != paperRepeatWorld ||
        oldDelegate.camera != camera ||
        oldDelegate.listenable != listenable;
  }
}
