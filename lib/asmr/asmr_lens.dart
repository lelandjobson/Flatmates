import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The cut-mode camera: a lens looking along the scissors, from straight down
/// to a low view like a map following a route.
///
/// The paper is the ground. [elevation] is how far the lens sits above the
/// horizon: π/2 looks straight down and [project] is the identity, so the desk
/// matches the flat view. Lowering it swings the lens back from the cut and
/// down toward the paper. [focal] is the lens length in pixels; a shorter
/// lens sits closer and exaggerates the near and far paper. The cut, at
/// [pivot], stays put.
class AsmrCutLens {
  AsmrCutLens({
    required this.pivot,
    required this.focal,
    required this.elevation,
  });

  /// Straight down. [project] and [unproject] leave points where they are.
  static final overhead = AsmrCutLens(
    pivot: Offset.zero,
    focal: 1,
    elevation: math.pi / 2,
  );

  /// Full-frame sensor height. Lens length in millimetres maps to a vertical
  /// field of view through this.
  static const double sensorHeightMm = 24;

  /// How close to the horizon the fully pitched view gets, above horizontal.
  static const double horizonElevation = 20 * math.pi / 180;

  /// Where the cut sits on screen. It is the projection's fixed point.
  final Offset pivot;

  /// Lens length in screen pixels. Matched to the camera distance, so a
  /// straight-down view does not change size when the lens changes.
  final double focal;

  /// Radians above the horizon. π/2 is straight down.
  final double elevation;

  bool get isOverhead => (elevation - math.pi / 2).abs() < 1e-6;

  /// [perspectiveness] 0 is straight down. 1 looks along the cut, just above
  /// the horizon.
  static double elevationFor(double perspectiveness) {
    final t = perspectiveness.clamp(0.0, 1.0);
    return math.pi / 2 + (horizonElevation - math.pi / 2) * t;
  }

  /// Pixels of focal length for a lens of [lensMm] on a view [viewHeight] tall.
  static double focalPixels(double lensMm, double viewHeight) =>
      viewHeight * lensMm / sensorHeightMm;

  /// Vertical field of view, in degrees, of a [lensMm] lens.
  static double verticalFovDegrees(double lensMm) =>
      2 * math.atan((sensorHeightMm / 2) / lensMm) * 180 / math.pi;

  /// Flat screen point to the pitched view.
  Offset project(Offset flat) {
    if (isOverhead) return flat;
    final x = flat.dx - pivot.dx;
    final yUp = pivot.dy - flat.dy;
    final c = math.cos(elevation);
    final s = math.sin(elevation);
    final depth = focal + yUp * c;
    if (depth.abs() < 1e-4) return flat;
    return Offset(
      pivot.dx + focal * x / depth,
      pivot.dy - focal * yUp * s / depth,
    );
  }

  /// Pitched screen point back to the flat view. The inverse of [project].
  Offset unproject(Offset screen) {
    if (isOverhead) return screen;
    final sx = screen.dx - pivot.dx;
    final syUp = pivot.dy - screen.dy;
    final c = math.cos(elevation);
    final s = math.sin(elevation);
    final denom = s * focal - syUp * c;
    if (denom.abs() < 1e-4) return screen;
    final yUp = syUp * focal / denom;
    final x = sx * (focal + yUp * c) / focal;
    return Offset(pivot.dx + x, pivot.dy - yUp);
  }

  /// Desk point to screen, for the canvas. Null when the view is overhead, so
  /// the painter keeps its flat translate, rotate, and scale.
  Float64List? deskMatrix({
    required Offset origin,
    required double scale,
    required double angle,
  }) {
    if (isOverhead) return null;
    final c = math.cos(elevation);
    final s = math.sin(elevation);
    final px = pivot.dx;
    final py = pivot.dy;
    final f = focal;

    // Flat screen (u, v) to pitched screen. Rows of the homography.
    final h00 = f;
    final h01 = -(px * c);
    final h02 = px * c * py;
    final h11 = s * f - py * c;
    final h12 = py * (f * (1 - s) + c * py);
    final h21 = -c;
    final h22 = f + c * py;

    final rc = math.cos(angle);
    final rs = math.sin(angle);
    final a00 = scale * rc;
    final a01 = -scale * rs;
    final a02 = origin.dx;
    final a10 = scale * rs;
    final a11 = scale * rc;
    final a12 = origin.dy;

    final m = Float64List(16);
    // Row 0.
    m[0] = h00 * a00 + h01 * a10;
    m[4] = h00 * a01 + h01 * a11;
    m[12] = h00 * a02 + h01 * a12 + h02;
    // Row 1. The homography's first column is 0.
    m[1] = h11 * a10;
    m[5] = h11 * a11;
    m[13] = h11 * a12 + h12;
    // Row 3, the perspective row. Its first column is 0.
    m[3] = h21 * a10;
    m[7] = h21 * a11;
    m[15] = h21 * a12 + h22;
    m[10] = 1;
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is AsmrCutLens &&
      other.pivot == pivot &&
      other.focal == focal &&
      other.elevation == elevation;

  @override
  int get hashCode => Object.hash(pivot, focal, elevation);
}
