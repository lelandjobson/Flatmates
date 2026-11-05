import 'package:flatmates/protoplane/materials.dart';
import 'construction_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/gestures/point_scrub.dart';

void main() {
  test(
    'release reset clears an uncommitted trace without spending material',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      final balances = Map.of(c.balances);
      c.beginGesture();
      for (final n in [0, 1, 4, 3, 0]) {
        c.appendNode(n);
      }
      expect(c.closed, isTrue);
      c.finishGesture(resetDrawing: true);
      expect(c.draft.path, isEmpty);
      expect(c.objects, isEmpty);
      expect(c.balances, balances);
      expect(c.canUndo, isFalse);
      c.beginGesture();
      c.appendNode(0);
      c.appendNode(1);
      c.finishGesture();
      expect(c.draft.path, [0, 9, 1]);
    },
  );

  test(
    'clear world resets construction and balances, saves and supports undo',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      c.beginGesture();
      for (final n in [0, 1, 4, 3, 0]) {
        c.appendNode(n);
      }
      c.finishGesture();
      expect(c.create(), isTrue);
      final original = c.toJson();
      Map<String, dynamic>? saved;
      c.onCommitted = (json) => saved = json;
      c.clearWorld();
      expect(c.objects, isEmpty);
      expect(c.planes.length, c.landscape.terrain.tiles.length);
      expect(c.activePlane, isNull);
      expect(c.drafts, isEmpty);
      expect(c.balances, {
        PaperMaterial.paperWhite: 256,
        PaperMaterial.graphite: 0,
        PaperMaterial.cork: 0,
      });
      expect(saved, c.toJson());
      c.undo();
      expect(c.toJson(), original);
      c.redo();
      expect(c.objects, isEmpty);
    },
  );

  test(
    'rewind keeps selected past point, protects start and restores suffix on undo',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      c.beginGesture();
      for (final n in [0, 1, 2, 5, 8]) {
        c.appendNode(n);
      }
      c.finishGesture();
      expect(c.rewindDraftTo(0), isFalse);
      expect(c.rewindDraftTo(8), isFalse);
      expect(c.rewindDraftTo(1), isTrue);
      expect(c.draft.path, [0, 9, 1]);
      c.undo();
      expect(c.draft.path, [0, 9, 1, 10, 2, 15, 5, 22, 8]);
      c.redo();
      expect(c.draft.path, [0, 9, 1]);
    },
  );

  test(
    'far collinear node fills intermediate nodes in one drag transaction',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      c.beginGesture();
      expect(c.appendNode(0), isTrue);
      expect(c.appendNode(2), isTrue);
      expect(c.draft.path, [0, 9, 1, 10, 2]);
      c.finishGesture();
      c.undo();
      expect(c.draft.path, isEmpty);
      c.redo();
      expect(c.draft.path, [0, 9, 1, 10, 2]);
    },
  );

  test('scrub rejects jitter, monotonic movement and slow reversals', () {
    final scrub = PointScrub();
    var time = Duration.zero;
    bool move(double x, {int ms = 30}) {
      time += Duration(milliseconds: ms);
      return scrub.update(Offset(x, 0), Offset.zero, time);
    }

    for (final x in [0.0, 2.0, -2.0, 3.0, -3.0, 4.0]) {
      expect(move(x), isFalse);
    }
    scrub.reset();
    for (final x in [0.0, 10.0, 15.0, 20.0, 25.0]) {
      expect(move(x), isFalse);
    }
    scrub.reset();
    expect(move(0), isFalse);
    expect(move(12), isFalse);
    expect(move(-12, ms: 800), isFalse);
    expect(move(12), isFalse);
    expect(move(40), isFalse);
    expect(move(0), isFalse);
  });
  test('scrub accepts deliberate reversals on any axis', () {
    final scrub = PointScrub();
    for (final (i, y) in [0.0, 12.0, -12.0, 12.0].indexed) {
      expect(
        scrub.update(Offset(0, y), Offset.zero, Duration(milliseconds: i * 50)),
        i == 3,
      );
    }
  });
  test(
    'step back reopens a loop, preserves balance and participates in drag history',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      c.enter('ground-starter-paperWhite-0-0');
      final balances = Map.of(c.balances);
      c.beginGesture();
      for (final n in [0, 9, 12, 11, 0]) {
        c.appendNode(n);
      }
      c.finishGesture();
      expect(c.closed, isTrue);
      c.removeLastDraftNode();
      expect(c.closed, isFalse);
      expect(c.draft.path, [0, 9, 12, 11]);
      c.undo();
      expect(c.closed, isTrue);
      c.redo();
      expect(c.draft.path, [0, 9, 12, 11]);
      c.beginGesture();
      c.removeLastDraftNode(continuous: true);
      c.removeLastDraftNode(continuous: true);
      c.finishGesture();
      expect(c.draft.path, [0, 9]);
      c.undo();
      expect(c.draft.path, [0, 9, 12, 11]);
      c.beginGesture();
      c.removeLastDraftNode(continuous: true);
      c.cancelGesture();
      expect(c.draft.path, [0, 9, 12, 11]);
      expect(c.balances, balances);
    },
  );
}
