import 'dart:math' as math;

import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/map_look_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

MapLookCameraController _look() {
  final camera = Camera(
    name: 'yaw',
    position: Vector3(10, 20, 10),
    target: Vector3.zero(),
  );
  return MapLookCameraController(
    camera: camera,
    vsync: const TestVSync(),
    lookAt: Vector3.zero(),
    distance: 50,
    minDistance: 22,
    maxDistance: 100,
    ladderZoom: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('next corner from a diagonal stays on traditional corners', () {
    const rest = MapLookCameraController.defaultYaw;
    expect(mapLookNextCornerYaw(rest, 1), closeTo(rest + math.pi / 2, 1e-9));
    expect(mapLookNextCornerYaw(rest, -1), closeTo(rest - math.pi / 2, 1e-9));
    expect(
      mapLookNextCornerYaw(rest + 0.2, -1),
      closeTo(rest, 1e-9),
    );
  });

  test('one rotate aims at the next corner', () {
    final look = _look();
    addTearDown(look.dispose);
    final start = look.yaw;
    look.rotateClockwise();
    expect(look.targetYaw, closeTo(start - math.pi / 2, 1e-6));
  });

  test('a second click queues one more corner and keeps the first target', () {
    final look = _look();
    addTearDown(look.dispose);
    final start = look.yaw;
    look.rotateClockwise();
    look.rotateClockwise();
    expect(look.targetYaw, closeTo(start - math.pi, 1e-6));
  });

  test('a third rapid click does not queue a third corner', () {
    final look = _look();
    addTearDown(look.dispose);
    final start = look.yaw;
    look.rotateClockwise();
    look.rotateClockwise();
    look.rotateClockwise();
    expect(look.targetYaw, closeTo(start - math.pi, 1e-6));
  });

  test('opposite click retargets to the next corner the other way', () {
    final look = _look();
    addTearDown(look.dispose);
    final start = look.yaw;
    look.rotateClockwise();
    look.rotateCounterClockwise();
    expect(look.targetYaw, closeTo(start + math.pi / 2, 1e-6));
  });
}
