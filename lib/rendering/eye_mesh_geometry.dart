import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import 'iso/friend_expression.dart';

/// Shared 3D eye meshes for scene views (expression editor, previews, debug).
///
/// [FriendEyeGeometry3d.sphere] uses a lat/lon ellipsoid (legacy look).
/// [FriendEyeGeometry3d.cylinder] uses a capped cylinder along local +Z with
/// circular caps (triangle fans) and a smooth side strip — no sphere facets.
Geometry buildEyeMeshGeometry(
  String id,
  FriendEyeGeometry3d style,
  double rx,
  double ry,
  double rz,
) {
  switch (style) {
    case FriendEyeGeometry3d.sphere:
      return buildEllipsoidEyeGeometry(id, rx, ry, rz);
    case FriendEyeGeometry3d.cylinder:
      return buildCappedCylinderEyeGeometry(
        id,
        radius: rx,
        halfLength: ry,
      );
  }
}

/// UV-sphere style ellipsoid (same topology as previous inline builders).
Geometry buildEllipsoidEyeGeometry(String id, double rx, double ry, double rz) {
  const latSteps = 6;
  const lonSteps = 8;
  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  for (var lat = 0; lat <= latSteps; lat++) {
    final theta = math.pi * lat / latSteps;
    final sinTheta = math.sin(theta);
    final cosTheta = math.cos(theta);
    for (var lon = 0; lon <= lonSteps; lon++) {
      final phi = 2.0 * math.pi * lon / lonSteps;
      vertices.add(
        Vector3(
          rx * sinTheta * math.cos(phi),
          ry * cosTheta,
          rz * sinTheta * math.sin(phi),
        ),
      );
    }
  }

  for (var lat = 0; lat < latSteps; lat++) {
    for (var lon = 0; lon < lonSteps; lon++) {
      final a = lat * (lonSteps + 1) + lon;
      final b = a + lonSteps + 1;
      faces.add([a, b, b + 1]);
      faces.add([a, b + 1, a + 1]);
    }
  }

  return Geometry(id: id, name: id, vertices: vertices, faces: faces);
}

/// Right circular cylinder along local +Z: caps in XY planes at z = ±[halfLength].
///
/// [radius] is the circle radius; [halfLength] is half the extrusion (use
/// [eyeRadiusY] from [FriendExpressionConfig] so blink scales length).
Geometry buildCappedCylinderEyeGeometry(
  String id, {
  required double radius,
  required double halfLength,
  int segments = 40,
}) {
  final n = segments.clamp(8, 128);
  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  const bottomCenter = 0;
  vertices.add(Vector3(0, 0, -halfLength));

  for (var i = 0; i < n; i++) {
    final t = 2.0 * math.pi * i / n;
    vertices.add(
      Vector3(
        radius * math.cos(t),
        radius * math.sin(t),
        -halfLength,
      ),
    );
  }

  final topCenter = vertices.length;
  vertices.add(Vector3(0, 0, halfLength));

  final topRimStart = vertices.length;
  for (var i = 0; i < n; i++) {
    final t = 2.0 * math.pi * i / n;
    vertices.add(
      Vector3(
        radius * math.cos(t),
        radius * math.sin(t),
        halfLength,
      ),
    );
  }

  // Bottom cap (normal -Z): CCW from -Z is CW in +X/+Y in right-handed if
  // vertices go +angle — use order so normal points -Z.
  for (var i = 0; i < n; i++) {
    final i1 = 1 + i;
    final i2 = 1 + (i + 1) % n;
    faces.add([bottomCenter, i2, i1]);
  }

  // Top cap (normal +Z)
  for (var i = 0; i < n; i++) {
    final i1 = topRimStart + i;
    final i2 = topRimStart + (i + 1) % n;
    faces.add([topCenter, i1, i2]);
  }

  // Side quads → two triangles each, outward normal radial in XY
  for (var i = 0; i < n; i++) {
    final b0 = 1 + i;
    final b1 = 1 + (i + 1) % n;
    final t0 = topRimStart + i;
    final t1 = topRimStart + (i + 1) % n;
    faces.add([b0, b1, t1]);
    faces.add([b0, t1, t0]);
  }

  return Geometry(id: id, name: id, vertices: vertices, faces: faces);
}
