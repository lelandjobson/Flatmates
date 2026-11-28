import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

class FailedWorldStorage extends ProtoplaneStorage {
  Map<String, dynamic>? resetWorld;
  @override
  Future<Map<String, dynamic>?> load(WorldValidator validate) async =>
      throw const FormatException('Broken world');
  @override
  Future<void> reset(Map<String, dynamic> json) async {
    resetWorld = json;
  }
}

void main() {
  test(
    'explicit reset archives failed saves, unlocks writes, and replaces stale backup',
    () async {
      final dir = await Directory.systemTemp.createTemp('world-reset-');
      addTearDown(() => dir.delete(recursive: true));
      final folder = await Directory('${dir.path}/protoplane_concept').create();
      final file = File('${folder.path}/world-paper.json');
      final backup = File('${file.path}.backup');
      await file.writeAsString('broken primary');
      await backup.writeAsString('broken backup');
      final model = ProtoplaneController();
      addTearDown(model.dispose);
      final store = ProtoplaneStorage(directory: () async => dir);
      await expectLater(store.load(model.load), throwsFormatException);
      await expectLater(store.save(model.toJson()), throwsStateError);
      final fresh = model.toJson();
      await store.reset(fresh);
      expect(jsonDecode(await file.readAsString()), fresh);
      expect(jsonDecode(await backup.readAsString()), fresh);
      final retained = await folder
          .list()
          .where((f) => f.path.contains('.reset-'))
          .toList();
      expect(retained, hasLength(2));
      expect(
        await Future.wait(retained.map((f) => File(f.path).readAsString())),
        containsAll(['broken primary', 'broken backup']),
      );
      model.housing.coins = 12;
      await store.save(model.toJson());
      final reload = ProtoplaneStorage(directory: () async => dir);
      final loaded = await reload.load(model.load);
      expect(loaded!['housing']['coins'], 12);
    },
  );

  testWidgets(
    'Clear world stays available in devtools after load failure and restores play',
    (tester) async {
      final model = ProtoplaneController();
      addTearDown(model.dispose);
      model.housing.day = 9;
      model.housing.coins = 42;
      final store = FailedWorldStorage();
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(
            controller: model,
            storage: store,
            animateFog: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load world. Saved files were retained.'),
        findsOneWidget,
      );
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('clear-world'));
      await tester.ensureVisible(clear);
      expect(tester.widget<ListTile>(clear).enabled, isTrue);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(store.resetWorld, isNotNull);
      expect(store.resetWorld!['objects'], isEmpty);
      expect(model.housing.day, 1);
      expect(model.housing.coins, 0);
      expect(
        find.text('Could not load world. Saved files were retained.'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('construction-toolbar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
