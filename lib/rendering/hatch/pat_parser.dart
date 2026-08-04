import 'dart:math' as math;
import 'dart:ui';

import 'hatch_pattern.dart';

/// A single line-family definition from an AutoCAD PAT file.
///
/// Each definition produces an infinite set of parallel lines at [angle],
/// spaced [deltaY] apart perpendicularly, with an optional repeating dash
/// pattern.  [deltaX] staggers the dash phase between successive parallel
/// lines.
class PatLineDef {
  const PatLineDef({
    required this.angle,
    required this.xOrigin,
    required this.yOrigin,
    required this.deltaX,
    required this.deltaY,
    this.dashes = const [],
  });

  final double angle;
  final double xOrigin;
  final double yOrigin;
  final double deltaX;
  final double deltaY;
  final List<double> dashes;
}

/// Parses AutoCAD `.pat` hatch-pattern files and converts the result into
/// [HatchPattern] instances suitable for the [HatchRenderer].
///
/// PAT format reference (per Autodesk):
///   *name, description
///   angle, x-origin, y-origin, delta-x, delta-y [,dash1, dash2, …]
///   …
///   (blank line)
abstract final class PatParser {
  /// Parse raw PAT file text into a pattern name and list of line definitions.
  static (String name, List<PatLineDef> lines) parse(String content) {
    final rawLines = content.split('\n');
    String name = '';
    final defs = <PatLineDef>[];

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('*')) {
        final comma = trimmed.indexOf(',');
        name = comma > 0 ? trimmed.substring(1, comma) : trimmed.substring(1);
        continue;
      }

      if (trimmed.startsWith(';') || trimmed.startsWith('//')) continue;

      final parts = trimmed.split(',').map((s) => s.trim()).toList();
      if (parts.length < 5) continue;

      final angle = double.tryParse(parts[0]);
      final xOrigin = double.tryParse(parts[1]);
      final yOrigin = double.tryParse(parts[2]);
      final deltaX = double.tryParse(parts[3]);
      final deltaY = double.tryParse(parts[4]);

      if (angle == null ||
          xOrigin == null ||
          yOrigin == null ||
          deltaX == null ||
          deltaY == null) {
        continue;
      }

      final dashes = <double>[];
      for (var i = 5; i < parts.length; i++) {
        final d = double.tryParse(parts[i]);
        if (d != null) dashes.add(d);
      }

      defs.add(PatLineDef(
        angle: angle,
        xOrigin: xOrigin,
        yOrigin: yOrigin,
        deltaX: deltaX,
        deltaY: deltaY,
        dashes: dashes,
      ));
    }

    return (name, defs);
  }

  /// Convert parsed [PatLineDef]s into a [HatchPattern].
  ///
  /// [tileWidth] / [tileHeight] must match the natural repeat period of the
  /// PAT definition for seamless tiling.  [scale] uniformly scales all
  /// coordinates (origin, spacing, dash lengths).
  static HatchPattern toHatchPattern({
    required String id,
    required List<PatLineDef> lineDefs,
    required double tileWidth,
    required double tileHeight,
    double scale = 1.0,
    Color strokeColor = const Color(0xFF000000),
    double strokeWidth = 0.8,
  }) {
    final tw = tileWidth * scale;
    final th = tileHeight * scale;
    final geometries = <HatchGeometry>[];

    for (final def in lineDefs) {
      _generateSegments(def, tw, th, scale, geometries);
    }

    return HatchPattern(
      id: id,
      tileWidth: tw,
      tileHeight: th,
      layers: [
        HatchLayer(
          geometries: geometries,
          style: HatchLayerStyle(
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  static void _generateSegments(
    PatLineDef def,
    double tileW,
    double tileH,
    double scale,
    List<HatchGeometry> output,
  ) {
    final angleRad = def.angle * math.pi / 180.0;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);

    final dirX = cosA;
    final dirY = sinA;
    final perpX = -sinA;
    final perpY = cosA;

    final spacing = def.deltaY * scale;
    if (spacing.abs() < 1e-10) return;

    final x0 = def.xOrigin * scale;
    final y0 = def.yOrigin * scale;
    final dx = def.deltaX * scale;

    final dashes = def.dashes.map((d) => d * scale).toList();

    // Project tile corners onto the perpendicular axis to find which
    // parallel-line indices intersect the tile.
    double minProj = double.infinity;
    double maxProj = double.negativeInfinity;
    for (final c in [
      const Offset(0, 0),
      Offset(tileW, 0),
      Offset(tileW, tileH),
      Offset(0, tileH),
    ]) {
      final proj = c.dx * perpX + c.dy * perpY;
      if (proj < minProj) minProj = proj;
      if (proj > maxProj) maxProj = proj;
    }

    final originProj = x0 * perpX + y0 * perpY;
    final nMin = ((minProj - originProj) / spacing).floor() - 1;
    final nMax = ((maxProj - originProj) / spacing).ceil() + 1;

    for (var n = nMin; n <= nMax; n++) {
      final lx = x0 + n * spacing * perpX;
      final ly = y0 + n * spacing * perpY;
      final dashOffset = n * dx;

      final (tMin, tMax) = _clipLineToRect(lx, ly, dirX, dirY, tileW, tileH);
      if (tMin >= tMax) continue;

      _traceDashes(
          lx, ly, dirX, dirY, tMin, tMax, dashOffset, dashes, output);
    }
  }

  /// Parametric clip of the ray (lx + t*dirX, ly + t*dirY) to [0,w]×[0,h].
  static (double, double) _clipLineToRect(
    double lx,
    double ly,
    double dirX,
    double dirY,
    double w,
    double h,
  ) {
    double tMin = double.negativeInfinity;
    double tMax = double.infinity;

    if (dirX.abs() > 1e-12) {
      final t1 = -lx / dirX;
      final t2 = (w - lx) / dirX;
      tMin = math.max(tMin, math.min(t1, t2));
      tMax = math.min(tMax, math.max(t1, t2));
    } else if (lx < 0 || lx > w) {
      return (0.0, 0.0);
    }

    if (dirY.abs() > 1e-12) {
      final t1 = -ly / dirY;
      final t2 = (h - ly) / dirY;
      tMin = math.max(tMin, math.min(t1, t2));
      tMax = math.min(tMax, math.max(t1, t2));
    } else if (ly < 0 || ly > h) {
      return (0.0, 0.0);
    }

    return (tMin, tMax);
  }

  /// Walk the dash pattern along the clipped parametric range [tMin, tMax],
  /// emitting [HatchLine] (or [HatchCircle] for dots) into [output].
  static void _traceDashes(
    double lx,
    double ly,
    double dirX,
    double dirY,
    double tMin,
    double tMax,
    double dashOffset,
    List<double> dashes,
    List<HatchGeometry> output,
  ) {
    if (dashes.isEmpty) {
      output.add(HatchLine(
        Offset(lx + tMin * dirX, ly + tMin * dirY),
        Offset(lx + tMax * dirX, ly + tMax * dirY),
      ));
      return;
    }

    final dashTotal = dashes.fold<double>(0, (s, d) => s + d.abs());
    if (dashTotal < 1e-10) return;

    // Find the start of the dash cycle that covers tMin, accounting for
    // the per-line stagger offset.
    final adjusted = tMin - dashOffset;
    double t = (adjusted / dashTotal).floorToDouble() * dashTotal + dashOffset;
    int idx = 0;

    // Advance to the dash element that contains tMin.
    while (t + dashes[idx].abs() <= tMin) {
      t += dashes[idx].abs();
      idx = (idx + 1) % dashes.length;
    }

    while (t < tMax) {
      final d = dashes[idx];
      final segEnd = t + d.abs();

      if (d > 0) {
        final a = math.max(t, tMin);
        final b = math.min(segEnd, tMax);
        if (b - a > 1e-6) {
          output.add(HatchLine(
            Offset(lx + a * dirX, ly + a * dirY),
            Offset(lx + b * dirX, ly + b * dirY),
          ));
        }
      } else if (d == 0) {
        if (t >= tMin && t <= tMax) {
          output.add(HatchCircle(
            Offset(lx + t * dirX, ly + t * dirY),
            0.3,
          ));
        }
        // Advance a tiny epsilon so the loop doesn't stall on zero-length.
        t += 1e-6;
        idx = (idx + 1) % dashes.length;
        continue;
      }

      t = segEnd;
      idx = (idx + 1) % dashes.length;
    }
  }
}
