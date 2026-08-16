import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';

/// Draws a landscape atlas as a textured ground plane (XZ, Y=0) through [camera].
///
/// Uses a tessellated mesh so Flutter's affine UV interpolation does not create
/// the classic perspective "swim" / bow-tie warping of a single 4-vertex quad.
class LandscapePlanePainter extends CustomPainter {
  LandscapePlanePainter({
    required this.camera,
    required this.orbit,
    required this.image,
    required this.worldSize,
    required this.tilesSide,
    required this.pixelsPerTile,
    this.hoverWx,
    this.hoverWy,
  }) : super(repaint: orbit);

  final Camera camera;
  final OrbitCameraController orbit;
  final ui.Image? image;
  final double worldSize;
  final int tilesSide;
  final int pixelsPerTile;
  final int? hoverWx;
  final int? hoverWy;

  static final Paint _imagePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static final Paint _bgPaint = Paint()..color = const Color(0xFF101418);

  static final Paint _gridPaint = Paint()
    ..color = const Color(0x55FFFFFF)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _borderPaint = Paint()
    ..color = const Color(0x88FFFFFF)
    ..strokeWidth = 1.25
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _hoverPaint = Paint()
    ..color = const Color(0xAAFFFFFF)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bgPaint);

    final img = image;
    if (img == null || worldSize <= 0) return;

    final aspect = size.width / size.height;
    final mvp = camera.projectionMatrix(aspect) * camera.viewMatrix;
    final half = worldSize * 0.5;

    _drawTessellatedPlane(canvas, mvp, size, half, img);
    _drawTileGrid(canvas, mvp, size, half);
    _drawHoverPixel(canvas, mvp, size, half);
  }

  void _drawHoverPixel(Canvas canvas, Matrix4 mvp, Size size, double half) {
    final hx = hoverWx;
    final hy = hoverWy;
    if (hx == null || hy == null) return;
    final side = tilesSide * pixelsPerTile;
    if (hx < 0 || hy < 0 || hx >= side || hy >= side) return;

    final x0 = -half + hx;
    final z0 = -half + hy;
    final x1 = x0 + 1;
    final z1 = z0 + 1;
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
    // Enough subdivisions to keep affine UV error invisible while orbiting.
    // Prefer at least 2 segments per tile, capped for performance.
    final segments = math
        .max(tilesSide * 2, 24)
        .clamp(1, 64);

    final tw = img.width.toDouble();
    final th = img.height.toDouble();
    final positions = <Offset>[];
    final texCoords = <Offset>[];

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
      }
    }

    if (positions.isEmpty) return;

    final shader = ui.ImageShader(
      img,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
    );
    _imagePaint.shader = shader;
    canvas.drawVertices(
      ui.Vertices(
        VertexMode.triangles,
        positions,
        textureCoordinates: texCoords,
      ),
      BlendMode.srcOver,
      _imagePaint,
    );
    _imagePaint.shader = null;
  }

  void _drawTileGrid(Canvas canvas, Matrix4 mvp, Size size, double half) {
    final n = tilesSide.clamp(1, 512);
    final tileWorld = pixelsPerTile.toDouble().clamp(1.0, worldSize);
    final path = Path();

    for (var i = 0; i <= n; i++) {
      final x = -half + i * tileWorld;
      final a = _projectToScreen(Vector3(x, 0, -half), mvp, size);
      final b = _projectToScreen(Vector3(x, 0, half), mvp, size);
      if (a != null && b != null) {
        path.moveTo(a.dx, a.dy);
        path.lineTo(b.dx, b.dy);
      }

      final z = -half + i * tileWorld;
      final c = _projectToScreen(Vector3(-half, 0, z), mvp, size);
      final d = _projectToScreen(Vector3(half, 0, z), mvp, size);
      if (c != null && d != null) {
        path.moveTo(c.dx, c.dy);
        path.lineTo(d.dx, d.dy);
      }
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
        oldDelegate.camera != camera ||
        oldDelegate.orbit != orbit;
  }
}
