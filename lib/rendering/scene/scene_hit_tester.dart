import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';
import 'scene.dart';

class FocusedFace {
  const FocusedFace({
    required this.meshId,
    required this.faceIndex,
    required this.center,
    required this.normal,
    required this.extent,
  });

  final String meshId;
  final int faceIndex;
  final Vector3 center;
  final Vector3 normal;
  final double extent;
}

class SceneHitTester {
  SceneHitTester({
    required Scene scene,
    required Camera camera,
    required this.viewportSize,
  }) : _scene = scene,
       _camera = camera;

  final Scene _scene;
  final Camera _camera;
  final Size viewportSize;

  FocusedFace? hitTest(Offset position) {
    final all = hitTestAll(position);
    return all.isEmpty ? null : all.first;
  }

  /// Return every face hit along the ray, sorted nearest-to-farthest.
  List<FocusedFace> hitTestAll(Offset position) {
    final ray = _buildRay(position);
    if (ray == null) {
      return const [];
    }

    final hits = <(double, FocusedFace)>[];

    for (final mesh in _scene.meshes) {
      final world = mesh.transformMatrix;
      final isDoubleSided = mesh.material.doubleSided;

      for (
        var faceIndex = 0;
        faceIndex < mesh.geometry.faces.length;
        faceIndex++
      ) {
        final face = mesh.geometry.faces[faceIndex];
        if (face.length < 3) continue;

        final worldVertices = <Vector3>[];
        for (final index in face) {
          final localVertex = mesh.geometry.vertices[index];
          final worldPos = Vector3.copy(localVertex);
          world.transform3(worldPos);
          worldVertices.add(worldPos);
        }

        final intersection = _intersectFace(
          ray: ray,
          vertices: worldVertices,
          isDoubleSided: isDoubleSided,
        );
        if (intersection == null) {
          continue;
        }

        hits.add((
          intersection.distance,
          FocusedFace(
            meshId: mesh.id,
            faceIndex: faceIndex,
            center: intersection.center,
            normal: intersection.normal,
            extent: intersection.extent,
          ),
        ));
      }
    }

    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return hits.map((h) => h.$2).toList();
  }

  _Ray? _buildRay(Offset position) {
    final width = viewportSize.width;
    final height = viewportSize.height;
    if (width <= 0 || height <= 0) {
      return null;
    }
    final projection = _camera.projectionMatrix(width / height);
    final view = _camera.viewMatrix;
    final viewProjection = projection * view;
    final inverted = Matrix4.copy(viewProjection);
    final determinant = inverted.invert();
    if (determinant == 0) {
      return null;
    }
    final ndcX = (position.dx / width) * 2 - 1;
    final ndcY = 1 - (position.dy / height) * 2;
    final nearClip = Vector4(ndcX, ndcY, -1, 1);
    final farClip = Vector4(ndcX, ndcY, 1, 1);
    final worldNear = _transformVector4(inverted, nearClip);
    final worldFar = _transformVector4(inverted, farClip);
    if (worldNear.w.abs() <= 1e-6 || worldFar.w.abs() <= 1e-6) {
      return null;
    }
    final nearPoint = Vector3(
      worldNear.x / worldNear.w,
      worldNear.y / worldNear.w,
      worldNear.z / worldNear.w,
    );
    final farPoint = Vector3(
      worldFar.x / worldFar.w,
      worldFar.y / worldFar.w,
      worldFar.z / worldFar.w,
    );
    final direction = (farPoint - nearPoint);
    if (direction.length2 <= 1e-8) {
      return null;
    }
    direction.normalize();
    return _Ray(origin: nearPoint, direction: direction);
  }
}

Vector3 _faceNormal(List<Vector3> vertices) {
  if (vertices.length < 3) {
    return Vector3.zero();
  }
  final a = vertices[0];
  final b = vertices[1];
  final c = vertices[2];
  final normal = (b - a).cross(c - a);
  if (normal.length2 == 0) {
    return Vector3.zero();
  }
  return normal.normalized();
}

Vector3 _faceCentroid(List<Vector3> vertices) {
  final centroid = Vector3.zero();
  for (final vertex in vertices) {
    centroid.add(vertex);
  }
  centroid.scale(1 / vertices.length);
  return centroid;
}

double _maxDistance(List<Vector3> vertices, Vector3 center) {
  var maxDistance = 0.0;
  for (final vertex in vertices) {
    final distance = (vertex - center).length;
    if (distance > maxDistance) {
      maxDistance = distance;
    }
  }
  return maxDistance;
}
class _Ray {
  _Ray({required this.origin, required this.direction});

  final Vector3 origin;
  final Vector3 direction;
}

class _FaceIntersection {
  _FaceIntersection({
    required this.distance,
    required this.center,
    required this.normal,
    required this.extent,
  });

  final double distance;
  final Vector3 center;
  final Vector3 normal;
  final double extent;
}

_FaceIntersection? _intersectFace({
  required _Ray ray,
  required List<Vector3> vertices,
  required bool isDoubleSided,
}) {
  if (vertices.length < 3) {
    return null;
  }
  final normal = _faceNormal(vertices);
  final center = _faceCentroid(vertices);
  final extent = _maxDistance(vertices, center);

  final v0 = vertices[0];
  double? bestDistance;
  for (var i = 1; i < vertices.length - 1; i++) {
    final v1 = vertices[i];
    final v2 = vertices[i + 1];
    final t = _rayTriangleIntersection(ray, v0, v1, v2);
    if (t == null) {
      continue;
    }
    if (!isDoubleSided && normal.dot(ray.direction) > 0) {
      continue;
    }
    if (t <= 0) {
      continue;
    }
    if (bestDistance == null || t < bestDistance) {
      bestDistance = t;
    }
  }
  if (bestDistance == null) {
    return null;
  }
  final facingNormal =
      normal.dot(ray.direction) < 0 ? normal : -normal;
  return _FaceIntersection(
    distance: bestDistance,
    center: center,
    normal: facingNormal,
    extent: extent,
  );
}

double? _rayTriangleIntersection(_Ray ray, Vector3 v0, Vector3 v1, Vector3 v2) {
  const epsilon = 1e-7;
  final edge1 = v1 - v0;
  final edge2 = v2 - v0;
  final pvec = ray.direction.cross(edge2);
  final det = edge1.dot(pvec);
  if (det.abs() < epsilon) {
    return null;
  }
  final invDet = 1.0 / det;
  final tvec = ray.origin - v0;
  final u = tvec.dot(pvec) * invDet;
  if (u < 0 || u > 1) {
    return null;
  }
  final qvec = tvec.cross(edge1);
  final v = ray.direction.dot(qvec) * invDet;
  if (v < 0 || u + v > 1) {
    return null;
  }
  final t = edge2.dot(qvec) * invDet;
  if (t <= epsilon) {
    return null;
  }
  return t;
}
Vector4 _transformVector4(Matrix4 matrix, Vector4 vector) {
  final storage = matrix.storage;
  final x = vector.x;
  final y = vector.y;
  final z = vector.z;
  final w = vector.w;
  return Vector4(
    storage[0] * x + storage[4] * y + storage[8] * z + storage[12] * w,
    storage[1] * x + storage[5] * y + storage[9] * z + storage[13] * w,
    storage[2] * x + storage[6] * y + storage[10] * z + storage[14] * w,
    storage[3] * x + storage[7] * y + storage[11] * z + storage[15] * w,
  );
}
