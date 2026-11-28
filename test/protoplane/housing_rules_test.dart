import 'dart:convert';
import 'package:flatmates/protoplane/residents.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/room_geometry.dart';
import 'housing_test.dart' show draw, construct, makeRoom, cutDoor, addBlanket;
import 'layered_terrain_test.dart' show centerId;

void main() {
  ProtoplaneController world() {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    return c;
  }

  test(
    'housing reviews reuse navigation work and invalidate on construction and undo',
    () {
      final c = world(), room = makeRoom(c);
      cutDoor(c, room);
      final before = c.roomReviews;
      expect(identical(c.roomReviews, before), isTrue);
      c.clearError();
      expect(identical(c.roomReviews, before), isTrue);
      addBlanket(c, room);
      final occupied = c.roomReviews;
      expect(identical(occupied, before), isFalse);
      expect(occupied.single.sleepingPlaces, hasLength(1));
      c.undo();
      expect(identical(c.roomReviews, occupied), isFalse);
      expect(c.roomReviews.single.sleepingPlaces, isEmpty);
      c.redo();
      expect(c.roomReviews.single.sleepingPlaces, hasLength(1));
    },
  );
  test('valid construction staging leaves the live world untouched', () {
    final c = world(), room = makeRoom(c);
    cutDoor(c, room);
    final floor = 'surface-${room.id}-floor-in-0';
    draw(c, floor, rectangle(.25, .5, origin: const Offset(.5, .25)));
    final before = jsonEncode(c.toJson());
    final terrain = c.landscape;
    for (var i = 0; i < 3; i++) {
      final preview = c.evaluateConstruction(
        ConstructionTool.paper,
        floor,
        const Offset(.625, .5),
        paper: ConstructionPaper.cloth,
      );
      expect(preview.valid, isTrue, reason: preview.issue);
      expect(jsonEncode(c.toJson()), before);
      expect(identical(c.landscape, terrain), isTrue);
    }
  });
  test(
    'door and window cuts preserve holes, reject attachments, and undo atomically',
    () {
      final c = world(), room = makeRoom(c);
      final wall = 'surface-${room.id}-wall-0-1-in-0';
      final cut = rectangle(.25, .25, origin: const Offset(-.75, .5));
      draw(c, wall, cut);
      final sheet = construct(
        c,
        ConstructionTool.paper,
        wall,
        cut.bounds.center,
        ConstructionPaper.cloth,
      );
      final blocked = c.evaluateConstruction(
        ConstructionTool.scissors,
        wall,
        cut.bounds.center,
      );
      expect(blocked.valid, isFalse);
      expect(blocked.issue, contains('attached'));
      c.undo();
      final opened = construct(
        c,
        ConstructionTool.scissors,
        wall,
        cut.bounds.center,
      );
      expect(opened.openings.single.kind, 'window');
      expect(c.objects.containsKey(sheet.id), isFalse);
      final panel = roomPanels(
        opened,
        c.objectPlane(opened),
      ).firstWhere((p) => p.key == 'wall-0-1');
      expect(panel.regions.single.holes, hasLength(1));
      c.undo();
      expect(c.objects[room.id]!.openings, isEmpty);
      c.redo();
      expect(c.objects[room.id]!.openings.single.kind, 'window');
      c.load(jsonDecode(jsonEncode(c.toJson())));
      expect(c.planes[wall]!.region.holes, hasLength(1));
    },
  );
  test('room walls cannot be removed entirely and cuts do not fall back', () {
    final c = world(), room = makeRoom(c);
    final wall = 'surface-${room.id}-wall-0-1-out-0';
    expect(
      c
          .evaluateConstruction(
            ConstructionTool.scissors,
            wall,
            const Offset(.5, .5),
          )
          .valid,
      isFalse,
    );
    draw(c, wall, rectangle(1, 1));
    final e = c.evaluateConstruction(
      ConstructionTool.scissors,
      wall,
      const Offset(.5, .5),
    );
    expect(e.valid, isFalse);
    expect(e.issue, contains('part of the wall'));
  });
  test(
    'multiple blankets attract individuals, deterministic departures require improvement to refill',
    () {
      final c = world(), room = makeRoom(c);
      cutDoor(c, room);
      addBlanket(c, room);
      final floor = 'surface-${room.id}-floor-in-0';
      final region = rectangle(.25, .5, origin: const Offset(.25, .25));
      draw(c, floor, region);
      final sheet = construct(
        c,
        ConstructionTool.paper,
        floor,
        region.bounds.center,
        ConstructionPaper.cloth,
      );
      construct(
        c,
        ConstructionTool.volume,
        'surface-${sheet.id}',
        region.bounds.center,
      );
      expect(c.housing.tenants.length, 2);
      expect(c.housing.tenants.values.map((t) => t.rating), everyElement(40));
      c.housing.seed = 1;
      c.advancePhase();
      c.advancePhase();
      final clone = world()..load(jsonDecode(jsonEncode(c.toJson())));
      c.advancePhase();
      clone.advancePhase();
      expect(c.housing.toJson(), clone.housing.toJson());
      expect(c.housing.tenants, isEmpty);
      expect(c.housing.coins, 12);
      c.syncHousing();
      expect(c.housing.tenants, isEmpty);
      final wall = 'surface-${room.id}-wall-0-1-out-0';
      draw(c, wall, rectangle(.25, .25, origin: const Offset(.5, .5)));
      construct(c, ConstructionTool.scissors, wall, const Offset(.625, .625));
      expect(c.housing.tenants.length, 2);
      expect(c.housing.tenants.values.map((t) => t.rating), everyElement(60));
      expect(c.housing.vacancies[room.id], isEmpty);
      c.undo();
      expect(c.housing.tenants, isEmpty);
      c.redo();
      expect(c.housing.tenants.length, 2);
    },
  );
  test(
    'unusable sleeping place waits until overnight, earns nothing and can be repaired',
    () {
      final c = world(), room = makeRoom(c);
      cutDoor(c, room);
      final blanket = addBlanket(c, room);
      c.objects.remove(blanket.id);
      c.syncHousing();
      expect(c.housing.tenants.values.single.usable, isFalse);
      c.advancePhase();
      expect(c.housing.tenants.length, 1);
      c.objects[blanket.id] = blanket;
      c.syncHousing();
      expect(c.housing.tenants.values.single.usable, isTrue);
      c.objects.remove(blanket.id);
      c.syncHousing();
      c.advancePhase();
      c.advancePhase();
      expect(c.housing.tenants, isEmpty);
      expect(c.housing.coins, 0);
    },
  );
  test(
    'physical surfaces and inherited cloth layers keep context with no room focus',
    () {
      final c = world(), room = makeRoom(c);
      for (final p in c.planes.values.where((p) => p.owner == room.id)) {
        expect(
          c.contextFor(p.id),
          p.id.contains('-in-')
              ? MaterialContext.indoor
              : MaterialContext.outdoor,
        );
      }
      final wall = 'surface-${room.id}-wall-0-1-in-0';
      final region = rectangle(.25, .25, origin: const Offset(-.75, .5));
      draw(c, wall, region);
      final cloth = construct(
        c,
        ConstructionTool.paper,
        wall,
        region.bounds.center,
        ConstructionPaper.cloth,
      );
      expect(c.contextFor('surface-${cloth.id}'), MaterialContext.indoor);
      expect(c.planes['surface-${cloth.id}']!.roomFace, 'wall-0-1');
      final padded = construct(
        c,
        ConstructionTool.volume,
        'surface-${cloth.id}',
        region.bounds.center,
      );
      expect(padded.constructionName, 'cloth padding');
      expect(c.housing.tenants, isEmpty);
      expect(PaperMaterial.paperWhite.allows(MaterialContext.indoor), isFalse);
      expect(PaperMaterial.paperGreen.allows(MaterialContext.outdoor), isFalse);
      expect(PaperMaterial.cork.use, MaterialUse.both);
    },
  );
  test(
    'paper charges net area, insufficient funds reject atomically, and parcel purchase charges once',
    () {
      final c = world();
      final ground = centerId(c, PaperMaterial.paperWhite);
      draw(c, ground, rectangle(2, 2));
      final insufficient = c.evaluateConstruction(
        ConstructionTool.paper,
        ground,
        const Offset(.5, .5),
      );
      expect(insufficient.valid, isFalse);
      expect(c.balances[PaperMaterial.paperWhite], 32);
      expect(c.buyPaper(PaperMaterial.paperWhite), isFalse);
      c.housing.coins = 20;
      expect(c.buyPaper(PaperMaterial.paperWhite), isTrue);
      expect(c.balances[PaperMaterial.paperWhite], 48);
      final parcel = c.parcels
          .visible(c.landscape.terrain)
          .firstWhere((p) => p.x != 0 || p.y != 0);
      expect(c.buyParcel(parcel), isFalse);
      c.housing.coins = c.parcels.price;
      expect(c.buyParcel(parcel), isTrue);
      expect(c.housing.coins, 0);
      expect(c.buyParcel(parcel), isFalse);
      expect(c.housing.coins, 0);
      c.undo();
      expect(c.housing.coins, c.parcels.price);
    },
  );
  test(
    'older saves retain outdoor cloth and legacy solids without reinterpreting them',
    () {
      final c = world();
      final ground = centerId(c, PaperMaterial.paperWhite);
      draw(c, ground, rectangle(1, 1));
      final mat = construct(
        c,
        ConstructionTool.paper,
        ground,
        const Offset(.5, .5),
      );
      final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      saved['version'] = 11;
      saved.remove('housing');
      saved['objects'][0]['material'] = PaperMaterial.paperGreen.id;
      c.load(saved);
      expect(c.objects[mat.id]!.constructionName, 'cloth sheet');
      expect(
        c
            .evaluateConstruction(
              ConstructionTool.volume,
              'surface-${mat.id}',
              const Offset(.5, .5),
            )
            .valid,
        isFalse,
      );
      saved['objects'][0]['kind'] = 'solidVolume';
      saved['objects'][0]['material'] = PaperMaterial.paperWhite.id;
      c.load(saved);
      expect(c.objects[mat.id]!.kind, CraftKind.solidVolume);
      expect(c.housing.day, 1);
      expect(c.housing.coins, 0);
      expect(c.balances[PaperMaterial.paperWhite], 16);
    },
  );
  test(
    'malformed simulation and physical room saves fail without changing the live world',
    () {
      final c = world(), room = makeRoom(c);
      cutDoor(c, room);
      addBlanket(c, room);
      final before = jsonEncode(c.toJson());
      for (final field in ['coins', 'phase', 'surface', 'identity']) {
        final bad = jsonDecode(before) as Map<String, dynamic>;
        if (field == 'coins') bad['housing']['coins'] = -1;
        if (field == 'phase') bad['housing']['phase'] = 'tomorrow';
        if (field == 'surface') {
          final plane = (bad['planes'] as List).firstWhere(
            (p) => p['id'] == 'surface-${room.id}-floor-in-0',
          );
          plane['interior'] = false;
        }
        if (field == 'identity') bad['housing']['nextTenant'] = 1;
        expect(() => c.load(bad), throwsFormatException, reason: field);
        expect(jsonEncode(c.toJson()), before);
      }
    },
  );
  test('queued save snapshots do not share mutable vacancy lists', () {
    final c = world();
    c.housing.vacancies['room'] = [40];
    final saved = c.toJson();
    c.housing.vacancies['room']!.add(60);
    expect(saved['housing']['vacancies']['room'], [40]);
  });
  test(
    'Cube Boy wanders on the reachable floor without advancing time or jumping on resync',
    () {
      final c = world(), room = makeRoom(c);
      cutDoor(c, room);
      addBlanket(c, room);
      final scene = Scene(), residents = BedroomResidents();
      residents.syncHousing(scene, c);
      final actor = residents.friends.instances.single;
      final origin = actor.position.clone();
      var moved = false;
      for (var i = 0; i < 30; i++) {
        final before = actor.position.clone();
        if (i == 3 || i == 12) residents.syncHousing(scene, c);
        residents.tickHousing(scene, .1);
        expect((actor.position - before).length, lessThanOrEqualTo(.01201));
        moved = moved || (actor.position - origin).length > .02;
        expect(
          c.roomReviews.single.floor.region.contains(
            c.roomReviews.single.floor.local(actor.position),
          ),
          isTrue,
        );
      }
      expect(moved, isTrue);
      expect(
        scene.meshes.any((m) => m.id.startsWith('friend_tenant-')),
        isTrue,
      );
      expect(c.housing.day, 1);
      expect(c.housing.coins, 0);
    },
  );
}
