import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/scene/camera.dart';
import '../volumes/volume.dart';
import 'basement_spawn_mesh.dart';

/// Kept off while the door is the depth cue. Code stays wired for experiments.
const kBasementBlurVeilEnabled = false;

/// Default Gaussian sigma. Large enough to hide how far the ramp continues.
const kBasementBlurVeilSigma = 16.0;

/// Soft paper wash so the veil reads as a surface, not a raw smear.
const kBasementBlurVeilWash = Color(0x2EF4EFE6);

/// Skip projections that collapse to a line (edge-on / top-down).
const kBasementBlurVeilMinArea = 24.0;

/// Self-contained frosted portal: a world-space quad that blurs whatever
/// was already painted in its screen footprint.
///
/// Uses Flutter's Impeller/Skia [ui.ImageFilter.blur] via [BackdropFilter].
/// Pub wrappers (`blur`, `frosted_glass`, …) call the same filter and add
/// a full-screen layer unless clipped — they are not faster here.
@immutable
class BlurVeil {
  const BlurVeil({
    required this.corners,
    this.sigma = kBasementBlurVeilSigma,
    this.wash = kBasementBlurVeilWash,
  });

  /// Four world points, CCW when looking from +Z (south, down the ramp).
  final List<Vector3> corners;

  final double sigma;
  final Color wash;

  ui.ImageFilter get filter => ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      );

  Vector3 get center {
    final mid = Vector3.zero();
    for (final p in corners) {
      mid.add(p);
    }
    mid.scale(1 / corners.length);
    return mid;
  }

  /// Outward (+Z) for the basement door plane.
  Vector3 get normal {
    if (corners.length < 3) return Vector3(0, 0, 1);
    final n = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
    if (n.length2 < 1e-16) return Vector3(0, 0, 1);
    return n.normalized();
  }

  List<Offset>? project(Camera camera, Size viewport) {
    if (corners.length < 3 || viewport.width <= 0 || viewport.height <= 0) {
      return null;
    }
    final pts = <Offset>[];
    for (final p in corners) {
      final s = camera.projectToScreen(p, viewport);
      if (s == null) return null;
      pts.add(s);
    }
    if (_polygonArea(pts).abs() < kBasementBlurVeilMinArea) return null;
    return pts;
  }

  Path? clipPath(Camera camera, Size viewport) {
    final pts = project(camera, viewport);
    if (pts == null) return null;
    return Path()..addPolygon(pts, true);
  }
}

/// Door-plane veil on the shared edge of tiles (0,-1) and (0,-2).
///
/// Spans wall-to-wall and from Y=0 down to the ramp. The cut continues
/// past this plane; the blur makes that depth unreadable.
BlurVeil basementBlurVeil(VolumeGrid grid) {
  final z = grid.tileOrigin(0, -1).z;
  final x0 = grid.tileOrigin(0, 0).x;
  final x1 = x0 + grid.tileSize;
  final yFloor = basementRampHeight(grid, z);
  return BlurVeil(
    corners: [
      Vector3(x0, 0, z),
      Vector3(x0, yFloor, z),
      Vector3(x1, yFloor, z),
      Vector3(x1, 0, z),
    ],
  );
}

/// Clipped backdrop blur for one [BlurVeil]. Place after underground geo.
class BlurVeilOverlay extends StatelessWidget {
  const BlurVeilOverlay({
    super.key,
    required this.veil,
    required this.camera,
    required this.viewport,
    this.listenable,
  });

  final BlurVeil veil;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _build(),
      );
    }
    return _build();
  }

  Widget _build() {
    final pts = veil.project(camera, viewport);
    if (pts == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipPath(
        clipper: BlurVeilClipper(pts),
        clipBehavior: Clip.hardEdge,
        child: BackdropFilter(
          filter: veil.filter,
          child: ColoredBox(color: veil.wash),
        ),
      ),
    );
  }
}

class BlurVeilClipper extends CustomClipper<Path> {
  BlurVeilClipper(this.points);

  final List<Offset> points;

  @override
  Path getClip(Size size) => Path()..addPolygon(points, true);

  @override
  bool shouldReclip(covariant BlurVeilClipper oldClipper) {
    if (oldClipper.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (oldClipper.points[i] != points[i]) return true;
    }
    return false;
  }
}

double _polygonArea(List<Offset> pts) {
  var acc = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    acc += a.dx * b.dy - b.dx * a.dy;
  }
  return acc * 0.5;
}
