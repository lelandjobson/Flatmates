import 'dart:convert';
import 'dart:io';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/cube_blueprint.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('the authored cube matches the builder rings and fold edges', () {
    final raw = File('levels/cube/cube.json').readAsStringSync();
    final authored = GridBlueprint.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final built = cubeBlueprint();

    expect(authored.id, built.id);
    expect(authored.name, built.name);
    expect(authored.steps, hasLength(1));
    expect(built.steps, hasLength(1));
    final left = authored.steps.single;
    final right = built.steps.single;
    expect(left.id, right.id);
    expect(left.gridSpacing, 1);
    expect(left.paperMargin, 2);
    expect(left.polygons, hasLength(right.polygons.length));
    for (var i = 0; i < right.polygons.length; i++) {
      expect(left.polygons[i], right.polygons[i]);
      expect(left.edgeStyleOf(i), right.edgeStyleOf(i));
      expect(left.isRingClosed(i), isTrue);
    }
  });

  test('the net is a cross of six closed 6x6 squares', () {
    final step = cubeBlueprint().steps.single;
    expect(step.polygons, hasLength(6));
    final front = step.polygons.first;
    expect(front.first, const Offset(6, 6));
    expect(front[2], const Offset(12, 12));
    expect(step.edgeStyleOf(0), everyElement(EdgeStyle.penciled));

    var penciled = 0;
    for (var i = 0; i < step.polygons.length; i++) {
      final ring = step.polygons[i];
      expect(ring, hasLength(4));
      final xs = ring.map((point) => point.dx);
      final ys = ring.map((point) => point.dy);
      expect(xs.reduce(mathMax) - xs.reduce(mathMin), kCubeFace);
      expect(ys.reduce(mathMax) - ys.reduce(mathMin), kCubeFace);
      penciled += step
          .edgeStyleOf(i)
          .where((style) => style == EdgeStyle.penciled)
          .length;
    }
    expect(penciled, 10);
  });

  test('the net folds into a 6x6x6 cube and other blueprints do not', () {
    final faces = foldedCube(cubeBlueprint());
    expect(faces, isNotNull);
    final cube = faces!;
    expect(cube, hasLength(6));
    expect(cube.map((face) => face.role).toSet(), CubeFaceRole.values.toSet());
    expect(cube.every((face) => face.stepIndex == 0), isTrue);

    final corners = [for (final face in cube) ...face.corners];
    expect(_span(corners, (point) => point.x), kCubeFace);
    expect(_span(corners, (point) => point.y), kCubeFace);
    expect(_span(corners, (point) => point.z), kCubeFace);

    CubeFace face(CubeFaceRole role) =>
        cube.singleWhere((item) => item.role == role);
    expect(
      face(CubeFaceRole.front).corners.every((point) => point.z == 3),
      isTrue,
    );
    expect(
      face(CubeFaceRole.back).corners.every((point) => point.z == -3),
      isTrue,
    );
    expect(
      face(CubeFaceRole.left).corners.every((point) => point.x == -3),
      isTrue,
    );
    expect(
      face(CubeFaceRole.right).corners.every((point) => point.x == 3),
      isTrue,
    );
    expect(
      face(CubeFaceRole.top).corners.every((point) => point.y == 3),
      isTrue,
    );
    expect(
      face(CubeFaceRole.bottom).corners.every((point) => point.y == -3),
      isTrue,
    );

    expect(foldedCube(twinLsBlueprint()), isNull);
  });
}

double mathMin(double a, double b) => a < b ? a : b;

double mathMax(double a, double b) => a > b ? a : b;

double _span(List<Vector3> points, double Function(Vector3 point) axis) {
  var min = double.infinity;
  var max = -double.infinity;
  for (final point in points) {
    final value = axis(point);
    if (value < min) min = value;
    if (value > max) max = value;
  }
  return max - min;
}
