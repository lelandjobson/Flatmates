import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';

List<Offset> _line(Offset a, Offset b) {
  final stroke = <Offset>[a];
  addStrokePoint(stroke, b);
  return stroke;
}

AsmrPiece _sheet({
  String id = 's',
  Offset at = Offset.zero,
  double angle = 0,
}) => AsmrPiece.sheet(
  id: id,
  paper: kAsmrPapers.first,
  at: at,
  size: const Size(100, 100),
).copyWith(angle: angle);

void main() {
  test('a stroke across the sheet frees the smaller part', () {
    final cut = cutPieces([
      _sheet(),
    ], _line(const Offset(20, -60), const Offset(20, 60)))!;
    expect(cut.pieces, hasLength(2));
    expect(cut.split, isTrue);
    final freed = cut.pieces.where((p) => cut.freed.contains(p.id)).single;
    final kept = cut.pieces.where((p) => !cut.freed.contains(p.id)).single;
    expect(freed.liberated, isTrue);
    expect(kept.liberated, isFalse);
    expect(freed.area, closeTo(30 * 100, 1));
    expect(kept.area, closeTo(70 * 100, 1));
    expect(freed.edgeTone, isNotNull);
    expect(kept.edgeTone, isNotNull);
    expect(freed.edgeTone, isNot(kept.edgeTone));
    for (final piece in cut.pieces) {
      expect(piece.cutEdges, isNotEmpty);
      expect(
        piece.cutEdges
            .expand((edge) => edge)
            .every((p) => (p.dx - 20).abs() < 1e-6),
        isTrue,
      );
      final length = piece.cutEdges.fold<double>(
        0,
        (total, edge) => total + (edge.last - edge.first).distance,
      );
      expect(length, closeTo(100, 1e-6));
      expect(piece.copyWith(angle: 1).unbound().cutEdges, piece.cutEdges);
      expect(piece.copyWith(angle: 1).unbound().edgeTone, piece.edgeTone);
    }
  });

  test('a cut that stops short of the edge scores, and a second one frees', () {
    final first = cutPieces([
      _sheet(),
    ], _line(const Offset(20, -60), const Offset(20, 0)))!;
    expect(first.split, isFalse);
    expect(first.pieces.single.scores, hasLength(1));
    expect(first.pieces.single.edgeTone, isNull);
    expect(first.pieces.single.cutEdges, isEmpty);
    final second = cutPieces(
      first.pieces,
      _line(const Offset(20, 1.5), const Offset(20, 60)),
    )!;
    expect(second.split, isTrue);
    expect(second.pieces, hasLength(2));
  });

  test('a hand-drawn loop inside the paper cuts out a piece', () {
    final stroke = <Offset>[const Offset(-10, -10)];
    for (final corner in const [
      Offset(10, -10),
      Offset(10, 10),
      Offset(-10, 10),
      Offset(-10, -8.5),
    ]) {
      addStrokePoint(stroke, corner);
    }
    final cut = cutPieces([_sheet()], stroke)!;
    expect(cut.split, isTrue);
    final freed = cut.pieces.where((p) => cut.freed.contains(p.id)).single;
    expect(freed.area, closeTo(400, 20));
    final kept = cut.pieces.where((p) => !cut.freed.contains(p.id)).single;
    expect(kept.holes, hasLength(1));
  });

  test('later splits keep inherited cut edges but not factory edges', () {
    final first = cutPieces(
      [_sheet()],
      const [Offset(20, -60), Offset(20, 60)],
      exact: true,
    )!;
    final second = cutPieces(first.pieces, const [
      Offset(-60, 0),
      Offset(60, 0),
    ], exact: true)!;
    expect(second.pieces, hasLength(4));
    for (final piece in second.pieces) {
      expect(piece.cutEdges, hasLength(2));
      for (final edge in piece.cutEdges) {
        expect(
          edge.every((p) => (p.dx - 20).abs() < 1e-6) ||
              edge.every((p) => p.dy.abs() < 1e-6),
          isTrue,
        );
      }
    }
  });

  test('cuts land in paper coordinates of a moved, turned piece', () {
    final sheet = _sheet(at: const Offset(300, 100), angle: math.pi / 2);
    final cut = cutPieces([
      sheet,
    ], _line(const Offset(240, 120), const Offset(360, 120)))!;
    expect(cut.pieces, hasLength(2));
    for (final piece in cut.pieces) {
      expect(piece.position, sheet.position);
      expect(piece.angle, sheet.angle);
    }
    final freed = cut.pieces.where((p) => cut.freed.contains(p.id)).single;
    expect(freed.area, closeTo(30 * 100, 1));
    expect(freed.deskCentroid.dy, closeTo(135, 1));
  });

  test('parts keep their binding, and freed parts stay liberated', () {
    final model = asmrCubeModel();
    final net = unfoldSelection(model, faceAdjacency(model), [
      const HologramPick(0),
    ]);
    final bound = _sheet().copyWith(liberated: true, binding: net);
    final cut = cutPieces([
      bound,
    ], _line(const Offset(20, -60), const Offset(20, 60)))!;
    for (final piece in cut.pieces) {
      expect(piece.binding, same(net));
      expect(piece.liberated, isTrue);
    }
  });

  test('turning about the centroid keeps the centroid in place', () {
    final piece = _sheet(at: const Offset(10, 20));
    final turned = piece.turnedTo(1.1);
    expect((turned.deskCentroid - piece.deskCentroid).distance, lessThan(1e-9));
  });

  test('turning about an edge center keeps that center in place', () {
    final piece = _sheet(at: const Offset(10, 20));
    const above = Offset(10, -80);
    final pivot = piece.edgeCenterOpposite(above);
    expect(pivot, const Offset(10, -30));
    final turned = piece.turnedAbout(math.pi / 2, pivot);
    final local = piece.toLocal(pivot);
    expect((turned.toDesk(local) - pivot).distance, lessThan(1e-9));
    expect((turned.deskCentroid - piece.deskCentroid).distance, greaterThan(1));
  });

  test('curve smoothing keeps the ends and pulls a corner in', () {
    const corner = [Offset(0, 0), Offset(10, 0), Offset(10, 10)];
    final raw = smoothToolCurve(corner, 0);
    expect(raw, corner);
    final smooth = smoothToolCurve(corner, 1);
    expect(smooth.first, corner.first);
    expect(smooth.last, corner.last);
    expect(smooth[1].dx, lessThan(10));
  });

  test(
    'a straight segment cuts every piece it crosses, and stops at its ends',
    () {
      final left = _sheet(id: 'left', at: const Offset(-80, 0));
      final right = _sheet(id: 'right', at: const Offset(80, 0));
      final aside = _sheet(id: 'aside', at: const Offset(0, 200));
      const segment = [Offset(-200, 0), Offset(200, 0)];
      final cut = cutPieces([left, right, aside], segment, exact: true)!;
      expect(cut.pieces, hasLength(5));
      expect(cut.freed, hasLength(2));
      final untouched = cut.pieces.where((p) => p.id == aside.id).single;
      expect(untouched.ring, aside.ring);
      for (final piece in cut.pieces.where((p) => p.id != aside.id)) {
        for (final point in piece.ring) {
          final onCut = (point.dy).abs() < 1e-6;
          final corner =
              (point.dx.abs() - 50).abs() < 1e-6 &&
              (point.dy.abs() - 50).abs() < 1e-6;
          expect(onCut || corner, isTrue, reason: '$point');
        }
      }
    },
  );

  test(
    'a straight segment that stops inside the paper is not carried to the edge',
    () {
      const segment = [Offset(20, -60), Offset(20, 48)];
      final exact = cutPieces([_sheet()], segment, exact: true)!;
      expect(exact.split, isFalse);
      expect(exact.pieces.single.scores, [segment]);
      final reached = cutPieces([_sheet()], segment)!;
      expect(reached.split, isTrue);
    },
  );

  test('the straight cut preview lies on the paper it will cut', () {
    final preview = straightCutPreview(
      [_sheet()],
      const Offset(-5, 10),
      const Offset(5, 10),
    );
    expect(preview, hasLength(1));
    final xs = preview.single.map((p) => p.dx).toList()..sort();
    expect(xs.first, closeTo(-50, 1e-4));
    expect(xs.last, closeTo(50, 1e-4));
    for (final p in preview.single) {
      expect(p.dy, closeTo(10, 1e-6));
    }
  });

  test('a short straight drag cuts right through each piece it touches', () {
    final sheet = _sheet(id: 'sheet');
    final along = _sheet(id: 'along', at: const Offset(300, 0));
    final cut = cutPiecesAlongLine(
      [sheet, along],
      const Offset(-5, 10),
      const Offset(5, 10),
    )!;
    expect(cut.freed, hasLength(1));
    expect(cut.pieces.where((p) => p.id == 'along').single.ring, along.ring);
    final parts = cut.pieces.where((p) => p.id != 'along').toList();
    expect(parts, hasLength(2));
    final areas = parts.map((p) => p.area).toList()..sort();
    expect(areas.first, closeTo(40 * 100, 1));
    expect(areas.last, closeTo(60 * 100, 1));
  });

  test('a limit on the line stops the straight cut short', () {
    final lines = straightCutLines(
      [_sheet()],
      const Offset(-5, 10),
      const Offset(5, 10),
      hi: 2.5,
    );
    final line = lines.single.$2;
    expect(line.first.dx, closeTo(-50.5, 1e-9));
    expect(line.last.dx, closeTo(20, 1e-9));
    final cut = cutPiecesAlongLine(
      [_sheet()],
      const Offset(-5, 10),
      const Offset(5, 10),
      hi: 2.5,
    )!;
    expect(cut.split, isFalse);
    expect(cut.pieces.single.scores, hasLength(1));
  });

  test('a straight drag that misses the paper cuts nothing', () {
    expect(
      cutPiecesAlongLine([_sheet()], const Offset(-5, 80), const Offset(5, 80)),
      isNull,
    );
  });

  test('a stroke off the paper misses', () {
    expect(
      cutPieces([_sheet()], _line(const Offset(200, 0), const Offset(300, 0))),
      isNull,
    );
  });
}
