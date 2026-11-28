import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  ProtoplaneController world() => ProtoplaneController()
    ..enableInPlaceDrawing()
    ..balances[PaperMaterial.paperWhite] = 256;
  String ground(ProtoplaneController c) =>
      centerId(c, PaperMaterial.paperWhite);
  void drawGround(ProtoplaneController c, [double size = 1]) {
    c.constructionTool = ConstructionTool.pencil;
    c.enter(ground(c));
    final region = rectangle(size, size);
    expect(c.commitDrawingPath([...region.outer, region.outer.first]), isTrue);
  }

  CraftObject sheet(
    ProtoplaneController c,
    String plane,
    Offset point, [
    ConstructionPaper paper = ConstructionPaper.building,
  ]) {
    final e = c.evaluateConstruction(
      ConstructionTool.paper,
      plane,
      point,
      paper: paper,
    );
    expect(e.valid, isTrue, reason: e.issue);
    expect(c.applyConstruction(e), isTrue);
    return c.objects[e.object!.id]!;
  }

  CraftObject inflate(
    ProtoplaneController c,
    CraftObject mat, [
    Offset? point,
  ]) {
    final e = c.evaluateConstruction(
      ConstructionTool.volume,
      'surface-${mat.id}',
      point ?? mat.region.bounds.center,
    );
    expect(e.valid, isTrue, reason: e.issue);
    expect(c.applyConstruction(e), isTrue);
    return c.objects[mat.id]!;
  }

  test(
    'ground requires a corner-constrained closed boundary and a sheet before inflation',
    () {
      final c = world();
      addTearDown(c.dispose);
      expect(
        c
            .evaluateConstruction(
              ConstructionTool.volume,
              ground(c),
              const Offset(.5, .5),
            )
            .valid,
        isFalse,
      );
      expect(
        c
            .evaluateConstruction(
              ConstructionTool.paper,
              ground(c),
              const Offset(.5, .5),
            )
            .valid,
        isFalse,
      );
      c.constructionTool = ConstructionTool.pencil;
      c.enter(ground(c));
      expect(
        c.focusDrawingGrid!.nodes.every(
          (p) => p.dx == p.dx.round() && p.dy == p.dy.round(),
        ),
        isTrue,
      );
      expect(c.commitDrawingPath([Offset.zero, const Offset(.25, 0)]), isFalse);
      expect(c.commitDrawingPath([Offset.zero, const Offset(1, 1)]), isFalse);
      drawGround(c, 2);
      final mat = sheet(c, ground(c), const Offset(.5, .5));
      expect(mat.region.area, 4);
      expect(mat.constructionName, 'building mat');
      expect(mat.depth, .01);
      expect(c.drawingSpacingFor('surface-${mat.id}'), 1);
      c.enter('surface-${mat.id}');
      expect(c.commitDrawingPath([Offset.zero, const Offset(1, 0)]), isTrue);
      final volume = inflate(c, mat);
      expect(c.objects.length, 1);
      expect(volume.kind, CraftKind.room);
      expect(volume.depth, 1);
      expect(volume.constructionName, 'building volume');
      expect(c.drawingSpacingFor('surface-${volume.id}-roof-out-0'), .25);
      final drawing = c.drawingGraphs.values.firstWhere(
        (g) => g.surfaceId == 'surface-${volume.id}-roof-out-0',
      );
      expect(
        drawing.frame.origin,
        c.planes['surface-${volume.id}-roof-out-0']!.origin,
      );
      expect(
        c.planes.keys
            .where(
              (id) =>
                  id.startsWith('surface-${volume.id}-wall-') &&
                  id.contains('-out-'),
            )
            .length,
        4,
      );
      c.undo();
      expect(c.objects[mat.id]!.constructionName, 'building mat');
      c.redo();
      expect(c.objects[mat.id]!.constructionName, 'building volume');
    },
  );
  test(
    'cloth becomes a shallow blanket; side sheets and save/load retain their frames',
    () {
      final c = world();
      addTearDown(c.dispose);
      drawGround(c);
      final volume = inflate(c, sheet(c, ground(c), const Offset(.5, .5)));
      c.balances[PaperMaterial.paperGreen] = 32;
      c.enter('surface-${volume.id}-floor-in-0');
      final bedding = rectangle(.5, .5, origin: const Offset(.25, .25));
      expect(
        c.commitDrawingPath([...bedding.outer, bedding.outer.first]),
        isTrue,
      );
      final cloth = sheet(
        c,
        'surface-${volume.id}-floor-in-0',
        const Offset(.5, .5),
        ConstructionPaper.cloth,
      );
      expect(cloth.constructionName, 'cloth sheet');
      expect(cloth.material, PaperMaterial.paperGreen);
      expect(c.drawingSpacingFor('surface-${cloth.id}'), .25);
      final blanket = inflate(c, cloth);
      expect(blanket.kind, CraftKind.inflatedCloth);
      expect(blanket.depth, .05);
      expect(blanket.constructionName, 'large blanket');
      final side = c.planes.keys.firstWhere(
        (id) =>
            id.startsWith('surface-${volume.id}-wall-') && id.contains('-out-'),
      );
      final sideMat = sheet(c, side, c.planes[side]!.region.bounds.center);
      final sideVolume = inflate(c, sideMat);
      expect(c.objectPlane(sideVolume).normal, c.planes[side]!.normal);
      final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final loaded = world()..load(saved);
      addTearDown(loaded.dispose);
      expect(saved['version'], 12);
      expect(loaded.objects.length, 3);
      expect(loaded.objects[blanket.id]!.constructionName, 'large blanket');
      expect(loaded.planes[side]!.normal, c.planes[side]!.normal);
    },
  );
  test(
    'inflation rejects occupied space and attached objects without changing the sheet',
    () {
      final c = world();
      addTearDown(c.dispose);
      drawGround(c);
      final mat = sheet(c, ground(c), const Offset(.5, .5));
      sheet(
        c,
        'surface-${mat.id}',
        const Offset(.5, .5),
        ConstructionPaper.building,
      );
      final before = jsonEncode(c.toJson());
      final e = c.evaluateConstruction(
        ConstructionTool.volume,
        'surface-${mat.id}',
        const Offset(.5, .5),
      );
      expect(e.valid, isFalse);
      expect(c.applyConstruction(e), isFalse);
      expect(jsonEncode(c.toJson()), before);
      c.undo();
      final valid = c.evaluateConstruction(
        ConstructionTool.volume,
        'surface-${mat.id}',
        const Offset(.5, .5),
      );
      expect(c.applyConstruction(valid), isTrue);
      expect(c.applyConstruction(valid), isFalse);
      expect(c.objects[mat.id]!.kind, CraftKind.room);
    },
  );
  test('inflated region preserves holes and hole walls face the opening', () {
    final c = world();
    addTearDown(c.dispose);
    c.enter(ground(c));
    // A legacy quarter-unit drawing remains valid in an older saved world.
    final outer = rectangle(2, 2),
        hole = rectangle(.5, .5, origin: const Offset(.75, .75));
    expect(c.commitDrawingPath([...outer.outer, outer.outer.first]), isTrue);
    expect(c.commitDrawingPath([...hole.outer, hole.outer.first]), isTrue);
    final mat = sheet(c, ground(c), const Offset(.25, .25));
    expect(mat.region.holes, hasLength(1));
    final volume = inflate(c, mat, const Offset(.25, .25));
    expect(volume.region.holes, hasLength(1));
    final sides = c.planes.values.where(
      (p) =>
          p.id.startsWith('surface-${volume.id}-wall-1-') &&
          p.id.contains('-out-'),
    );
    expect(sides, hasLength(4));
    final frame = c.objectPlane(volume),
        opening = frame.point(hole.bounds.center, .5);
    for (final side in sides) {
      final center = side.point(side.region.bounds.center);
      expect(side.normal.dot(opening - center), greaterThan(0));
    }
  });
  test('version 10 remains readable and invalid grid metadata cannot load', () {
    final c = world();
    addTearDown(c.dispose);
    final json = c.toJson()..['version'] = 10;
    (json['balances'] as Map).remove('paper.green');
    c.load(json);
    expect(c.balances[PaperMaterial.paperGreen], 0);
    drawGround(c);
    sheet(c, ground(c), const Offset(.5, .5));
    final invalid = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
    invalid['objects'][0]['drawingSpacing'] = 0;
    expect(() => c.load(invalid), throwsFormatException);
    expect(c.objects.values.single.constructionName, 'building mat');
  });
}
