import 'dart:ui';

// ---------------------------------------------------------------------------
// Geometry primitives -- drawn within tile-local pixel space (0,0 → w,h).
// ---------------------------------------------------------------------------

/// Base class for a single geometric element inside a hatch tile.
abstract class HatchGeometry {
  const HatchGeometry();

  /// Draw this element onto [canvas] using [paint].
  void paint(Canvas canvas, Paint paint);
}

/// A straight line segment from [start] to [end].
class HatchLine extends HatchGeometry {
  const HatchLine(this.start, this.end);

  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Paint paint) {
    canvas.drawLine(start, end, paint);
  }
}

/// An axis-aligned rectangle.
class HatchRect extends HatchGeometry {
  const HatchRect(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Paint paint) {
    canvas.drawRect(rect, paint);
  }
}

/// A circle centred at [center] with the given [radius].
class HatchCircle extends HatchGeometry {
  const HatchCircle(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Paint paint) {
    canvas.drawCircle(center, radius, paint);
  }
}

/// An arbitrary closed or open path.
class HatchPathGeometry extends HatchGeometry {
  const HatchPathGeometry(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Paint paint) {
    canvas.drawPath(path, paint);
  }
}

// ---------------------------------------------------------------------------
// Layer style
// ---------------------------------------------------------------------------

/// Stroke and fill settings applied to every geometry in a [HatchLayer].
///
/// At least one of [fillColor] or [strokeColor] should be non-null; if both
/// are provided the fill is drawn first, then the stroke on top.
class HatchLayerStyle {
  const HatchLayerStyle({
    this.fillColor,
    this.strokeColor,
    this.strokeWidth = 1.0,
    this.strokeCap = StrokeCap.butt,
  });

  final Color? fillColor;
  final Color? strokeColor;
  final double strokeWidth;
  final StrokeCap strokeCap;
}

// ---------------------------------------------------------------------------
// Layer & pattern
// ---------------------------------------------------------------------------

/// One visual layer within a hatch tile.  A pattern is composed of one or
/// more layers that are painted in order (bottom-to-top).
class HatchLayer {
  const HatchLayer({
    required this.geometries,
    required this.style,
  });

  final List<HatchGeometry> geometries;
  final HatchLayerStyle style;
}

/// A complete hatch-pattern definition.
///
/// [tileWidth] and [tileHeight] define the repeating cell size in logical
/// pixels.  [layers] are painted bottom-to-top when the tile image is
/// rasterised.
class HatchPattern {
  const HatchPattern({
    required this.id,
    required this.tileWidth,
    required this.tileHeight,
    required this.layers,
  });

  final String id;
  final double tileWidth;
  final double tileHeight;
  final List<HatchLayer> layers;
}
