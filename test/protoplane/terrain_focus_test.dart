import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/geometry.dart' show Region;
import 'package:flatmates/protoplane/models.dart';
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  test('lower focus cuts topmost intersecting material and stays anchored', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final white = centerId(c, PaperMaterial.paperWhite);
    final cork = centerId(c, PaperMaterial.cork);
    c.enter(cork);
    c.selectTool(CraftTool.scissors);
    drawTile(c);
    expect(c.operationPlane!.id, white);
    expect(c.commitDrawing()!.plane.id, white);
    expect(c.activePlaneId, cork);
    drawTile(c);
    expect(c.operationPlane!.id, centerId(c, PaperMaterial.graphite));
    expect(c.drawingReady, isFalse);
    c.cancelGesture();
    c.selectTool(CraftTool.eraser);
    expect(c.beginErasing(), isTrue);
    expect(c.eraserPlane!.origin.y, -.03);
    c.eraseGraphite([(const Offset(0, .5), const Offset(1, .5))]);
    expect(c.balances[PaperMaterial.graphite], greaterThan(0));
    c.cancelGesture();
    expect(c.balances[PaperMaterial.graphite], 0);
    expect(c.activePlaneId, cork);
  });

  test(
    'clipped disconnected placement uses top layer, exact cost and history',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final white = centerId(c, PaperMaterial.paperWhite);
      final graphite = centerId(c, PaperMaterial.graphite);
      c.landscape.deplete(
        white,
        Region([
          const Offset(.25, 0),
          const Offset(.75, 0),
          const Offset(.75, 1),
          const Offset(.25, 1),
        ]),
      );
      c.enter(graphite);
      c.selectTool(CraftTool.place);
      final before = snapshot(c);
      drawTile(c);
      expect(c.operationPlane!.id, white);
      expect(c.previewObjects.length, 2);
      expect(c.quote, 64);
      expect(c.previewObjects.every((o) => o.planeId == white), isTrue);
      final completion = c.commitDrawing()!;
      expect(completion.paper.length, 2);
      expect(completion.placedIds.length, 2);
      expect(c.balances[PaperMaterial.paperWhite], 192);
      expect(c.activePlaneId, graphite);
      final after = snapshot(c);
      c.undo();
      expect(snapshot(c), before);
      c.redo();
      expect(snapshot(c), after);
    },
  );

  test(
    'placement chooses exposed lower support and empty columns award nothing',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final white = centerId(c, PaperMaterial.paperWhite);
      final graphite = centerId(c, PaperMaterial.graphite);
      c.landscape.deplete(white, rectangle(1, 1));
      c.enter(white);
      c.selectTool(CraftTool.place);
      drawTile(c);
      expect(c.operationPlane!.id, graphite);
      expect(c.commitDrawing()!.plane.origin.y, -.03);
      c.undo();
      for (final p in c.terrainColumn) {
        c.landscape.deplete(p.id, rectangle(1, 1));
      }
      drawTile(c);
      expect(c.operationPlane, isNull);
      expect(c.previewObjects, isEmpty);
      expect(c.commitDrawing(), isNull);
    },
  );
}
