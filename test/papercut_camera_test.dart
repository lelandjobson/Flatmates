import 'dart:math' as math;

import 'package:flatmates/papercut/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  Vector3 turntable(double turn, double tilt) => Vector3(
    math.cos(turn) * math.cos(tilt),
    math.sin(turn) * math.cos(tilt),
    math.sin(tilt),
  );

  PapercutCamera orbiting(Vector3 direction) {
    final camera = PapercutCamera()
      ..setFocal(PapercutCamera.perspectiveFocalMm);
    camera.orbitTo(direction, up: Vector3(0, 0, 1));
    return camera;
  }

  void expectSmoothFlight(PapercutCamera camera, Vector3 normal) {
    final start = camera.camera.up.normalized();
    camera.flyTo(Vector3(0, 0, 10), normal, 300);
    var last = camera.camera.up.normalized();
    var lastView = camera.viewDirection;
    for (var i = 1; i <= 120; i++) {
      camera.setFly(i / 120);
      final up = camera.camera.up.normalized();
      final view = camera.viewDirection;
      expect(up.dot(last), greaterThan(math.cos(4 * math.pi / 180)));
      expect(view.dot(lastView), greaterThan(math.cos(4 * math.pi / 180)));
      last = up;
      lastView = view;
    }
    expect(camera.viewDirection.dot(normal.normalized()), closeTo(1, 1e-6));
    expect(last.dot(normal), closeTo(0, 1e-6));
    expect(last.dot(start), greaterThan(0.5));
  }

  test('focusing a face on the orbit pole keeps screen-up', () {
    final camera = orbiting(turntable(-math.pi / 2 + 0.6, 0.4));
    expectSmoothFlight(camera, Vector3(0, -1, 0));
  });

  test('focusing each cube face turns without a flip', () {
    for (final normal in [
      Vector3(1, 0, 0),
      Vector3(-1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, 1),
    ]) {
      final camera = orbiting(
        (normal + turntable(0.9, 0.35) * 0.6).normalized(),
      );
      expectSmoothFlight(camera, normal);
    }
  });

  test('a flight back to the room stays upright', () {
    final room = turntable(-math.pi / 2, 32 * math.pi / 180);
    for (final turn in [0.2, 1.1, 2.4, 3.5, -0.8]) {
      final camera = orbiting(turntable(turn, 0.9));
      final start = math.acos(camera.camera.up.z.clamp(-1.0, 1.0));
      camera.beginFly(
        camera.poseFacing(
          Vector3(40, -20, 12),
          room,
          800,
          up: Vector3(0, 0, 1),
        ),
        turn: true,
      );
      for (var i = 0; i <= 60; i++) {
        camera.setFly(i / 60);
        final lean = math.acos(camera.camera.up.z.clamp(-1.0, 1.0));
        expect(lean, lessThan(start + 4 * math.pi / 180));
      }
    }
  });

  test('carrying a view through a yaw keeps its up', () {
    final camera = orbiting(turntable(0.4, 0.5));
    final yaw = Matrix4.rotationZ(0.7).getRotation();
    final direction = yaw.transformed(camera.viewDirection).normalized();
    final up = yaw.transformed(camera.camera.up).normalized();
    camera.orbitTo(direction, up: up);
    expect(camera.camera.up.normalized().dot(up), closeTo(1, 1e-6));
  });

  test('upAlong adds no roll of its own', () {
    final camera = orbiting(turntable(0.3, 0.2));
    final up = camera.upAlong(camera.viewDirection);
    expect(up.dot(camera.camera.up.normalized()), closeTo(1, 1e-9));
    for (final direction in [
      turntable(1.4, 0.7),
      turntable(-2.0, -0.3),
      Vector3(0, 1, 0),
    ]) {
      expect(camera.upAlong(direction).dot(direction), closeTo(0, 1e-9));
    }
  });
}
