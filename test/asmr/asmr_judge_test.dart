import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_judge.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final model = asmrCubeModel();
  final net = unfoldSelection(model, faceAdjacency(model), const [
    HologramPick(0),
  ]);
  final face = net.faces.single.ring;

  /// The blueprint's face, grown outward by [by] on every side.
  AsmrPiece square(String id, double by, {Offset shift = Offset.zero}) {
    final box = Rect.fromPoints(face[0], face[2]).inflate(by).shift(shift);
    return AsmrPiece(
      id: id,
      paper: kAsmrPapers.first,
      ring: [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft],
      liberated: true,
    );
  }

  final cutEdges = [
    for (final edge in net.edges)
      if (!edge.fold) edge.key,
  ];

  test('the colors run blue, green, yellow, orange', () {
    expect(asmrJudgeColor(0), kAsmrJudgePerfectColor);
    expect(asmrJudgeColor(kAsmrJudgeGood), kAsmrJudgeGoodColor);
    expect(asmrJudgeColor(kAsmrJudgeFair), kAsmrJudgeFairColor);
    expect(asmrJudgeColor(kAsmrJudgeAcceptable), kAsmrJudgeAcceptableColor);
    expect(asmrJudgeColor(9), kAsmrJudgeAcceptableColor);
    expect(
      asmrJudgeColor((kAsmrJudgeGood + kAsmrJudgeFair) / 2),
      Color.lerp(kAsmrJudgeGoodColor, kAsmrJudgeFairColor, 0.5),
    );
  });

  test('a close cut is judged by how far it strays', () {
    for (final (by, color) in [
      (0.3, kAsmrJudgePerfectColor),
      (1.5, Color.lerp(kAsmrJudgeGoodColor, kAsmrJudgeFairColor, 0.5)),
    ]) {
      final judge = AsmrJudge()..update(net, [square('a', by)]);
      expect(judge.judged.keys, unorderedEquals(cutEdges));
      for (final key in cutEdges) {
        expect(judge.of(key)!.mean, closeTo(by, 1e-9));
        expect(judge.of(key)!.worst, closeTo(by, 1e-9));
        expect(judge.of(key)!.color, color);
      }
    }
  });

  test('paper too far from an edge leaves it uncut', () {
    final judge = AsmrJudge()..update(net, [square('a', 5)]);
    expect(judge.judged, isEmpty);
  });

  test('only edges near paper that changed are judged again', () {
    final sheet = square('sheet', 60);
    final judge = AsmrJudge();
    expect(judge.update(net, [sheet]), unorderedEquals(cutEdges));
    expect(judge.judged, isEmpty);

    final far = square('far', 0, shift: const Offset(300, 0));
    expect(judge.update(net, [sheet, far]), isEmpty);

    final close = square('close', 0.5);
    expect(judge.update(net, [sheet, far, close]), unorderedEquals(cutEdges));

    final fresh = AsmrJudge()..update(net, [sheet, far, close]);
    expect(judge.judged.keys, unorderedEquals(fresh.judged.keys));
    for (final key in fresh.judged.keys) {
      expect(judge.of(key)!.mean, fresh.of(key)!.mean);
    }

    judge.update(net, [sheet, far]);
    expect(judge.judged, isEmpty);
  });

  test(
    'manual submission accepts half the edges, even with missing paper or overhang',
    () {
      final box = Rect.fromPoints(face[0], face[2]);
      final triangle = AsmrPiece(
        id: 'half',
        paper: kAsmrPapers.first,
        ring: [box.topLeft, box.topRight, box.bottomLeft],
      );
      expect(asmrSubmissionQuality(triangle, net), 0.5);
      final overhang = AsmrPiece(
        id: 'rough',
        paper: kAsmrPapers.first,
        ring: [
          box.topLeft,
          box.topRight + const Offset(15, 0),
          box.bottomRight + const Offset(15, 15),
          box.bottomLeft + const Offset(0, 15),
        ],
      );
      // Top and left fully match; right and bottom do not.
      expect(asmrSubmissionQuality(overhang, net), 0.5);
      final narrow = AsmrPiece(
        id: 'one',
        paper: kAsmrPapers.first,
        ring: [box.topLeft, box.topRight, box.center],
      );
      expect(asmrSubmissionQuality(narrow, net), 0.25);
      final frame = AsmrPiece(
        id: 'frame',
        paper: kAsmrPapers.first,
        ring: square('outer', 20).ring,
        holes: [square('inner', 0).ring],
      );
      expect(asmrSubmissionQuality(frame, net), 0);
      expect(asmrSubmissionQuality(square('far', 10), net), 0);
    },
  );

  test('the gate takes a close cut and refuses one too big or too far', () {
    expect(asmrMatchedOutline(square('a', 1), net), isNotNull);
    expect(
      asmrMatchedOutline(square('a', 0, shift: const Offset(3, 0)), net),
      isNotNull,
    );
    expect(asmrMatchedOutline(square('a', 5), net), isNull);

    final box = Rect.fromPoints(face[0], face[2]);
    final spike = AsmrPiece(
      id: 'spike',
      paper: kAsmrPapers.first,
      ring: [
        box.topLeft,
        box.topLeft + const Offset(-20, -20),
        box.topLeft + const Offset(2, 0),
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ],
    );
    expect(asmrMatchedOutline(spike, net), isNull);
  });
}
