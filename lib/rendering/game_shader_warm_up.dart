import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Pre-compiles the Impeller / Skia pipelines GameView actually uses.
///
/// The 3D bench is CPU-projected [Canvas] drawing, not a GPU scene graph.
/// Arbitrary meshes do not spawn new programs — unique *paint configurations*
/// do (solid fill, hairline stroke, textured [drawVertices], blur, modulate).
///
/// Assign to [PaintingBinding.shaderWarmUp] before [runApp] so first-use
/// compilation happens at startup instead of mid-orbit / first tool enable.
class GameViewShaderWarmUp extends ShaderWarmUp {
  const GameViewShaderWarmUp();

  @override
  ui.Size get size => const ui.Size(128, 128);

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {
    final atlas = await _tinyAtlas();
    try {
      _warmSolidFaces(canvas);
      _warmStrokes(canvas);
      _warmTexturedLandscape(canvas, atlas);
      _warmShadowsAndSprites(canvas);
      _warmHudText(canvas);
    } finally {
      atlas.dispose();
    }
  }

  /// 4×4 paper-diorama stand-in so [ImageShader] + [drawVertices] compile.
  static Future<ui.Image> _tinyAtlas() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const Color(0xFF88AA66),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(2, 0, 2, 2),
      ui.Paint()..color = const Color(0xFF446633),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 2, 2, 2),
      ui.Paint()..color = const Color(0xFFC4A574),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    picture.dispose();
    return image;
  }

  /// ScenePainter / face-paint: filled convex polygons, opaque and alpha.
  static void _warmSolidFaces(ui.Canvas canvas) {
    final path = ui.Path()
      ..addPolygon(const [
        ui.Offset(8, 8),
        ui.Offset(40, 10),
        ui.Offset(36, 44),
        ui.Offset(6, 38),
      ], true);
    canvas.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = const Color(0xFFE8DCC8),
    );
    canvas.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = const Color(0x55FF8A80),
    );
    canvas.drawCircle(
      const ui.Offset(96, 24),
      8,
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 128, 128),
      ui.Paint()..color = const Color(0x2E3A2A68),
    );
  }

  /// Volume edges, landscape grid, gizmos, eraser outline.
  static void _warmStrokes(ui.Canvas canvas) {
    final stroke = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true
      ..color = const Color(0x3DFFFFFF);
    canvas.drawPath(
      ui.Path()..addPolygon(const [
        ui.Offset(48, 8),
        ui.Offset(80, 12),
        ui.Offset(76, 40),
      ], true),
      stroke,
    );
    canvas.drawLine(const ui.Offset(8, 56), const ui.Offset(80, 56), stroke);
    canvas.drawPath(
      ui.Path()
        ..moveTo(8, 64)
        ..lineTo(80, 64)
        ..moveTo(8, 72)
        ..lineTo(80, 72),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true
        ..color = const Color(0x55FFFFFF),
    );
    canvas.drawPath(
      ui.Path()..addOval(const ui.Rect.fromLTWH(88, 48, 28, 20)),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xCCFF8A80),
    );
  }

  /// LandscapePlanePainter: atlas tris, day-night modulate, paper multiply.
  static void _warmTexturedLandscape(ui.Canvas canvas, ui.Image atlas) {
    final shader = ui.ImageShader(
      atlas,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
    );
    final verts = ui.Vertices(
      ui.VertexMode.triangles,
      const [
        ui.Offset(8, 80),
        ui.Offset(56, 80),
        ui.Offset(8, 120),
        ui.Offset(8, 120),
        ui.Offset(56, 80),
        ui.Offset(56, 120),
      ],
      textureCoordinates: const [
        ui.Offset(0, 0),
        ui.Offset(4, 0),
        ui.Offset(0, 4),
        ui.Offset(0, 4),
        ui.Offset(4, 0),
        ui.Offset(4, 4),
      ],
    );
    final paint = ui.Paint()
      ..isAntiAlias = false
      ..filterQuality = ui.FilterQuality.none
      ..shader = shader;
    canvas.drawVertices(verts, ui.BlendMode.srcOver, paint);
    paint.colorFilter = const ColorFilter.mode(
      Color(0xFFE8E0F0),
      BlendMode.modulate,
    );
    canvas.drawVertices(verts, ui.BlendMode.srcOver, paint);

    final paperShader = ui.ImageShader(
      atlas,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      Matrix4.identity().storage,
    );
    paint
      ..colorFilter = const ColorFilter.mode(
        Color(0xFFE8E0F0),
        BlendMode.modulate,
      )
      ..filterQuality = ui.FilterQuality.medium
      ..blendMode = ui.BlendMode.multiply
      ..shader = paperShader;
    canvas.drawVertices(verts, ui.BlendMode.srcOver, paint);
    paint
      ..colorFilter = null
      ..blendMode = ui.BlendMode.srcOver
      ..filterQuality = ui.FilterQuality.none
      ..shader = null;
    shader.dispose();
    paperShader.dispose();

    canvas.drawLine(
      const ui.Offset(8, 124),
      const ui.Offset(56, 124),
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true
        ..color = const Color(0x55FFFFFF)
        ..colorFilter = const ColorFilter.mode(
          Color(0xFFE8E0F0),
          BlendMode.modulate,
        ),
    );
  }

  /// Ground-shadow [MaskFilter.blur] and a ColorFiltered-style saveLayer.
  static void _warmShadowsAndSprites(ui.Canvas canvas) {
    canvas.drawPath(
      ui.Path()..addPolygon(const [
        ui.Offset(64, 80),
        ui.Offset(120, 82),
        ui.Offset(116, 118),
        ui.Offset(68, 114),
      ], true),
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..color = const Color(0x382C2A32)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );

    canvas.saveLayer(
      const ui.Rect.fromLTWH(64, 8, 56, 40),
      ui.Paint()
        ..colorFilter = const ColorFilter.mode(
          Color(0xFFD0D8E8),
          BlendMode.modulate,
        ),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(64, 8, 56, 40),
      ui.Paint()..color = const Color(0xFF88AA66),
    );
    canvas.restore();
  }

  static void _warmHudText(ui.Canvas canvas) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'Aa 12',
        style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const ui.Offset(8, 108));
    painter.dispose();
  }
}
