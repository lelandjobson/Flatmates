import 'dart:math' as math;

import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/map_look_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

MapLookCameraController _look({double distance = 50}) {
  final camera = Camera(
    name: 'zoom',
    position: Vector3(10, 20, 10),
    target: Vector3.zero(),
  );
  return MapLookCameraController(
    camera: camera,
    vsync: const TestVSync(),
    lookAt: Vector3.zero(),
    distance: distance,
    minDistance: 22,
    maxDistance: 100,
    ladderZoom: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scroll zoom is slower than the old 0.0025 sensitivity', () {
    final look = _look();
    addTearDown(look.dispose);
    look.zoomByScroll(80);
    expect(
      look.distance,
      closeTo(50 * math.exp(80 * look.zoomSensitivity), 1e-6),
    );
    expect(look.zoomSensitivity, lessThan(0.0025));
    expect(look.distance, lessThan(50 * math.exp(80 * 0.0025)));
  });

  test('endZoom stops at the last live distance', () {
    final look = _look();
    addTearDown(look.dispose);
    look.zoomByScroll(80);
    final afterScroll = look.distance;
    look.endZoom();
    expect(look.targetDistance, closeTo(afterScroll, 1e-6));
  });

  test('animateDistance springs toward a look-inside radius', () {
    final look = _look(distance: 42);
    addTearDown(look.dispose);
    look.animateDistance(26);
    expect(look.targetDistance, 26);
  });
}
