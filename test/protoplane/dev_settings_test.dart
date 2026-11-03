import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/protoplane/models.dart';

void main() {
  test('settings persist separately and reject invalid ranges', () async {
    final dir = await Directory.systemTemp.createTemp('protoplane-settings');
    addTearDown(() => dir.delete(recursive: true));
    final store = ProtoplaneStorage(
      directory: () async => dir,
      fileName: 'settings.json',
    );
    await store.load((j) => ProtoplaneSettings()..load(j));
    final settings = ProtoplaneSettings()
      ..resetDrawingOnRelease = true
      ..gridLines = true
      ..sun = .4;
    await store.save(settings.toJson());
    final loaded = ProtoplaneSettings();
    expect(loaded.entryFocusLevel, 1);
    expect(loaded.disableFocusZoom, isTrue);
    loaded.load((await store.load((j) => ProtoplaneSettings()..load(j)))!);
    expect(loaded.gridLines, isTrue);
    expect(loaded.resetDrawingOnRelease, isTrue);
    loaded.load({...settings.toJson(), 'entryFocusLevel': .4});
    expect(loaded.entryFocusLevel, .4);
    final legacy = Map<String, dynamic>.of(settings.toJson())
      ..remove('entryFocusLevel');
    legacy.remove('disableFocusZoom');
    loaded.load(legacy);
    expect(loaded.disableFocusZoom, isTrue);
    expect(loaded.entryFocusLevel, 1);
    expect(loaded.sun, .4);
    expect(
      () => loaded.load({...settings.toJson(), 'wallFar': 1}),
      throwsFormatException,
    );
    expect(loaded.sun, .4);
    expect(
      await File('${dir.path}/protoplane_concept/world.json').exists(),
      isFalse,
    );
  });
  test(
    'orthogonal dots and directional or complete dots advertise connections',
    () {
      final grid = lattice('ground', rectangle(1, 1));
      expect(
        grid.nodes.indexed.every((p) => grid.dotStyle(p.$1) == 'square'),
        isTrue,
      );
      expect(grid.connection(0, 4), isNull);
      final angular = CraftGrid(
        id: 'a',
        name: 'a',
        nodes: [Offset.zero, const Offset(1, 1), const Offset(0, 1)],
        edges: [const GridEdge(0, 1)],
        recipes: [],
      );
      expect(angular.dotStyle(0), 'circle');
      final complete = CraftGrid(
        id: 's',
        name: 's',
        nodes: angular.nodes,
        edges: [
          const GridEdge(0, 1),
          const GridEdge(0, 2),
          const GridEdge(1, 2),
        ],
        recipes: [],
      );
      expect(complete.dotStyle(0), 'star');
    },
  );
}
