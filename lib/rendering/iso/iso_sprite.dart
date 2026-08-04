import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'iso_sprite_grid.dart';

/// Which depth layer to draw for a sprite.
enum SpriteLayer { combined, background, foreground }

/// Abstract base for a sprite (view) of an asset
///
/// This allows us to support both:
/// 1. Raster sprites (ui.Image) - fast for imported PNGs
/// 2. Vector sprites (ui.Picture) - scalable for generated 3D projections
abstract class IsoSprite {
  /// Original authoring size (for aspect ratio calculations)
  Size get size;

  /// Draw the sprite into the target rect
  void draw(Canvas canvas, Rect destination, Paint? paint);

  /// Whether this sprite has separate background/foreground depth layers.
  bool get hasDepthLayers => false;

  /// Draw only the background layer (cells behind the center for [viewIndex]).
  /// Falls back to [draw] if no depth layers are available.
  void drawBackground(Canvas canvas, Rect destination, Paint? paint,
      {int viewIndex = 0}) {
    draw(canvas, destination, paint);
  }

  /// Draw only the foreground layer (cells in front of center for [viewIndex]).
  /// No-op if no depth layers are available.
  void drawForeground(Canvas canvas, Rect destination, Paint? paint,
      {int viewIndex = 0}) {}

  /// Draw grid cells interleaved with friends based on depth.
  ///
  /// [friends] is a list of (depth, drawCallback) pairs sorted ascending by
  /// depth. Cells with depth below a friend's depth are drawn before that
  /// friend; cells above are drawn after. Falls back to drawing combined +
  /// all friends when no grid is available.
  void drawInterleaved(
    Canvas canvas, Rect destination, Paint? paint,
    List<(double, VoidCallback)> friends, {
    int viewIndex = 0,
  }) {
    draw(canvas, destination, paint);
    for (final (_, drawFn) in friends) {
      drawFn();
    }
  }

  /// Projected 2D position of the bottom-face centroid of the 3D bounding
  /// box, in sprite-local pixel coordinates.  Used to align the entity so
  /// it appears to stand on the tile.  Null for raster sprites.
  Offset? get groundPoint => null;

  /// Release resources
  void dispose();
}

/// For bitmap assets (PNGs)
class RasterIsoSprite extends IsoSprite {
  final ui.Image image;

  /// Pre-computed alpha mask (downscaled for performance)
  /// Stored as row-major Uint8List where 0 = transparent, 255 = opaque
  final Uint8List? alphaMask;

  /// Width of the alpha mask (may be smaller than image for performance)
  final int alphaMaskWidth;

  /// Height of the alpha mask (may be smaller than image for performance)
  final int alphaMaskHeight;

  RasterIsoSprite(
    this.image, {
    this.alphaMask,
    this.alphaMaskWidth = 0,
    this.alphaMaskHeight = 0,
  });

  @override
  Size get size => Size(image.width.toDouble(), image.height.toDouble());

  /// Check if a point (in normalized 0-1 coordinates) is opaque.
  /// Returns true if the point is within the visible (non-transparent) area.
  bool isOpaqueAt(double normalizedX, double normalizedY) {
    if (alphaMask == null || alphaMaskWidth <= 0 || alphaMaskHeight <= 0) {
      // No alpha mask - assume fully opaque (fallback to bounding box)
      return normalizedX >= 0 &&
          normalizedX <= 1 &&
          normalizedY >= 0 &&
          normalizedY <= 1;
    }

    // Clamp to valid range
    if (normalizedX < 0 ||
        normalizedX > 1 ||
        normalizedY < 0 ||
        normalizedY > 1) {
      return false;
    }

    // Map to alpha mask coordinates
    final maskX = (normalizedX * (alphaMaskWidth - 1)).round().clamp(
      0,
      alphaMaskWidth - 1,
    );
    final maskY = (normalizedY * (alphaMaskHeight - 1)).round().clamp(
      0,
      alphaMaskHeight - 1,
    );

    // Get alpha value from mask
    final index = maskY * alphaMaskWidth + maskX;
    if (index < 0 || index >= alphaMask!.length) {
      return false;
    }

    // Consider opaque if alpha > threshold (e.g., 10 to handle anti-aliasing)
    return alphaMask![index] > 10;
  }

  @override
  void draw(Canvas canvas, Rect destination, Paint? paint) {
    final src = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, destination, paint ?? Paint());
  }

  @override
  void dispose() => image.dispose();
}

/// For vector assets (3D Projections)
///
/// Stores recorded draw commands (Path, Paint, etc) in a ui.Picture.
/// These commands are replayed at draw time, allowing for infinite scaling
/// without pixelation.
class VectorIsoSprite extends IsoSprite {
  final ui.Picture picture;
  final Size originalSize;

  /// Optional 5x5 grid of cell pictures for view-aware depth splitting.
  /// When present, [drawBackground] and [drawForeground] use grid cells
  /// instead of the legacy binary bg/fg pictures.
  final IsoSpriteGrid? grid;

  /// Foreground wireframe edges (from visible faces)
  /// Each edge is a pair of points (start, end) in sprite-local coordinates
  final List<(Offset, Offset)> foregroundWireframeEdges;

  /// Background wireframe edges (from hidden/culled faces)
  /// Each edge is a pair of points (start, end) in sprite-local coordinates
  final List<(Offset, Offset)> backgroundWireframeEdges;

  /// Closed outline polygon for accurate hit testing.
  /// Traced from foreground wireframe edges to form the outer boundary.
  /// Points are in sprite-local coordinates (same space as wireframe edges).
  final List<Offset>? outlinePolygon;

  VectorIsoSprite(
    this.picture,
    this.originalSize, {
    this.grid,
    this.foregroundWireframeEdges = const [],
    this.backgroundWireframeEdges = const [],
    this.outlinePolygon,
    Offset? groundPoint,
  }) : _groundPoint = groundPoint;

  final Offset? _groundPoint;

  /// Pre-rasterized image of the combined picture for fast drawing.
  /// Lazily created on first draw call.
  ui.Image? _rasterCache;

  @override
  Offset? get groundPoint => _groundPoint;

  @override
  Size get size => originalSize;

  @override
  bool get hasDepthLayers => grid != null;

  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  /// Rasterize the picture to a ui.Image for fast blitting.
  void rasterize() {
    if (_rasterCache != null) return;
    _rasterCache = picture.toImageSync(
      originalSize.width.ceil(),
      originalSize.height.ceil(),
    );
  }

  @override
  void draw(Canvas canvas, Rect destination, Paint? paint) {
    _rasterCache ??= picture.toImageSync(
      originalSize.width.ceil(),
      originalSize.height.ceil(),
    );
    _drawRasterized(canvas, destination, paint);
  }

  void _drawRasterized(Canvas canvas, Rect destination, Paint? paint) {
    final img = _rasterCache!;
    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());

    final alpha = paint?.color.a ?? 1.0;
    final hasOpacity = alpha < 1.0;
    final hasColorFilter = paint?.colorFilter != null;

    if (hasOpacity || hasColorFilter) {
      _imagePaint.color = Color.fromRGBO(0, 0, 0, alpha);
      _imagePaint.colorFilter = paint?.colorFilter;
      canvas.drawImageRect(img, src, destination, _imagePaint);
      _imagePaint.color = const Color(0xFFFFFFFF);
      _imagePaint.colorFilter = null;
    } else {
      canvas.drawImageRect(img, src, destination, _imagePaint);
    }
  }

  @override
  void drawBackground(Canvas canvas, Rect destination, Paint? paint,
      {int viewIndex = 0}) {
    if (grid != null) {
      grid!.drawBehind(canvas, destination, paint, viewIndex: viewIndex);
      return;
    }
    draw(canvas, destination, paint);
  }

  @override
  void drawForeground(Canvas canvas, Rect destination, Paint? paint,
      {int viewIndex = 0}) {
    if (grid != null) {
      grid!.drawInFront(canvas, destination, paint, viewIndex: viewIndex);
      return;
    }
  }

  @override
  void drawInterleaved(
    Canvas canvas, Rect destination, Paint? paint,
    List<(double, VoidCallback)> friends, {
    int viewIndex = 0,
  }) {
    if (grid != null) {
      grid!.drawInterleaved(canvas, destination, paint, friends, viewIndex);
      return;
    }
    draw(canvas, destination, paint);
    for (final (_, drawFn) in friends) {
      drawFn();
    }
  }


  /// Draw foreground wireframe edges scaled to destination
  /// Used for selection highlighting of visible edges (full opacity)
  void drawForegroundWireframe(Canvas canvas, Rect destination, Paint paint) {
    if (foregroundWireframeEdges.isEmpty) return;

    final scaleX = destination.width / originalSize.width;
    final scaleY = destination.height / originalSize.height;

    for (final (start, end) in foregroundWireframeEdges) {
      final p1 = Offset(
        destination.left + start.dx * scaleX,
        destination.top + start.dy * scaleY,
      );
      final p2 = Offset(
        destination.left + end.dx * scaleX,
        destination.top + end.dy * scaleY,
      );

      canvas.drawLine(p1, p2, paint);
    }
  }

  /// Draw background wireframe edges scaled to destination
  /// Used for selection highlighting of hidden edges (thinner, more subtle)
  void drawBackgroundWireframe(Canvas canvas, Rect destination, Paint paint) {
    if (backgroundWireframeEdges.isEmpty) return;

    final scaleX = destination.width / originalSize.width;
    final scaleY = destination.height / originalSize.height;

    for (final (start, end) in backgroundWireframeEdges) {
      final p1 = Offset(
        destination.left + start.dx * scaleX,
        destination.top + start.dy * scaleY,
      );
      final p2 = Offset(
        destination.left + end.dx * scaleX,
        destination.top + end.dy * scaleY,
      );

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  void dispose() {
    picture.dispose();
    grid?.dispose();
  }
}
