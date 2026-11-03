import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/bedroom_items.dart';
import 'package:flatmates/protoplane/bedrooms.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/residents.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'bedroom_fixture.dart';

void main() {
  test('rooms have independent comfort and one resident each', () {
    final first = BedroomFixture();
    final c = first.c;
    addTearDown(c.dispose);
    final second = BedroomFixture(controller: c, tile: 'ground-5-4');
    craft(
      c,
      'surface-${first.mattress!.id}',
      rectanglePath(5, 0, 0, 4, 1),
      kind: CraftKind.pillow,
    );
    expect(c.bedrooms.where((b) => b.usable), hasLength(2));
    expect(
      c.bedrooms.singleWhere((b) => b.floorId == first.floor.id).comfort,
      52,
    );
    expect(
      c.bedrooms.singleWhere((b) => b.floorId == second.floor.id).comfort,
      40,
    );
    expect(c.bedrooms.map((b) => b.residentId).toSet(), hasLength(2));
  });
  test('making a mattress unusable updates residency and undo restores it', () {
    final f = BedroomFixture();
    final c = f.c;
    addTearDown(c.dispose);
    final resident = c.bedrooms.single.resident;
    c.enter(f.mattress!.planeId, editObject: f.mattress!.id);
    c.setDepth(0);
    expect(c.applyEdit(), isTrue, reason: c.error);
    expect(c.bedrooms.single.resident, isNull);
    expect(c.bedrooms.single.missing, contains('Mattress'));
    c.undo();
    expect(c.bedrooms.single.resident, resident);
  });
  test(
    'frame plus mattress in enclosed reachable room brings one resident',
    () {
      final f = BedroomFixture();
      addTearDown(f.c.dispose);
      final room = f.c.bedrooms.single;
      expect(room.missing, isEmpty);
      expect(room.usable, isTrue);
      expect(room.resident, anyOf(ResidentKind.frogman, ResidentKind.cubeBoy));
      expect(room.comfort, 40);
      expect(f.floor.region.contains(room.position!), isTrue);
      expect(f.bed.region.contains(room.position!), isFalse);
    },
  );
  test('walls, a real door, and a mattress are independently required', () {
    final open = BedroomFixture(walls: false),
        sealed = BedroomFixture(door: false),
        bare = BedroomFixture(mattress: false);
    for (final f in [open, sealed, bare]) {
      addTearDown(f.c.dispose);
      expect(f.c.bedrooms.single.resident, isNull);
    }
    expect(open.c.bedrooms.single.missing, containsAll(['Walls', 'Door']));
    expect(sealed.c.bedrooms.single.missing, contains('Door'));
    expect(bare.c.bedrooms.single.missing, contains('Mattress'));
  });
  test('each furnishing category raises comfort, duplicates do not', () {
    final f = BedroomFixture();
    final c = f.c;
    addTearDown(c.dispose);
    final bedding = 'surface-${f.mattress!.id}';
    craft(c, bedding, rectanglePath(5, 0, 0, 2, 1), kind: CraftKind.pillow);
    expect(c.bedrooms.single.comfort, 52);
    craft(c, bedding, rectanglePath(5, 2, 0, 4, 1), kind: CraftKind.pillow);
    expect(c.bedrooms.single.comfort, 52);
    craft(c, bedding, rectanglePath(5, 0, 1, 4, 4), kind: CraftKind.blanket);
    expect(c.bedrooms.single.comfort, 68);
    final surface = 'surface-${f.floor.id}',
        index = c.planes['surface-${f.floor.id}']!.grids.length - 1;
    final examples = c.planes[surface]!.grids[index].examples;
    craft(
      c,
      surface,
      examples[CraftKind.lamp]!,
      grid: index,
      kind: CraftKind.lamp,
    );
    expect(c.bedrooms.single.comfort, 80);
    craft(
      c,
      surface,
      examples[CraftKind.storage]!,
      grid: index,
      kind: CraftKind.storage,
    );
    expect(c.bedrooms.single.comfort, 92);
    craft(
      c,
      surface,
      examples[CraftKind.rug]!,
      grid: index,
      kind: CraftKind.rug,
    );
    expect(c.bedrooms.single.comfort, 100);
    expect(c.bedrooms.single.mood, 'Delighted');
  });
  test('furniture blocking the doorway prevents move-in', () {
    final f = BedroomFixture();
    addTearDown(f.c.dispose);
    f.c.objects['blocker'] = CraftObject(
      id: 'blocker',
      planeId: 'surface-${f.floor.id}',
      kind: CraftKind.storage,
      region: rectangle(.9, .14, origin: const Offset(.05, 0)),
      color: PaperColor.green,
      depth: .2,
    );
    final rooms = evaluateBedrooms(f.c.objects, f.c.planes);
    expect(rooms.single.missing, contains('Clear access'));
    expect(rooms.single.resident, isNull);
  });
  test(
    'partial walls and holes without an authored opening do not enclose a room',
    () {
      final f = BedroomFixture();
      addTearDown(f.c.dispose);
      final wall = f.c.objects[f.wallIds.last]!;
      f.c.objects[wall.id] = wall.copyWith(region: rectangle(.5, 1));
      expect(
        evaluateBedrooms(f.c.objects, f.c.planes).single.missing,
        contains('Walls'),
      );
      f.c.objects[wall.id] = wall.copyWith(
        region: Region(wall.region.outer, [
          rectangle(.2, .2, origin: const Offset(.4, .2)).outer,
        ]),
      );
      expect(
        evaluateBedrooms(f.c.objects, f.c.planes).single.missing,
        contains('Walls'),
      );
    },
  );
  test(
    'undo redo and reload preserve identity and avoid duplicate residents',
    () {
      final f = BedroomFixture();
      final c = f.c;
      addTearDown(c.dispose);
      final id = c.bedrooms.single.residentId,
          kind = c.bedrooms.single.resident;
      c.undo();
      expect(c.bedrooms.single.resident, isNull);
      c.redo();
      expect(c.bedrooms.single.residentId, id);
      expect(c.bedrooms.single.resident, kind);
      final restored = ProtoplaneController()
        ..load(jsonDecode(jsonEncode(c.toJson())));
      addTearDown(restored.dispose);
      expect(restored.bedrooms.single.residentId, id);
      expect(restored.bedrooms.single.resident, kind);
      final actorAdapter = BedroomResidents(), scene = Scene();
      addTearDown(scene.dispose);
      actorAdapter.sync(
        scene,
        restored.bedrooms,
        restored.objects,
        restored.planes,
      );
      actorAdapter.sync(
        scene,
        restored.bedrooms,
        restored.objects,
        restored.planes,
      );
      expect(actorAdapter.friends.instances, hasLength(1));
      expect(scene.meshes, hasLength(1));
      expect(
        actorAdapter.friends.instances.single.expression.opacity,
        greaterThan(0),
      );
      actorAdapter.sync(scene, [], restored.objects, restored.planes);
      expect(scene.meshes, isEmpty);
    },
  );
  test(
    'old saved floors gain Bedroom acetate without changing existing grids',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final floor = craft(c, 'ground-4-4', rectanglePath(3, 0, 0, 2, 2));
      final p = c.planes['surface-${floor.id}']!;
      c.planes[p.id] = p.withGrids(p.grids.take(3).toList());
      final old = jsonEncode(
        c.planes[p.id]!.grids.map((g) => g.toJson()).toList(),
      );
      c.load(c.toJson());
      final upgraded = c.planes[p.id]!;
      expect(upgraded.grids.last.name, 'Bedroom');
      expect(upgraded.grids, hasLength(4));
      expect(
        jsonEncode(upgraded.grids.take(3).map((g) => g.toJson()).toList()),
        old,
      );
      c.load(c.toJson());
      expect(c.planes[p.id]!.grids, hasLength(4));
    },
  );
  test('bedroom recipes enforce contextual supports', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final invalid = CraftObject(
      id: 'invalid',
      planeId: 'ground-4-4',
      kind: CraftKind.mattress,
      region: rectangle(.5, .5),
      color: PaperColor.red,
      depth: .03,
    );
    expect(c.validateObject(invalid), contains('supporting furniture'));
    expect(
      bedroomItems.keys,
      containsAll([
        CraftKind.bedFrame,
        CraftKind.mattress,
        CraftKind.pillow,
        CraftKind.blanket,
        CraftKind.lamp,
        CraftKind.storage,
      ]),
    );
  });
}
