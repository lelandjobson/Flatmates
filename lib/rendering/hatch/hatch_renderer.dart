import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import 'hatch_pattern.dart';

/// GPU-accelerated hatch renderer.
///
/// Usage:
/// 1. Call [prepare] once per pattern (async -- rasterises the tile).
/// 2. Call [draw] every frame (sync, zero-allocation).
/// 3. Call [dispose] when the renderer is no longer needed.
class HatchRenderer {
  final Map<String, ui.Image> _cache = {};

  /// Pre-built shaders keyed by pattern ID (identity transform).
  /// Avoids creating a new [ImageShader] + [Matrix4] every frame.
  final Map<String, ui.ImageShader> _shaderCache = {};

  static final Float64List _identityMatrix = Matrix4.identity().storage;

  /// Shared paint reused across [draw] calls to avoid per-frame allocation.
  final Paint _shaderPaint = Paint()..style = PaintingStyle.fill;

  /// Whether a tile image is ready for [patternId].
  bool isReady(String patternId) => _shaderCache.containsKey(patternId);

  // -----------------------------------------------------------------------
  // Tile image generation
  // -----------------------------------------------------------------------

  /// Rasterise a single tile of [pattern] and cache the resulting image
  /// together with a pre-built [ImageShader] for the identity transform.
  ///
  /// Uses [picture.toImage] (async) which schedules GPU rasterisation across
  /// frames — much safer than the synchronous variant which can overwhelm the
  /// native command buffer when called in a tight loop.
  ///
  /// [pixelRatio] lets you render at a higher resolution for sharper results
  /// on high-DPI screens (the shader matrix in [draw] will compensate).
  ///
  /// Safe to call again for the same pattern id -- the old image is disposed
  /// before the new one is stored.
  Future<void> prepare(
    HatchPattern pattern, {
    double pixelRatio = 1.0,
  }) async {
    final w = (pattern.tileWidth * pixelRatio).ceilToDouble();
    final h = (pattern.tileHeight * pixelRatio).ceilToDouble();

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      if (pixelRatio != 1.0) {
        canvas.scale(pixelRatio);
      }

      _paintLayers(canvas, pattern.layers);

      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), h.toInt());

      if (_disposed) {
        image.dispose();
        return;
      }

      _cache[pattern.id]?.dispose();
      _cache[pattern.id] = image;
      _shaderCache[pattern.id] = ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        Float64List.fromList(_identityMatrix),
      );
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Drawing
  // -----------------------------------------------------------------------

  /// Draw the cached hatch identified by [patternId] into [boundary].
  ///
  /// [origin]   -- world-space anchor for the pattern grid.
  /// [rotation] -- rotation in radians applied around [origin].
  /// [scale]    -- uniform scale applied to the tile size.
  ///
  /// No-ops silently if the tile image has not been [prepare]d yet.
  bool _disposed = false;

  void draw(
    Canvas canvas,
    Path boundary,
    String patternId, {
    Offset origin = Offset.zero,
    double rotation = 0.0,
    double scale = 1.0,
    double opacity = 1.0,
    double brightness = 0.0,
  }) {
    if (_disposed) return;
    try {
      if (origin == Offset.zero && rotation == 0.0 && scale == 1.0) {
        final shader = _shaderCache[patternId];
        if (shader == null) return;
        _shaderPaint.shader = shader;
      } else {
        final image = _cache[patternId];
        if (image == null) return;
        final matrix = Matrix4.identity()
          ..translateByDouble(origin.dx, origin.dy, 0.0, 1.0)
          ..rotateZ(rotation)
          ..scaleByDouble(scale, scale, 1.0, 1.0);
        _shaderPaint.shader = ui.ImageShader(
          image,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          matrix.storage,
        );
      }

      _shaderPaint.color =
          Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

      final b = (brightness.clamp(0.0, 1.0) * 255).roundToDouble();
      _shaderPaint.colorFilter = ColorFilter.matrix(<double>[
        0, 0, 0, 0, b,
        0, 0, 0, 0, b,
        0, 0, 0, 0, b,
        0, 0, 0, 1, 0,
      ]);

      canvas.drawPath(boundary, _shaderPaint);
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Dispose and remove the cached tile for [patternId].
  void evict(String patternId) {
    _shaderCache.remove(patternId);
    _cache.remove(patternId)?.dispose();
  }

  /// Dispose **all** cached tile images.  Call when the renderer is torn down.
  void dispose() {
    _disposed = true;
    _shaderPaint.shader = null;
    _shaderCache.clear();
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

  void _paintLayers(Canvas canvas, List<HatchLayer> layers) {
    for (final layer in layers) {
      final style = layer.style;

      if (style.fillColor != null) {
        _fillPaint.color = style.fillColor!;
        for (final geom in layer.geometries) {
          geom.paint(canvas, _fillPaint);
        }
      }

      if (style.strokeColor != null) {
        _strokePaint
          ..color = style.strokeColor!
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeCap;
        for (final geom in layer.geometries) {
          geom.paint(canvas, _strokePaint);
        }
      }
    }
  }
}
