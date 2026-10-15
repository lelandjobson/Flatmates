import 'dart:ui';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/criteria.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter_test/flutter_test.dart';

const _yellow = Color(0xFFFFF3B0);

const _square = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];

GridStep _step({List<EdgeStyle>? styles}) => GridStep(
  id: 'level',
  label: 'Level',
  polygons: const [_square],
  edgeStyles: styles == null ? const [] : [styles],
);

PapercutPiece _piece(String id, List<Offset> vertices) =>
    PapercutPiece(id: id, color: _yellow, vertices: vertices);

void main() {
  test('penned edges are cut criteria and penciled edges are folds', () {
    final step = _step(
      styles: const [
        EdgeStyle.penned,
        EdgeStyle.penciled,
        EdgeStyle.penned,
        EdgeStyle.penned,
      ],
    );
    final kinds = [for (final c in stepCriteria(step).single) c.kind];
    expect(kinds, [
      CriterionKind.cut,
      CriterionKind.fold,
      CriterionKind.cut,
      CriterionKind.cut,
    ]);
  });

  test('a cut along part of an edge meets only that part', () {
    final sheet = PapercutSheet(
      pieces: [
        _piece('a', const [
          Offset(-2, -2),
          Offset(1, -2),
          Offset(1, 0),
          Offset(-2, 0),
        ]),
      ],
    );
    final progress = blueprintProgress(_step(), sheet);
    final bottom = progress.edge(0, 0)!;
    expect(bottom.met, hasLength(1));
    expect(bottom.metLength, closeTo(1, 1e-6));
    expect(bottom.done, isFalse);
    expect(progress.complete(0), isFalse);
  });

  test('cutting the piece out completes it', () {
    final sheet = PapercutSheet(
      pieces: [
        _piece('out', _square),
        PapercutPiece(
          id: 'frame',
          color: _yellow,
          vertices: const [
            Offset(-2, -2),
            Offset(4, -2),
            Offset(4, 4),
            Offset(-2, 4),
          ],
          holes: const [_square],
          separation: const Offset(3, 0),
        ),
      ],
    );
    expect(blueprintProgress(_step(), sheet).complete(0), isTrue);
  });

  test('a fold meets a penciled edge and a cut does not', () {
    final step = _step(
      styles: const [
        EdgeStyle.penned,
        EdgeStyle.penciled,
        EdgeStyle.penned,
        EdgeStyle.penned,
      ],
    );
    final cutOnly = PapercutSheet(
      pieces: [
        _piece('a', const [
          Offset(2, -2),
          Offset(4, -2),
          Offset(4, 4),
          Offset(2, 4),
        ]),
      ],
    );
    expect(blueprintProgress(step, cutOnly).edge(0, 1)!.met, isEmpty);

    const folded = PapercutSheet(
      pieces: [],
      folds: [
        FoldJoint(
          a: Offset(2, -1),
          b: Offset(2, 3),
          side: 1,
          facing: FoldFacing.toward,
        ),
      ],
    );
    expect(blueprintProgress(step, folded).edge(0, 1)!.done, isTrue);
  });

  test('covered spans merge overlapping collinear segments', () {
    final spans = coveredSpans(const Offset(0, 0), const Offset(4, 0), const [
      (Offset(0.5, 0), Offset(2, 0)),
      (Offset(1.5, 0), Offset(3, 0)),
      (Offset(0, 1), Offset(4, 1)),
    ]);
    expect(spans, hasLength(1));
    expect(spans.single.$1.dx, closeTo(0.5, 1e-6));
    expect(spans.single.$2.dx, closeTo(3, 1e-6));
  });
}
