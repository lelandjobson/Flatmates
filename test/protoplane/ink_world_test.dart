import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/harvest.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/protoplane/paper_patterns.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/protoplane/world_sessions.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void loop(ProtoplaneController c) {
  for (final node in [0, 2, 8, 6, 0]) {
    expect(c.appendNode(node), isTrue);
  }
}

Map<String, dynamic> copy(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Ink defaults and settings selection', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    expect(c.materials, inkMaterials);
    expect(c.balances.values, [256, 256, 256, 256, 0, 0]);
    expect(c.paper, PaperMaterial.white);
    final settings = ProtoplaneSettings();
    expect(settings.worldPreset, WorldPreset.ink);
    settings.worldPreset = WorldPreset.pastel;
    expect(
      (ProtoplaneSettings()..load(settings.toJson())).worldPreset,
      WorldPreset.pastel,
    );
    final legacy = settings.toJson()..remove('worldPreset');
    expect((ProtoplaneSettings()..load(legacy)).worldPreset, WorldPreset.ink);
  });
  for (final seed in [0, 42, 91, 173]) {
    test('calibrated area coverage and accent rarity for seed $seed', () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final landscape = PaperLandscape(seed: seed);
      final areas = {for (final m in inkMaterials) m: 0.0};
      for (final plane in c.planes.values) {
        for (final patch in landscape.generated(plane)) {
          areas[patch.color] = areas[patch.color]! + patch.region.area;
          expect(patch.grain, 0);
        }
      }
      final total = areas.values.reduce((a, b) => a + b);
      expect(total, closeTo(64, 1e-6));
      for (final (index, material) in inkMaterials.indexed) {
        expect(
          areas[material]! / total,
          closeTo([.40, .20, .15, .15, .08, .02][index], .012),
        );
      }
      expect(areas[PaperMaterial.inkBlue], greaterThan(0));
      expect(
        areas[PaperMaterial.inkBlue],
        lessThan(areas[PaperMaterial.inkRed]!),
      );
    });
  }
  test('pattern harvesting, fractions and exact undo/redo', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final plane = c.planes.values.firstWhere((p) {
      final materials = c.landscape.generated(p).map((p) => p.color).toSet();
      return materials.contains(PaperMaterial.dots) && materials.length > 1;
    });
    c.enter(plane.id);
    final before = copy(c.toJson());
    c.beginGesture();
    loop(c);
    final yields = c.harvestPreview!.units;
    expect(yields.containsKey(PaperMaterial.dots), isTrue);
    expect(c.completeCraft(), isTrue);
    c.finishGesture();
    for (final m in yields.keys) {
      expect(
        c.balances[m]! - m.starterUnits + c.landscape.remainders[m]!,
        closeTo(yields[m]!, 1e-7),
      );
    }
    final after = copy(c.toJson());
    c.undo();
    expect(c.toJson(), before);
    c.redo();
    expect(c.toJson(), after);
    c.undo();
    c.beginGesture();
    loop(c);
    c.completeCraft();
    c.cancelGesture();
    expect(c.toJson(), before);
  });
  test('patterned construction, cuts and serialization retain material', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-4-4');
    c.landscape.deplete(c.activePlaneId!, c.activePlane!.region);
    c.selectPaper(PaperMaterial.lines);
    c.beginGesture();
    loop(c);
    expect(c.completeCraft(), isTrue);
    c.finishGesture();
    expect(c.balances[PaperMaterial.lines], 128);
    final object = c.objects.values.single;
    expect(object.material, PaperMaterial.lines);
    final meshes = objectMeshes(object, c.planes[object.planeId]!);
    expect(meshes, isNotEmpty);
    expect(meshes.every((m) => m.surfaceTexture != null), isTrue);
    expect(
      object.copyWith(id: 'split', region: rectangle(.5, 1)).material,
      PaperMaterial.lines,
    );
    final loaded = ProtoplaneController()..load(c.toJson());
    addTearDown(loaded.dispose);
    expect(loaded.objects.values.single.material, PaperMaterial.lines);
    expect(loaded.toJson(), c.toJson());
    c.enter(object.planeId, editObject: object.id);
    for (final node in [1, 4, 7]) {
      c.appendNode(node);
    }
    expect(c.applyEdit(), isTrue, reason: c.error);
    expect(c.objects, hasLength(2));
    expect(
      c.objects.values.every((o) => o.material == PaperMaterial.lines),
      isTrue,
    );
    c.undo();
    expect(c.objects, hasLength(1));
    c.redo();
    expect(c.objects, hasLength(2));
  });
  test('legacy version 2 migrates colors, depletion and balances exactly', () {
    final c = ProtoplaneController(preset: WorldPreset.pastel);
    addTearDown(c.dispose);
    c.balances[PaperMaterial.red] = 20000;
    c.landscape.deplete('ground-4-4', rectangle(.5, 1));
    c.landscape.remainders[PaperMaterial.sand] = .75;
    final expected = copy(c.toJson());
    final legacy = copy(expected)..remove('preset');
    legacy['version'] = 2;
    legacy['balances'] = {
      for (final m in pastelMaterials) m.name: c.balances[m],
    };
    legacy['landscape'].remove('preset');
    legacy['landscape']['remainders'] = {
      for (final m in pastelMaterials) m.name: c.landscape.remainders[m],
    };
    final loaded = ProtoplaneController()..load(legacy);
    addTearDown(loaded.dispose);
    expect(loaded.preset, WorldPreset.pastel);
    expect(loaded.toJson(), expected);
    final invalid = copy(expected);
    invalid['preset'] = 'ink';
    expect(() => loaded.load(invalid), throwsA(anything));
    expect(loaded.toJson(), expected);
  });
  test(
    'world switching retains drafts/history and uses independent recovery',
    () async {
      final dir = await Directory.systemTemp.createTemp('ink-worlds');
      addTearDown(() => dir.delete(recursive: true));
      WorldSessions sessions() => WorldSessions(
        storageFactory: (p) =>
            ProtoplaneStorage(directory: () async => dir, fileName: p.fileName),
      );
      final worlds = sessions();
      addTearDown(worlds.dispose);
      await worlds.load(WorldPreset.ink);
      final ink = worlds.controller(WorldPreset.ink)..enter('ground-4-4');
      ink.beginGesture();
      loop(ink);
      ink.completeCraft();
      ink.finishGesture();
      final harvested = copy(ink.toJson());
      ink.appendNode(0);
      final draft = ink.draft.path.toList();
      final pastel = await worlds.switchFrom(
        WorldPreset.ink,
        WorldPreset.pastel,
      );
      expect(pastel.balances.values, everyElement(256));
      pastel.balances[PaperMaterial.red] = 999;
      expect(
        await worlds.switchFrom(WorldPreset.pastel, WorldPreset.ink),
        same(ink),
      );
      expect(ink.draft.path, draft);
      ink.undo(); // draft append
      ink.undo(); // harvest
      expect(ink.landscape.depleted('ground-4-4'), isEmpty);
      ink.redo();
      expect(ink.toJson(), harvested);
      await worlds.switchFrom(WorldPreset.ink, WorldPreset.pastel);
      final fresh = sessions();
      addTearDown(fresh.dispose);
      await fresh.load(WorldPreset.pastel);
      expect(
        fresh.controller(WorldPreset.pastel).balances[PaperMaterial.red],
        999,
      );
      await File(
        '${dir.path}/protoplane_concept/world-ink.json',
      ).writeAsString('broken');
      await fresh.load(WorldPreset.ink);
      expect(fresh.storage(WorldPreset.ink).recoveryMessage, isNotNull);
      expect(fresh.controller(WorldPreset.ink).toJson(), harvested);
      pastel.clearWorld();
      expect(pastel.balances[PaperMaterial.red], 256);
      expect(ink.toJson(), harvested);
    },
  );
  test(
    'failed save blocks switching and active gesture is cancelled',
    () async {
      final dir = await Directory.systemTemp.createTemp('ink-failure');
      addTearDown(() => dir.delete(recursive: true));
      var fail = false;
      final worlds = WorldSessions(
        storageFactory: (p) => ProtoplaneStorage(
          fileName: p.fileName,
          directory: () async {
            if (fail) throw const FileSystemException('unavailable');
            return dir;
          },
        ),
      );
      addTearDown(worlds.dispose);
      await worlds.load(WorldPreset.ink);
      final ink = worlds.controller(WorldPreset.ink)..enter('ground-4-4');
      final before = copy(ink.toJson());
      ink.beginGesture();
      loop(ink);
      ink.completeCraft();
      fail = true;
      await expectLater(
        worlds.switchFrom(WorldPreset.ink, WorldPreset.pastel),
        throwsA(isA<FileSystemException>()),
      );
      expect(ink.toJson(), before);
      fail = false;
      await worlds.switchFrom(WorldPreset.ink, WorldPreset.pastel);
    },
  );
  test(
    'atlas caches patterns, changes only harvested slots and invalidates preset',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final cache = HarvestMeshCache();
      addTearDown(cache.dispose);
      cache.synchronize(c.planes.values, c.landscape);
      final image = cache.atlas.image;
      final pattern = PaperPatternAtlas.shared.texture(PaperMaterial.dots);
      cache.synchronize(c.planes.values, c.landscape);
      expect(cache.atlas.image, same(image));
      expect(cache.rasterizedTiles, 64);
      c.landscape.deplete('ground-4-4', rectangle(.5, 1));
      cache.synchronize(c.planes.values, c.landscape);
      expect(cache.rasterizedTiles, 65);
      expect(
        PaperPatternAtlas.shared.texture(PaperMaterial.dots),
        same(pattern),
      );
      cache.synchronize(
        c.planes.values,
        PaperLandscape(preset: WorldPreset.pastel),
      );
      expect(cache.rasterizedTiles, 129);
    },
  );
}
