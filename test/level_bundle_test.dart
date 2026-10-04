import 'dart:io';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every levels collection folder is bundled in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final folders = Directory('levels')
        .listSync()
        .whereType<Directory>()
        .where((dir) => File('${dir.path}/collection.json').existsSync())
        .map((dir) => dir.path.split(Platform.pathSeparator).last);
    for (final folder in folders) {
      expect(pubspec, contains('- levels/$folder/'), reason: folder);
    }
  });

  test('bundled collections load without a levels folder on disk', () async {
    final directory = Directory.systemTemp.createTempSync('bundle-empty');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(
      directory: Directory('${directory.path}/levels'),
      bundle: rootBundle,
    );

    final collections = await store.loadCollections();
    final sharp = collections.firstWhere((c) => c.id == 'sharp-turns');
    expect(sharp.name, 'Sharp Turns');
    expect(sharp.puzzles, hasLength(10));
    expect(sharp.puzzles.map((p) => p.name), contains('Wrong Way Round'));
  });

  test('disk puzzles win over bundled copies with the same id', () async {
    final directory = Directory.systemTemp.createTempSync('bundle-disk');
    addTearDown(() => directory.deleteSync(recursive: true));
    final root = Directory('${directory.path}/levels');
    final disk = LevelStore(directory: root);
    final edited = GridBlueprint(
      id: 'sharp-turns-01',
      name: 'Edited Round',
      steps: twinLsBlueprint().steps,
    );
    await disk.savePuzzle(
      collectionName: 'Sharp Turns',
      puzzle: edited,
      fromCollectionId: null,
    );

    final store = LevelStore(directory: root, bundle: rootBundle);
    final collections = await store.loadCollections();
    final sharp = collections.where((c) => c.id == 'sharp-turns').toList();
    expect(sharp, hasLength(1));
    expect(sharp.single.puzzles, hasLength(10));
    final first = sharp.single.puzzles.where((p) => p.id == 'sharp-turns-01');
    expect(first.single.name, 'Edited Round');
  });
}
