import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import 'camera.dart';
import 'scene.dart';
import 'scene_hit_tester.dart';

/// Angular + center-zone face picker for "what face am I looking at?"
///
/// Ranking currently uses screen-center proximity only; [kFaceDistanceWeight]
/// is reserved for a future distance term.
const double kFaceAngularToleranceDeg = 35;
const double kFaceCenterZoneInset = 0.25;
const double kFaceDistanceWeight = 0.0;
const double kFaceScreenCenterWeight = 1.0;

class FaceFocusPicker {
  const FaceFocusPicker({
    this.angularToleranceDeg = kFaceAngularToleranceDeg,
    this.centerZoneInset = kFaceCenterZoneInset,
    this.distanceWeight = kFaceDistanceWeight,
    this.screenCenterWeight = kFaceScreenCenterWeight,
  });

  final double angularToleranceDeg;
  final double centerZoneInset;
  final double distanceWeight;
  final double screenCenterWeight;

  FocusedFace? pick({
    required Scene scene,
    required Camera camera,
    required Size viewportSize,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return null;
    }

    final aspect = viewportSize.width / viewportSize.height;
    final viewProjection = camera.projectionMatrix(aspect) * camera.viewMatrix;
    final screenCenter = Offset(
      viewportSize.width * 0.5,
      viewportSize.height * 0.5,
    );
    final inset = centerZoneInset.clamp(0.0, 0.49);
    final zone = Rect.fromLTRB(
      viewportSize.width * inset,
      viewportSize.height * inset,
      viewportSize.width * (1 - inset),
      viewportSize.height * (1 - inset),
    );

    final cosTol = math.cos(angularToleranceDeg * math.pi / 180);
    final camForward = camera.forward;
    final camPos = camera.position;

    FocusedFace? best;
    var bestScore = double.infinity;

    for (final mesh in scene.meshes) {
      final world = mesh.transformMatrix;
      for (var faceIndex = 0; faceIndex < mesh.geometry.faces.length; faceIndex++) {
        final face = mesh.geometry.faces[faceIndex];
        if (face.length < 3) continue;

        final worldVerts = <Vector3>[];
        for (final index in face) {
          final local = mesh.geometry.vertices[index];
          final wp = Vector3.copy(local);
          world.transform3(wp);
          worldVerts.add(wp);
        }

        final center = _centroid(worldVerts);
        final normal = _faceNormal(worldVerts);
        if (normal.length2 <= 1e-10) continue;

        // Front-facing relative to camera.
        final toCamera = (camPos - center)..normalize();
        if (normal.dot(toCamera) <= 0) continue;

        // Angular: face normal roughly anti-aligned with camera look.
        final facing = (-normal).dot(camForward);
        if (facing < cosTol) continue;

        final screen = _projectToScreen(center, viewProjection, viewportSize);
        if (screen == null || !zone.contains(screen)) continue;

        final screenDist = (screen - screenCenter).distance;
        final camDist = (center - camPos).length;
        final score =
            screenDist * screenCenterWeight + camDist * distanceWeight;

        if (score < bestScore) {
          bestScore = score;
          best = FocusedFace(
            meshId: mesh.id,
            faceIndex: faceIndex,
            center: center,
            normal: normal,
            extent: _extent(worldVerts, center),
          );
        }
      }
    }

    return best;
  }

  /// World-space edge segments for [face] on [mesh].
  static List<(Vector3, Vector3)> faceWorldEdges(Mesh mesh, int faceIndex) {
    if (faceIndex < 0 || faceIndex >= mesh.geometry.faces.length) {
      return const [];
    }
    final face = mesh.geometry.faces[faceIndex];
    if (face.length < 2) return const [];
    final world = mesh.transformMatrix;
    final verts = <Vector3>[];
    for (final index in face) {
      final wp = Vector3.copy(mesh.geometry.vertices[index]);
      world.transform3(wp);
      verts.add(wp);
    }
    final edges = <(Vector3, Vector3)>[];
    for (var i = 0; i < verts.length; i++) {
      edges.add((verts[i], verts[(i + 1) % verts.length]));
    }
    return edges;
  }
}

Vector3 _centroid(List<Vector3> verts) {
  final c = Vector3.zero();
  for (final v in verts) {
    c.add(v);
  }
  if (verts.isNotEmpty) {
    c.scale(1.0 / verts.length);
  }
  return c;
}

Vector3 _faceNormal(List<Vector3> verts) {
  if (verts.length < 3) return Vector3.zero();
  final n = (verts[1] - verts[0]).cross(verts[2] - verts[0]);
  if (n.length2 <= 1e-12) return Vector3.zero();
  return n.normalized();
}

double _extent(List<Vector3> verts, Vector3 center) {
  var maxR = 0.0;
  for (final v in verts) {
    final d = (v - center).length;
    if (d > maxR) maxR = d;
  }
  return maxR * 2;
}

Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
  final clip = Vector4(worldPos.x, worldPos.y, worldPos.z, 1);
  mvp.transform(clip);
  if (clip.w.abs() <= 1e-6) return null;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (!ndcX.isFinite || !ndcY.isFinite) return null;
  return Offset(
    (ndcX * 0.5 + 0.5) * size.width,
    (1 - (ndcY * 0.5 + 0.5)) * size.height,
  );
}
