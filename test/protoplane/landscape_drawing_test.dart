import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/models.dart';
import 'layered_terrain_test.dart' show centerId;

void drawRectangle(ProtoplaneController c) {
  c.beginGesture();
  for (final p in [
    const Offset(0, 0),
    const Offset(2, 0),
    const Offset(2, 1),
    const Offset(0, 1),
    const Offset(0, 0),
  ]) {
    expect(c.appendNode(c.grid!.nodes.indexWhere((n) => near(n, p))), isTrue);
  }
  c.finishGesture();
}

void main() {
  test('light pencil bonds tile corners into one persistent volume', () {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    c.enter(centerId(c, PaperMaterial.paperWhite));
    expect(c.sharedLandscapeFocus, isTrue);
    expect(c.grid!.nodes.toSet().length, c.grid!.nodes.length);
    expect(
      c.grid!.nodes.every(
        (n) => n.dx == n.dx.roundToDouble() && n.dy == n.dy.roundToDouble(),
      ),
      isTrue,
    );
    c.balances[PaperMaterial.paperWhite] = 1000;
    drawRectangle(c);
    expect(c.closed, isTrue);
    expect(c.objects, isEmpty);
    c.selectTool(CraftTool.volume);
    c.setDepth(.1);
    expect(c.previewObject!.region.area, closeTo(2, 1e-6));
    expect(c.create(), isTrue, reason: c.error);
    expect(c.objects.length, 1);
    expect(c.objects.values.single.depth, .1);
    final saved = c.toJson();
    final restored = ProtoplaneController()..load(saved);
    addTearDown(restored.dispose);
    expect(restored.objects.values.single.region.area, closeTo(2, 1e-6));
    c.undo();
    expect(c.objects, isEmpty);
    c.redo();
    expect(c.objects.values.single.region.area, closeTo(2, 1e-6));
  });

  test('diagonals are rejected and removal invalidates spanning support', () {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    final id = centerId(c, PaperMaterial.paperWhite);
    c.enter(id);
    final grid = c.grid!;
    c.appendNode(grid.nodes.indexOf(Offset.zero));
    expect(c.appendNode(grid.nodes.indexOf(const Offset(1, 1))), isFalse);
    c.clearDraft();
    drawRectangle(c);
    c.balances[PaperMaterial.paperWhite] = 1000;
    c.landscape.deplete(id, rectangle(1, 1));
    expect(c.create(), isFalse);
    expect(c.error, contains('support'));
  });
}
