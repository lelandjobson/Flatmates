import 'recipe_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:vector_math/vector_math_64.dart';

ProtoplaneController paperWorld({Region? region}) {
  final c = ProtoplaneController();
  final p = CraftPlane(
    id: 'test-support',
    origin: Vector3.zero(),
    u: Vector3(1, 0, 0),
    v: Vector3(0, 0, -1),
    region: rectangle(1, 1),
    grids: [lattice('test', rectangle(1, 1))],
  );
  c.planes[p.id] = p;
  final r = region ?? rectangle(1, 1);
  c.objects['paper'] = CraftObject(
    id: 'paper',
    planeId: p.id,
    kind: CraftKind.floor,
    region: r,
    material: PaperMaterial.paperWhite,
    depth: 0,
  );
  c.planes['surface-paper'] = CraftPlane(
    id: 'surface-paper',
    origin: p.origin,
    u: p.u,
    v: p.v,
    region: r,
    owner: 'paper',
    grids: floorGrids('test', r, 42),
  );
  c.balances[PaperMaterial.graphite] = 128;
  c.enter('surface-paper');
  return c;
}

void main() {
  test(
    'blank half grid, quarter pencil, intersections do not unlock unmarked paths',
    () {
      final r = rectangle(1, 1);
      expect(paperDrawingGrid('a', r, [], []).nodes, hasLength(9));
      expect(
        paperDrawingGrid('a', r, [], [], pencil: true).nodes,
        hasLength(25),
      );
      final g = paperDrawingGrid('a', r, [
        const PencilSegment(Offset(0, .25), Offset(1, .75)),
      ], []);
      expect(
        g.nodes,
        containsAll([
          const Offset(0, .25),
          const Offset(.5, .5),
          const Offset(1, .75),
        ]),
      );
      final a = g.nodes.indexOf(const Offset(0, .25)),
          b = g.nodes.indexOf(const Offset(.5, 0));
      expect(g.collinearRoute(a, b), isNull);
    },
  );
  test('clip holes, subtract reversed and subdivided coincident coverage', () {
    final s = const PencilSegment(Offset(0, .5), Offset(1, .5));
    final r = Region(rectangle(1, 1).outer, [
      rectangle(.5, .5, origin: const Offset(.25, .25)).outer,
    ]);
    final clipped = clipPencil([s], r);
    expect(clipped.fold<double>(0, (a, s) => a + s.length), closeTo(.5, 1e-8));
    expect(
      newPencilCoverage(
        [s],
        [
          const PencilSegment(Offset(.5, .5), Offset(0, .5)),
          const PencilSegment(Offset(1, .5), Offset(.5, .5)),
        ],
      ),
      isEmpty,
    );
  });
  for (final motif in PencilMotif.values) {
    for (var turn = 0; turn < 4; turn++) {
      test(
        '${motif.name} rotation $turn reversed/subdivided/extra coverage',
        () {
          final lines = motif.segments(turns: turn), marks = <PencilSegment>[];
          for (final s in lines) {
            final mid = (s.a + s.b) / 2;
            marks.addAll([PencilSegment(s.b, mid), PencilSegment(mid, s.a)]);
          }
          marks.add(const PencilSegment(Offset.zero, Offset(.25, .75)));
          expect(motif.covered(marks.reversed, Offset.zero), isTrue);
          expect(motif.covered(lines.skip(1), Offset.zero), isFalse);
        },
      );
    }
  }
  test(
    'commit, cost, free retrace, persistent discoveries, erasing, undo and load',
    () {
      final c = paperWorld();
      addTearDown(c.dispose);
      final nav = c.navigationGraph;
      expect(c.commitMarks(PencilMotif.parallel.segments()), isTrue);
      expect(c.balances[PaperMaterial.graphite], 116);
      expect(identical(c.navigationGraph, nav), isTrue);
      expect(c.discoveredMotifs, {PencilMotif.parallel});
      expect(c.motifNotices, hasLength(1));
      c.motifNotices.clear();
      c.commitMarks(PencilMotif.parallel.segments());
      expect(c.balances[PaperMaterial.graphite], 116);
      expect(c.motifNotices, isEmpty);
      c.undo();
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], 128);
      expect(c.discoveredMotifs, {PencilMotif.parallel});
      c.redo();
      c.beginGesture();
      c.eraseMarks(const Offset(.5, .2), const Offset(.5, .8));
      c.finishGesture();
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], 116);
      c.undo();
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      final saved = c.toJson();
      c.load(saved);
      c.enter('surface-paper');
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      final empty = paperWorld();
      addTearDown(empty.dispose);
      c.load(empty.toJson());
      expect(c.discoveredMotifs, isEmpty);
    },
  );
  test('diagonal fractional charge, cancellation and insufficient preview', () {
    final c = paperWorld();
    addTearDown(c.dispose);
    c.selectTool(CraftTool.pencil);
    c.beginPencil(Offset.zero);
    c.extendPencil(const Offset(1, 1));
    expect(c.pencilPreview, hasLength(5));
    c.cancelPencil();
    expect(c.balances[PaperMaterial.graphite], 128);
    c.beginPencil(Offset.zero);
    c.extendPencil(const Offset(1, 1));
    expect(c.commitPencil(), isTrue);
    expect(c.balances[PaperMaterial.graphite], 122);
    expect(c.graphiteMilli, 343);
    c.balances[PaperMaterial.graphite] = 0;
    c.graphiteMilli = 0;
    c.beginPencil(const Offset(1, 0));
    c.extendPencil(const Offset(0, 1));
    final count = c.marksOn(c.activePlane!).length;
    expect(c.commitPencil(), isFalse);
    expect(c.previewMarks, isNotEmpty);
    expect(c.marksOn(c.activePlane!), hasLength(count));
    c.leave();
    expect(c.previewMarks, isEmpty);
  });
  test('clipped stamp atomic cost and incomplete motifs', () {
    final c = paperWorld(region: rectangle(.5, 1));
    addTearDown(c.dispose);
    c.commitMarks(PencilMotif.parallel.segments());
    expect(c.balances[PaperMaterial.graphite], 122);
    expect(c.discoveredMotifs, isEmpty);
    expect(c.grid!.nodes.every(c.paperRegion.contains), isTrue);
  });
}
