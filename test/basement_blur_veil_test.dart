import 'package:flatmates/gameplay/spawns/basement_blur_veil.dart';
import 'package:flatmates/gameplay/spawns/basement_spawn_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  const grid = VolumeGrid(tilesSide: 48, tileSize: 8);

  test('veil sits on the (0,-1)/(0,-2) seam, wall to wall, ground to ramp', () {
    final veil = basementBlurVeil(grid);
    final z = grid.tileOrigin(0, -1).z;
    final x0 = grid.tileOrigin(0, 0).x;
    final x1 = x0 + grid.tileSize;
    final yFloor = basementRampHeight(grid, z);
    expect(z, grid.tileOrigin(0, -2).z + grid.tileSize);
    expect(veil.corners, hasLength(4));
    for (final p in veil.corners) {
      expect(p.z, closeTo(z, 1e-6));
      expect(p.x, anyOf(closeTo(x0, 1e-6), closeTo(x1, 1e-6)));
      expect(p.y, anyOf(closeTo(0, 1e-6), closeTo(yFloor, 1e-6)));
    }
    expect(yFloor, lessThan(0));
    expect(veil.normal.z, greaterThan(0.9));
  });

  test('a south vantage projects a clip polygon', () {
    final veil = basementBlurVeil(grid);
    final camera = Camera(
      name: 'veil',
      position: Vector3(20, 24, 40),
      target: Vector3(4, -6, -8),
    );
    const viewport = Size(800, 600);
    final pts = veil.project(camera, viewport);
    expect(pts, isNotNull);
    expect(pts, hasLength(4));
    expect(veil.clipPath(camera, viewport), isNotNull);
  });

  test('an unusable viewport does not open a blur layer', () {
    final veil = basementBlurVeil(grid);
    final camera = Camera(
      name: 'veil',
      position: Vector3(20, 24, 40),
      target: Vector3(4, -6, -8),
    );
    expect(veil.project(camera, Size.zero), isNull);
  });
}
