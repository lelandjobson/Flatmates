import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../mesh.dart';
import 'camera.dart';
import 'scene.dart';
import 'scene_hit_tester.dart';

/// Center-screen raycast object picker. Among hits, nearest (shortest ray) wins —
/// [SceneHitTester.hitTestAll] already sorts nearest-first.
class ObjectFocusPicker {
  const ObjectFocusPicker();

  /// Nearest face hit under the viewport center, or null if nothing is hit.
  FocusedFace? pick({
    required Scene scene,
    required Camera camera,
    required Size viewportSize,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return null;
    }
    final center = Offset(
      viewportSize.width * 0.5,
      viewportSize.height * 0.5,
    );
    return SceneHitTester(
      scene: scene,
      camera: camera,
      viewportSize: viewportSize,
    ).hitTest(center);
  }

  /// Mesh id of the nearest center-ray hit, or null.
  String? pickMeshId({
    required Scene scene,
    required Camera camera,
    required Size viewportSize,
  }) =>
      pick(scene: scene, camera: camera, viewportSize: viewportSize)?.meshId;

  /// Silhouette edges of [mesh] as seen from [cameraPosition] (world space).
  /// Falls back to all unique edges if silhouette detection finds none.
  static List<(Vector3, Vector3)> meshOutlineEdges(
    Mesh mesh,
    Vector3 cameraPosition,
  ) {
    final geometry = mesh.geometry;
    final world = mesh.transformMatrix;

    // Edge key → adjacent face indices
    final edgeFaces = <_UndirectedEdge, List<int>>{};
    for (var fi = 0; fi < geometry.faces.length; fi++) {
      final face = geometry.faces[fi];
      for (var i = 0; i < face.length; i++) {
        final a = face[i];
        final b = face[(i + 1) % face.length];
        final key = _UndirectedEdge(a, b);
        edgeFaces.putIfAbsent(key, () => <int>[]).add(fi);
      }
    }

    final faceFront = List<bool>.generate(geometry.faces.length, (fi) {
      final face = geometry.faces[fi];
      if (face.length < 3) return false;
      final verts = <Vector3>[];
      for (final idx in face) {
        final wp = Vector3.copy(geometry.vertices[idx]);
        world.transform3(wp);
        verts.add(wp);
      }
      final center = Vector3.zero();
      for (final v in verts) {
        center.add(v);
      }
      center.scale(1.0 / verts.length);
      final n = (verts[1] - verts[0]).cross(verts[2] - verts[0]);
      if (n.length2 <= 1e-12) return false;
      n.normalize();
      return n.dot(cameraPosition - center) > 0;
    });

    final silhouette = <(Vector3, Vector3)>[];
    final allEdges = <(Vector3, Vector3)>[];

    for (final entry in edgeFaces.entries) {
      final a = Vector3.copy(geometry.vertices[entry.key.a]);
      final b = Vector3.copy(geometry.vertices[entry.key.b]);
      world.transform3(a);
      world.transform3(b);
      allEdges.add((a, b));

      final faces = entry.value;
      if (faces.length == 1) {
        silhouette.add((a, b));
        continue;
      }
      if (faces.length >= 2) {
        final f0 = faceFront[faces[0]];
        final f1 = faceFront[faces[1]];
        if (f0 != f1) {
          silhouette.add((a, b));
        }
      }
    }

    return silhouette.isNotEmpty ? silhouette : allEdges;
  }
}

class _UndirectedEdge {
  _UndirectedEdge(int a, int b)
      : a = a < b ? a : b,
        b = a < b ? b : a;

  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is _UndirectedEdge && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
