import 'dart:ui';

import '../rendering/ground_occlusion.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/scene.dart';
import 'models.dart';

/// Screen-space visibility of ink on a plane. Reuses the renderer's face
/// clipping, including crop boxes and ground openings, before projecting masks.
Path drawingVisibility(
  Scene scene,
  Camera camera,
  Size size,
  CraftPlane plane,
) {
  var visible = Path()..addRect(Offset.zero & size);
  final inkOrigin = plane.origin + plane.normal * .009;
  final towardCamera = plane.normal.dot(camera.position - inkOrigin) >= 0
      ? plane.normal
      : -plane.normal;
  final forward = camera.forward;
  for (final mesh in scene.meshes) {
    // Preview ghosts and translucent plane guides are not physical covers.
    if (!mesh.visible ||
        mesh.material.opacity < .35 ||
        mesh.id.startsWith('sticker-preview-')) {
      continue;
    }
    final transform = mesh.transformMatrix;
    for (final face in mesh.geometry.faces) {
      if (face.length < 3) continue;
      final vertices = [
        for (final i in face) transform.transformed3(mesh.geometry.vertices[i]),
      ];
      final normal = (vertices[1] - vertices[0]).cross(
        vertices[2] - vertices[0],
      );
      if (normal.length2 == 0) continue;
      final center =
          vertices.reduce((a, b) => a + b) / vertices.length.toDouble();
      if (!mesh.material.doubleSided &&
          normal.normalized().dot((camera.position - center).normalized()) <=
              -.15) {
        continue;
      }
      final cropped = mesh.cropBox?.clip(vertices) ?? vertices;
      final parts = mesh.groundOcclusion == null
          ? [cropped]
          : clipFaceToVisibleParts(camera, cropped, mesh.groundOcclusion!);
      for (final part in parts) {
        // A tiny separation keeps coplanar supporting faces from hiding ink.
        var front = clipPolygonHalfspace(
          part,
          inkOrigin + towardCamera * .0001,
          towardCamera,
          eps: 0,
        );
        front = clipPolygonHalfspace(
          front,
          camera.position + forward * camera.near,
          forward,
          eps: 0,
        );
        if (front.length < 3) continue;
        final points = [
          for (final vertex in front) camera.projectToScreen(vertex, size),
        ];
        if (points.any((p) => p == null)) continue;
        final cover = Path()..addPolygon(points.cast<Offset>(), true);
        visible = Path.combine(PathOperation.difference, visible, cover);
      }
    }
  }
  return visible;
}
