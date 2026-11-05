import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/completion.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'construction_fixture.dart';

void loop(ProtoplaneController c) {
  for (final i in [0, 2, 8, 6, 0]) {
    expect(c.appendNode(i), isTrue);
  }
}

Map<String, dynamic> snapshot(ProtoplaneController c) =>
    jsonDecode(jsonEncode(c.toJson()));
void main() {
  test(
    'ready harvest is read-only, cancellation awards nothing, release is one transaction',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      final before = snapshot(c);
      var commits = 0;
      c.onCommitted = (_) => commits++;
      c.beginGesture();
      loop(c);
      for (var i = 0; i < 10; i++) {
        expect(c.drawingReady, isTrue, reason: c.completionError());
      }
      expect(c.toJson(), before);
      expect(commits, 0);
      c.cancelGesture();
      expect(c.toJson(), before);
      expect(c.draft.path, isEmpty);
      c.beginGesture();
      loop(c);
      final result = c.commitDrawing()!;
      expect(result.action, PaperAction.removal);
      expect(result.harvest, isNotNull);
      expect(commits, 1);
      expect(c.harvestPending, isFalse);
      final after = snapshot(c);
      c.undo();
      expect(c.toJson(), before);
      expect(c.draft.path, isEmpty);
      c.redo();
      expect(c.toJson(), after);
    },
  );
  test(
    'placement readiness respects budget and retains patterned material',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      c.balances[c.paper] = 0;
      c.beginGesture();
      loop(c);
      expect(c.drawingReady, isFalse);
      expect(c.commitDrawing(), isNull);
      expect(c.objects, isEmpty);
      c.cancelGesture();
      c.balances[c.paper] = 256;
      final before = snapshot(c);
      c.beginGesture();
      loop(c);
      expect(c.objects, isEmpty);
      final result = c.commitDrawing()!;
      expect(result.action, PaperAction.placement);
      expect(result.placedIds, {c.objects.values.single.id});
      expect(c.balances[c.paper], 128);
      c.undo();
      expect(c.toJson(), before);
      expect(c.draft.path, isEmpty);
    },
  );
  test('open scissors split releases both pieces with one undo', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.beginGesture();
    loop(c);
    c.commitDrawing();
    final original = c.objects.values.single;
    c.enter(original.planeId, editObject: original.id);
    final before = snapshot(c);
    c.beginGesture();
    for (final i in [1, 4, 7]) {
      c.appendNode(i);
    }
    expect(c.drawingReady, isTrue, reason: c.completionError());
    expect(c.toJson(), before);
    final result = c.commitDrawing()!;
    expect(result.action, PaperAction.split);
    expect(result.paper, isEmpty);
    expect(c.objects.length, 2);
    c.undo();
    expect(c.toJson(), before);
    expect(c.draft.path, isEmpty);
    c.redo();
    expect(c.objects.length, 2);
  });
  test('closed scissors cut captures only removed area', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.beginGesture();
    loop(c);
    c.commitDrawing();
    final original = c.objects.values.single;
    c.enter(original.planeId, editObject: original.id);
    final before = snapshot(c);
    c.beginGesture();
    for (final i in [0, 1, 4, 3, 0]) {
      c.appendNode(i);
    }
    expect(c.drawingReady, isTrue, reason: c.completionError());
    expect(c.toJson(), before);
    final result = c.commitDrawing()!;
    expect(result.action, PaperAction.removal);
    expect(
      result.paper.fold<double>(0, (sum, o) => sum + o.region.area),
      closeTo(.25, 1e-7),
    );
    expect(c.objects.values.single.region.area, closeTo(.75, 1e-7));
    c.undo();
    expect(c.toJson(), before);
  });
  test('blocked harvest never advertises readiness or succeeds', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.objects['obstacle'] = CraftObject(
      id: 'obstacle',
      planeId: c.activePlaneId!,
      kind: CraftKind.floor,
      region: rectangle(.25, .25),
      material: PaperMaterial.paperWhite,
    );
    final before = snapshot(c);
    c.beginGesture();
    loop(c);
    expect(c.drawingReady, isFalse);
    expect(c.commitDrawing(), isNull);
    expect(c.toJson(), before);
  });
  test('effect settings migrate, persist, and reject malformed values', () {
    final settings = ProtoplaneSettings();
    final legacy = settings.toJson()
      ..remove('effectDurationMs')
      ..remove('haptics')
      ..remove('screenShake');
    settings.load(legacy);
    expect(settings.effectDurationMs, 400);
    expect(settings.haptics, isTrue);
    settings.effectDurationMs = 850;
    settings.haptics = false;
    settings.screenShake = false;
    final loaded = ProtoplaneSettings()..load(settings.toJson());
    expect(loaded.toJson(), settings.toJson());
    expect(
      () => loaded.load({...settings.toJson(), 'effectDurationMs': 0}),
      throwsFormatException,
    );
  });
}
