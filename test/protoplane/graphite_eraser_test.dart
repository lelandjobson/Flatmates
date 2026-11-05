import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/graphite_eraser.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart' show Region;
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

ProtoplaneController graphiteWorld() {
  final c = ProtoplaneController(preset: WorldPreset.paper);
  c.enter(centerId(c, PaperMaterial.paperWhite));
  drawTile(c);
  c.commitDrawing();
  c.enter(centerId(c, PaperMaterial.graphite));
  return c;
}

List<(Offset, Offset)> sweep() => [
  for (var y = 0; y < 16; y++)
    (Offset(0, (y + .5) / 16), Offset(1, (y + .5) / 16)),
];
void main() {
  test(
    'mask uses 32 bytes, merges runs, swept fast paths never skip cells',
    () {
      final mask = GraphiteMask();
      expect(mask.bytes.length, 32);
      expect(mask.rectangles(), [const Rect.fromLTWH(0, 0, 1, 1)]);
      final brush = GraphiteBrush([rectangle(1, 1)], [rectangle(1, 1)], []);
      final cells = brush
          .touched(const Offset(0, .5), const Offset(1, .5))
          .toSet();
      expect(cells.length, 32);
      for (final i in cells) {
        mask.remove(i);
      }
      expect(mask.rectangles().length, 2);
      for (var i = 0; i < 256; i++) {
        mask.remove(i);
      }
      expect(mask.rectangles(), isEmpty);
    },
  );
  test(
    'scrub collects immediately, once per cell, one save and exact undo/redo',
    () {
      final c = graphiteWorld();
      addTearDown(c.dispose);
      expect(c.graphiteSelected, isTrue);
      expect(c.tool, CraftTool.eraser);
      final before = snapshot(c);
      var commits = 0;
      c.onCommitted = (_) => commits++;
      expect(c.beginErasing(), isTrue);
      final pieces = c.eraseGraphite([
        (const Offset(.1, .5), const Offset(.9, .5)),
      ]);
      expect(pieces, isNotEmpty);
      final balance = c.balances[PaperMaterial.graphite]!;
      expect(balance, greaterThan(0));
      expect(commits, 0);
      expect(
        c.eraseGraphite([(const Offset(.9, .5), const Offset(.1, .5))]),
        isEmpty,
      );
      expect(c.balances[PaperMaterial.graphite], balance);
      c.finishErasing();
      expect(commits, 1);
      final after = snapshot(c);
      c.undo();
      expect(snapshot(c), before);
      c.redo();
      expect(snapshot(c), after);
      final loaded = ProtoplaneController()..load(after);
      addTearDown(loaded.dispose);
      expect(snapshot(loaded), after);
      final sheet = c.landscape.terrain!.tiles[c.activePlaneId]!.sheet;
      expect(sheet.cuts, isEmpty);
      expect(sheet.erased.values.single.bytes.length, 32);
      expect(jsonEncode(sheet.toJson()['eraser']).length, lessThan(100));
    },
  );
  test('cancel restores masks, resources and exposure without a save', () {
    final c = graphiteWorld();
    addTearDown(c.dispose);
    final before = snapshot(c);
    var commits = 0;
    c.onCommitted = (_) => commits++;
    c.beginErasing();
    c.eraseGraphite(sweep());
    expect(c.balances[PaperMaterial.graphite], 128);
    c.cancelGesture();
    expect(snapshot(c), before);
    expect(commits, 0);
    c.beginErasing();
    c.eraseGraphite(sweep());
    c.finishErasing();
    expect(c.balances[PaperMaterial.graphite], 128);
    expect(c.activePlaneId, centerId(c, PaperMaterial.graphite));
    expect(c.tool, CraftTool.eraser);
  });
  test(
    'covered graphite, partial cover cells, and construction are protected',
    () {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      c.enter(centerId(c, PaperMaterial.graphite));
      c.beginErasing();
      expect(c.eraseGraphite(sweep()), isEmpty);
      c.cancelGesture();
      final p = c.planes[centerId(c, PaperMaterial.paperWhite)]!;
      c.landscape.collect(c.landscape.preview(p, rectangle(.03, 1))!);
      c.beginErasing();
      expect(c.eraseGraphite(sweep()), isEmpty);
      c.cancelGesture();
      final d = graphiteWorld();
      addTearDown(d.dispose);
      d.objects['blocked'] = CraftObject(
        id: 'blocked',
        planeId: d.activePlaneId!,
        kind: CraftKind.floor,
        region: rectangle(.5, 1),
        material: PaperMaterial.paperWhite,
      );
      d.beginErasing();
      d.eraseGraphite(sweep());
      d.finishErasing();
      expect(d.balances[PaperMaterial.graphite], 64);
    },
  );
  test('rotated edge fragments and legacy cuts retain exact yield', () {
    final edge = ProtoplaneController(preset: WorldPreset.paper);
    addTearDown(edge.dispose);
    final terrain = edge.landscape.terrain!;
    double area(List<Region> regions) =>
        regions.fold<double>(0, (a, r) => a + r.area);
    final tile = terrain.tiles.values.firstWhere(
      (t) =>
          t.sheet.material == PaperMaterial.graphite &&
          area(terrain.remainingInTile(t.id)) > 1e-6 &&
          area(terrain.remainingInTile(t.id)) < .5 &&
          (area(terrain.remainingInTile(t.id)) - area(terrain.exposed(t.id)))
                  .abs() <
              1e-7,
    );
    final expected = area(terrain.remainingInTile(tile.id)) * 128;
    edge.enter(tile.id);
    edge.beginErasing();
    edge.eraseGraphite(sweep());
    edge.finishErasing();
    expect(
      edge.balances[PaperMaterial.graphite]! +
          edge.landscape.remainders[PaperMaterial.graphite]!,
      closeTo(expected, 1e-7),
    );
    final restored = ProtoplaneController()..load(snapshot(edge));
    addTearDown(restored.dispose);
    expect(snapshot(restored), snapshot(edge));

    final c = graphiteWorld();
    addTearDown(c.dispose);
    final id = c.activePlaneId!;
    c.landscape.deplete(
      id,
      rectangle(.21, 1),
    ); // version-4 style cut, not a new eraser cell
    c.beginErasing();
    c.eraseGraphite(sweep());
    c.finishErasing();
    expect(
      c.balances[PaperMaterial.graphite]! +
          c.landscape.remainders[PaperMaterial.graphite]!,
      closeTo(.79 * 128, 1e-7),
    );
    expect(c.activePlaneId, centerId(c, PaperMaterial.graphite));
    c.selectTool(CraftTool.scissors);
    drawTile(c);
    expect(c.commitDrawing(), isNotNull);
    restored.load(snapshot(c));
    expect(snapshot(restored), snapshot(c));
  });
  test(
    'small fractional cells accumulate, legacy save loads and malformed masks fail',
    () {
      final c = graphiteWorld();
      addTearDown(c.dispose);
      c.beginErasing();
      // A zero length sample still overlaps squares; fractional total is conserved.
      c.eraseGraphite([
        (const Offset(.03125, .03125), const Offset(.03125, .03125)),
      ]);
      c.finishErasing();
      final tile =
          c.landscape.terrain!.tiles[centerId(c, PaperMaterial.graphite)]!;
      final count = List.generate(
        256,
        (i) => i,
      ).where(tile.sheet.erased[tile.maskKey]!.removed).length;
      expect(
        c.balances[PaperMaterial.graphite]! +
            c.landscape.remainders[PaperMaterial.graphite]!,
        closeTo(count * .5, 1e-8),
      );
      final good = snapshot(c), bad = snapshot(c);
      (bad['landscape']['sheets'] as List).firstWhere(
        (s) => s['material'] == 'paper.graphite',
      )['eraser']['tiles']['0,0'] = 'AA==';
      expect(() => c.load(bad), throwsFormatException);
      expect(snapshot(c), good);
      final legacy = graphiteWorld();
      addTearDown(legacy.dispose);
      final json = snapshot(legacy)..['version'] = 4;
      c.load(json);
      expect(c.balances[PaperMaterial.graphite], 0);
    },
  );
}
