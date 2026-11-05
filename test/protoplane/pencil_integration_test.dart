import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/models.dart';
import 'pencil_test.dart' show paperWorld;

void main() {
  test(
    'fused constituent ownership, alias coordinates and one atomic charge',
    () {
      final c = paperWorld();
      addTearDown(c.dispose);
      final source = c.planes['test-support']!;
      c.planes['other-support'] = CraftPlane(
        id: 'other-support',
        origin: source.point(const Offset(1, 0)),
        u: source.u,
        v: source.v,
        region: rectangle(1, 1),
        grids: source.grids,
      );
      c.objects['other'] = CraftObject(
        id: 'other',
        planeId: 'other-support',
        kind: CraftKind.floor,
        region: rectangle(1, 1),
        material: PaperMaterial.paperWhite,
        depth: 0,
      );
      final p = c.planes['other-support']!;
      c.planes['surface-other'] = CraftPlane(
        id: 'surface-other',
        origin: p.origin,
        u: p.u,
        v: p.v,
        region: p.region,
        grids: source.grids,
        owner: 'other',
      );
      c.surfaceFusion.rebuild(c.planes, c.objects);
      expect(c.activePlane!.region.area, 2);
      expect(
        c.commitMarks([const PencilSegment(Offset(0, .25), Offset(2, .25))]),
        isTrue,
      );
      expect(c.balances[PaperMaterial.graphite], 120);
      expect(c.pencilMarks.keys, containsAll(['paper', 'other']));
      expect(
        c.pencilMarks['other']!.single.segments.single.a,
        const Offset(0, .25),
      );
      expect(
        c.pencilMarks['other']!.single.id,
        c.pencilMarks['paper']!.single.id,
      );
      c.enter('surface-other');
      expect(
        c.commitMarks([const PencilSegment(Offset(-1, .25), Offset(1, .25))]),
        isTrue,
      );
      expect(c.balances[PaperMaterial.graphite], 120);
      final nav = c.navigationGraph;
      c.selectTool(CraftTool.pencil);
      expect(c.commitMarks(PencilMotif.parallel.segments()), isTrue);
      expect(c.navigationGraph, same(nav));
      final saved = c.toJson();
      c.load(saved);
      c.enter('surface-paper');
      expect(
        c.marksOn(c.activePlane!).fold<double>(0, (sum, s) => sum + s.length),
        closeTo(4, 1e-6),
      );
      expect(c.activePlane!.grids, hasLength(1));
    },
  );
  test('splits and extrusion retain local lattice and clip marks', () {
    final c = paperWorld();
    addTearDown(c.dispose);
    c.commitMarks(PencilMotif.parallel.segments());
    c.enter('test-support', editObject: 'paper');
    c.selectTool(CraftTool.scissors);
    final grid = c.grid!;
    c.beginGesture();
    for (final p in [
      const Offset(.5, 0),
      const Offset(.5, .25),
      const Offset(.5, .5),
      const Offset(.5, .75),
      const Offset(.5, 1),
    ]) {
      expect(c.appendNode(grid.nodes.indexOf(p)), isTrue);
    }
    c.finishGesture();
    expect(c.applyEdit(), isTrue, reason: c.error);
    expect(c.objects.length, 2);
    for (final o in c.objects.values) {
      expect(c.pencilMarks[o.id], isNotEmpty);
      expect(
        c.pencilMarks[o.id]!
            .expand((s) => s.segments)
            .every((s) => o.region.contains(s.a) && o.region.contains(s.b)),
        isTrue,
      );
    }
    final total = c.pencilMarks.values
        .expand((s) => s)
        .expand((s) => s.segments)
        .fold<double>(0, (a, s) => a + s.length);
    expect(total, closeTo(3, 1e-6));
    c.enter('test-support', editObject: 'paper');
    c.setDepth(.1);
    expect(c.applyEdit(), isTrue, reason: c.error);
    c.enter('surface-paper');
    expect(c.marksOn(c.activePlane!), isNotEmpty);
    expect(c.grid!.nodes.where((p) => p.dy == .25), isNotEmpty);
    expect(c.pencilMarks.keys.every(c.objects.containsKey), isTrue);
  });
  test('v5 migration preserves world content and resets marks/discoveries', () {
    final c = paperWorld();
    addTearDown(c.dispose);
    final json = c.toJson()..['version'] = 5;
    for (final key in [
      'pencilMarks',
      'motifs',
      'graphiteMilli',
      'nextStrokeId',
    ]) {
      json.remove(key);
    }
    c.commitMarks(PencilMotif.parallel.segments());
    c.load(json);
    expect(c.pencilMarks, isEmpty);
    expect(c.discoveredMotifs, isEmpty);
    expect(c.objects.length, 1);
    expect(c.balances[PaperMaterial.graphite], 128);
    c.enter('surface-paper');
    expect(c.grid!.nodes, hasLength(9));
    expect(c.activePlane!.grids, hasLength(1));
  });
}
