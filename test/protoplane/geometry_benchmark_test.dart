import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/protoplane/geometry_benchmark.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene_view.dart';

void main() {
  test('batches have exact counts, stay in map, and reset reproducibly', () {
    final benchmark = GeometryBenchmark()..add(wall: true);
    final first = benchmark.meshes.first.geometry.vertices.first.clone();
    benchmark.add(wall: false);
    expect(benchmark.walls, 100);
    expect(benchmark.volumes, 100);
    expect(benchmark.meshes.length, 200);
    expect(benchmark.meshes.map((m) => m.id).toSet().length, 200);
    for (final mesh in benchmark.meshes) {
      for (final p in mesh.geometry.vertices) {
        expect(p.x.abs(), lessThanOrEqualTo(16));
        expect(p.z.abs(), lessThanOrEqualTo(16));
      }
    }
    benchmark.expand();
    expect(benchmark.side, 64);
    expect(benchmark.meshes.length, 200);
    benchmark.reset();
    expect(benchmark.active, isFalse);
    expect(benchmark.side, 32);
    benchmark.add(wall: true);
    expect(benchmark.meshes.first.geometry.vertices.first, first);
  });

  test('renderer distinguishes on-screen, off-screen and hidden meshes', () {
    final benchmark = GeometryBenchmark()..add(wall: false);
    final scene = Scene()
      ..camera = Camera(
        name: 'test',
        position: Vector3(0, 15, 20),
        target: Vector3.zero(),
        up: Vector3(0, 1, 0),
        near: .1,
        far: 1000,
      );
    final onScreen = benchmark.ground;
    final offScreen = benchmark.meshes.first;
    for (final p in offScreen.geometry.vertices) {
      p.x += 10000;
    }
    final hidden = benchmark.meshes.last..visible = false;
    scene.setMeshes([onScreen, offScreen, hidden]);
    final recorder = ui.PictureRecorder();
    ScenePainter(scene: scene).paint(Canvas(recorder), const Size(400, 400));
    recorder.endRecording().dispose();
    expect(scene.paintStats!.meshes, 3);
    expect(scene.paintStats!.visibleMeshes, 2);
    expect(scene.paintStats!.viewportMeshes, 1);
    scene.dispose();
  });
}
