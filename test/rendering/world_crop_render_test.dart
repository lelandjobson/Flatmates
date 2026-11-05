import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/geometry/geometry.dart';
import 'package:flatmates/rendering/mesh.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/planar_texture.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/rendering/world_crop_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'crop trims faces and atlas sprites while preserving atlas transparency',
    () async {
      final atlasRecorder = ui.PictureRecorder();
      final atlasCanvas = Canvas(atlasRecorder);
      atlasCanvas.drawRect(
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint()..color = Colors.green,
      );
      atlasCanvas.drawRect(
        const Rect.fromLTWH(4, 4, 8, 8),
        Paint()..blendMode = BlendMode.clear,
      );
      final atlasPicture = atlasRecorder.endRecording();
      final atlas = PlanarTextureAtlas()
        ..replace(await atlasPicture.toImage(32, 32));
      addTearDown(() {
        atlas.dispose();
        atlasPicture.dispose();
      });
      const size = Size(200, 200);
      final camera = Camera(name: 'crop', position: Vector3(0, 0, 3));
      for (final textured in [false, true]) {
        final mesh = Mesh(
          id: 'paper',
          name: 'paper',
          groundPlane: true,
          geometry: Geometry(
            id: 'quad',
            name: 'quad',
            colorSeed: 1,
            vertices: [
              Vector3(-1, -1, 0),
              Vector3(1, -1, 0),
              Vector3(1, 1, 0),
              Vector3(-1, 1, 0),
            ],
            faces: [
              [0, 1, 2, 3],
            ],
          ),
          material: MaterialModel(
            color: Colors.red,
            doubleSided: true,
            strokeEdges: false,
          ),
          planarTexture: textured
              ? PlanarTexture(
                  origin: Vector3.zero(),
                  u: Vector3(1, 0, 0),
                  v: Vector3(0, 1, 0),
                  bounds: const Rect.fromLTWH(-1, -1, 2, 2),
                  source: const Rect.fromLTWH(0, 0, 32, 32),
                  atlas: atlas,
                )
              : null,
        )..cropBox = WorldCropBox(Vector3(-1, -1, -.1), Vector3(0, 1, .1));
        final scene = Scene(globalIllumination: 1)
          ..camera = camera
          ..addMesh(mesh);
        final recorder = ui.PictureRecorder();
        ScenePainter(scene: scene).paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 200);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        List<int> pixel(double x, double y) {
          final p = camera.projectToScreen(Vector3(x, y, 0), size)!;
          final index = (p.dy.floor() * 200 + p.dx.floor()) * 4;
          return List.generate(4, (i) => bytes.getUint8(index + i));
        }

        expect(pixel(.5, .5)[3], 0, reason: 'Outside crop box');
        expect(pixel(-.5, .5)[3], 255);
        if (textured) {
          expect(
            pixel(-.5, .5)[1],
            greaterThan(pixel(-.5, .5)[0]),
            reason: 'Atlas remains green',
          );
          expect(
            pixel(-.5, -.5)[3],
            0,
            reason: 'A cut in the atlas remains transparent',
          );
        } else {
          expect(pixel(-.5, .5)[0], greaterThan(pixel(-.5, .5)[1]));
        }
        image.dispose();
        picture.dispose();
        scene.dispose();
      }
    },
  );
}
