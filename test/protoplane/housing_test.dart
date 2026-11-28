import 'dart:convert';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/housing.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/room_geometry.dart';
import 'layered_terrain_test.dart' show centerId;

void draw(ProtoplaneController c, String plane, Region r) {
  c.constructionTool = ConstructionTool.pencil;
  c.enter(plane);
  expect(
    c.commitDrawingPath([...r.outer, r.outer.first]),
    isTrue,
    reason: c.error,
  );
}

CraftObject construct(
  ProtoplaneController c,
  ConstructionTool tool,
  String plane,
  Offset point, [
  ConstructionPaper paper = ConstructionPaper.building,
]) {
  final e = c.evaluateConstruction(tool, plane, point, paper: paper);
  expect(e.valid, isTrue, reason: e.issue);
  expect(c.applyConstruction(e), isTrue, reason: c.error);
  return c.objects[e.object!.id]!;
}

CraftObject makeRoom(ProtoplaneController c) {
  final ground = centerId(c, PaperMaterial.paperWhite);
  draw(c, ground, rectangle(1, 1));
  final mat = construct(
    c,
    ConstructionTool.paper,
    ground,
    const Offset(.5, .5),
  );
  return construct(
    c,
    ConstructionTool.volume,
    'surface-${mat.id}',
    const Offset(.5, .5),
  );
}

void cutDoor(ProtoplaneController c, CraftObject room) {
  final wall = 'surface-${room.id}-wall-0-0-out-0';
  draw(c, wall, rectangle(.25, .5, origin: const Offset(.25, 0)));
  construct(c, ConstructionTool.scissors, wall, const Offset(.375, .25));
}

CraftObject addBlanket(ProtoplaneController c, CraftObject room) {
  final floor = 'surface-${room.id}-floor-in-0';
  draw(c, floor, rectangle(.25, .5, origin: const Offset(.5, .25)));
  final sheet = construct(
    c,
    ConstructionTool.paper,
    floor,
    const Offset(.625, .5),
    ConstructionPaper.cloth,
  );
  return construct(
    c,
    ConstructionTool.volume,
    'surface-${sheet.id}',
    const Offset(.625, .5),
    ConstructionPaper.cloth,
  );
}

void main() {
  test(
    'room, doorway, indoor cloth, resident, rent and purchase form a playable loop',
    () {
      final c = ProtoplaneController()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final room = makeRoom(c);
      expect(room.kind, CraftKind.room);
      expect(c.balances[PaperMaterial.paperWhite], 16);
      expect(roomPanels(room, c.objectPlane(room)), hasLength(6));
      expect(
        c
            .evaluateConstruction(
              ConstructionTool.paper,
              'surface-${room.id}-floor-in-0',
              const Offset(.5, .5),
            )
            .valid,
        isFalse,
      );
      expect(
        c
            .evaluateConstruction(
              ConstructionTool.paper,
              'surface-${room.id}-roof-out-0',
              const Offset(.5, .5),
              paper: ConstructionPaper.cloth,
            )
            .valid,
        isFalse,
      );
      cutDoor(c, room);
      expect(c.objects[room.id]!.openings.single.kind, 'door');
      final blanket = addBlanket(c, room);
      expect(blanket.constructionName, 'small blanket');
      expect(c.housing.tenants.length, 1);
      final tenant = c.housing.tenants.values.single;
      expect(tenant.rating, 60);
      c.advancePhase();
      c.advancePhase();
      c.advancePhase();
      expect(c.housing.day, 2);
      expect(c.housing.coins, 7);
      expect(c.canUndo, isFalse);
      for (var i = 0; i < 6; i++) {
        c.advancePhase();
      }
      expect(c.buyPaper(PaperMaterial.paperWhite), isTrue);
      expect(c.housing.coins, 1);
      expect(c.balances[PaperMaterial.paperWhite], 32);
      c.undo();
      expect(c.housing.coins, 21);
      c.redo();
      expect(c.housing.coins, 1);
      final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final loaded = ProtoplaneController()..load(saved);
      addTearDown(loaded.dispose);
      expect(loaded.housing.tenants.keys, c.housing.tenants.keys);
      expect(loaded.housing.day, c.housing.day);
      expect(loaded.objects[room.id]!.openings.single.kind, 'door');
    },
  );
  test(
    'invalid placement preserves supplies; eligibility is physical and inherited',
    () {
      final c = ProtoplaneController()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final room = makeRoom(c);
      final before = jsonEncode(c.toJson());
      final e = c.evaluateConstruction(
        ConstructionTool.paper,
        'surface-${room.id}-roof-out-0',
        const Offset(.5, .5),
        paper: ConstructionPaper.cloth,
      );
      expect(e.valid, isFalse);
      expect(c.applyConstruction(e), isFalse);
      expect(jsonEncode(c.toJson()), before);
      final floor = 'surface-${room.id}-floor-in-0';
      draw(c, floor, rectangle(.25, .5, origin: const Offset(.5, .25)));
      final sheet = construct(
        c,
        ConstructionTool.paper,
        floor,
        const Offset(.625, .5),
        ConstructionPaper.cloth,
      );
      expect(c.contextFor('surface-${sheet.id}'), MaterialContext.indoor);
      expect(c.housing.tenants, isEmpty);
      final stale = c.evaluateConstruction(
        ConstructionTool.volume,
        'surface-${sheet.id}',
        const Offset(.625, .5),
      );
      expect(c.applyConstruction(stale), isTrue);
      expect(c.applyConstruction(stale), isFalse);
      expect(c.housing.tenants, isEmpty, reason: 'No doorway');
    },
  );
  test('emergency supply refill is capped and phase state survives reload', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.balances[PaperMaterial.paperWhite] = 0;
    c.balances[PaperMaterial.paperGreen] = 0;
    c.claimSupplies();
    c.claimSupplies();
    expect(c.balances[PaperMaterial.paperWhite], 16);
    expect(c.balances[PaperMaterial.paperGreen], 8);
    c.advancePhase();
    final saved = c.toJson();
    c.load(saved);
    expect(c.housing.phase, DayPhase.afternoon);
    expect(c.canUndo, isFalse);
  });
}
