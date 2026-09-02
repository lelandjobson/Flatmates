import 'dart:math' as math;

import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/map_look_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const rest = MapLookCameraController.defaultPitch;
  const min = MapLookCameraController.defaultMinPitch;
  const max = MapLookCameraController.defaultMaxPitch;

  test('zero effort stays at rest pitch', () {
    expect(
      mapLookPitchFromEffort(rest: rest, min: min, max: max, effort: 0),
      rest,
    );
  });

  test('finite effort never reaches the ground or a true top-down', () {
    final high = mapLookPitchFromEffort(
      rest: rest,
      min: min,
      max: max,
      effort: 8,
    );
    final low = mapLookPitchFromEffort(
      rest: rest,
      min: min,
      max: max,
      effort: -8,
    );
    expect(high, lessThan(max));
    expect(high, greaterThan(rest));
    expect(low, greaterThan(min));
    expect(low, lessThan(rest));
    expect(high, lessThan(math.pi / 2));
    expect(low, greaterThan(0));
  });

  test('small effort is nearly 1:1 from rest', () {
    const effort = 0.04;
    final pitch = mapLookPitchFromEffort(
      rest: rest,
      min: min,
      max: max,
      effort: effort,
    );
    expect(pitch, closeTo(rest + effort, 0.003));
  });

  test('effort from pitch inverts the squash', () {
    for (final effort in [-1.2, -0.3, 0.0, 0.25, 1.6]) {
      final pitch = mapLookPitchFromEffort(
        rest: rest,
        min: min,
        max: max,
        effort: effort,
      );
      final back = lookPitchEffortFromPitch(
        rest: rest,
        min: min,
        max: max,
        pitch: pitch,
      );
      expect(back, closeTo(effort, 1e-6));
    }
  });

  test('dragging down orbits toward top-down at a fixed distance', () {
    final camera = Camera(
      name: 'pitch',
      position: Vector3(10, 20, 10),
      target: Vector3.zero(),
    );
    final look = MapLookCameraController(
      camera: camera,
      vsync: const TestVSync(),
      lookAt: Vector3.zero(),
      distance: 80,
      ladderZoom: false,
    );
    addTearDown(look.dispose);
    final before = look.distance;
    final restPitch = look.pitch;
    look.peekPitchByDeltaY(40);
    expect(look.pitch, greaterThan(restPitch));
    expect(look.distance, closeTo(before, 1e-6));
    final toTarget = camera.position - look.lookAt;
    expect(toTarget.length, closeTo(before, 1e-5));
  });
}
