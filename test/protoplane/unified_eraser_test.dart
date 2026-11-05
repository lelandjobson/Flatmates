import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'layered_terrain_test.dart' show centerId, snapshot;
import 'pencil_test.dart' show paperWorld;

ProtoplaneController mixedEraserWorld() {
  final c = ProtoplaneController();
  c.balances[PaperMaterial.graphite] = 128;
  final white = centerId(c, PaperMaterial.paperWhite);
  c.enter(white);
  c.commitMarks([const PencilSegment(Offset(.25, .5), Offset(.75, .5))]);
  c.selectTool(CraftTool.scissors);
  c.beginGesture();
  for (final p in [
    const Offset(.5, 0),
    const Offset(1, 0),
    const Offset(1, 1),
    const Offset(.5, 1),
    const Offset(.5, 0),
  ]) {
    final n = c.grid!.nodes.indexWhere((n) => (n - p).distance < 1e-7);
    expect(c.appendNode(n), isTrue);
  }
  expect(c.commitDrawing(), isNotNull);
  c.enter(white);
  c.selectTool(CraftTool.eraser);
  return c;
}

void main() {
  test(
    'one eraser gesture clears marks and exposed graphite with exact undo/redo',
    () {
      final c = mixedEraserWorld();
      addTearDown(c.dispose);
      expect(c.paperSurface, isTrue);
      expect(c.graphitePlane, isNotNull);
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      final before = snapshot(c), balance = c.balances[PaperMaterial.graphite]!;
      final graphite = c.graphitePlane!.id;
      var saves = 0;
      c.onCommitted = (_) => saves++;
      expect(c.beginErasing(), isTrue);
      final pieces = c.eraseStroke([
        (const Offset(.1, .5), const Offset(.9, .5)),
      ]);
      expect(pieces, isNotEmpty);
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], greaterThan(balance));
      expect(
        c.landscape.terrain
            .remainingInTile(graphite)
            .any((r) => r.contains(const Offset(.25, .5))),
        isTrue,
      );
      expect(saves, 0);
      c.finishErasing();
      expect(saves, 1);
      final after = snapshot(c);
      c.undo();
      expect(snapshot(c), before);
      c.redo();
      expect(snapshot(c), after);
      c.beginErasing();
      c.eraseStroke([(const Offset(.9, .6), const Offset(.5, .6))]);
      c.cancelGesture();
      expect(snapshot(c), after);
    },
  );
  test(
    'same eraser supports mark-only surfaces without refunding graphite',
    () {
      final c = paperWorld();
      addTearDown(c.dispose);
      c.commitMarks([const PencilSegment(Offset(.25, .5), Offset(.75, .5))]);
      c.selectTool(CraftTool.eraser);
      final beforeMarks = c
          .marksOn(c.activePlane!)
          .map((s) => s.toJson())
          .toList();
      final balance = c.balances[PaperMaterial.graphite];
      expect(c.graphitePlane, isNull);
      expect(c.beginErasing(), isTrue);
      expect(
        c.eraseStroke([(const Offset(.5, .25), const Offset(.5, .75))]),
        isEmpty,
      );
      c.finishErasing();
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], balance);
      c.undo();
      expect(
        c.marksOn(c.activePlane!).map((s) => s.toJson()).toList(),
        beforeMarks,
      );
    },
  );
}
