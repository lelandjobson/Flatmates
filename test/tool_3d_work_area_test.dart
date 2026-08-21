import 'package:flatmates/gameplay/tools/tool_3d.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('projects world points to a padded 2D frame', () {
    final camera = Camera(
      name: 'test',
      position: Vector3(0, 30, 30),
      target: Vector3.zero(),
    );
    const viewport = Size(800, 600);
    final points = [
      Vector3(-4, 0, -4),
      Vector3(4, 0, -4),
      Vector3(-4, 0, 4),
      Vector3(4, 0, 4),
      Vector3(-4, 6, -4),
      Vector3(4, 6, -4),
      Vector3(-4, 6, 4),
      Vector3(4, 6, 4),
    ];

    final unpadded = Tool3dScreenFrame.project(
      camera: camera,
      viewport: viewport,
      worldPoints: points,
      pad: EdgeInsets.zero,
      screenMargin: 0,
    );
    final padded = Tool3dScreenFrame.project(
      camera: camera,
      viewport: viewport,
      worldPoints: points,
      pad: const EdgeInsets.all(40),
      screenMargin: 0,
    );

    expect(unpadded, isNotNull);
    expect(padded, isNotNull);
    expect(padded!.bounds.width, closeTo(unpadded!.bounds.width + 80, 0.5));
    expect(padded.bounds.height, closeTo(unpadded.bounds.height + 80, 0.5));
    expect(
      padded.corner(Tool3dCorner.topRight).dx,
      closeTo(padded.bounds.right, 0.01),
    );
    expect(
      padded.corner(Tool3dCorner.bottomRight).dy,
      closeTo(padded.bounds.bottom, 0.01),
    );
  });
}
