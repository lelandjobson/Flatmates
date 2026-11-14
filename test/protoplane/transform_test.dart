import 'construction_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/models.dart';

void main() {
  test(
    'completed craft commits once, preserves failed draft and undoes whole drag',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
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
      c.enter('ground-starter-paperWhite-1-0');
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

  test(
    'direct placement is plain paper and has no inferred transformations',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      drawPoints(c, const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
        Offset(0, 0),
      ]);
      expect(c.matches, [CraftKind.floor]);
      expect(c.create(), isTrue);
      final floor = c.objects.values.single;
      c.enter('surface-${floor.id}');
      drawPoints(c, recipePoints(c, CraftKind.rug));
      expect(c.matches, [CraftKind.floor]);
      expect(c.create(), isTrue);
      final paper = c.objects.values.last;
      expect(paper.kind, CraftKind.floor);
      expect(c.transformations(paper.id), isEmpty);
      expect(c.transformObject(paper.id, CraftKind.tabletop), isFalse);
    },
  );
}
