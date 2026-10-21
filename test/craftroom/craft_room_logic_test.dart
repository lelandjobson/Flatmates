import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flatmates/asmr/asmr_net.dart' show HologramPick, kAsmrIslandGap;
import 'package:flatmates/asmr/hologram_selection.dart';
import 'package:flatmates/craftroom/attach.dart';
import 'package:flatmates/craftroom/bench_paper.dart';
import 'package:flatmates/asmr/hologram_painter.dart';
import 'package:flatmates/craftroom/craft_bench_painter.dart';
import 'package:flatmates/craftroom/craft_theme.dart';
import 'package:flatmates/craftroom/room_crafts.dart';
import 'package:flatmates/craftroom/scissors.dart';
import 'package:flatmates/craftroom/selection_group.dart';
import 'package:flatmates/craftroom/snap_rules.dart';
import 'package:flatmates/geometry/polygon_union.dart'
    show isInsidePolygon, polygonCentroid;
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart' show faceAdjacency;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('snap rules', () {
    const rules = SnapRules();
    const square = [Offset(2.3, 1), Offset(6, 1), Offset(6, 4), Offset(2.3, 4)];
    const context = SnapContext(paperRings: [square]);

    test('the straight cut, scissors and straight edge keep to the grid', () {
      for (final user in [
        SnapUser.straightCut,
        SnapUser.scissors,
        SnapUser.straightEdge,
      ]) {
        expect(
          snapPoint(rules, user, const Offset(2.26, 1.1), context),
          const Offset(2, 1),
        );
      }
    });

    test('the exacto is free', () {
      expect(
        snapPoint(rules, SnapUser.exacto, const Offset(2.26, 1.1), context),
        const Offset(2.26, 1.1),
      );
    });

    test('the folder takes a paper corner nearer than the grid point', () {
      expect(
        snapPoint(rules, SnapUser.folder, const Offset(2.26, 1.1), context),
        const Offset(2.3, 1),
      );
    });

    test('an edge pulls only when no point is allowed', () {
      var edgesOnly = rules;
      for (final target in [
        SnapTarget.craftGrid,
        SnapTarget.paperVertex,
        SnapTarget.blueprintVertex,
      ]) {
        edgesOnly = edgesOnly.toggled(SnapUser.folder, target, false);
      }
      expect(
        snapPoint(edgesOnly, SnapUser.folder, const Offset(4, 1.3), context),
        const Offset(4, 1),
      );
      expect(
        snapPoint(edgesOnly, SnapUser.folder, const Offset(4, 2.5), context),
        const Offset(4, 2.5),
      );
    });

    test('a rule switched off leaves the aim alone', () {
      final off = rules.toggled(
        SnapUser.straightCut,
        SnapTarget.craftGrid,
        false,
      );
      expect(
        snapPoint(off, SnapUser.straightCut, const Offset(2.26, 1.1), context),
        const Offset(2.26, 1.1),
      );
    });

    test('moving paper puts its nearest corner on the grid', () {
      const loose = [
        Offset(2.3, 1.2),
        Offset(6.4, 1.2),
        Offset(6.4, 4.2),
        Offset(2.3, 4.2),
      ];
      final shift = snapShift(rules, SnapUser.paperMove, loose, context);
      expect(shift.dx, closeTo(-0.3, 1e-9));
      expect(shift.dy, closeTo(-0.2, 1e-9));
      expect(
        snapShift(rules, SnapUser.paperMove, square, context),
        Offset.zero,
      );
    });

    test('turns keep to their step', () {
      expect(
        snapAngle(rules, SnapUser.paperMove, 1.4),
        closeTo(math.pi / 2, 1e-9),
      );
      expect(
        snapAngle(rules, SnapUser.straightEdge, 0.7),
        closeTo(math.pi / 4, 1e-9),
      );
      final free = rules.withRule(
        SnapUser.paperMove,
        rules[SnapUser.paperMove].copyWith(rotationStep: () => null),
      );
      expect(snapAngle(free, SnapUser.paperMove, 1.4), 1.4);
    });

    test('rules survive a round trip through JSON', () {
      final changed = rules
          .toggled(SnapUser.scissors, SnapTarget.paperEdge, true)
          .withRule(SnapUser.exacto, const SnapRule(free: false));
      final back = SnapRules.fromJson(changed.toJson());
      for (final user in SnapUser.values) {
        expect(back[user], changed[user], reason: user.name);
      }
    });
  });

  group('scissors', () {
    test('cut exactly 3 squares in each of the 8 directions', () {
      const start = Offset(5, 5);
      const ends = [
        Offset(8, 5),
        Offset(8, 8),
        Offset(5, 8),
        Offset(2, 8),
        Offset(2, 5),
        Offset(2, 2),
        Offset(5, 2),
        Offset(8, 2),
      ];
      for (var k = 0; k < 8; k++) {
        final angle = k * math.pi / 4 + 0.2;
        final drag = Offset(math.cos(angle), math.sin(angle)) * 1.3;
        final cut = scissorCut(start, drag);
        expect(cut, isNotNull, reason: 'direction $k');
        expect(cut!.$1, start);
        expect(cut.$2.dx, closeTo(ends[k].dx, 1e-9), reason: 'direction $k');
        expect(cut.$2.dy, closeTo(ends[k].dy, 1e-9), reason: 'direction $k');
      }
    });

    test('a drag too short picks no direction', () {
      expect(scissorCut(Offset.zero, const Offset(0.1, 0.1)), isNull);
    });

    test('snips that close a loop free the square inside', () {
      var papers = [BenchPaper.fresh('paper-0', Offset.zero)];
      var next = 1;
      String nextId() => 'paper-${next++}';
      const loop = [
        Offset(2, 2),
        Offset(5, 2),
        Offset(5, 5),
        Offset(2, 5),
        Offset(2, 2),
      ];
      BenchCut? last;
      for (var i = 0; i + 1 < loop.length; i++) {
        last = cutBench(papers, [loop[i], loop[i + 1]], nextId: nextId);
        expect(last, isNotNull);
        papers = last!.papers;
        if (i < loop.length - 2) expect(last.split, isFalse, reason: 'snip $i');
      }
      expect(last!.split, isTrue);
      expect(papers, hasLength(2));
      final areas = [for (final paper in papers) paper.area]..sort();
      expect(areas.first, closeTo(9, 1e-6));
      expect(areas.last, closeTo(17 * 22 - 9, 1e-6));
    });
  });

  group('selection groups and the net', () {
    final model = roomCubeModel();
    final adjacency = faceAdjacency(model);
    final all = hologramPicks([
      for (var f = 0; f < model.faces.length; f++) f,
    ], adjacency);

    test('every craft in the room can be built', () {
      final room = CraftCollection.fromJson(
        jsonDecode(File(kCraftRoomAsset).readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(room.crafts.map((spot) => spot.puzzleId), [
        kRoomCubeId,
        'box-stack',
        'rocket',
        'birdhouse',
      ]);
      for (final spot in room.crafts) {
        final craft = roomCraft(spot.puzzleId);
        expect(craft, isNotNull, reason: spot.puzzleId);
        expect(craft!.model.faces, isNotEmpty);
      }
    });

    test('separate volumes sit apart by their bounding boxes', () {
      for (final id in ['rocket', 'birdhouse']) {
        final model = roomCraft(id)!.model;
        final adjacency = faceAdjacency(model);
        final net = gridNet(
          model,
          adjacency,
          hologramPicks([
            for (var f = 0; f < model.faces.length; f++) f,
          ], adjacency),
        );
        expect(net.islands.length, greaterThan(1), reason: id);
        for (final a in net.faces) {
          final middle = polygonCentroid(a.ring);
          for (final b in net.faces) {
            if (identical(a, b) || a.island != b.island) continue;
            expect(
              isInsidePolygon(middle, b.ring),
              isFalse,
              reason: '$id face ${a.face} overlaps ${b.face}',
            );
          }
        }
        final boxes = [
          for (final island in net.islands) islandBounds(net, island),
        ];
        for (var i = 0; i < boxes.length; i++) {
          for (var j = i + 1; j < boxes.length; j++) {
            expect(
              boxes[i].overlaps(boxes[j]),
              isFalse,
              reason: '$id islands $i and $j',
            );
          }
        }
        for (var i = 0; i < boxes.length - 1; i++) {
          expect(
            boxes[i + 1].left - boxes[i].right,
            closeTo(kAsmrIslandGap, 1e-4),
            reason: '$id gap after island $i',
          );
          expect(
            boxes[i + 1].center.dy,
            closeTo(boxes[i].center.dy, 1e-4),
            reason: '$id centers',
          );
        }
      }
    });

    test('the room cube is 3 squares a side and its net sits on the grid', () {
      final net = gridNet(model, adjacency, all);
      expect(net.islands, hasLength(1));
      for (final face in net.faces) {
        for (final p in face.ring) {
          expect((p.dx - p.dx.roundToDouble()).abs(), lessThan(1e-6));
          expect((p.dy - p.dy.roundToDouble()).abs(), lessThan(1e-6));
        }
      }
      expect(net.bounds.width * net.bounds.height, closeTo(9 * 12, 1e-6));
    });

    test('cutting along an island outline matches that island', () {
      final net = gridNet(model, adjacency, all);
      final outline = net.outlines.single;
      final corner = net.bounds.topLeft - const Offset(2, 2);
      var papers = [BenchPaper.fresh('paper-0', corner)];
      var next = 1;
      final cut = cutBench(papers, [
        ...outline,
        outline.first,
      ], nextId: () => 'paper-${next++}');
      expect(cut, isNotNull);
      expect(cut!.split, isTrue);
      papers = cut.papers;
      final matched = [
        for (final paper in papers)
          if (matchedIsland(paper, net) != null) paper,
      ];
      expect(matched, hasLength(1));
      expect(matched.single.area, closeTo(54, 1e-6));
      final piece = boundPiece(matched.single, net);
      expect(piece.binding, same(net));
      expect(piece.area, closeTo(54, 1e-6));
    });

    test('paper bigger than the island does not match', () {
      final net = gridNet(model, adjacency, all);
      final paper = BenchPaper.fresh('paper-0', net.bounds.topLeft);
      expect(matchedIsland(paper, net), isNull);
      expect(insideBlueprint(paper, net), isFalse);
    });

    test('a straight cut runs through the paper it crosses', () {
      final paper = BenchPaper.fresh('paper-0', Offset.zero);
      var next = 1;
      final cut = cutStraight(
        [paper],
        const Offset(2, 5),
        const Offset(6, 5),
        nextId: () => 'paper-${next++}',
      );
      expect(cut, isNotNull);
      expect(cut!.papers, hasLength(2));
      expect(
        cut.papers.map((p) => p.area).reduce((a, b) => a + b),
        closeTo(17 * 22, 1e-6),
      );
      final heights = [
        for (final part in cut.papers)
          part.flatRings.single.map((p) => p.dy).reduce(math.max) -
              part.flatRings.single.map((p) => p.dy).reduce(math.min),
      ]..sort();
      expect(heights[0], closeTo(5, 1e-6));
      expect(heights[1], closeTo(17, 1e-6));
    });

    test('merging places the dropped layout 3 squares to the right', () {
      final first = CraftGroup(
        letter: 0,
        picks: const [HologramPick(0)],
        net: gridNet(model, adjacency, const [HologramPick(0)]),
      );
      final second = CraftGroup(
        letter: 1,
        picks: const [HologramPick(1)],
        net: gridNet(model, adjacency, const [HologramPick(1)]),
      );
      final merged = mergeGroups(first, second);
      expect(merged.faces, {0, 1});
      final kept = merged.net.of(0)!.ring;
      final moved = merged.net.of(1)!.ring;
      double right(List<Offset> ring) => ring.map((p) => p.dx).reduce(math.max);
      double left(List<Offset> ring) => ring.map((p) => p.dx).reduce(math.min);
      double top(List<Offset> ring) => ring.map((p) => p.dy).reduce(math.min);
      expect(left(moved) - right(kept), closeTo(kMergeGap, 1e-9));
      expect(top(moved), closeTo(top(kept), 1e-9));
      expect(merged.net.islands, hasLength(2));
    });

    test('inverting takes every other face', () {
      final picks = invertedPicks(model, adjacency, {0, 1});
      expect({for (final pick in picks) pick.face}, {2, 3, 4, 5});
    });

    CraftGroup lettered(int letter, Set<int> faces) => CraftGroup(
      letter: letter,
      picks: [for (final face in faces) HologramPick(face)],
      net: gridNet(model, adjacency, [
        for (final face in faces) HologramPick(face),
      ]),
    );

    test('a face of a group brings its group, and no face is in two', () {
      final groups = [
        lettered(0, {0, 1}),
        lettered(1, {2}),
      ];
      final tapped = resolveSelection({1}, groups, prefer: 1);
      expect(tapped.open, 0);
      expect(tapped.free, isEmpty);

      final across = resolveSelection({1, 2, 3}, groups, prefer: 2);
      expect(across.open, 1);
      expect(across.free, {3});

      final most = resolveSelection({0, 1, 2, 4}, groups);
      expect(most.open, 0);
      expect(most.free, {4});

      final loose = resolveSelection({3, 5}, groups, prefer: 3);
      expect(loose.open, isNull);
      expect(loose.free, {3, 5});
    });

    test('there are at most five groups, A to E, each its own theme', () {
      final groups = [
        for (var i = 0; i < 4; i++) lettered(i, {i}),
      ];
      expect(nextLetter(groups), 4);
      expect(
        nextLetter([
          ...groups,
          lettered(4, {4}),
        ]),
        isNull,
      );
      expect(
        nextLetter([
          lettered(0, {0}),
          lettered(2, {2}),
        ]),
        1,
      );
      final accents = {
        for (var i = 0; i < kMaxCraftGroups; i++) craftGroupTheme(i).accent,
      };
      expect(accents, hasLength(kMaxCraftGroups));
      expect(lettered(2, {2}).theme.accent, kCraftGroupAccents[2]);
      expect(lettered(2, {2}).theme.line, kCraftGroupAccents[2]);
      expect(lettered(2, {2}).theme.desk, kCraftNoneTheme.desk);
      expect(lettered(2, {2}).theme.dot, kCraftNoneTheme.dot);
      expect(CraftGroup.none.theme.line, kCraftNoneTheme.line);
    });
  });

  group('blueprint on paper', () {
    test('an edge across a sheet is a pencil line on the sheet only', () {
      final paper = BenchPaper.fresh('paper-0', Offset.zero);
      final guide = splitCraftGuide(
        [
          const HologramEdgeView(
            a: Offset(-2, 5),
            b: Offset(20, 5),
            fold: true,
            opacity: 1,
          ),
        ],
        [paper],
      );
      expect(guide.pencil, hasLength(1));
      expect(guide.pencil.single.fold, isTrue);
      expect(guide.pencil.single.a.dx, closeTo(0, 1e-4));
      expect(guide.pencil.single.b.dx, closeTo(17, 1e-4));
      expect(
        guide.pencil.single.ink,
        Color.from(
          alpha: 1,
          red: 1 - kBenchPaperColor.r,
          green: 1 - kBenchPaperColor.g,
          blue: 1 - kBenchPaperColor.b,
        ),
      );
      expect(guide.bare, hasLength(2));
    });

    test(
      'an edge along the sheet border is pencil, not the glowing outline',
      () {
        final paper = BenchPaper.fresh('paper-0', Offset.zero);
        final guide = splitCraftGuide(
          [
            const HologramEdgeView(
              a: Offset(0, 0),
              b: Offset(17, 0),
              fold: false,
              opacity: 1,
            ),
          ],
          [paper],
        );
        expect(guide.pencil, hasLength(1));
        expect(guide.bare, isEmpty);
      },
    );
  });

  group('folding', () {
    test('a fold keeps the paper one piece of paper', () {
      final paper = BenchPaper.fresh('paper-0', Offset.zero);
      final guide = benchFolderGuide(paper, const Offset(8.5, 3.2));
      expect(guide, isNotNull);
      final folded = foldBench(paper, guide!.guide);
      expect(folded, isNotNull);
      expect(folded!.sheet.folds, hasLength(1));
      expect(splitSheet(folded.sheet), hasLength(1));
      expect(folded.area, closeTo(17 * 22, 1e-6));
      final opened = unfoldBench(folded, guide.a);
      expect(opened, isNotNull);
    });
  });
}
