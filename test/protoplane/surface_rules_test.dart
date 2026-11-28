import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/room_geometry.dart';
import 'housing_test.dart' show draw, construct;
import 'surface_construction_test.dart' show loop;

void main() {
  test('an absent landscape connection cannot be invented by a stroke', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final p = c.planes[c.startingTile]!,
        g = c.planes[c.startingTile]!.grids.first;
    c.planes[p.id] = p.withGrids([
      CraftGrid(
        id: g.id,
        name: g.name,
        nodes: g.nodes,
        edges: g.edges.skip(1).toList(),
        recipes: g.recipes,
      ),
    ]);
    expect(c.surfaceGrid(p.id).edges, hasLength(3));
    final before = jsonEncode(c.toJson());
    expect(c.applyVolumeStroke(p.id, loop(0, 0)), isFalse);
    expect(jsonEncode(c.toJson()), before);
  });
  test(
    'concave loops, collisions, stale previews and opening undo boundary',
    () {
      final c = ProtoplaneController()
        ..enableInPlaceDrawing()
        ..openingComplete = true
        ..balances[PaperMaterial.paperWhite] = 160;
      addTearDown(c.dispose);
      final path = [
        Offset.zero,
        const Offset(2, 0),
        const Offset(2, 1),
        const Offset(1, 1),
        const Offset(1, 2),
        const Offset(0, 2),
        Offset.zero,
      ];
      final e = c.evaluateVolumeStroke(c.startingTile, path);
      expect(e.valid, isTrue, reason: e.issue);
      expect(c.applyConstruction(e), isTrue);
      expect(c.objects.values.single.region.area, 3);
      final before = jsonEncode(c.toJson());
      expect(c.applyConstruction(e), isFalse);
      expect(jsonEncode(c.toJson()), before);
      final floor = 'surface-${c.objects.values.single.id}-floor-in-0';
      draw(c, floor, rectangle(.25, .5, origin: const Offset(.25, .25)));
      c.undo();
      c.undo();
      expect(c.objects, isEmpty);
      expect(c.openingComplete, isTrue);
    },
  );
  for (final hingeRight in [false, true]) {
    test(
      'door hinge ${hingeRight ? 'right' : 'left'} blocks access until folded and rejects obstruction',
      () {
        final c = ProtoplaneController();
        addTearDown(c.dispose);
        expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
        final room = c.objects.values.single;
        final panel = roomPanels(
          room,
          c.objectPlane(room),
        ).firstWhere((p) => p.key == 'wall-0-0');
        final id = 'surface-${room.id}-wall-0-0-in-0',
            p = c.planes['surface-${room.id}-wall-0-0-in-0']!;
        final nodes = hingeRight
            ? [
                const Offset(.75, 0),
                const Offset(.25, 0),
                const Offset(.25, .75),
                const Offset(.75, .75),
              ]
            : [
                const Offset(.25, 0),
                const Offset(.75, 0),
                const Offset(.75, .75),
                const Offset(.25, .75),
              ];
        expect(
          c.cutSurfaceStroke(
            id,
            nodes.map((n) => p.local(panel.frame.point(n))).toList(),
          ),
          isTrue,
        );
        expect(c.roomReviews.single.reachable, isEmpty);
        final aim = p.local(panel.frame.point(const Offset(.5, .3)));
        final floor = c.planes['surface-${room.id}-floor-in-0']!;
        c.objects['blocker'] = CraftObject(
          id: 'blocker',
          planeId: floor.id,
          kind: CraftKind.solidVolume,
          region: rectangle(.8, .6, origin: const Offset(.1, .1)),
          depth: .4,
        );
        expect(
          c.evaluateConstruction(ConstructionTool.fold, id, aim).issue,
          'Clear the door swing',
        );
        c.objects.remove('blocker');
        final e = c.evaluateConstruction(ConstructionTool.fold, id, aim);
        expect(e.valid, isTrue, reason: e.issue);
        expect(c.applyConstruction(e), isTrue);
        expect(c.roomReviews.single.reachable, isNotEmpty);
        c.undo();
        expect(c.roomReviews.single.reachable, isEmpty);
      },
    );
  }
  test('a room reached through its neighbor qualifies for rent', () {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
    final a = c.objects.values.single;
    expect(c.applyVolumeStroke(c.startingTile, loop(1, 0)), isTrue);
    final b = c.objects.values.last;
    void cut(CraftObject room, String face) {
      final panel = roomPanels(
        room,
        c.objectPlane(room),
      ).firstWhere((p) => p.key == face);
      final id = 'surface-${room.id}-$face-in-0',
          p = c.planes['surface-${room.id}-$face-in-0']!;
      final nodes = rectangle(.5, .75, origin: const Offset(.25, 0)).outer;
      expect(
        c.cutSurfaceStroke(
          id,
          [
            ...nodes,
            nodes.first,
          ].map((n) => p.local(panel.frame.point(n))).toList(),
        ),
        isTrue,
        reason: c.error,
      );
    }

    final shared = c.walls
        .firstWhere((w) => w.shared)
        .sides
        .firstWhere((s) => s.room == a.id);
    cut(a, shared.panel.key);
    expect(c.roomReviews.every((r) => r.reachable.isEmpty), isTrue);
    cut(a, 'wall-0-0');
    expect(c.roomReviews.every((r) => r.reachable.isNotEmpty), isTrue);
    final floor = 'surface-${b.id}-floor-in-0';
    draw(c, floor, rectangle(.25, .5, origin: const Offset(1.5, .25)));
    final sheet = construct(
      c,
      ConstructionTool.paper,
      floor,
      const Offset(1.625, .5),
      ConstructionPaper.cloth,
    );
    construct(
      c,
      ConstructionTool.fold,
      'surface-${sheet.id}',
      const Offset(1.625, .5),
      ConstructionPaper.cloth,
    );
    expect(c.housing.tenants, hasLength(1));
    c.advancePhase();
    c.advancePhase();
    c.advancePhase();
    expect(c.housing.coins, greaterThan(0));
  });
  test('older saves bypass the opening and keep their geometry', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final old = c.toJson()
      ..['version'] = 12
      ..remove('openingComplete');
    c.load(old);
    expect(c.openingComplete, isTrue);
    expect(c.objects, isEmpty);
  });
}
