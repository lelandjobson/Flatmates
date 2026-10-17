import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/gridcraft/craft_collection_painter.dart';
import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

CraftCollection _testRoom() => CraftCollection.fromJson(
  jsonDecode(File(kTestRoomAsset).readAsStringSync()) as Map<String, dynamic>,
);

FoldedModel _cube() {
  final craft = CraftV1.fromJson(
    jsonDecode(File('$kCubeCraftDirectory/craft.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final level = GridBlueprint.fromJson(
    jsonDecode(File('levels/cube/cube.json').readAsStringSync())
        as Map<String, dynamic>,
  ).steps.first;
  return foldedModelFromCraft(craft, 1, level)!;
}

FoldedModel _puzzleModel(String puzzleId) {
  final file = Directory('levels')
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere((file) => file.uri.pathSegments.last == '$puzzleId.json');
  final step = GridBlueprint.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
  ).steps.first;
  final link = step.craft!;
  final craft = CraftV1.fromJson(
    jsonDecode(
          File('assets/craft_viewer/${link.id}/craft.json').readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  return foldedModelFromCraft(craft, link.step, step)!;
}

/// Shortest distance between two rectangles, 0 when they meet.
double _gap(Rect a, Rect b) {
  final dx = math.max(0.0, math.max(b.left - a.right, a.left - b.right));
  final dy = math.max(0.0, math.max(b.top - a.bottom, a.top - b.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

double _area(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

CollectionSurface _wallFacing(List<CollectionSurface> surfaces, Vector3 n) =>
    surfaces.singleWhere((surface) => (surface.normal - n).length < 1e-9);

void main() {
  test('the test room parses into a floor, four walls, and six crafts', () {
    final room = _testRoom();
    expect(room.id, 'test-room');
    expect(room.name, 'Test Room');
    expect(room.crafts.map((spot) => spot.puzzleId), [
      'cube',
      'box-stack',
      'grid-cube',
      'rocket',
      'birdhouse',
      'coffee-cup',
    ]);
    expect(room.crafts.first.at, const Offset(-12, 4));
    expect(room.crafts.first.turnDegrees, 20);
    expect(room.surfaces, hasLength(5));
    final occluding = room.surfaces
        .where((surface) => surface.category == SurfaceCategory.occludingGeo)
        .toList();
    expect(occluding, hasLength(4));
    final floor = room.surfaces.singleWhere(
      (surface) => surface.category == SurfaceCategory.plain,
    );
    expect(floor.normal, Vector3(0, 0, 1));
    expect(room.groundBounds, const Rect.fromLTRB(-32, -26, 32, 26));
    expect(room.camera.direction.y, lessThan(0));
    expect(
      room.camera.direction.z,
      closeTo(math.sin(32 * math.pi / 180), 1e-9),
    );
  });

  test('every craft in the test room stands inside it, clear of the rest', () {
    final room = _testRoom();
    const clearance = 3.0;
    final ground = room.groundBounds.deflate(clearance);
    final footprints = <Rect>[];
    for (final spot in room.crafts) {
      final box = placedCraft(_puzzleModel(spot.puzzleId), spot).bounds;
      final footprint = Rect.fromLTRB(
        box.min.x,
        box.min.y,
        box.max.x,
        box.max.y,
      );
      expect(
        ground.contains(footprint.topLeft) &&
            ground.contains(footprint.bottomRight),
        isTrue,
        reason: '${spot.puzzleId} at $footprint',
      );
      for (final other in footprints) {
        expect(
          _gap(footprint, other),
          greaterThanOrEqualTo(clearance),
          reason: '${spot.puzzleId} at $footprint meets $other',
        );
      }
      footprints.add(footprint);
    }
  });

  test('a polygon entry is one surface as given', () {
    final collection = CraftCollection.fromJson({
      'id': 'yard',
      'geometry': [
        {
          'type': 'polygon',
          'category': 'occluding_geo',
          'rings': [
            [
              [0, 0, 0],
              [4, 0, 0],
              [4, 4, 0],
              [0, 4, 0],
            ],
            [
              [1, 1, 0],
              [1, 2, 0],
              [2, 2, 0],
              [2, 1, 0],
            ],
          ],
        },
      ],
    });
    expect(collection.name, 'yard');
    expect(collection.crafts, isEmpty);
    final surface = collection.surfaces.single;
    expect(surface.category, SurfaceCategory.occludingGeo);
    expect(surface.rings, hasLength(2));
    expect(surface.normal, Vector3(0, 0, 1));
  });

  test('the north wall has the door notch and the side walls a window', () {
    final surfaces = _testRoom().surfaces;
    final north = _wallFacing(surfaces, Vector3(0, -1, 0));
    final east = _wallFacing(surfaces, Vector3(-1, 0, 0));
    final west = _wallFacing(surfaces, Vector3(1, 0, 0));
    final south = _wallFacing(surfaces, Vector3(0, 1, 0));
    expect(north.rings, hasLength(1));
    expect(north.rings.single, hasLength(8));
    for (final point in north.rings.single) {
      expect(point.y, closeTo(26, 1e-9));
    }
    Offset onWall(Vector3 point, bool alongX) =>
        Offset(alongX ? point.x : point.y, point.z);
    expect(
      _area([for (final p in north.rings.single) onWall(p, true)]),
      closeTo(64 * 14 - 6 * 10, 1e-9),
    );
    for (final side in [east, west]) {
      expect(side.rings, hasLength(2));
      expect(
        _area([for (final p in side.rings.first) onWall(p, false)]),
        closeTo(52 * 14, 1e-9),
      );
      expect(
        _area([for (final p in side.rings.last) onWall(p, false)]),
        closeTo(8 * 5, 1e-9),
      );
      for (final point in side.rings.last) {
        expect(point.z, inInclusiveRange(5 - 1e-9, 10 + 1e-9));
      }
    }
    expect(south.rings, hasLength(1));
    expect(south.rings.single, hasLength(4));
  });

  test('openings that do not fit are left out', () {
    final wall = punchedWall(10, 5, const [
      WallOpening(
        wall: RoomWall.north,
        kind: OpeningKind.window,
        width: 12,
        sill: 1,
        height: 2,
      ),
      WallOpening(
        wall: RoomWall.north,
        kind: OpeningKind.door,
        width: 2,
        height: 6,
      ),
    ]);
    expect(wall.holes, isEmpty);
    expect(_area(wall.exterior.points), closeTo(50, 1e-9));
  });

  test('a placed craft stands on the ground at its spot, turned', () {
    final raw = _cube();
    const spot = CraftSpot(
      puzzleId: 'cube',
      at: Offset(-7, 3),
      turnDegrees: 20,
    );
    final placed = placedCraft(raw, spot);
    final box = placed.bounds;
    expect(box.min.z, closeTo(0, 1e-9));
    expect(
      box.max.z - box.min.z,
      closeTo(raw.bounds.max.z - raw.bounds.min.z, 1e-9),
    );
    final by = craftPlacement(raw, spot);
    final turn = by.getRotation();
    final expected = Matrix3.rotationZ(20 * math.pi / 180);
    for (var i = 0; i < 9; i++) {
      expect(turn.storage[i], closeTo(expected.storage[i], 1e-9));
    }
    final rawBox = raw.bounds;
    final footprint = Vector3(
      (rawBox.min.x + rawBox.max.x) / 2,
      (rawBox.min.y + rawBox.max.y) / 2,
      rawBox.min.z,
    );
    final standing = by.transformed3(footprint);
    expect(standing.x, closeTo(-7, 1e-9));
    expect(standing.y, closeTo(3, 1e-9));
    expect(standing.z, closeTo(0, 1e-9));
    for (var i = 0; i < raw.faces.length; i++) {
      final moved = by.transformed3(raw.worldCenter(i));
      expect((placed.worldCenter(i) - moved).length, lessThan(1e-9));
    }
  });

  test('a view carried into the collection and back is unchanged', () {
    final raw = _cube();
    final by = craftPlacement(
      raw,
      const CraftSpot(puzzleId: 'cube', at: Offset(6, -2), turnDegrees: -10),
    )..translateByVector3(Vector3(-3, 1, -4));
    final target = Vector3(2, 3, 4);
    final direction = Vector3(0.3, -0.8, 0.5).normalized();
    final there = carryView(by, target, direction);
    final back = carryView(Matrix4.inverted(by), there.target, there.direction);
    expect((back.target - target).length, lessThan(1e-9));
    expect((back.direction - direction).length, lessThan(1e-9));
    expect(there.direction.z, closeTo(direction.z, 1e-9));
  });

  test('surfaces behind every craft draw first; walls fade from behind', () {
    final room = _testRoom();
    final crafts = [
      for (final spot in room.crafts.take(1)) placedCraft(_cube(), spot),
    ];
    final floor = room.surfaces.first;
    final north = _wallFacing(room.surfaces, Vector3(0, -1, 0));
    final south = _wallFacing(room.surfaces, Vector3(0, 1, 0));
    final outside = Vector3(0, -40, 25);
    expect(isBackground(floor, outside, crafts), isTrue);
    expect(isBackground(north, outside, crafts), isTrue);
    expect(isBackground(south, outside, crafts), isFalse);
    expect(isBackground(floor, Vector3(0, 0, -5), crafts), isFalse);

    expect(surfaceOpacity(north, outside), 1);
    expect(surfaceOpacity(south, outside), closeTo(kOccludedOpacity, 1e-9));
    expect(surfaceOpacity(floor, Vector3(0, 0, -5)), 1);
    final edgeOn = Vector3(0, -26, 7) + Vector3(0, 0.02, 1) * 30;
    final between = surfaceOpacity(south, edgeOn);
    expect(between, lessThan(1));
    expect(between, greaterThan(kOccludedOpacity));
  });

  test('a wall in front blocks a pick, and a faded one does not', () {
    final room = _testRoom();
    final crafts = [placedCraft(_cube(), room.crafts.first)];
    final target = crafts.single.center;
    final surfaces = [
      CollectionSurface(
        category: SurfaceCategory.occludingGeo,
        rings: [
          [
            Vector3(-20, 0, -10),
            Vector3(20, 0, -10),
            Vector3(20, 0, 20),
            Vector3(-20, 0, 20),
          ],
        ],
        normal: Vector3(0, -1, 0),
      ),
    ];
    final front = Vector3(target.x, -30, target.z);
    final behind = Vector3(target.x, 30, target.z);
    final away = Vector3(target.x, 0, target.z);
    final walled = [
      placedCraft(
        _cube(),
        CraftSpot(puzzleId: 'cube', at: Offset(target.x, 10)),
      ),
    ];
    expect(
      pickCraft(
        walled,
        surfaces,
        front,
        (walled.single.center - front).normalized(),
      ),
      isNull,
    );
    final inside = [
      placedCraft(
        _cube(),
        CraftSpot(puzzleId: 'cube', at: Offset(target.x, -10)),
      ),
    ];
    expect(
      pickCraft(
        inside,
        surfaces,
        behind,
        (inside.single.center - behind).normalized(),
      )?.craft,
      0,
    );
    expect(
      raySurface(surfaces.single, front, (away - front).normalized()),
      closeTo(30, 1e-9),
    );
  });

  test('near-plane clipping keeps the part in front of the camera', () {
    final view = Matrix4.identity();
    final ring = [
      Vector3(-1, -1, -5),
      Vector3(1, -1, -5),
      Vector3(1, -1, 5),
      Vector3(-1, -1, 5),
    ];
    final clipped = clipToNearPlane(ring, view, 1);
    expect(clipped, hasLength(4));
    for (final point in clipped) {
      expect(point.z, lessThanOrEqualTo(-1 + 1e-9));
    }
    final segment = clipToNearPlane(
      [Vector3(0, 0, 3), Vector3(0, 0, -3)],
      view,
      1,
    );
    expect(segment, hasLength(2));
    expect(segment.first.z, closeTo(-1, 1e-9));
    expect(segment.last.z, closeTo(-3, 1e-9));
    expect(
      clipToNearPlane([Vector3(0, 0, 3), Vector3(1, 0, 2)], view, 1),
      isEmpty,
    );
  });
}
