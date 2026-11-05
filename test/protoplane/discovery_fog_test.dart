import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/discovery.dart';
import 'package:flatmates/protoplane/fog_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/map_look_camera_controller.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  test(
    'loading current saves retains discovery independently of remote objects',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final tile = c.landscape.terrain.tiles.values.firstWhere(
        (t) =>
            t.sheet.island == 'northeast' &&
            t.sheet.material == PaperMaterial.paperWhite &&
            c
                    .surfaceRegions(c.planes[t.id]!)
                    .fold<double>(0, (sum, r) => sum + r.area) >
                .999,
      );
      c.enter(tile.id);
      c.selectTool(CraftTool.place);
      c.appendNode(0);
      c.appendNode(1);
      expect(c.commitDrawing(), isNotNull);
      c.revealedAreas.remove('northeast');
      final saved = c.toJson();
      c.load(saved);
      expect(c.revealedAreas, {'starter'});
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'camera entry reveals whole island exactly once; loading replays no events',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final target = c.areas.values.firstWhere((a) => a.id != 'starter');
      expect(c.revealedAreas, {'starter'});
      final notices = <AreaRevealed>[];
      c.onAreaRevealed = notices.add;
      var saves = 0;
      c.onCommitted = (_) => saves++;
      c.discoverAt(const Offset(0, 0));
      c.discoverAt(target.bounds.topLeft - const Offset(1, 1));
      expect(saves, 0);
      c.discoverAt(target.bounds.center);
      c.discoverAt(target.bounds.center);
      expect(c.revealedAreas.length, 2);
      expect(saves, 1);
      expect(notices.single.source, 'camera');
      expect(notices.single.areaId, target.id);
      expect(c.revealArea('missing'), isFalse);
      c.load(snapshot(c));
      expect(notices.length, 1);
      expect(c.revealedAreas.length, 2);
    },
  );
  test(
    'discovery survives crafting undo and cancellation; clear undo restores it',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final other = c.areas.keys.firstWhere((id) => id != 'starter');
      c.enter(centerId(c, PaperMaterial.paperWhite));
      drawTile(c);
      c.commitDrawing();
      c.revealArea(other);
      c.undo();
      expect(c.revealedAreas.length, 2);
      c.redo();
      expect(c.revealedAreas.length, 2);
      c.beginGesture();
      c.cancelGesture();
      expect(c.revealedAreas.length, 2);
      c.clearWorld();
      expect(c.revealedAreas, {'starter'});
      c.undo();
      expect(c.revealedAreas.length, 2);
      c.redo();
      expect(c.revealedAreas, {'starter'});
    },
  );
  test(
    'migration reveals worked islands and rejects malformed discovery atomically',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final other = c.areas.keys.firstWhere((id) => id != 'starter');
      final tile = c.landscape.terrain.tiles.values.firstWhere(
        (t) => t.sheet.island == other,
      );
      c.landscape.collect(
        c.landscape.preview(c.planes[tile.id]!, rectangle(1, 1))!,
      );
      final old = snapshot(c)
        ..['version'] = 6
        ..remove('revealedAreas');
      c.load(old);
      expect(c.revealedAreas.contains(other), isTrue);
      final before = snapshot(c);
      for (final bad in [
        null,
        ['unknown'],
        ['starter', 'starter'],
        [],
      ]) {
        expect(
          () => c.load(snapshot(c)..['revealedAreas'] = bad),
          throwsFormatException,
        );
        expect(snapshot(c), before);
      }
    },
  );
  test('area distances show northeast corner but hide its interior', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final island = c.areas.values.firstWhere((a) => a.id != 'starter');
    final corner = island.footprints
        .expand((r) => r.outer)
        .reduce(
          (a, b) => c.discoveryDistance(a) < c.discoveryDistance(b) ? a : b,
        );
    final d = c.discoveryDistance(corner);
    expect(d, greaterThan(.35));
    expect(d, lessThan(4.35));
    expect(c.discoveryDistance(island.bounds.center), greaterThan(4.35));
    expect(c.discoveryDistance(const Offset(0, 0)), 0);
  });
  test('discovery follows atomic backup recovery', () async {
    final dir = await Directory.systemTemp.createTemp('discovery');
    addTearDown(() => dir.delete(recursive: true));
    final store = ProtoplaneStorage(
      directory: () async => dir,
      fileName: 'world-paper.json',
    );
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.revealAllAreas();
    await store.load((_) {});
    await store.save(c.toJson());
    await store.save(c.toJson());
    await File(
      '${dir.path}/protoplane_concept/world-paper.json',
    ).writeAsString('{bad');
    final recovered = await store.load((j) {
      final validator = ProtoplaneController();
      try {
        validator.load(j);
      } finally {
        validator.dispose();
      }
    });
    expect(store.recoveryMessage, isNotNull);
    c.load(recovered!);
    expect(c.revealedAreas.length, 2);
  });
  test('fog themes and camera limits persist and validate', () {
    final settings = ProtoplaneSettings();
    settings.fog.theme = FogTheme.charcoal;
    settings.fog.style.base = const Color(0xff123456);
    settings.fog.style.speed = .12;
    settings.nearestDistance = 3;
    settings.farthestDistance = 17;
    final saved =
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
    final restored = ProtoplaneSettings()..load(saved);
    expect(restored.toJson(), saved);
    restored.fog.theme = FogTheme.paper;
    expect(restored.fog.style.base, FogTheme.paper.base);
    restored.fog.theme = FogTheme.charcoal;
    expect(restored.fog.style.base, const Color(0xff123456));
    expect(
      () => ProtoplaneSettings().load({...saved, 'farthestDistance': 3}),
      throwsFormatException,
    );
    final invalid = jsonDecode(jsonEncode(saved)) as Map<String, dynamic>;
    invalid['fog']['styles']['paper']['speed'] = -1;
    expect(() => ProtoplaneSettings().load(invalid), throwsFormatException);
    final old = {...saved}
      ..remove('fog')
      ..remove('nearestDistance')
      ..remove('farthestDistance');
    final defaults = ProtoplaneSettings()..load(old);
    expect(defaults.nearestDistance, 2);
    expect(defaults.farthestDistance, 25);
    expect(defaults.fog.theme, FogTheme.paper);
  });
  test(
    'strict orbit limits cover scroll, pinch, animation and restored poses',
    () {
      final camera = Camera(name: 'test', position: Vector3(7, 9, 7));
      final orbit = MapLookCameraController(
        camera: camera,
        vsync: const TestVSync(),
        minDistance: 2,
        maxDistance: 25,
        distance: 11,
        strictZoomBounds: true,
        ladderZoom: false,
      );
      addTearDown(orbit.dispose);
      orbit.zoomByScale(10000);
      expect(orbit.distance, 2);
      orbit.zoomByScroll(100000);
      expect(orbit.distance, 25);
      orbit.setDistanceLimits(3, 7);
      expect(orbit.distance, 7);
      expect(orbit.targetDistance, 7);
      orbit.restorePose(lookAt: Vector3.zero(), distance: 200, yaw: 0);
      expect(orbit.distance, 7);
      final pose = camera.position.clone();
      orbit.setDistanceLimits(3, 5, applyPose: false);
      expect(camera.position, pose);
      expect(orbit.distance, 5);
      expect(() => orbit.setDistanceLimits(8, 3), throwsArgumentError);
      orbit.setPanBounds(Vector3(-4, 0, -25), Vector3(25, 0, 4));
      orbit.restorePose(lookAt: Vector3(15, 0, -15), distance: 4, yaw: 0);
      expect(orbit.lookAt, Vector3(15, 0, -15));
    },
  );
}
