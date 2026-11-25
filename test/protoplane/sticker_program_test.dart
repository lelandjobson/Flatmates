import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/drawing_graph.dart';
import 'package:flatmates/protoplane/sticker_program.dart';
import 'layered_terrain_test.dart' show centerId;

ProtoplaneController world() {
  final c = ProtoplaneController()..enableInPlaceDrawing();
  c.enter(centerId(c, PaperMaterial.paperWhite));
  return c;
}

void draw(ProtoplaneController c, Region r) {
  expect(c.commitDrawingPath([...r.outer, r.outer.first]), isTrue);
}

void main() {
  test(
    'explicit terrain target spans tiles without changing focus and rejects removed target',
    () {
      final c = world();
      addTearDown(c.dispose);
      final region = rectangle(2, 2);
      draw(c, region);
      final target = centerId(c, PaperMaterial.paperWhite);
      c.leave();
      final evaluation = c.evaluateSticker(
        StickerKind.house,
        region.bounds.center,
        targetPlaneId: target,
      );
      expect(evaluation.valid, isTrue, reason: evaluation.issue);
      expect(c.activePlaneId, isNull);
      expect(c.applySticker(evaluation), isTrue, reason: c.error);
      expect(c.activePlaneId, isNull);
      expect(c.assemblies.length, 1);
      c.undo();
      expect(c.assemblies, isEmpty);
      c.planes.remove(target);
      expect(c.applySticker(evaluation), isFalse);
      expect(c.assemblies, isEmpty);
    },
  );

  test(
    'unsupported connections reject the whole stroke instead of clipping partial edges',
    () {
      final c = world();
      addTearDown(c.dispose);
      final before = jsonEncode(c.toJson());
      expect(
        c.commitDrawingPath([
          Offset.zero,
          const Offset(1, 0),
          const Offset(100, 0),
        ]),
        isFalse,
      );
      expect(jsonEncode(c.toJson()), before);
    },
  );
  for (final kind in [StickerKind.house, StickerKind.hill, StickerKind.bed]) {
    test(
      '${kind.name} is atomic, free, persistent and independent of guides',
      () {
        final c = world();
        addTearDown(c.dispose);
        final r = kind == StickerKind.bed
            ? rectangle(.75, 1.5)
            : rectangle(2, 2);
        draw(c, r);
        final before = jsonEncode(c.toJson()), balance = Map.of(c.balances);
        final evaluation = c.evaluateSticker(kind, r.bounds.center);
        expect(evaluation.valid, isTrue, reason: evaluation.issue);
        expect(jsonEncode(c.toJson()), before);
        expect(c.applySticker(evaluation), isTrue, reason: c.error);
        expect(c.assemblies.length, 1);
        expect(c.balances, balance);
        final count = c.objects.length;
        expect(count, greaterThanOrEqualTo(3));
        final restored = ProtoplaneController()..load(c.toJson());
        addTearDown(restored.dispose);
        expect(restored.objects.length, count);
        expect(restored.drawingGraphs.length, 1);
        c.undo();
        expect(c.objects, isEmpty);
        c.redo();
        expect(c.objects.length, count);
        c.eraseDrawingLine(const Offset(.2, -.1), const Offset(.2, .1));
        expect(c.objects.length, count);
      },
    );
  }
  test(
    'implements never join; smallest face wins before validation; stale drop is rejected',
    () {
      final c = world();
      addTearDown(c.dispose);
      draw(c, rectangle(2, 2));
      final preview = c.evaluateSticker(
        StickerKind.house,
        const Offset(.3, .3),
      );
      c.selectDrawingImplement(DrawingImplement.pen);
      draw(c, rectangle(.5, .5));
      expect(
        c.evaluateSticker(StickerKind.house, const Offset(.3, .3)).issue,
        contains('at least'),
      );
      expect(c.applySticker(preview), isFalse);
      expect(c.objects, isEmpty);
    },
  );
  test('same terrain surface identity, graph save, and v9 migration', () {
    final c = world();
    addTearDown(c.dispose);
    draw(c, rectangle(1, 1));
    final id = c.drawingSurface!.id;
    c.enter('ground-starter-paperWhite-1-0');
    expect(c.drawingSurface!.id, id);
    expect(c.surfaceGraphs.length, 1);
    final saved = c.toJson();
    expect(saved['version'], 10);
    final legacy = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
    legacy['version'] = 9;
    legacy.remove('drawingGraphs');
    legacy.remove('assemblies');
    final other = ProtoplaneController()..load(legacy);
    addTearDown(other.dispose);
    expect(other.drawingGraphs, isEmpty);
  });
  test('door and window cut exact wall regions and reject oversize', () {
    final c = world();
    addTearDown(c.dispose);
    draw(c, rectangle(2, 2));
    expect(
      c.applySticker(c.evaluateSticker(StickerKind.house, const Offset(1, 1))),
      isTrue,
    );
    final wall = c.objects.values.firstWhere((o) => o.kind == CraftKind.wall);
    c.enter('surface-${wall.id}');
    draw(c, rectangle(.25, .75, origin: const Offset(.25, 0)));
    final wallTarget = c.activePlaneId!;
    c.enter(centerId(c, PaperMaterial.paperWhite));
    final focused = c.activePlaneId;
    final door = c.evaluateSticker(
      StickerKind.door,
      const Offset(.375, .3),
      targetPlaneId: wallTarget,
    );
    expect(door.valid, isTrue, reason: door.issue);
    expect(c.applySticker(door), isTrue, reason: c.error);
    expect(c.activePlaneId, focused);
    expect(c.objects[wall.id]!.region.area, closeTo(2 - .25 * .75, 1e-6));
    c.enter(wallTarget);
    draw(c, rectangle(.25, .5, origin: const Offset(1, .25)));
    final window = c.evaluateSticker(
      StickerKind.window,
      const Offset(1.125, .5),
    );
    expect(window.valid, isTrue, reason: window.issue);
    expect(c.applySticker(window), isTrue, reason: c.error);
    expect(c.objects[wall.id]!.region.holes.length, 1);
    draw(c, rectangle(.25, .25, origin: const Offset(1.5, .5)));
    final second = c.evaluateSticker(
      StickerKind.window,
      const Offset(1.625, .625),
    );
    expect(second.valid, isTrue, reason: second.issue);
    expect(c.applySticker(second), isTrue, reason: c.error);
    expect(c.objects[wall.id]!.region.holes.length, 2);
  });
  test(
    'crooked rectangles build rotated beds; independent graphs erase together',
    () {
      final c = world();
      addTearDown(c.dispose);
      c.selectDrawingImplement(DrawingImplement.crookedPencil);
      final impl = c.drawingImplement;
      final r = Region(
        rectangle(
          .75,
          1.25,
          origin: const Offset(.5, 0),
        ).outer.map(impl.toSurface).toList(),
      );
      draw(c, r);
      final evaluation = c.evaluateSticker(
        StickerKind.bed,
        impl.toSurface(const Offset(.75, .5)),
      );
      expect(evaluation.valid, isTrue, reason: evaluation.issue);
      expect(c.applySticker(evaluation), isTrue);
      expect(c.objects.values.first.region.area, closeTo(r.area, 1e-6));
      expect(c.objects.values.first.region.containsRegion(r), isTrue);
      c.selectDrawingImplement(DrawingImplement.pencil);
      draw(c, rectangle(1, 1));
      c.selectDrawingImplement(DrawingImplement.pen);
      draw(c, rectangle(1, 1));
      expect(
        c.eraseDrawingLine(const Offset(.5, -.1), const Offset(.5, .1)),
        isTrue,
      );
      expect(
        c.surfaceGraphs
            .where(
              (g) =>
                  g.implement == DrawingImplement.pencil ||
                  g.implement == DrawingImplement.pen,
            )
            .every((g) => g.edges.length == 3),
        isTrue,
      );
      expect(c.objects.length, 4);
    },
  );
  test(
    'courtyard house preserves holes and collision or missing support rolls back',
    () {
      final c = world();
      addTearDown(c.dispose);
      draw(c, rectangle(2, 2));
      draw(c, rectangle(.5, .5, origin: const Offset(.75, .75)));
      final e = c.evaluateSticker(StickerKind.house, const Offset(.25, .25));
      expect(e.valid, isTrue, reason: e.issue);
      expect(c.applySticker(e), isTrue);
      expect(c.objects.values.first.region.holes.length, 1);
      expect(c.objects.length, 9);
      final before = jsonEncode(c.toJson());
      expect(c.applySticker(e), isFalse);
      expect(jsonEncode(c.toJson()), before);
      c.undo();
      c.landscape.deplete(
        centerId(c, PaperMaterial.paperWhite),
        rectangle(1, 1),
      );
      final removed = jsonEncode(c.toJson());
      expect(
        c.evaluateSticker(StickerKind.house, const Offset(.25, .25)).issue,
        contains('support'),
      );
      expect(jsonEncode(c.toJson()), removed);
      expect(
        c.focusDrawingGrid!.nodes.any((p) => near(p, const Offset(.5, .5))),
        isFalse,
      );
    },
  );
  test(
    'malformed v10 drawing load preserves existing world and open paths are not targets',
    () {
      final c = world();
      addTearDown(c.dispose);
      expect(
        c.commitDrawingPath([
          Offset.zero,
          const Offset(1, 0),
          const Offset(1, 1),
        ]),
        isTrue,
      );
      expect(
        c.evaluateSticker(StickerKind.house, const Offset(.5, .5)).valid,
        isFalse,
      );
      final before = jsonEncode(c.toJson());
      final broken = jsonDecode(before) as Map<String, dynamic>;
      broken['drawingGraphs'][0]['edges'][0] = [0, 0, 1, 1];
      expect(() => c.load(broken), throwsFormatException);
      expect(jsonEncode(c.toJson()), before);
    },
  );
}
