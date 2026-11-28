import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'housing_test.dart' show draw, construct;

List<Offset> loop(double x, double y) => [
  Offset(x, y),
  Offset(x + 1, y),
  Offset(x + 1, y + 1),
  Offset(x, y + 1),
  Offset(x, y),
];
void main() {
  test('four pips, closed volume, capabilities, inventory and undo', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final id = c.startingTile;
    expect(c.surfaceGrid(id).nodes, hasLength(4));
    expect(c.toolsFor(id), {ConstructionTool.volume});
    final before = jsonEncode(c.toJson());
    expect(c.evaluateVolumeStroke(id, loop(0, 0).sublist(0, 4)).valid, isFalse);
    expect(jsonEncode(c.toJson()), before);
    expect(c.applyVolumeStroke(id, loop(0, 0)), isTrue, reason: c.error);
    final room = c.objects.values.single;
    expect(room.kind, CraftKind.room);
    expect(c.openingComplete, isTrue);
    expect(c.balances[PaperMaterial.paperWhite], 16);
    expect(c.toolsFor('surface-${room.id}-floor-in-0'), {
      ConstructionTool.pencil,
      ConstructionTool.paper,
    });
    c.undo();
    expect(c.openingComplete, isFalse);
    expect(c.objects, isEmpty);
    c.redo();
    expect(c.objects.values.single.roomName, 'Room 1');
    final saved = c.toJson();
    c.load(saved);
    expect(c.objects.values.single.roomName, 'Room 1');
  });
  test('shared cuts, pending flap and fold are atomic', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    expect(
      c.applyVolumeStroke(c.startingTile, loop(0, 0)),
      isTrue,
      reason: c.error,
    );
    final a = c.objects.values.single;
    final next = c.landscape.terrain.tiles.values
        .firstWhere(
          (t) =>
              t.x == 1 &&
              t.y == 0 &&
              t.sheet.material == PaperMaterial.paperWhite &&
              t.sheet.island == 'starter',
        )
        .id;
    expect(c.applyVolumeStroke(next, loop(1, 0)), isTrue, reason: c.error);
    final shared = c.walls.where((w) => w.shared).single;
    final side = shared.sides.firstWhere((s) => s.room == a.id);
    final id = 'surface-${a.id}-${side.panel.key}-in-0';
    final p = c.planes[id]!;
    final world = [
      const Offset(.25, 0),
      const Offset(.75, 0),
      const Offset(.75, .75),
      const Offset(.25, .75),
    ].map(side.panel.frame.point).toList();
    final path = world.map(p.local).toList();
    expect(c.cutSurfaceStroke(id, path), isTrue, reason: c.error);
    expect(
      c.objects.values.every((r) => r.openings.single.kind == 'flap'),
      isTrue,
    );
    final other = shared.sides.firstWhere((s) => s.room != a.id);
    final exteriorAlias =
        c.planes['surface-${other.room}-${other.panel.key}-out-0']!;
    expect(exteriorAlias.interior, isTrue);
    final alternate = c.evaluateConstruction(
      ConstructionTool.fold,
      exteriorAlias.id,
      exteriorAlias.local(side.panel.frame.point(const Offset(.5, .4))),
    );
    expect(alternate.valid, isTrue, reason: alternate.issue);
    expect(
      alternate.object!.openings.last.swingSide,
      1,
      reason:
          'The visible outward alias is indoor, but must still swing toward its oriented normal.',
    );
    final target = p.local(side.panel.frame.point(const Offset(.5, .4)));
    final e = c.evaluateConstruction(ConstructionTool.fold, id, target);
    expect(e.valid, isTrue, reason: e.issue);
    expect(c.applyConstruction(e), isTrue, reason: c.error);
    expect(
      c.objects.values.every((r) => r.openings.single.kind == 'door'),
      isTrue,
    );
    final saved = c.toJson();
    final restored = ProtoplaneController()..load(saved);
    addTearDown(restored.dispose);
    expect(
      restored.objects.values.every((r) => r.openings.single.kind == 'door'),
      isTrue,
    );
    c.undo();
    expect(
      c.objects.values.every((r) => r.openings.single.kind == 'flap'),
      isTrue,
    );
    c.undo();
    expect(c.objects.values.every((r) => r.openings.isEmpty), isTrue);
  });
  test('floor pencil, cloth and Fold still welcome a resident', () {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
    final room = c.objects.values.single,
        wall = 'surface-${c.objects.values.single.id}-wall-0-0-in-0';
    final p = c.planes[wall]!;
    final path = [
      const Offset(-.25, 0),
      const Offset(-.75, 0),
      const Offset(-.75, .75),
      const Offset(-.25, .75),
    ];
    expect(c.cutSurfaceStroke(wall, path), isTrue, reason: c.error);
    final e = c.evaluateConstruction(
      ConstructionTool.fold,
      wall,
      const Offset(-.5, .3),
    );
    expect(e.valid, isTrue, reason: e.issue);
    expect(c.applyConstruction(e), isTrue);
    final floor = 'surface-${room.id}-floor-in-0';
    draw(c, floor, rectangle(.25, .5, origin: const Offset(.5, .25)));
    final sheet = construct(
      c,
      ConstructionTool.paper,
      floor,
      const Offset(.625, .5),
      ConstructionPaper.cloth,
    );
    expect(c.toolsFor('surface-${sheet.id}'), {ConstructionTool.fold});
    construct(
      c,
      ConstructionTool.fold,
      'surface-${sheet.id}',
      const Offset(.625, .5),
      ConstructionPaper.cloth,
    );
    expect(c.housing.tenants, hasLength(1));
    expect(p.interior, isTrue);
  });
}
