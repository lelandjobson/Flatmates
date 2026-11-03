import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/recipes.dart';
import 'package:flatmates/protoplane/storage.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/protoplane/collision.dart';

void draw(ProtoplaneController c, List<int> path) {
  c.beginGesture();
  for (final node in path) {
    expect(c.appendNode(node), isTrue, reason: '$node in $path: ${c.error}');
  }
  c.finishGesture();
}

CraftObject floor(ProtoplaneController c, {String tile = 'ground-4-4'}) {
  c.enter(tile);
  draw(c, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
  expect(c.create(), isTrue, reason: c.error);
  return c.objects.values.last;
}

void main() {
  group('geometry', () {
    test('rejects crossings, doubling back, repeated vertices, zero area', () {
      expect(
        simplePath(const [
          Offset(0, 0),
          Offset(1, 1),
          Offset(0, 1),
          Offset(1, 0),
        ], closed: true),
        isFalse,
      );
      expect(
        simplePath(const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(.5, 0),
        ], closed: false),
        isFalse,
      );
      expect(
        simplePath(const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
        ], closed: true),
        isFalse,
      );
      expect(simplePath(rectangle(1, 1).outer, closed: true), isTrue);
    });
    test(
      'shared boundaries are allowed, coincident and crossing regions overlap',
      () {
        final a = rectangle(1, 1);
        expect(
          a.overlaps(rectangle(1, 1, origin: const Offset(1, 0))),
          isFalse,
        );
        expect(
          a.overlaps(rectangle(1, 1, origin: const Offset(.9, 0))),
          isTrue,
        );
        expect(a.overlaps(a), isTrue);
        expect(
          a.containsRegion(rectangle(.4, .4, origin: const Offset(.1, .1))),
          isTrue,
        );
        expect(
          a.containsRegion(rectangle(.4, .4, origin: const Offset(.9, .1))),
          isFalse,
        );
      },
    );
    test(
      'subtract interior hole and edge notch; triangulate actual material',
      () {
        final square = rectangle(1, 1);
        final result = square.subtract(
          rectangle(.4, .4, origin: const Offset(.3, .3)),
        );
        expect(result, hasLength(1));
        expect(result.single.valid, isTrue);
        expect(result.single.holes, hasLength(1));
        expect(result.single.area, closeTo(.84, 1e-6));
        expect(result.single.contains(const Offset(.5, .5)), isFalse);
        final triArea = result.single.triangles.fold(
          0.0,
          (s, t) => s + cross(t[1] - t[0], t[2] - t[0]).abs() / 2,
        );
        expect(triArea, closeTo(.84, 1e-6));
        final door = square.subtract(
          rectangle(.4, .6, origin: const Offset(.3, 0)),
        );
        expect(door, hasLength(1));
        expect(door.single.valid, isTrue);
        expect(door.single.area, closeTo(.76, 1e-6));
      },
    );
    test('concave subtraction can split into multiple valid pieces', () {
      final pieces = rectangle(
        1,
        1,
      ).subtract(rectangle(.2, 1, origin: const Offset(.4, 0)));
      expect(pieces, hasLength(2));
      expect(pieces.every((p) => p.valid), isTrue);
      expect(pieces.fold(0.0, (s, p) => s + p.area), closeTo(.8, 1e-6));
    });
    test('curve flattening is consistent and finite', () {
      final curve = flattenCurve(
        Offset.zero,
        const Offset(.5, -.2),
        const Offset(1, 0),
      );
      expect(curve.length, greaterThan(4));
      expect(curve.first, Offset.zero);
      expect(curve.last, const Offset(1, 0));
      expect(simplePath(curve, closed: false), isTrue);
    });
  });
  group('recognition and grids', () {
    test(
      'all three seeded grids retain guaranteed recipes on different floor shapes',
      () {
        final regions = [
          rectangle(1, 1),
          Region(const [Offset(0, 0), Offset(1, 0), Offset(0, 1)]),
          Region(const [
            Offset(0, 0),
            Offset(1, 0),
            Offset(1, .5),
            Offset(.5, .5),
            Offset(.5, 1),
            Offset(0, 1),
          ]),
        ];
        for (final region in regions) {
          for (final seed in [1, 25, 777]) {
            final grids = floorGrids('test', region, seed);
            expect(grids, hasLength(3));
            expect(
              jsonEncode(grids.map((g) => g.toJson()).toList()),
              jsonEncode(
                floorGrids(
                  'test',
                  region,
                  seed,
                ).map((g) => g.toJson()).toList(),
              ),
            );
            final plane = CraftPlane(
              id: 'test',
              origin: Vector3.zero(),
              u: Vector3(1, 0, 0),
              v: Vector3(0, 0, -1),
              region: region,
              grids: grids,
            );
            for (final grid in grids) {
              expect(grid.recipes.length, inInclusiveRange(3, 5));
              for (final example in grid.examples.entries) {
                expect(
                  recognize(plane, grid, example.value),
                  contains(example.key),
                  reason: '${grid.name}: ${example.key} seed $seed',
                );
                expect(
                  recognize(plane, grid, example.value.reversed.toList()),
                  contains(example.key),
                );
              }
            }
          }
        }
      },
    );
    test('geometry aspect is invariant under rotation and reflection', () {
      final points = rectangle(3, 1).outer;
      for (final angle in [.2, .8, 1.7]) {
        final transformed = points
            .map(
              (p) => Offset(
                -p.dx * math.cos(angle) - p.dy * math.sin(angle) + 9,
                -p.dx * math.sin(angle) + p.dy * math.cos(angle) - 3,
              ),
            )
            .toList();
        expect(aspectRatio(transformed), closeTo(3, 1e-6));
      }
    });
    test('door touches bottom, window is interior', () {
      final region = rectangle(1, 1);
      final grid = lattice(
        'w',
        region,
        count: 5,
        recipes: [CraftKind.window, CraftKind.door],
      );
      final plane = CraftPlane(
        id: 'w',
        origin: Vector3.zero(),
        u: Vector3(1, 0, 0),
        v: Vector3(0, 1, 0),
        region: region,
        grids: [grid],
      );
      expect(recognize(plane, grid, [6, 7, 8, 13, 18, 17, 16, 11, 6]), [
        CraftKind.window,
      ]);
      expect(recognize(plane, grid, [1, 2, 3, 8, 13, 12, 11, 6, 1]), [
        CraftKind.door,
      ]);
    });
  });
  group('world and history', () {
    test('screen cuts retain separate panel runs without refunding paper', () {
      final c = ProtoplaneController();
      final f = floor(c);
      c.enter('surface-${f.id}');
      c.selectGrid(2);
      draw(c, c.grid!.examples[CraftKind.screen]!);
      c.choose(CraftKind.screen);
      expect(c.create(), isTrue, reason: c.error);
      final screen = c.objects.values.last,
          balance = c.balances[PaperColor.red];
      c.enter(screen.planeId, editObject: screen.id);
      c.selectGrid(2);
      draw(c, [2, 7, 12, 17, 22]);
      expect(c.screenCutPreview, hasLength(2));
      expect(c.applyEdit(), isTrue, reason: c.error);
      final screens = c.objects.values
          .where((o) => o.kind == CraftKind.screen)
          .toList();
      expect(screens, hasLength(2));
      expect(
        screens.fold(0.0, (s, o) => s + pathLength(o.path)),
        closeTo(pathLength(screen.path), 1e-7),
      );
      expect(c.balances[PaperColor.red], balance);
      c.undo();
      expect(
        c.objects.values.where((o) => o.kind == CraftKind.screen),
        hasLength(1),
      );
    });
    for (final kind in [
      CraftKind.rug,
      CraftKind.tabletop,
      CraftKind.bench,
      CraftKind.planter,
      CraftKind.screen,
    ]) {
      test('${kind.label} has a drawable recipe, mesh and material quote', () {
        final c = ProtoplaneController();
        final f = floor(c);
        c.enter('surface-${f.id}');
        c.selectGrid(2);
        draw(c, c.grid!.examples[kind]!);
        c.choose(kind);
        final candidate = c.previewObject!;
        expect(candidate.kind, kind);
        final cost = c.quote;
        expect(cost, greaterThan(0));
        if (kind == CraftKind.planter) {
          expect(candidate.region.holes, hasLength(1));
          expect(
            cost,
            (128 *
                        (candidate.region.area +
                            candidate.region.perimeter * candidate.depth) -
                    1e-8)
                .ceil(),
          );
        }
        final before = c.balances[c.paper]!;
        expect(c.create(), isTrue, reason: c.error);
        final created = c.objects.values.last;
        expect(c.balances[c.paper], before - cost);
        expect(
          objectMeshes(
            created,
            c.planes[created.planeId]!,
          ).every((m) => m.geometry.vertices.isNotEmpty),
          isTrue,
        );
        c.undo();
        expect(c.balances[c.paper], before);
        c.redo();
        expect(c.objects[created.id]!.kind, kind);
      });
    }
    test('depth edits charge only growth; reduction and cuts never refund', () {
      final c = ProtoplaneController();
      final f = floor(c);
      c.enter(f.planeId, editObject: f.id);
      c.setDepth(.1);
      expect(c.quote, 52);
      expect(c.applyEdit(), isTrue, reason: c.error);
      final afterGrowth = c.balances[PaperColor.red];
      c.setDepth(.05);
      expect(c.quote, 0);
      expect(c.applyEdit(), isTrue, reason: c.error);
      expect(c.balances[PaperColor.red], afterGrowth);
      draw(c, [1, 4, 7]);
      expect(c.previewDepth, .05);
      expect(c.applyEdit(), isTrue, reason: c.error);
      expect(c.objects.values.every((o) => o.depth == .05), isTrue);
      expect(c.balances[PaperColor.red], afterGrowth);
    });
    test('acetates preserve independent drafts and a new edit clears redo', () {
      final c = ProtoplaneController();
      final f = floor(c);
      c.enter('surface-${f.id}');
      draw(c, [0, 1, 2]);
      c.selectGrid(1);
      expect(c.draft.path, isEmpty);
      draw(c, [5, 6, 7]);
      c.selectGrid(0);
      expect(c.draft.path, [0, 1, 2]);
      c.undo();
      c.selectGrid(0);
      c.clearDraft();
      expect(c.canRedo, isFalse);
    });
    test(
      'perpendicular solid collision rejects penetration but allows face contact',
      () {
        CraftPlane plane(String id, Vector3 origin, Vector3 u, Vector3 v) =>
            CraftPlane(
              id: id,
              origin: origin,
              u: u,
              v: v,
              region: rectangle(1, 1),
              grids: [],
            );
        final ground = plane(
          'ground',
          Vector3.zero(),
          Vector3(1, 0, 0),
          Vector3(0, 0, -1),
        );
        final wall = plane(
          'wall',
          Vector3(.5, 0, 0),
          Vector3(0, 0, -1),
          Vector3(0, 1, 0),
        );
        CraftObject block(String id, String p) => CraftObject(
          id: id,
          planeId: p,
          kind: CraftKind.tabletop,
          region: rectangle(1, 1),
          color: PaperColor.red,
          depth: .2,
        );
        expect(
          solidsOverlap(block('a', 'ground'), ground, block('b', 'wall'), wall),
          isTrue,
        );
        final touching = plane(
          'wall',
          Vector3(1, 0, 0),
          Vector3(0, 0, -1),
          Vector3(0, 1, 0),
        );
        expect(
          solidsOverlap(
            block('a', 'ground'),
            ground,
            block('b', 'wall'),
            touching,
          ),
          isFalse,
        );
      },
    );
    test(
      'door cuts a bottom notch and cannot be placed in an existing opening',
      () {
        final c = ProtoplaneController();
        final f = floor(c);
        c.enter('wall-${f.id}-0');
        draw(c, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
        expect(c.create(), isTrue);
        final wall = c.objects.values.last;
        c.enter('surface-${wall.id}');
        draw(c, [1, 2, 3, 8, 13, 12, 11, 6, 1]);
        expect(c.chosen, CraftKind.door);
        expect(c.create(), isTrue, reason: c.error);
        expect(c.objects[wall.id]!.region.holes, isEmpty);
        expect(
          c.objects[wall.id]!.region.contains(const Offset(.5, .1)),
          isFalse,
        );
        draw(c, [1, 2, 3, 8, 13, 12, 11, 6, 1]);
        expect(c.create(), isFalse);
        expect(c.error, contains('remaining wall'));
      },
    );
    test('complete build, openings, upper floor, save round trip and undo', () {
      final c = ProtoplaneController();
      final f = floor(c);
      expect(c.balances[PaperColor.red], 12672);
      expect(c.planes.keys.where((id) => id.startsWith('wall-')), hasLength(4));
      c.enter('surface-${f.id}');
      draw(c, c.grid!.examples[CraftKind.rug]!);
      c.choose(CraftKind.rug);
      expect(c.create(), isTrue, reason: c.error);
      final rug = c.objects.values.last;
      c.enter('wall-${f.id}-0');
      draw(c, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
      expect(c.create(), isTrue, reason: c.error);
      final wall = c.objects.values.last;
      expect(c.planes.containsKey('upper-${f.id}'), isTrue);
      c.enter('surface-${wall.id}');
      draw(c, [6, 7, 8, 13, 18, 17, 16, 11, 6]);
      expect(c.chosen, CraftKind.window);
      expect(c.create(), isTrue, reason: c.error);
      expect(c.objects[wall.id]!.region.holes, hasLength(1));
      c.enter('upper-${f.id}');
      draw(c, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
      expect(c.create(), isTrue, reason: c.error);
      expect(
        c.objects.values.where((o) => o.kind == CraftKind.floor),
        hasLength(2),
      );
      final saved = jsonEncode(c.toJson());
      final restored = ProtoplaneController()..load(jsonDecode(saved));
      expect(jsonEncode(restored.toJson()), saved);
      expect(restored.objects.containsKey(rug.id), isTrue);
      final wallet = Map.of(c.balances);
      c.undo();
      expect(
        c.objects.values.where((o) => o.kind == CraftKind.floor),
        hasLength(1),
      );
      c.redo();
      expect(c.balances, wallet);
      expect(jsonEncode(c.toJson()), saved);
    });
    test('multiple adjacent floors, overlap rejection, insufficient paper', () {
      final c = ProtoplaneController()..enter('ground-4-4');
      draw(c, [0, 1, 4, 3, 0]);
      expect(c.create(), isTrue, reason: c.error);
      draw(c, [1, 2, 5, 4, 1]);
      expect(c.create(), isTrue, reason: c.error);
      draw(c, [0, 1, 4, 3, 0]);
      expect(c.create(), isFalse);
      expect(c.error, contains('Overlaps'));
      c.clearDraft();
      c.balances[PaperColor.red] = 0;
      draw(c, [3, 4, 7, 6, 3]);
      expect(c.create(), isFalse);
      expect(c.draft.path, isNotEmpty);
    });
    test('stroke undo, draft isolation, exact accounting and redo branch', () {
      final c = ProtoplaneController()..enter('ground-4-4');
      draw(c, [0, 1, 2]);
      c.undo();
      expect(c.draft.path, isEmpty);
      c.redo();
      expect(c.draft.path, [0, 1, 2]);
      draw(c, [5, 8, 7, 6, 3, 0]);
      c.setDepth(.1);
      expect(c.quote, 180);
      expect(c.create(), isTrue, reason: c.error);
      expect(c.balances[PaperColor.red], 12620);
      c.undo();
      expect(c.balances[PaperColor.red], 12800);
      c.clearDraft();
      expect(c.canRedo, isFalse);
    });
    test(
      'splits keep pieces and cuts do not refund; undo restores geometry',
      () {
        final c = ProtoplaneController();
        final f = floor(c);
        c.enter(f.planeId, editObject: f.id);
        draw(c, [1, 4, 7]);
        expect(c.cutPreview, hasLength(2));
        final balance = c.balances[PaperColor.red];
        expect(c.applyEdit(), isTrue, reason: c.error);
        expect(c.objects, hasLength(2));
        expect(c.balances[PaperColor.red], balance);
        c.undo();
        expect(c.objects, hasLength(1));
        expect(c.objects[f.id]!.region.area, 1);
      },
    );
    test('support edits cannot strand attachments', () {
      final c = ProtoplaneController();
      final f = floor(c);
      c.enter('surface-${f.id}');
      draw(c, c.grid!.examples[CraftKind.rug]!);
      expect(c.create(), isTrue, reason: c.error);
      c.enter(f.planeId, editObject: f.id);
      c.setDepth(.1);
      expect(c.applyEdit(), isFalse);
      expect(c.error, contains('support'));
    });
    test('hole mesh has no cap triangles over hole', () {
      final c = ProtoplaneController();
      final p = c.planes['ground-4-4']!;
      final r = rectangle(
        1,
        1,
      ).subtract(rectangle(.4, .4, origin: const Offset(.3, .3))).single;
      final mesh = regionGeometry('test', p, r, .1);
      for (final face in mesh.faces.where((f) => f.length == 3)) {
        final center =
            face.map((i) => mesh.vertices[i]).reduce((a, b) => a + b) / 3;
        expect(r.contains(p.local(center)), isTrue);
      }
    });
  });
  group('storage', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('protoplane-test-');
    });
    tearDown(() async {
      await temp.delete(recursive: true);
    });
    void validate(Map<String, dynamic> j) {
      final c = ProtoplaneController();
      try {
        c.load(j);
      } finally {
        c.dispose();
      }
    }

    test('serialized writes and recovery preserve last valid save', () async {
      final s = ProtoplaneStorage(directory: () async => temp);
      expect(await s.load(validate), isNull);
      final c = ProtoplaneController();
      final empty = c.toJson();
      final first = s.save(empty);
      floor(c);
      final built = c.toJson();
      final second = s.save(built);
      await Future.wait([first, second]);
      expect((await s.load(validate))!['objects'], hasLength(1));
      await File(
        '${temp.path}/protoplane_concept/world.json',
      ).writeAsString('{broken');
      final recovered = await s.load(validate);
      expect(recovered!['objects'], isEmpty);
      expect(s.recoveryMessage, isNotNull);
      expect(
        Directory(
          '${temp.path}/protoplane_concept',
        ).listSync().where((f) => f.path.contains('.damaged-')),
        hasLength(1),
      );
    });
    test('corrupt primary and backup cannot be silently overwritten', () async {
      final dir = Directory('${temp.path}/protoplane_concept');
      await dir.create();
      final file = File('${dir.path}/world.json');
      await file.writeAsString('broken');
      final s = ProtoplaneStorage(directory: () async => temp);
      await expectLater(s.load(validate), throwsFormatException);
      await expectLater(
        s.save(ProtoplaneController().toJson()),
        throwsStateError,
      );
      expect(await file.readAsString(), 'broken');
    });
  });
}
