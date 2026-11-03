import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/recipes.dart';

void main() {
  test(
    'completed craft commits once, preserves failed draft and undoes whole drag',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      c.enter('ground-4-4');
      c.beginGesture();
      for (final n in [0, 1, 4, 3, 0]) {
        c.appendNode(n);
      }
      expect(c.completeCraft(), isTrue);
      expect(c.objects.length, 1);
      expect(c.draft.path, isEmpty);
      c.finishGesture();
      c.undo();
      expect(c.objects, isEmpty);
      expect(c.draft.path, isEmpty);
      expect(c.canUndo, isFalse);
      c.redo();
      expect(c.objects.length, 1);
      c.enter('ground-5-4');
      c.balances[c.paper] = 0;
      c.beginGesture();
      for (final n in [0, 1, 4, 3, 0]) {
        c.appendNode(n);
      }
      expect(c.completeCraft(), isFalse);
      expect(c.closed, isTrue);
      expect(c.error, isNotNull);
      expect(c.objects.length, 1);
    },
  );

  test('automatic first match follows recipe priority', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.enter('ground-4-4');
    c.beginGesture();
    for (final n in [0, 2, 8, 6, 0]) {
      c.appendNode(n);
    }
    c.finishGesture();
    c.create();
    final floor = c.objects.values.single;
    c.enter('surface-${floor.id}');
    c.beginGesture();
    for (final n in c.grid!.examples[CraftKind.rug]!) {
      c.appendNode(n);
    }
    c.finishGesture();
    expect(c.matches.length, greaterThan(1));
    expect(c.chosen, c.matches.first);
    expect(
      recipes[c.chosen]!.priority,
      lessThanOrEqualTo(recipes[CraftKind.tabletop]!.priority),
    );
    expect(c.create(), isTrue);
    final rug = c.objects.values.last;
    expect(rug.kind, CraftKind.rug);
    final outline = rug.region.toJson(), balances = Map.of(c.balances);
    expect(c.transformations(rug.id), contains(CraftKind.tabletop));
    final quote = c.transformationQuote(rug.id, CraftKind.tabletop);
    expect(c.transformObject(rug.id, CraftKind.tabletop), isTrue);
    expect(c.objects[rug.id]!.region.toJson(), outline);
    expect(c.objects[rug.id]!.kind, CraftKind.tabletop);
    expect(c.balances[rug.color], balances[rug.color]! - quote);
    c.undo();
    expect(c.objects[rug.id]!.kind, CraftKind.rug);
    expect(c.balances, balances);
    c.redo();
    expect(c.objects[rug.id]!.kind, CraftKind.tabletop);
    expect(c.transformObject(floor.id, CraftKind.rug), isFalse);
  });
}
