import 'package:flatmates/gameplay/spawns/basement_spawn.dart';
import 'package:flatmates/gameplay/spawns/basement_spawn_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/rendering/ground_occlusion.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 48, tileSize: 8);
  final occlusion = GroundOcclusion(
    holeTiles: BasementSpawn.cutTileSet,
    tileSize: grid.tileSize,
  );

  Camera lookFrom(Vector3 position, Vector3 target) => Camera(
        name: 'occ',
        position: position,
        target: target,
      );

  test('point under the bridge is hidden from a typical orbit', () {
    final under = Vector3(
      4,
      basementRampHeight(grid, grid.tileOrigin(0, -2).z + 4),
      grid.tileOrigin(0, -2).z + 4,
    );
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(4, 0, -12));
    expect(visibleThroughGround(camera, under, occlusion), isFalse);
  });

  test('same underground point is visible when the ray goes through the hole', () {
    final under = Vector3(
      4,
      basementRampHeight(grid, grid.tileOrigin(0, -1).z + 2),
      grid.tileOrigin(0, -1).z + 2,
    );
    final camera = lookFrom(Vector3(4, 40, 28), Vector3(4, -8, -4));
    expect(visibleThroughGround(camera, under, occlusion), isTrue);
  });

  test('a face straddling the hole edge keeps a visible remnant', () {
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(4, 0, -12));
    final zHole = grid.tileOrigin(0, 0).z + 4;
    final zBridge = grid.tileOrigin(0, -2).z + 4;
    final face = [
      Vector3(2, basementRampHeight(grid, zHole), zHole),
      Vector3(6, basementRampHeight(grid, zHole), zHole),
      Vector3(6, basementRampHeight(grid, zBridge), zBridge),
      Vector3(2, basementRampHeight(grid, zBridge), zBridge),
    ];
    final vis = [
      for (final v in face) visibleThroughGround(camera, v, occlusion),
    ];
    expect(vis.contains(true), isTrue);
    expect(vis.contains(false), isTrue);
    final clipped = clipFaceToVisible(camera, face, occlusion);
    expect(clipped.length, greaterThanOrEqualTo(3));
    expect(clipped.length, lessThan(face.length + 3));
  });

  test('a fully hidden face is dropped', () {
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(4, 0, -12));
    final z = grid.tileOrigin(0, -2).z + 2;
    final y = basementRampHeight(grid, z);
    final face = [
      Vector3(1, y, z),
      Vector3(7, y, z),
      Vector3(7, y, z + 2),
      Vector3(1, y, z + 2),
    ];
    expect(clipFaceToVisible(camera, face, occlusion), isEmpty);
  });

  test('an outline under the bridge is dropped', () {
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(4, 0, -12));
    final z = grid.tileOrigin(0, -2).z + 2;
    final y = basementRampHeight(grid, z);
    expect(
      clipSegmentToVisible(
        camera,
        Vector3(2, y, z),
        Vector3(6, y, z),
        occlusion,
      ),
      isEmpty,
    );
  });

  test('an outline straddling the hole keeps the visible remnant', () {
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(4, 0, -12));
    final zHole = grid.tileOrigin(0, 0).z + 4;
    final zBridge = grid.tileOrigin(0, -2).z + 4;
    final a = Vector3(4, basementRampHeight(grid, zHole), zHole);
    final b = Vector3(4, basementRampHeight(grid, zBridge), zBridge);
    expect(visibleThroughGround(camera, a, occlusion), isTrue);
    expect(visibleThroughGround(camera, b, occlusion), isFalse);
    final clipped = clipSegmentToVisible(camera, a, b, occlusion);
    expect(clipped, hasLength(2));
    expect((clipped[0] - a).length, lessThan(1e-6));
    expect((clipped[1] - b).length, greaterThan(1));
    expect(visibleThroughGround(camera, clipped[0], occlusion), isTrue);
  });

  test('door facade is all-or-nothing through the hole', () {
    final hole = GroundOcclusion(
      holeTiles: BasementSpawn.cutTileSet,
      tileSize: grid.tileSize,
    );
    final door = basementCutDoorWall(grid);
    expect(
      basementDoorFacadeVisible(
        lookFrom(Vector3(4, 40, 28), Vector3(4, -8, -4)),
        door,
        hole,
      ),
      isTrue,
    );
    expect(
      basementDoorFacadeVisible(
        lookFrom(Vector3(4, 40, -40), Vector3(4, -4, 0)),
        door,
        hole,
      ),
      isFalse,
    );
  });

  test('door wall hides ramp behind the jamb but not the opening', () {
    final door = basementCutDoorWall(grid);
    final occluded = basementGroundOcclusion(grid);
    final fromHole = lookFrom(Vector3(4, -6, 20), Vector3(4, -6, 0));
    final midY = (door.doorY0 + door.doorY1) * 0.5;
    final behindOpening = Vector3(
      (door.doorX0 + door.doorX1) * 0.5,
      midY,
      door.z - 4,
    );
    final behindJamb = Vector3(
      (door.x0 + door.doorX0) * 0.5,
      midY,
      door.z - 4,
    );
    expect(visibleThroughGround(fromHole, behindOpening, occluded), isTrue);
    expect(visibleThroughGround(fromHole, behindJamb, occluded), isFalse);
    final clipped = clipSegmentToVisible(
      fromHole,
      Vector3(behindJamb.x, midY, door.z + 4),
      Vector3(behindJamb.x, midY, door.z - 4),
      occluded,
    );
    expect(clipped, hasLength(2));
    expect(clipped.last.z, greaterThanOrEqualTo(door.z - 1e-3));
  });

  test('door frustum keeps a stable polygon through the opening', () {
    final door = basementCutDoorWall(grid);
    final occluded = basementGroundOcclusion(grid);
    final fromHole = lookFrom(Vector3(4, -6, 20), Vector3(4, -6, 0));
    final midY = (door.doorY0 + door.doorY1) * 0.5;
    final behind = [
      Vector3(door.x0, midY - 1, door.z - 3),
      Vector3(door.x1, midY - 1, door.z - 3),
      Vector3(door.x1, midY + 1, door.z - 3),
      Vector3(door.x0, midY + 1, door.z - 3),
    ];
    final parts = clipFaceToVisibleParts(fromHole, behind, occluded);
    expect(parts, hasLength(1));
    final xs = parts.first.map((p) => p.x).toList()..sort();
    expect(xs.first, greaterThan(door.x0 + 1));
    expect(xs.last, lessThan(door.x1 - 1));
    expect(xs.last - xs.first, greaterThan(door.doorX1 - door.doorX0 - 0.5));
    expect(xs.last - xs.first, lessThan(door.x1 - door.x0 - 2));

    final shifted = lookFrom(Vector3(3.2, -5.4, 18), Vector3(4.1, -6.2, -1));
    final again = clipFaceToVisibleParts(shifted, behind, occluded);
    expect(again, hasLength(1));
    expect(again.first, hasLength(greaterThanOrEqualTo(3)));
  });

  test('at-grade path outlines are not eaten by basement hole clip', () {
    final occluded = basementGroundOcclusion(grid);
    final camera = lookFrom(Vector3(40, 50, 40), Vector3(16, 0, 16));
    final a = Vector3(16, 0, 16);
    final b = Vector3(20, 0, 16);
    final kept = clipSegmentToVisible(camera, a, b, occluded);
    expect(kept, hasLength(2));
    expect((kept[0] - a).length, lessThan(1e-9));
    expect((kept[1] - b).length, lessThan(1e-9));
    final stubZ = grid.tileOrigin(0, 2).z;
    expect(
      clipSegmentToVisible(
        camera,
        Vector3(3, 0, stubZ + 2),
        Vector3(5, 0, stubZ + 2),
        occluded,
      ),
      hasLength(2),
    );
  });

  test('door wall stays visible from an acute hole-side angle', () {
    final door = basementCutDoorWall(grid);
    final wallOcc = GroundOcclusion(
      holeTiles: BasementSpawn.cutTileSet,
      tileSize: grid.tileSize,
      groundHole: GroundHoleRect.fromTiles(
        BasementSpawn.cutTileSet,
        grid.tileSize,
      ),
    );
    final jamb = [
      Vector3(door.x0, door.yTop, door.z),
      Vector3(door.x0, door.yFloor, door.z),
      Vector3(door.doorX0, door.yFloor, door.z),
      Vector3(door.doorX0, door.yTop, door.z),
    ];
    final acute = lookFrom(Vector3(28, 12, 10), Vector3(4, -4, 0));
    final parts = clipFaceToVisibleParts(acute, jamb, wallOcc);
    expect(parts, isNotEmpty);
    expect(parts.first, hasLength(greaterThanOrEqualTo(3)));
  });

  test('door wall is hidden when the camera looks through the grass', () {
    final door = basementCutDoorWall(grid);
    final wallOcc = GroundOcclusion(
      holeTiles: BasementSpawn.cutTileSet,
      tileSize: grid.tileSize,
      groundHole: GroundHoleRect.fromTiles(
        BasementSpawn.cutTileSet,
        grid.tileSize,
      ),
    );
    final jamb = [
      Vector3(door.x0, door.yTop, door.z),
      Vector3(door.x0, door.yFloor, door.z),
      Vector3(door.doorX0, door.yFloor, door.z),
      Vector3(door.doorX0, door.yTop, door.z),
    ];
    final throughGrass = lookFrom(Vector3(24, 30, -18), Vector3(4, -4, 0));
    expect(clipFaceToVisibleParts(throughGrass, jamb, wallOcc), isEmpty);
  });

  test('door sill outline is hidden when the ray hits the bridge', () {
    final camera = lookFrom(Vector3(4, 40, -40), Vector3(4, -4, 0));
    final opening = basementCutDoorWall(grid);
    expect(
      clipSegmentToVisible(
        camera,
        Vector3(opening.doorX0, opening.doorY0, opening.z),
        Vector3(opening.doorX1, opening.doorY0, opening.z),
        occlusion,
      ),
      isEmpty,
    );
  });
}
