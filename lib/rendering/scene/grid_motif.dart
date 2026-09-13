import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Tileable ground-plane stamp. UVs are world XZ / [worldSize], so a swap of
/// [image] (or [worldSize]) changes the grid type without new path math.
class GridMotif {
  GridMotif({
    required this.id,
    required this.worldSize,
    required this.image,
  }) : assert(worldSize > 0);

  /// One subtile stamp: wrapping seam lines so repeats stay antialiased.
  factory GridMotif.subtileLines({
    required double worldSize,
    int pixels = 32,
    Color line = const Color(0x88FFFFFF),
  }) {
    return GridMotif(
      id: 'subtile_lines',
      worldSize: worldSize,
      image: rasterizeEdgeLines(pixels: pixels, line: line),
    );
  }

  /// One subtile stamp: dots at wrapping corners (grid intersections).
  factory GridMotif.subtileDots({
    required double worldSize,
    int pixels = 32,
    Color dot = const Color(0x1A000000),
  }) {
    return GridMotif(
      id: 'subtile_dots',
      worldSize: worldSize,
      image: rasterizeCornerDots(pixels: pixels, dot: dot),
    );
  }

  final String id;
  final double worldSize;
  final ui.Image image;

  ui.ImageShader? _shader;

  /// Cached repeating shader. Valid until [dispose].
  ui.ImageShader get shader =>
      _shader ??= ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      );

  /// Bilinear sample of the repeating stamp. Triangle edges stay aliased so
  /// adjacent subtile quads do not double-blend.
  Paint samplingPaint() {
    return Paint()
      ..shader = shader
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low;
  }

  static double _coverage(double distance, double inner, double feather) {
    final t = ((distance - inner) / feather).clamp(0.0, 1.0);
    final s = t * t * (3 - 2 * t);
    return 1 - s;
  }

  static (double, double) _seamDistances(int x, int y, int size) {
    final u = (x + 0.5) / size;
    final v = (y + 0.5) / size;
    return (math.min(u, 1 - u) * size, math.min(v, 1 - v) * size);
  }

  /// Pixel coverage for a wrapping grid line. Distance is to the nearest
  /// tile seam so adjacent stamps reconstruct one antialiased stroke.
  static double seamCoverage(
    int x,
    int y,
    int size, {
    double halfWidth = 0.7,
    double feather = 1.2,
  }) {
    final (du, dv) = _seamDistances(x, y, size);
    return _coverage(math.min(du, dv), halfWidth, feather);
  }

  /// Pixel coverage for a wrapping grid intersection. Four adjacent stamps
  /// reconstruct one antialiased dot.
  static double cornerCoverage(
    int x,
    int y,
    int size, {
    double radius = 1.6,
    double feather = 1.3,
  }) {
    final (du, dv) = _seamDistances(x, y, size);
    return _coverage(math.sqrt(du * du + dv * dv), radius, feather);
  }

  static ui.Image rasterizeEdgeLines({
    int pixels = 32,
    Color line = const Color(0x88FFFFFF),
  }) {
    return _rasterizeCoverage(
      pixels: pixels,
      color: line,
      coverage: seamCoverage,
    );
  }

  static ui.Image rasterizeCornerDots({
    int pixels = 32,
    Color dot = const Color(0x1A000000),
  }) {
    return _rasterizeCoverage(
      pixels: pixels,
      color: dot,
      coverage: cornerCoverage,
    );
  }

  static ui.Image _rasterizeCoverage({
    required int pixels,
    required Color color,
    required double Function(int x, int y, int size) coverage,
  }) {
    final size = pixels.clamp(8, 256);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final cover = coverage(x, y, size);
        if (cover <= 1 / 255) continue;
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()
            ..color = color.withValues(alpha: color.a * cover)
            ..isAntiAlias = false
            ..filterQuality = FilterQuality.none,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  /// Perspective-correct-enough ground cells: one quad per [worldSize] so the
  /// motif copies in a single later [drawVertices].
  static void projectCells({
    required double minX,
    required double maxX,
    required double minZ,
    required double maxZ,
    required double y,
    required double worldSize,
    required double imageWidth,
    required double imageHeight,
    required Offset? Function(double x, double y, double z) project,
    required List<Offset> positions,
    required List<Offset> texCoords,
  }) {
    if (worldSize <= 1e-8 || maxX - minX < 1e-8 || maxZ - minZ < 1e-8) {
      return;
    }
    final segsX = math.max(1, ((maxX - minX) / worldSize).ceil());
    final segsZ = math.max(1, ((maxZ - minZ) / worldSize).ceil());
    Offset tex(double x, double z) => Offset(
      (x / worldSize) * imageWidth,
      (z / worldSize) * imageHeight,
    );

    for (var jz = 0; jz < segsZ; jz++) {
      final z0 = minZ + (maxZ - minZ) * (jz / segsZ);
      final z1 = minZ + (maxZ - minZ) * ((jz + 1) / segsZ);
      for (var ix = 0; ix < segsX; ix++) {
        final x0 = minX + (maxX - minX) * (ix / segsX);
        final x1 = minX + (maxX - minX) * ((ix + 1) / segsX);
        final p00 = project(x0, y, z0);
        final p10 = project(x1, y, z0);
        final p11 = project(x1, y, z1);
        final p01 = project(x0, y, z1);
        if (p00 == null || p10 == null || p11 == null || p01 == null) {
          continue;
        }
        positions
          ..add(p00)
          ..add(p10)
          ..add(p11)
          ..add(p00)
          ..add(p11)
          ..add(p01);
        texCoords
          ..add(tex(x0, z0))
          ..add(tex(x1, z0))
          ..add(tex(x1, z1))
          ..add(tex(x0, z0))
          ..add(tex(x1, z1))
          ..add(tex(x0, z1));
      }
    }
  }

  /// One [worldSize] stamp per cell over a world-XZ rectangle, appended for a
  /// later batched [Canvas.drawVertices]. Small quads keep affine UVs honest
  /// under perspective; the shader still repeats the same subtile image.
  void appendRepeating({
    required double minX,
    required double maxX,
    required double minZ,
    required double maxZ,
    required double y,
    required Offset? Function(double x, double y, double z) project,
    required List<Offset> positions,
    required List<Offset> texCoords,
  }) {
    projectCells(
      minX: minX,
      maxX: maxX,
      minZ: minZ,
      maxZ: maxZ,
      y: y,
      worldSize: worldSize,
      imageWidth: image.width.toDouble(),
      imageHeight: image.height.toDouble(),
      project: project,
      positions: positions,
      texCoords: texCoords,
    );
  }

  void dispose() {
    _shader?.dispose();
    _shader = null;
    image.dispose();
  }
}
