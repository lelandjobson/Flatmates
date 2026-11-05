import 'dart:convert';
import 'package:flatmates/protoplane/appearance.dart';
import 'package:flatmates/landscape/color_texture_catalog.dart';
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
  final source = lattice('outline', rectangle(1, 1));
  for (final point in path.map((i) => source.nodes[i])) {
    final node = c.grid!.nodes.indexWhere((n) => (n - point).distance < 1e-6);
    expect(node, greaterThanOrEqualTo(0));
    expect(c.appendNode(node), isTrue, reason: '${c.error}: $point');
  }
}

void main() {
  testWidgets(
    'existing paper asset textures atlas once and retains exact geometry',
    (tester) async {
      await tester.runAsync(() async {
        final texture = await ColorTextureCatalog.load(
          ColorTextureCatalog.white,
        );
        expect(texture, isNotNull);
        final c = ProtoplaneController(), cache = HarvestMeshCache();
        try {
          final p = c.planes['ground-starter-paperWhite-0-0']!;
          final original = cache.mesh(p, c.landscape).geometry;
          final untextured = cache.atlas.image;
          cache.setPaperTexture(texture);
          final textured = cache.mesh(p, c.landscape);
          expect(identical(cache.atlas.image, untextured), isFalse);
          expect(textured.geometry.faceColors, original.faceColors);
          expect(textured.geometry.vertices, original.vertices);
          final count = cache.rasterizedTiles;
          cache.setPaperTexture(texture);
          cache.mesh(p, c.landscape);
          expect(cache.rasterizedTiles, count);
          final fill = SurfaceAppearance()..brightness = .1;
          final grain = SurfaceAppearance()..contrast = .8;
          cache.configureStyle(
            fill: fill,
            grain: grain,
            strength: .4,
            repeat: 3,
          );
          cache.mesh(p, c.landscape);
          expect(cache.rasterizedTiles, count + 1);
          cache.configureStyle(
            fill: fill,
            grain: grain,
            strength: .4,
            repeat: 3,
          );
          cache.mesh(p, c.landscape);
          expect(cache.rasterizedTiles, count + 1);
          expect(fill.brightness, .1);
          expect(grain.brightness, 0);
          Future<int> alphaAt(double x, double y) async {
            final mesh = cache.mesh(p, c.landscape),
                source = cache.mesh(p, c.landscape).planarTexture!.source;
            final image = cache.atlas.image!;
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final px = (source.left + x * source.width).floor(),
                py = (source.top + y * source.height).floor();
            expect(mesh.geometry.faces.isNotEmpty, isTrue);
            return bytes[(py * image.width + px) * 4 + 3];
          }

          expect(await alphaAt(.5, .5), 255);
          c.landscape.deplete(
            p.id,
            rectangle(.4, .4, origin: const ui.Offset(.3, .3)),
          );
          // This updates an occupied atlas slot: transparency must overwrite its old pixels.
          expect(await alphaAt(.5, .5), 0);
          expect(await alphaAt(.1, .1), 255);
          final cut = rectangle(.4, .4, origin: const ui.Offset(.3, .3));
          for (final face in cache.mesh(p, c.landscape).geometry.faces) {
            final vertices = cache.mesh(p, c.landscape).geometry.vertices;
            final center =
                face.map((i) => p.local(vertices[i])).reduce((a, b) => a + b) /
                face.length.toDouble();
            expect(cut.contains(center, boundary: false), isFalse);
          }
        } finally {
          cache.dispose();
          texture?.dispose();
          c.dispose();
        }
      });
    },
  );

  test(
    'harvest credits white paper, undo restores it, placement requires switching tools after harvesting',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      expect(c.balances, {
        PaperMaterial.paperWhite: 256,
        PaperMaterial.graphite: 0,
        PaperMaterial.cork: 0,
      });
      c.enter('ground-starter-paperWhite-0-0');
      expect(c.grid!.nodes.length, 9);
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
      expect(identical(graph, c.navigationGraph), isFalse);
      final harvested = c.toJson();
      c.undo();
      expect(c.balances, {
        PaperMaterial.paperWhite: 256,
        PaperMaterial.graphite: 0,
        PaperMaterial.cork: 0,
      });
      expect(c.landscape.remaining(c.activePlane!), isNotEmpty);
      expect(c.draft.path, isEmpty);
      c.redo();
      expect(c.toJson(), harvested);
      c.selectTool(CraftTool.place);
      c.beginGesture();
      outline(c);
      final balance = c.balances[c.paper]!;
      expect(c.harvestPreview, isNull);
      expect(c.completeCraft(), isTrue);
      c.finishGesture();
      expect(c.objects.values.single.kind, CraftKind.floor);
      expect(c.balances[c.paper], balance - 128);
    },
  );

  test('open and cancelled drawings never credit or persist a harvest', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
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
      final plane = c.planes['ground-starter-paperWhite-0-0']!;
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
      for (final color in paperMaterials) {
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
      c.enter('ground-starter-paperWhite-0-0');
      c.beginGesture();
      outline(c);
      c.completeCraft();
      c.finishGesture();
      c.selectTool(CraftTool.place);
      c.beginGesture();
      outline(c);
      c.completeCraft();
      c.finishGesture();
      c.balances[PaperColor.paperWhite] = 20000;
      final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      final restored = ProtoplaneController()..load(saved);
      addTearDown(restored.dispose);
      expect(restored.toJson(), saved);
      final old = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
      old['version'] = 6;
      old.remove('pencilMarks');
      old.remove('motifs');
      old.remove('graphiteMilli');
      old.remove('revealedAreas');
      restored.load(old);
      expect(restored.balances[PaperMaterial.paperWhite], 20000);
      final invalid = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
      invalid['landscape']['remainders']['paper.white'] = 1;
      expect(() => restored.load(invalid), throwsFormatException);
      invalid['landscape']['remainders']['paper.white'] = 0;
      invalid['landscape']['depleted']['missing'] = [rectangle(1, 1).toJson()];
      expect(() => restored.load(invalid), throwsFormatException);
      c.clearWorld();
      expect(c.balances, {
        PaperMaterial.paperWhite: 256,
        PaperMaterial.graphite: 0,
        PaperMaterial.cork: 0,
      });
      expect(
        c.landscape.terrain.tiles['ground-starter-paperWhite-0-0']!.sheet.cuts,
        isEmpty,
      );
      c.undo();
      expect(c.toJson(), saved);
    },
  );

  test('harvest clips to remaining terrain and preserves placed paper', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final plane = c.planes['ground-starter-paperWhite-0-0']!;
    final patch = c.landscape
        .remaining(plane)
        .firstWhere((p) => p.region.area > .001);
    final preview = c.landscape.preview(plane, patch.region)!;
    expect(preview.units.keys, [patch.color]);
    expect(preview.units[patch.color], closeTo(patch.region.area * 128, 1e-6));
    c.enter(plane.id);
    c.beginGesture();
    outline(c, [0, 1, 4, 3, 0]);
    c.completeCraft();
    c.finishGesture();
    c.selectTool(CraftTool.place);
    c.beginGesture();
    outline(c, [0, 1, 4, 3, 0]);
    c.completeCraft();
    c.finishGesture();
    final before = c.toJson();
    c.selectTool(CraftTool.scissors);
    c.beginGesture();
    outline(c);
    expect(c.harvestPreview, isNotNull);
    expect(c.completeCraft(), isTrue);
    c.finishGesture();
    expect(c.toJson()['objects'], before['objects']);
    expect(
      c.balances[PaperMaterial.paperWhite],
      (before['balances']['paper.white'] as int) + 96,
    );
  });

  test('mesh cache reuses unaffected tiles and exact polygon colors', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final cache = HarvestMeshCache(),
        a = c.planes['ground-starter-paperWhite-0-0']!,
        b = c.planes['ground-starter-paperWhite-1-0']!;
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
    expect(cache.rasterizedTiles, c.planes.length);
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
    expect(PaintStatsProbe.scene!.drawCalls, greaterThan(0));
    expect(PaintStatsProbe.scene!.faces, greaterThan(0));
    scene.camera!.position.x += 1;
    paint();
    cache.synchronize(c.planes.values, c.landscape);
    expect(identical(initialImage, cache.atlas.image), isTrue);
    expect(cache.rasterizedTiles, c.planes.length);
    c.landscape.deplete('ground-starter-paperWhite-0-0', rectangle(.5, 1));
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, c.planes.length + 3);
    expect(identical(initialImage, cache.atlas.image), isFalse);
    final restored = PaperLandscape.fromJson(c.landscape.toJson(), c.planes);
    cache.synchronize(c.planes.values, restored);
    expect(cache.rasterizedTiles, c.planes.length + 3);
    // Explicit geometry debug views remain available without replacing the atlas.
    final recorder = ui.PictureRecorder();
    ScenePainter(
      scene: scene,
      debugOptions: const SceneDebugOptions(wireframeOnly: true),
    ).paint(ui.Canvas(recorder), const ui.Size(900, 700));
    recorder.endRecording().dispose();
    expect(PaintStatsProbe.scene!.faces, greaterThan(128));
    expect(cache.rasterizedTiles, c.planes.length + 3);
  });
}
