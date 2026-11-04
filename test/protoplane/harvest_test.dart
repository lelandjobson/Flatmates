import 'dart:convert';
import 'dart:ui' as ui;
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/debug/scene_paint_stats.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/harvest.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';

void outline(ProtoplaneController c, [List<int> path = const [0, 2, 8, 6, 0]]) {
  for (final node in path) {
    expect(c.appendNode(node), isTrue, reason: '${c.error}: $node');
  }
}

void main() {
  test(
    'field is deterministic, continuous at seams, and all five papers occur',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final other = PaperLandscape();
      final colors = <PaperColor>{};
      for (final plane in c.planes.values) {
        final patches = c.landscape.generated(plane);
        colors.addAll(patches.map((p) => p.color));
        expect(
          patches.fold<double>(0, (v, p) => v + p.region.area),
          closeTo(1, 1e-6),
        );
      }
      expect(colors, PaperColor.values.toSet());
      final a = c.planes['ground-4-4']!, b = c.planes['ground-5-4']!;
      for (var i = 0; i <= 16; i++) {
        final left = a.point(Offset(1, i / 16));
        final right = b.point(Offset(0, i / 16));
        expect(
          c.landscape.sample(left.x, -left.z),
          other.sample(right.x, -right.z),
        );
      }
      expect(
        c.landscape.generated(a).map((p) => p.region.toJson()),
        other.generated(a).map((p) => p.region.toJson()),
      );
    },
  );

  test('harvest credits visible mix, undo restores it, second cut builds', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    expect(c.balances.values, everyElement(256));
    c.enter('ground-4-4');
    expect(c.grid!.nodes.length, 25);
    final graph = c.navigationGraph;
    c.beginGesture();
    outline(c);
    final expected = c.harvestPreview!.units;
    expect(c.previewObject, isNull);
    expect(c.completeCraft(), isTrue);
    expect(c.objects, isEmpty);
    expect(c.harvestPending, isTrue);
    c.finishGesture();
    for (final color in expected.keys) {
      expect(
        c.balances[color]! - 256 + c.landscape.remainders[color]!,
        closeTo(expected[color]!, 1e-7),
      );
    }
    expect(c.landscape.remaining(c.activePlane!), isEmpty);
    expect(identical(graph, c.navigationGraph), isTrue);
    final harvested = c.toJson();
    c.undo();
    expect(c.balances.values, everyElement(256));
    expect(c.landscape.remaining(c.activePlane!), isNotEmpty);
    expect(c.draft.path, isEmpty);
    c.redo();
    expect(c.toJson(), harvested);
    c.beginGesture();
    outline(c);
    final balance = c.balances[c.paper]!;
    expect(c.harvestPreview, isNull);
    expect(c.completeCraft(), isTrue);
    c.finishGesture();
    expect(c.objects.values.single.kind, CraftKind.floor);
    expect(c.balances[c.paper], balance - 128);
  });

  test('open and cancelled drawings never credit or persist a harvest', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-4-4');
    final initial = c.toJson();
    var saves = 0;
    c.onCommitted = (_) => saves++;
    c.beginGesture();
    outline(c, [0, 2, 8]);
    expect(c.completeCraft(allowOpen: true), isFalse);
    c.cancelGesture();
    expect(c.toJson(), initial);
    c.beginGesture();
    outline(c);
    expect(c.completeCraft(), isTrue);
    expect(saves, 0);
    c.cancelGesture();
    expect(c.toJson(), initial);
    expect(c.canUndo, isFalse);
    expect(saves, 0);
  });

  test(
    'partial overlap collects only untouched portions and fractional yield is conserved',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final plane = c.planes['ground-4-4']!;
      final whole = PaperLandscape(), split = PaperLandscape();
      final fullCredits = whole.collect(whole.preview(plane, plane.region)!);
      final totals = <PaperColor, int>{};
      for (var x = 0; x < 4; x++) {
        final cut = Region([
          Offset(x / 4, 0),
          Offset((x + 1) / 4, 0),
          Offset((x + 1) / 4, 1),
          Offset(x / 4, 1),
        ]);
        final credits = split.collect(split.preview(plane, cut)!);
        for (final e in credits.entries) {
          totals.update(e.key, (n) => n + e.value, ifAbsent: () => e.value);
        }
        expect(split.preview(plane, cut), isNull);
      }
      for (final color in PaperColor.values) {
        expect(
          (totals[color] ?? 0) + split.remainders[color]!,
          closeTo((fullCredits[color] ?? 0) + whole.remainders[color]!, 1e-6),
        );
      }
      c.enter(plane.id);
      c.beginGesture();
      outline(c, [0, 1, 7, 6, 0]);
      c.completeCraft();
      c.finishGesture();
      c.beginGesture();
      outline(c);
      expect(
        c.harvestPreview!.units.values.fold<double>(0, (a, b) => a + b),
        closeTo(64, 1e-6),
      );
      c.completeCraft();
      c.finishGesture();
      expect(c.objects, isEmpty);
    },
  );

  test(
    'save migration, large balances, malformed depletion, and clear world',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      c.enter('ground-4-4');
      c.beginGesture();
      outline(c);
      c.completeCraft();
      c.finishGesture();
      c.beginGesture();
      outline(c);
      c.completeCraft();
      c.finishGesture();
      c.balances[PaperColor.red] = 20000;
      final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final restored = ProtoplaneController()..load(saved);
      addTearDown(restored.dispose);
      expect(restored.toJson(), saved);
      final old = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
      old['version'] = 1;
      old.remove('landscape');
      (old['balances'] as Map).remove('blue');
      (old['balances'] as Map).remove('sand');
      final ground = (old['planes'] as List).firstWhere(
        (p) => p['id'] == 'ground-4-4',
      );
      ground['grids'] = [lattice('ground-4-4', rectangle(1, 1)).toJson()];
      restored.load(old);
      expect(restored.balances[PaperColor.red], 20000);
      expect(restored.balances[PaperColor.blue], 256);
      expect(
        restored.planes['ground-4-4']!.grids.first.nodes.take(9),
        lattice('old', rectangle(1, 1)).nodes,
      );
      expect(
        restored.landscape.remaining(restored.planes['ground-4-4']!),
        isEmpty,
      );
      final invalid = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
      invalid['landscape']['remainders']['red'] = 1;
      expect(() => restored.load(invalid), throwsFormatException);
      invalid['landscape']['remainders']['red'] = 0;
      invalid['landscape']['depleted']['missing'] = [rectangle(1, 1).toJson()];
      expect(() => restored.load(invalid), throwsFormatException);
      c.clearWorld();
      expect(c.balances.values, everyElement(256));
      expect(c.landscape.depleted('ground-4-4'), isEmpty);
      c.undo();
      expect(c.toJson(), saved);
    },
  );

  test(
    'single-color patch yields only its color and placed paper blocks mixed cuts',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final plane = c.planes['ground-4-4']!;
      final patch = c.landscape
          .generated(plane)
          .firstWhere((p) => p.region.area > .001);
      final preview = c.landscape.preview(plane, patch.region)!;
      expect(preview.units.keys, [patch.color]);
      expect(
        preview.units[patch.color],
        closeTo(patch.region.area * 128, 1e-6),
      );
      c.enter(plane.id);
      c.beginGesture();
      outline(c, [0, 1, 4, 3, 0]);
      c.completeCraft();
      c.finishGesture();
      c.beginGesture();
      outline(c, [0, 1, 4, 3, 0]);
      c.completeCraft();
      c.finishGesture();
      final before = c.toJson();
      c.beginGesture();
      outline(c);
      expect(c.harvestPreview, isNotNull);
      expect(c.completeCraft(), isFalse);
      expect(c.error, 'Cutout overlaps placed paper');
      c.finishGesture();
      expect(c.toJson(), before);
    },
  );

  test('mesh cache reuses unaffected tiles and exact polygon colors', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final cache = HarvestMeshCache(),
        a = c.planes['ground-4-4']!,
        b = c.planes['ground-5-4']!;
    addTearDown(cache.dispose);
    final before = cache.mesh(a, c.landscape),
        neighbor = cache.mesh(b, c.landscape);
    expect(before.geometry.faces.length, c.landscape.remaining(a).length);
    expect(before.material.exactPerFaceColors, isTrue);
    c.landscape.deplete(a.id, rectangle(.5, 1));
    expect(
      identical(cache.mesh(a, c.landscape).geometry, before.geometry),
      isFalse,
    );
    expect(
      identical(cache.mesh(b, c.landscape).geometry, neighbor.geometry),
      isTrue,
    );
    final restored = PaperLandscape.fromJson(c.landscape.toJson(), c.planes);
    expect(
      identical(cache.mesh(b, restored).geometry, neighbor.geometry),
      isTrue,
    );
  });
  test('atlas rasterizes only dirty slots and submits one sprite per tile', () {
    final c = ProtoplaneController(), cache = HarvestMeshCache();
    final scene = Scene(globalIllumination: 1)
      ..camera = Camera(name: 'Atlas test', position: Vector3(8, 12, 8));
    addTearDown(() {
      scene.dispose();
      cache.dispose();
      c.dispose();
    });
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, 64);
    final initialImage = cache.atlas.image;
    scene.setMeshes(c.planes.values.map((p) => cache.mesh(p, c.landscape)));
    void paint() {
      final recorder = ui.PictureRecorder();
      ScenePainter(
        scene: scene,
      ).paint(ui.Canvas(recorder), const ui.Size(900, 700));
      recorder.endRecording().dispose();
    }

    paint();
    expect(PaintStatsProbe.scene!.drawCalls, 64);
    expect(PaintStatsProbe.scene!.faces, 128);
    scene.camera!.position.x += 1;
    paint();
    cache.synchronize(c.planes.values, c.landscape);
    expect(identical(initialImage, cache.atlas.image), isTrue);
    expect(cache.rasterizedTiles, 64);
    c.landscape.deplete('ground-4-4', rectangle(.5, 1));
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, 65);
    expect(identical(initialImage, cache.atlas.image), isFalse);
    final restored = PaperLandscape.fromJson(c.landscape.toJson(), c.planes);
    cache.synchronize(c.planes.values, restored);
    expect(cache.rasterizedTiles, 65);
    // Explicit geometry debug views remain available without replacing the atlas.
    final recorder = ui.PictureRecorder();
    ScenePainter(
      scene: scene,
      debugOptions: const SceneDebugOptions(wireframeOnly: true),
    ).paint(ui.Canvas(recorder), const ui.Size(900, 700));
    recorder.endRecording().dispose();
    expect(PaintStatsProbe.scene!.faces, greaterThan(128));
    expect(cache.rasterizedTiles, 65);
  });
}
