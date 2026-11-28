import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/drawing_visibility.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart' show Region;
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/scene.dart';

void main() {
  testWidgets(
    'composited ink preserves background and holes under overlapping covers',
    (tester) async {
      await tester.runAsync(() async {
        final scene = Scene();
        final camera = Camera(
          name: 'mask',
          position: Vector3(0, 8, 0),
          target: Vector3.zero(),
          up: Vector3(0, 0, -1),
        );
        final paper = CraftPlane(
          id: 'paper',
          origin: Vector3.zero(),
          u: Vector3(1, 0, 0),
          v: Vector3(0, 0, -1),
          region: rectangle(2, 2, origin: const Offset(-1, -1)),
          grids: const [],
        );
        final cover = CraftPlane(
          id: 'ground-cover',
          origin: Vector3(0, 1, 0),
          u: paper.u,
          v: paper.v,
          region: Region(paper.region.outer, [
            rectangle(.5, .5, origin: const Offset(-.25, -.25)).outer,
          ]),
          grids: const [],
        );
        scene.setMeshes([
          planeMesh(cover),
          planeMesh(cover)..setScale(Vector3(-1, 1, 1)),
        ]);
        const size = Size(400, 400);
        final recorder = PictureRecorder();
        // Use a separate ink layer so erasing ink cannot erase the world.
        final output = Canvas(recorder);
        output.drawColor(const Color(0xff0000ff), BlendMode.src);
        output.saveLayer(Offset.zero & size, Paint());
        output.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xffff0000),
        );
        output.drawPath(
          drawingOcclusion(scene, camera, size, paper),
          Paint()..blendMode = BlendMode.clear,
        );
        output.restore();
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final bytes = (await image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!;
        int red(Offset p) =>
            bytes.getUint8((p.dy.floor() * 400 + p.dx.floor()) * 4);
        expect(red(const Offset(200, 200)), 255);
        expect(
          red(camera.projectToScreen(cover.point(const Offset(.7, 0)), size)!),
          0,
        );
        expect(red(const Offset(20, 20)), 255);
        image.dispose();
        picture.dispose();
        scene.dispose();
      });
    },
  );
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
      scene.addMesh(
        planeMesh(plane('ground-second-cover', 2))..setScale(Vector3(-1, 1, 1)),
      );
      mask = drawingVisibility(scene, camera, size, paper);
      expect(mask.contains(const Offset(200, 200)), isFalse);
      final ring = CraftPlane(
        id: 'ground-ring',
        origin: Vector3(0, 1, 0),
        u: paper.u,
        v: paper.v,
        region: Region(paper.region.outer, [
          rectangle(.5, .5, origin: const Offset(-.25, -.25)).outer,
        ]),
        grids: const [],
      );
      scene.setMeshes([planeMesh(ring)]);
      mask = drawingVisibility(scene, camera, size, paper);
      expect(
        mask.contains(const Offset(200, 200)),
        isTrue,
        reason: 'A hole stays open',
      );
      expect(
        mask.contains(
          camera.projectToScreen(ring.point(const Offset(.7, 0)), size)!,
        ),
        isFalse,
      );
    },
  );
}
