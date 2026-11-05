import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'layered_terrain_test.dart' show centerId;
import 'package:flatmates/protoplane/models.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/pencil_rendering.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:vector_math/vector_math_64.dart';
import 'edge_shading_test.dart' as fixture;

void main() {
  testWidgets('landscape atlas renders darker focused marks without rebaking', (
    tester,
  ) async {
    final c = ProtoplaneController();
    final atlas = HarvestMeshCache(), cache = PencilTextureCache();
    addTearDown(c.dispose);
    addTearDown(atlas.dispose);
    addTearDown(cache.dispose);
    final id = centerId(c, PaperMaterial.paperWhite);
    final p = c.planes[id]!;
    atlas.synchronize(c.planes.values, c.landscape);
    final mesh = atlas.mesh(p, c.landscape)..groundPlane = true;
    final center = p.point(const ui.Offset(.5, .5));
    final scene = Scene(globalIllumination: 1)
      ..camera = Camera(
        name: 'terrain-pencil',
        position: center + Vector3(0, 2, 0),
        target: center,
        up: Vector3(0, 0, -1),
        projection: ProjectionType.orthographic,
        orthographicScale: .65,
      );
    scene.setMeshes([mesh]);
    addTearDown(scene.dispose);
    const size = ui.Size(700, 700);
    await tester.runAsync(() async {
      final blank = await fixture.render(scene, size);
      cache.attach(
        [mesh],
        p,
        p.region,
        .001,
        PencilMotif.crosshatch.segments(),
        opacity: .35,
      );
      final world = await fixture.render(scene, size);
      mesh.pencilOpacity = .8;
      final focused = await fixture.render(scene, size);
      final point = scene.camera!.projectToScreen(
        p.point(const ui.Offset(.25, .15)),
        size,
      )!;
      final a = fixture.brightness((await blank.toByteData())!, size, point);
      final b = fixture.brightness((await world.toByteData())!, size, point);
      final d = fixture.brightness((await focused.toByteData())!, size, point);
      expect(a - b, greaterThan(5));
      expect(b - d, greaterThan(5));
      final bakes = cache.bakeCount, rasterized = atlas.rasterizedTiles;
      scene.camera!.position.x += .1;
      cache.beginFrame();
      cache.attach(
        [mesh],
        p,
        p.region,
        .001,
        PencilMotif.crosshatch.segments(),
        opacity: .35,
      );
      atlas.synchronize(c.planes.values, c.landscape);
      expect(cache.bakeCount, bakes);
      expect(atlas.rasterizedTiles, rasterized);
      for (final image in [blank, world, focused]) {
        image.dispose();
      }
    });
  });

  testWidgets(
    'marks respect holes, face depth, opacity, perspective and camera cache',
    (tester) async {
      final p = fixture.plane(), cache = PencilTextureCache();
      final region = Region(rectangle(1, 1).outer, [
        rectangle(.3, .3, origin: const ui.Offset(.35, .35)).outer,
      ]);
      final o = fixture.paper(p, region: region);
      final meshes = objectMeshes(o, p);
      final scene = Scene(globalIllumination: 1)
        ..camera = Camera(
          name: 'pencil',
          position: Vector3(.5, 2, -.5),
          target: Vector3(.5, 0, -.5),
          up: Vector3(0, 0, -1),
          projection: ProjectionType.orthographic,
          orthographicScale: .65,
        );
      scene.setMeshes(meshes);
      addTearDown(scene.dispose);
      addTearDown(cache.dispose);
      final marks = clipPencil(PencilMotif.crosshatch.segments(), region);
      const size = ui.Size(700, 700);
      await tester.runAsync(() async {
        final blank = await fixture.render(scene, size);
        cache.attach(meshes, p, region, .082, marks, opacity: .35);
        expect(meshes.single.pencilShades, isNotEmpty);
        final world = await fixture.render(scene, size);
        meshes.single.pencilOpacity = .8;
        final crafting = await fixture.render(scene, size);
        final a = (await blank.toByteData())!,
            b = (await world.toByteData())!,
            c = (await crafting.toByteData())!;
        double sample(bytes, ui.Offset at) => fixture.brightness(
          bytes,
          size,
          scene.camera!.projectToScreen(p.point(at, .082), size)!,
        );
        const line = ui.Offset(.25, .15), hole = ui.Offset(.5, .5);
        expect(sample(a, line) - sample(b, line), greaterThan(5));
        expect(sample(b, line) - sample(c, line), greaterThan(5));
        expect((sample(a, hole) - sample(c, hole)).abs(), lessThan(1));
        final bakes = cache.bakeCount;
        for (var i = 0; i < 10; i++) {
          scene.camera!.position.x += .02;
          cache.beginFrame();
          cache.attach(meshes, p, region, .082, marks, opacity: .35);
        }
        expect(cache.bakeCount, bakes);
        expect(cache.retainedBytes, lessThanOrEqualTo(8 * 1024 * 1024));
        scene.camera!.projection = ProjectionType.perspective;
        scene.camera!.position.setValues(1.3, 1.5, 1.1);
        scene.camera!.setTarget(Vector3(.5, 0, -.5));
        final perspective = await fixture.render(scene, size);
        await File('/tmp/flatmates-pencil-crafting.png').writeAsBytes(
          (await crafting.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        await File('/tmp/flatmates-pencil-perspective.png').writeAsBytes(
          (await perspective.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        for (final image in [blank, world, crafting, perspective]) {
          image.dispose();
        }
      });
    },
  );
}
