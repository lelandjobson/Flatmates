import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'layered_terrain_test.dart' show centerId;

ProtoplaneController world() {
  final c = ProtoplaneController();
  c.enter(centerId(c, PaperMaterial.paperWhite));
  c.selectTool(CraftTool.place);
  c.balances[PaperMaterial.paperWhite] = 4096;
  return c;
}

void draw(ProtoplaneController c, List<Offset> points) {
  c.beginGesture();
  for (final p in points) {
    final n = c.grid!.nodes.indexWhere((n) => (n - p).distance < 1e-6);
    expect(n, greaterThanOrEqualTo(0), reason: '$p');
    expect(c.appendNode(n), isTrue, reason: '$p');
  }
}

void main() {
  test('cuts cannot remove the landscape support under a wall', () {
    final c = world();
    addTearDown(c.dispose);
    draw(c, const [Offset(0, .5), Offset(1, .5)]);
    c.commitDrawing();
    c.selectTool(CraftTool.scissors);
    draw(c, const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
      Offset(0, 0),
    ]);
    expect(c.completionError(), isNotNull);
    expect(c.commitDrawing(), isNull);
    expect(c.objects, hasLength(1));
  });

  test(
    'fused walls resize and cut as one surface while retaining member marks',
    () {
      final c = world();
      addTearDown(c.dispose);
      draw(c, const [Offset(0, .5), Offset(.5, .5)]);
      c.commitDrawing();
      draw(c, const [Offset(.5, .5), Offset(1, .5)]);
      c.commitDrawing();
      final id = c.objects.keys.first;
      final balance = c.balances[PaperMaterial.paperWhite]!;
      final oldArea = c.objects.values.fold<double>(
        0,
        (n, o) => n + o.materialArea,
      );
      expect(c.resizeLinear(id, extent: 1.5), isTrue);
      final newArea = c.objects.values.fold<double>(
        0,
        (n, o) => n + o.materialArea,
      );
      expect(
        balance - c.balances[PaperMaterial.paperWhite]!,
        ((newArea - oldArea) * 128 - 1e-8).ceil(),
      );
      expect(c.objects.values.every((o) => o.linear!.extent == 1.5), isTrue);
      c.enter('surface-$id');
      c.selectTool(CraftTool.pencil);
      c.balances[PaperMaterial.graphite] = 128;
      c.commitMarks(PencilMotif.crosshatch.segments());
      c.selectTool(CraftTool.scissors);
      expect(c.editingMembers, hasLength(2));
      draw(c, const [
        Offset(.25, .25),
        Offset(.75, .25),
        Offset(.75, .75),
        Offset(.25, .75),
        Offset(.25, .25),
      ]);
      expect(c.completionError(), isNull);
      expect(c.commitDrawing(), isNotNull);
      expect(c.planes['surface-$id']!.region.holes, hasLength(1));
      expect(
        c.objects.values.fold<double>(0, (n, o) => n + o.region.area),
        closeTo(1.25, 1e-7),
      );
      expect(
        c.pencilMarks.values.every((strokes) => strokes.isNotEmpty),
        isTrue,
      );
      c.undo();
      expect(c.planes['surface-$id']!.region.holes, isEmpty);
      c.redo();
      c.load(c.toJson());
      expect(c.planes['surface-$id']!.region.holes, hasLength(1));
    },
  );

  test(
    'created wall has a cuttable, markable surface and retains holes on load',
    () {
      final c = world();
      addTearDown(c.dispose);
      draw(c, const [Offset(0, 0), Offset(1, 0)]);
      c.commitDrawing();
      final wall = c.objects.values.single;
      c.enter('surface-${wall.id}');
      c.selectTool(CraftTool.pencil);
      c.balances[PaperMaterial.graphite] = 128;
      expect(c.commitMarks(PencilMotif.crosshatch.segments()), isTrue);
      c.selectTool(CraftTool.scissors);
      expect(c.editId, wall.id);
      draw(c, const [
        Offset(.25, .25),
        Offset(.75, .25),
        Offset(.75, .75),
        Offset(.25, .75),
        Offset(.25, .25),
      ]);
      expect(c.completionError(), isNull);
      expect(c.commitDrawing(), isNotNull);
      expect(c.objects[wall.id]!.region.holes, hasLength(1));
      expect(
        c
            .marksOn(c.planes['surface-${wall.id}']!)
            .fold<double>(0, (n, s) => n + s.length),
        lessThan(6),
      );
      c.load(c.toJson());
      c.enter('surface-${wall.id}');
      expect(c.objects[wall.id]!.region.holes, hasLength(1));
      c.selectTool(CraftTool.place);
      expect(c.editId, isNull);
      draw(c, const [Offset(0, 0), Offset(1, 0)]);
      expect(c.previewObject!.kind, CraftKind.floor);
    },
  );
  test(
    'coplanar walls fuse regardless of drawing direction, with no internal swipe',
    () {
      final c = world();
      addTearDown(c.dispose);
      final source = c.activePlaneId!;
      draw(c, const [Offset(0, .5), Offset(.5, .5)]);
      c.commitDrawing();
      draw(c, const [Offset(1, .5), Offset(.5, .5)]);
      expect(c.completionError(), isNull);
      c.commitDrawing();
      final walls = c.objects.values.toList();
      final canonical = c.surfaceFusion.canonical['surface-${walls.first.id}'];
      expect(canonical, isNotNull);
      expect(c.surfaceFusion.members[canonical], hasLength(2));
      expect(
        c.navigationGraph.neighbors[source]!
            .map((n) => n.planeId)
            .where((id) => id.startsWith('surface-'))
            .toSet(),
        {canonical},
      );
      expect(
        c.navigationGraph.neighbors[canonical]!.every(
          (n) => n.planeId != canonical,
        ),
        isTrue,
      );
      draw(c, const [Offset(0, .5), Offset(.5, .5)]);
      expect(c.completionError(), isNotNull);
    },
  );
  test('interior wall attachment cannot intercept a floor swipe', () {
    final c = world();
    addTearDown(c.dispose);
    final p = c.activePlane!;
    draw(c, const [Offset(0, .5), Offset(1, .5)]);
    c.commitDrawing();
    final target = 'surface-${c.objects.values.single.id}';
    expect(
      c.navigationGraph.neighbors[p.id]!.any((n) => n.planeId == target),
      isTrue,
    );
    final south = c.landscape.terrain.tiles.values
        .firstWhere(
          (t) =>
              t.x == 0 &&
              t.y == 1 &&
              t.sheet.island == 'starter' &&
              t.sheet.material == PaperMaterial.paperWhite,
        )
        .id;
    expect(
      c.navigationGraph.inDirection(
        p.id,
        const Offset(0, 1),
        const Offset(50, 50),
        (v) {
          final at = p.local(v);
          return at * 100;
        },
      ),
      south,
    );
  });
  test('implied planes default hidden, toggle focuses the real support', () {
    final c = world();
    addTearDown(c.dispose);
    // A floor placed on an exposed non-paper layer exercises legacy candidates.
    c.landscape.deplete(c.activePlaneId!, c.activePlane!.region);
    c.clearDraft();
    draw(c, const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
      Offset(0, 0),
    ]);
    expect(c.commitDrawing(), isNotNull);
    final floor = c.objects.values.single;
    final candidate = c.planes['wall-${floor.id}-0']!;
    expect(c.planeAvailable(candidate), isFalse);
    c.setImpliedProtoplanes(true);
    c.enter(candidate.id);
    expect(c.activePlaneId, candidate.id);
    c.setImpliedProtoplanes(false);
    expect(c.activePlaneId, 'surface-${floor.id}');
    expect(c.objects, hasLength(1));
  });

  test(
    'open floor line creates a real wall, attachment portal, history and save',
    () {
      final c = world();
      addTearDown(c.dispose);
      final source = c.activePlaneId!;
      draw(c, const [Offset(0, .5), Offset(1, .5)]);
      expect(c.linearPlacement, isTrue);
      expect(c.previewObject!.kind, CraftKind.wall);
      expect(c.completionError(), isNull);
      final cost = c.quote;
      expect(c.commitDrawing(), isNotNull);
      final o = c.objects.values.single;
      expect(o.linear!.extent, 1);
      expect(c.balances[PaperMaterial.paperWhite], 4096 - cost);
      expect(c.activePlaneId, source);
      expect(
        c.navigationGraph.neighbors[source]!.any(
          (n) => n.planeId == 'surface-${o.id}',
        ),
        isTrue,
      );
      final saved = c.toJson();
      c.undo();
      expect(c.objects, isEmpty);
      c.redo();
      expect(c.objects, hasLength(1));
      c.load(saved);
      expect(c.objects.values.single.linear, isNotNull);
      expect(c.resizeLinear(o.id, extent: 1.5), isTrue);
      expect(c.objects[o.id]!.region.bounds.height, 1.5);
    },
  );
  test(
    'bends commit atomically, closed outlines retain recipes, insufficient paper changes nothing',
    () {
      final c = world();
      addTearDown(c.dispose);
      draw(c, const [Offset(0, 0), Offset(1, 0), Offset(1, 1)]);
      expect(c.previewObjects, hasLength(2));
      expect(c.completionError(), isNull);
      c.balances[PaperMaterial.paperWhite] = 0;
      expect(c.commitDrawing(), isNull);
      expect(c.objects, isEmpty);
      c.balances[PaperMaterial.paperWhite] = 4096;
      expect(c.commitDrawing(), isNotNull);
      expect(c.objects, hasLength(2));
      c.undo();
      expect(c.objects, isEmpty);
      c.clearDraft();
      draw(c, const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
        Offset(0, 0),
      ]);
      expect(c.linearPlacement, isFalse);
      expect(c.previewObject!.kind, CraftKind.rug);
    },
  );
  test('wall creates level floor or marked ramp, vertical runs rejected', () {
    final c = world();
    addTearDown(c.dispose);
    draw(c, const [Offset(0, 0), Offset(1, 0)]);
    c.commitDrawing();
    final wall = c.objects.values.single;
    c.enter('surface-${wall.id}');
    c.selectTool(CraftTool.place);
    draw(c, const [Offset(0, .5), Offset(1, .5)]);
    expect(c.previewObject!.kind, CraftKind.floor);
    expect(c.completionError(), isNull);
    expect(c.commitDrawing(), isNotNull);
    final floor = c.objects.values.last;
    expect(c.objectPlane(floor).normal.y.abs(), closeTo(1, 1e-8));
    expect(c.resizeLinear(floor.id, flip: true), isTrue);
    c.undo();
    c.undo();
    c.enter('surface-${wall.id}');
    c.selectTool(CraftTool.place);
    c.balances[PaperMaterial.graphite] = 128;
    c.commitMarks([const PencilSegment(Offset(0, 0), Offset(1, 1))]);
    draw(c, const [Offset(0, 0), Offset(1, 1)]);
    expect(c.completionError(), isNull);
    expect(
      c.objectPlane(c.previewObject!).normal.y.abs(),
      closeTo(.70710678, 1e-6),
    );
    c.cancelGesture();
    c.clearDraft();
    draw(c, const [Offset(.5, 0), Offset(.5, 1)]);
    expect(c.completionError(), contains('horizontal or sloped'));
  });
}
