import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/drawing_visibility.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/scene.dart';

void main() {
  test(
    'ink is covered only by visible foreground geometry, including partial covers',
    () {
      final scene = Scene();
      addTearDown(scene.dispose);
      final camera = Camera(
        name: 'test',
        position: Vector3(0, 8, 0),
        target: Vector3.zero(),
        up: Vector3(0, 0, -1),
      );
      const size = Size(400, 400);
      CraftPlane plane(String id, double height) => CraftPlane(
        id: id,
        origin: Vector3(0, height, 0),
        u: Vector3(1, 0, 0),
        v: Vector3(0, 0, -1),
        region: rectangle(2, 2, origin: const Offset(-1, -1)),
        grids: const [],
      );
      final paper = plane('ground-paper', 0);
      final behind = planeMesh(plane('ground-behind', -1));
      scene.setMeshes([planeMesh(paper), behind]);
      expect(
        drawingVisibility(
          scene,
          camera,
          size,
          paper,
        ).contains(const Offset(200, 200)),
        isTrue,
      );
      final cover = planeMesh(plane('ground-cover', 1));
      scene.addMesh(cover);
      var mask = drawingVisibility(scene, camera, size, paper);
      expect(mask.contains(const Offset(200, 200)), isFalse);
      expect(mask.contains(const Offset(20, 20)), isTrue);
      cover.visible = false;
      expect(
        drawingVisibility(
          scene,
          camera,
          size,
          paper,
        ).contains(const Offset(200, 200)),
        isTrue,
      );
      cover.visible = true;
      // A second overlapping cover must not reopen the masked region.
      scene.addMesh(planeMesh(plane('ground-second-cover', 2)));
      mask = drawingVisibility(scene, camera, size, paper);
      expect(mask.contains(const Offset(200, 200)), isFalse);
    },
  );
}
