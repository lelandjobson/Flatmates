import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/rendering/surface_edge_shading.dart';

CraftPlane plane() => CraftPlane(
  id: 'test-plane',
  origin: Vector3.zero(),
  u: Vector3(1, 0, 0),
  v: Vector3(0, 0, -1),
  region: rectangle(1, 1),
  grids: [],
);

CraftObject paper(CraftPlane p, {Region? region, double depth = .08}) =>
    CraftObject(
      id: 'paper',
      planeId: p.id,
      kind: CraftKind.floor,
      region: region ?? rectangle(1, 1),
      material: PaperMaterial.white,
      depth: depth,
    );

Future<ui.Image> render(Scene scene, Size size) async {
  final recorder = ui.PictureRecorder();
  // Recording the real painter exercises projection, clipping and compositing.
  final target = ui.Canvas(recorder);
  target.drawColor(const ui.Color(0xff647082), ui.BlendMode.src);
  ScenePainter(
    scene: scene,
    debugOptions: const SceneDebugOptions(showWorldXyPlane: false),
  ).paint(target, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  return image;
}

double brightness(ByteData bytes, Size size, Offset point) {
  final x = point.dx.round().clamp(0, size.width.toInt() - 1);
  final y = point.dy.round().clamp(0, size.height.toInt() - 1);
  final index = (y * size.width.toInt() + x) * 4;
  return (bytes.getUint8(index) +
          bytes.getUint8(index + 1) +
          bytes.getUint8(index + 2)) /
      3;
}

void main() {
  testWidgets(
    'soft outer and hole edges leave centers, seams and cutouts unchanged',
    (tester) async {
      final p = plane();
      final object = paper(
        p,
        region: Region(rectangle(1, 1).outer, [
          rectangle(.3, .3, origin: const Offset(.35, .35)).outer,
        ]),
      );
      const size = Size(700, 700);
      final scene = Scene(globalIllumination: 1)
        ..camera = Camera(
          name: 'edge-test',
          position: Vector3(.5, 2, -.5),
          target: Vector3(.5, 0, -.5),
          up: Vector3(0, 0, -1),
          projection: ProjectionType.orthographic,
          orthographicScale: .65,
        );
      final cache = SurfaceEdgeShadingCache();
      addTearDown(scene.dispose);
      addTearDown(cache.dispose);
      final meshes = objectMeshes(object, p);
      scene.setMeshes(meshes);
      await tester.runAsync(() async {
        final before = await render(scene, size);
        cache.synchronize(meshes);
        final after = await render(scene, size);
        final a = (await before.toByteData())!, b = (await after.toByteData())!;
        double delta(Offset local) {
          final screen = scene.camera!.projectToScreen(
            p.point(local, .082),
            size,
          )!;
          return brightness(a, size, screen) - brightness(b, size, screen);
        }

        expect(delta(const Offset(.005, .2)), greaterThan(15));
        expect(delta(const Offset(.345, .5)), greaterThan(15));
        // Slab boundaries occur at hole x coordinates, but are not paper edges.
        expect(delta(const Offset(.35, .15)).abs(), lessThan(2));
        expect(delta(const Offset(.2, .2)).abs(), lessThan(2));
        expect(delta(const Offset(.5, .5)).abs(), lessThan(2));
        expect(delta(const Offset(1.025, .5)).abs(), lessThan(2));
        await File('/tmp/flatmates-edge-shading-top.png').writeAsBytes(
          (await after.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        before.dispose();
        after.dispose();
      });
    },
  );

  testWidgets(
    'rectangles share one mask through depth animation and camera movement',
    (tester) async {
      final cache = SurfaceEdgeShadingCache(), p = plane();
      addTearDown(cache.dispose);
      final scene = Scene(globalIllumination: .85)
        ..camera = Camera(
          name: 'edges',
          position: Vector3(1.4, 1.5, 1),
          target: Vector3(.5, 0, -.5),
        );
      addTearDown(scene.dispose);
      final times = <int>[];
      for (var frame = 0; frame < 90; frame++) {
        final meshes = objectMeshes(paper(p, depth: .04 + frame * .003), p);
        cache.synchronize(meshes);
        scene.setMeshes(meshes);
        scene.camera!.position.x += .001;
        final recorder = ui.PictureRecorder(), watch = Stopwatch()..start();
        ScenePainter(
          scene: scene,
          debugOptions: const SceneDebugOptions(showWorldXyPlane: false),
        ).paint(ui.Canvas(recorder), const Size(900, 700));
        times.add(watch.elapsedMicroseconds);
        recorder.endRecording().dispose();
        expect(
          meshes.single.edgeShades.length,
          meshes.single.geometry.faces.length,
        );
      }
      expect(cache.bakedMasks, 1);
      expect(cache.retainedBytes, 48 * 48 * 4);
      times.sort();
      // Timing reports CPU recording only, not GPU rasterization.
      // ignore: avoid_print
      print(
        'Edge shading CPU recording: median ${times[45]} us, p95 ${times[85]} us; 1 shared mask',
      );
      cache.synchronize([]);
      expect(cache.retainedBytes, 0);
    },
  );

  testWidgets(
    'irregular geometry reuse, edit invalidation and bounded resources',
    (tester) async {
      final cache = SurfaceEdgeShadingCache(), p = plane();
      addTearDown(cache.dispose);
      final shape = Region(const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, .4),
        Offset(.4, .4),
        Offset(.4, 1),
        Offset(0, 1),
      ]);
      cache.synchronize(objectMeshes(paper(p, region: shape), p));
      final baked = cache.bakedMasks;
      for (var i = 0; i < 20; i++) {
        cache.synchronize(
          objectMeshes(paper(p, region: shape), p, opacity: .1 + i * .04),
        );
      }
      expect(cache.bakedMasks, baked);
      expect(cache.retainedBytes, lessThanOrEqualTo(cache.maxBytes));
      cache.synchronize(objectMeshes(paper(p), p));
      expect(cache.retainedBytes, 48 * 48 * 4);
      final tiny = SurfaceEdgeShadingCache(maxBytes: 48 * 48 * 4);
      addTearDown(tiny.dispose);
      tiny.synchronize(objectMeshes(paper(p, region: shape), p));
      expect(tiny.retainedBytes, lessThanOrEqualTo(tiny.maxBytes));
      cache.clear();
      expect(cache.retainedBytes, 0);
    },
  );

  testWidgets('shading follows perspective and fades with paper opacity', (
    tester,
  ) async {
    final p = plane(), cache = SurfaceEdgeShadingCache();
    addTearDown(cache.dispose);
    const size = Size(900, 700);
    final scene = Scene(globalIllumination: .9)
      ..camera = Camera(
        name: 'perspective',
        position: Vector3(1.5, 1.5, 1),
        target: Vector3(.5, .1, -.5),
      );
    addTearDown(scene.dispose);
    final object = paper(
      p,
      depth: .18,
      region: Region(rectangle(1, 1).outer, [
        rectangle(.3, .3, origin: const Offset(.35, .35)).outer,
      ]),
    );
    await tester.runAsync(() async {
      ByteData? opaqueBefore, opaqueAfter;
      for (final opacity in [1.0, .08, 0.0]) {
        final meshes = objectMeshes(object, p, opacity: opacity);
        scene.setMeshes(meshes);
        final before = await render(scene, size);
        cache.synchronize(meshes);
        final after = await render(scene, size);
        final a = (await before.toByteData())!, b = (await after.toByteData())!;
        if (opacity == 1) {
          opaqueBefore = a;
          opaqueAfter = b;
          await File(
            '/tmp/flatmates-edge-shading-perspective.png',
          ).writeAsBytes(
            (await after.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
        } else if (opacity == 0) {
          expect(a.buffer.asUint8List(), b.buffer.asUint8List());
        } else {
          double total(ByteData x, ByteData y) {
            double result = 0;
            for (var i = 0; i < x.lengthInBytes; i += 4) {
              result += (x.getUint8(i) - y.getUint8(i)).abs();
            }
            return result;
          }

          expect(
            total(a, b),
            lessThan(total(opaqueBefore!, opaqueAfter!) * .4),
          );
        }
        before.dispose();
        after.dispose();
      }
    });
  });
}
