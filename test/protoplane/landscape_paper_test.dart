import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  test(
    'landscape paper shares pencil lattice, cost, discovery and history',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final id = centerId(c, PaperMaterial.paperWhite);
      c.enter(id);
      expect(c.paperSurface, isTrue);
      expect(c.grid!.nodes, hasLength(9));
      c.selectTool(CraftTool.pencil);
      expect(c.grid!.nodes, hasLength(25));
      c.balances[PaperMaterial.graphite] = 128;
      final navigation = c.navigationGraph;
      expect(c.commitMarks(PencilMotif.parallel.segments()), isTrue);
      expect(c.pencilMarks.keys, contains(id));
      expect(c.objects, isEmpty);
      expect(c.balances[PaperMaterial.graphite], 116);
      expect(c.discoveredMotifs, {PencilMotif.parallel});
      expect(identical(navigation, c.navigationGraph), isTrue);
      c.undo();
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], 128);
      expect(c.discoveredMotifs, {PencilMotif.parallel});
      c.redo();
      c.load(c.toJson());
      c.enter(id);
      expect(c.marksOn(c.activePlane!), hasLength(3));
      expect(c.balances[PaperMaterial.graphite], 116);
    },
  );

  test('landscape paper is floor support without a duplicate floor', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final id = centerId(c, PaperMaterial.paperWhite);
    c.enter(id);
    c.selectTool(CraftTool.place);
    c.beginGesture();
    for (final point in const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, .5),
      Offset(0, .5),
      Offset(0, 0),
    ]) {
      expect(c.appendNode(c.grid!.nodes.indexOf(point)), isTrue);
    }
    expect(c.matches, contains(CraftKind.bedFrame));
    c.choose(CraftKind.bedFrame);
    expect(c.completionError(), isNull);
    expect(c.commitDrawing(), isNotNull);
    expect(c.objects.values.single.kind, CraftKind.bedFrame);
    expect(c.objects.values.single.planeId, id);
    expect(c.surfaceRegions(c.planes[id]!), isNotEmpty);
  });

  test('harvesting removes landscape marks and undo restores them', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    final id = centerId(c, PaperMaterial.paperWhite);
    c.enter(id);
    c.balances[PaperMaterial.graphite] = 128;
    c.commitMarks(PencilMotif.parallel.segments());
    c.selectTool(CraftTool.scissors);
    c.beginGesture();
    for (final point in const [
      Offset(0, 0),
      Offset(.5, 0),
      Offset(.5, 1),
      Offset(0, 1),
      Offset(0, 0),
    ]) {
      expect(c.appendNode(c.grid!.nodes.indexOf(point)), isTrue);
    }
    expect(c.commitDrawing(), isNotNull);
    c.finishGesture();
    double length() =>
        c.marksOn(c.planes[id]!).fold<double>(0, (n, s) => n + s.length);
    expect(length(), closeTo(1.5, 1e-8));
    c.undo();
    expect(length(), closeTo(3, 1e-8));
    c.redo();
    expect(length(), closeTo(1.5, 1e-8));
  });

  test(
    'partial landscape clips marks and cannot discover incomplete motifs',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final id = centerId(c, PaperMaterial.paperWhite);
      c.landscape.deplete(id, rectangle(.5, 1));
      c.enter(id);
      c.selectTool(CraftTool.pencil);
      c.balances[PaperMaterial.graphite] = 128;
      expect(c.commitMarks(PencilMotif.parallel.segments()), isTrue);
      expect(c.balances[PaperMaterial.graphite], 122);
      expect(c.discoveredMotifs, isEmpty);
      expect(c.grid!.nodes.every(c.paperContains), isTrue);
      c.load(c.toJson());
      c.enter(id);
      expect(
        c.marksOn(c.activePlane!).fold<double>(0, (n, s) => n + s.length),
        closeTo(1.5, 1e-8),
      );
    },
  );
}
