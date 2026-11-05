import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/layered_terrain.dart';
import 'package:flatmates/protoplane/models.dart';

void drawTile(ProtoplaneController c) {
  final g = c.grid!;
  final corners = [
    const Offset(0, 0),
    const Offset(1, 0),
    const Offset(1, 1),
    const Offset(0, 1),
    const Offset(0, 0),
  ];
  c.beginGesture();
  for (final p in corners) {
    expect(
      c.appendNode(g.nodes.indexWhere((n) => (n - p).distance < 1e-7)),
      isTrue,
    );
  }
}

String centerId(ProtoplaneController c, PaperMaterial m) => c
    .landscape
    .terrain!
    .tiles
    .values
    .firstWhere(
      (t) =>
          t.x == 0 &&
          t.y == 0 &&
          t.sheet.island == 'starter' &&
          t.sheet.material == m,
    )
    .id;
Map<String, dynamic> snapshot(ProtoplaneController c) =>
    jsonDecode(jsonEncode(c.toJson()));

void main() {
  test('starter stack geometry, support, gap and partial cells', () {
    final t = LayeredTerrain.starter();
    expect(t.sheets.length, 6);
    expect(t.sheets[0].footprint.area, closeTo(25, 1e-8));
    expect(t.sheets[3].footprint.area, closeTo(64, 1e-8));
    expect(t.sheets.map((s) => s.elevation).take(3), [0, -.03, -.09]);
    for (final start in [0, 3]) {
      expect(
        t.sheets[start + 1].footprint.containsRegion(t.sheets[start].footprint),
        isTrue,
      );
      expect(
        t.sheets[start + 2].footprint.containsRegion(
          t.sheets[start + 1].footprint,
        ),
        isTrue,
      );
    }
    final a = t.sheets[2].footprint.bounds, b = t.sheets[5].footprint.bounds;
    expect(b.left - a.right, closeTo(2, 1e-8));
    expect(b.top - a.bottom, closeTo(2, 1e-8));
    final partial = t.tiles.values
        .where((v) => v.sheet.material == PaperMaterial.paperWhite)
        .map((v) => t.exposed(v.id).fold<double>(0, (a, r) => a + r.area));
    expect(partial.any((a) => a > 0 && a < .1), isTrue);
  });
  test(
    'release harvests one layer, focus stays stable, empty holes never craft, exact history and saves',
    () {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      expect(c.balances, {
        PaperMaterial.paperWhite: 256,
        PaperMaterial.graphite: 0,
        PaperMaterial.cork: 0,
      });
      final before = snapshot(c);
      final white = centerId(c, PaperMaterial.paperWhite);
      final graphite = centerId(c, PaperMaterial.graphite);
      final cork = centerId(c, PaperMaterial.cork);
      c.enter(white);
      drawTile(c);
      expect(c.drawingReady, isTrue);
      expect(snapshot(c), before);
      c.cancelGesture();
      expect(snapshot(c), before);
      for (final id in [white, graphite, cork]) {
        expect(c.activePlaneId, white);
        if (id == graphite) {
          c.selectTool(CraftTool.eraser);
          expect(c.beginErasing(), isTrue);
          c.eraseGraphite([
            for (var y = 0; y < 16; y++)
              (Offset(0, (y + .5) / 16), Offset(1, (y + .5) / 16)),
          ]);
          c.finishErasing();
        } else {
          c.selectTool(CraftTool.scissors);
          drawTile(c);
          final result = c.commitDrawing();
          expect(
            result?.harvest?.layerId,
            c.landscape.terrain!.tiles[id]!.sheet.id,
          );
        }
        expect(c.landscape.remaining(c.planes[id]!), isEmpty);
      }
      expect(c.balances, {
        PaperMaterial.paperWhite: 384,
        PaperMaterial.graphite: 128,
        PaperMaterial.cork: 128,
      });
      drawTile(c);
      expect(c.drawingReady, isFalse);
      expect(c.commitDrawing(), isNull);
      c.cancelGesture();
      final after = snapshot(c);
      for (var i = 0; i < 3; i++) {
        c.undo();
      }
      expect(snapshot(c), before);
      for (var i = 0; i < 3; i++) {
        c.redo();
      }
      expect(snapshot(c), after);
      final loaded = ProtoplaneController()..load(after);
      addTearDown(loaded.dispose);
      expect(snapshot(loaded), after);
      expect(loaded.landscape.remaining(loaded.planes[cork]!), isEmpty);
      loaded.clearWorld();
      expect(snapshot(loaded), before);
      loaded.undo();
      expect(snapshot(loaded), after);
    },
  );
  test(
    'selected layer masks, clipped slivers, partial overlap and fractional conservation',
    () {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      final landscape = c.landscape;
      final w = c.planes[centerId(c, PaperMaterial.paperWhite)]!;
      final g = c.planes[centerId(c, PaperMaterial.graphite)]!;
      expect(landscape.preview(g, rectangle(1, 1)), isNull);
      final cut = rectangle(.3, .3);
      final white = landscape.preview(w, cut)!;
      expect(landscape.collect(white), {PaperMaterial.paperWhite: 11});
      expect(
        landscape.preview(g, rectangle(1, 1))!.units[PaperMaterial.graphite],
        closeTo(11.52, 1e-7),
      );
      expect(landscape.preview(w, cut), isNull);
      landscape.collect(landscape.preview(w, rectangle(1, 1))!);
      expect(landscape.remainders[PaperMaterial.paperWhite], closeTo(0, 1e-7));
      final tile = landscape.terrain!.tiles.values.firstWhere(
        (t) =>
            t.sheet.material == PaperMaterial.paperWhite &&
            landscape.terrain!
                    .exposed(t.id)
                    .fold<double>(0, (a, r) => a + r.area) >
                0 &&
            landscape.terrain!
                    .exposed(t.id)
                    .fold<double>(0, (a, r) => a + r.area) <
                .1,
      );
      final sliver = landscape.preview(c.planes[tile.id]!, rectangle(1, 1))!;
      expect(sliver.units[PaperMaterial.paperWhite], lessThan(12.8));
      landscape.collect(sliver);
      expect(landscape.preview(c.planes[tile.id]!, rectangle(1, 1)), isNull);
    },
  );
  test(
    'place mode spends paper on support; resources and unsupported placements rejected',
    () {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      final id = centerId(c, PaperMaterial.paperWhite);
      c.enter(id);
      c.selectPaper(PaperMaterial.graphite);
      expect(c.paper, PaperMaterial.paperWhite);
      c.selectTool(CraftTool.place);
      drawTile(c);
      expect(c.harvestPreview, isNull);
      expect(c.commitDrawing(), isNotNull);
      expect(c.balances[PaperMaterial.paperWhite], 128);
      expect(c.landscape.remaining(c.planes[id]!), isNotEmpty);
      c.selectTool(CraftTool.scissors);
      drawTile(c);
      expect(c.drawingReady, isFalse);
      c.cancelGesture();
      c.undo();
      c.landscape.collect(
        c.landscape.preview(c.planes[id]!, rectangle(.5, .5))!,
      );
      c.enter(id);
      c.selectTool(CraftTool.place);
      drawTile(c);
      expect(c.completionError(), isNull);
      expect(c.previewObject!.region.area, closeTo(.75, 1e-8));
      expect(c.commitDrawing(), isNotNull);
    },
  );
  test(
    'settings migration and malformed terrain rejected without changing world',
    () {
      final settings = ProtoplaneSettings();
      final old = settings.toJson()
        ..remove('paperWorldDefault')
        ..remove('tileGridOpacity')
        ..['worldPreset'] = 'ink';
      settings.load(old);
      expect(settings.worldPreset, WorldPreset.paper);
      expect(settings.tileGridOpacity, .12);
      settings.worldPreset = WorldPreset.pastel;
      settings.tileGridOpacity = .37;
      final restored = ProtoplaneSettings()..load(settings.toJson());
      expect(restored.toJson(), settings.toJson());
      final c = ProtoplaneController(preset: WorldPreset.paper);
      addTearDown(c.dispose);
      final before = snapshot(c);
      final bad = snapshot(c);
      bad['landscape']['sheets'][0]['thickness'] = -1;
      expect(() => c.load(bad), throwsFormatException);
      expect(snapshot(c), before);
    },
  );
}
