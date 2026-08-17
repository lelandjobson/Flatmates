import 'package:flatmates/crafting/paper_splitting.dart';
import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sheet = [
    Offset(-2, -2),
    Offset(2, -2),
    Offset(2, 2),
    Offset(-2, 2),
  ];
  const hole = [
    Offset(-0.5, -0.5),
    Offset(0.5, -0.5),
    Offset(0.5, 0.5),
    Offset(-0.5, 0.5),
  ];
  const largeHole = [
    Offset(-0.5, -1.5),
    Offset(1.8, -1.5),
    Offset(1.8, 1.5),
    Offset(-0.5, 1.5),
  ];
  const leftHole = [
    Offset(-1.5, -0.4),
    Offset(-0.5, -0.4),
    Offset(-0.5, 0.4),
    Offset(-1.5, 0.4),
  ];
  const rightHole = [
    Offset(0.5, -0.4),
    Offset(1.5, -0.4),
    Offset(1.5, 0.4),
    Offset(0.5, 0.4),
  ];

  group('plain sheet', () {
    test('empty cuts leave the sheet unchanged', () {
      final pieces = splitPaperByCuts(sheet, const []);
      expect(pieces, hasLength(1));
      expect(pieces.single.$2, isEmpty);
      expectArea(pieces, sheet);
    });

    test('a horizontal cut yields two halves with no leftover original', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
      );
      expectSplit(pieces, count: 2, original: sheet);
    });

    test('a vertical cut yields two halves with no leftover original', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(0, -3), Offset(0, 3))],
      );
      expectSplit(pieces, count: 2, original: sheet);
    });

    test('a diagonal cut yields two pieces that cover the sheet', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, -3), Offset(3, 3))],
      );
      expectSplit(pieces, count: 2, original: sheet);
    });

    test('crossing cuts yield four pieces', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [
          (Offset(-3, 0), Offset(3, 0)),
          (Offset(0, -3), Offset(0, 3)),
        ],
      );
      expectSplit(pieces, count: 4, original: sheet);
    });

    test('a cut that misses the sheet leaves it intact', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(5, -1), Offset(5, 1))],
      );
      expect(pieces, hasLength(1));
      expectArea(pieces, sheet);
    });

    test('a zero-length cut leaves the sheet intact', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(0, 0), Offset(0, 0))],
      );
      expect(pieces, hasLength(1));
      expectArea(pieces, sheet);
    });

    test('an L-shaped sheet splits without duplicating the original', () {
      const ell = [
        Offset(-2, -2),
        Offset(2, -2),
        Offset(2, 0),
        Offset(0, 0),
        Offset(0, 2),
        Offset(-2, 2),
      ];
      final pieces = splitPaperByCuts(
        ell,
        const [(Offset(-3, 0.5), Offset(3, 0.5))],
      );
      expectSplit(pieces, count: 2, original: ell);
    });

    test('a diamond splits along a horizontal through-cut', () {
      const diamond = [
        Offset(0, -2),
        Offset(2, 0),
        Offset(0, 2),
        Offset(-2, 0),
      ];
      final pieces = splitPaperByCuts(
        diamond,
        const [(Offset(-3, 0), Offset(3, 0))],
      );
      expectSplit(pieces, count: 2, original: diamond);
    });
  });

  group('holed sheet', () {
    test('an uncut holed sheet stays one piece with its hole', () {
      final pieces = splitPaperByCuts(sheet, const [], holes: const [hole]);
      expect(pieces, hasLength(1));
      expect(pieces.single.$2, hasLength(1));
      expectArea(pieces, sheet, holes: const [hole]);
    });

    test('a cut that misses the paper leaves the holed sheet intact', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(5, -1), Offset(5, 1))],
        holes: const [hole],
      );
      expect(pieces, hasLength(1));
      expect(pieces.single.$2, hasLength(1));
      expectArea(pieces, sheet, holes: const [hole]);
    });

    test('a cut through the hole keeps both sides and opens the hole', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [hole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [hole]);
      expect(
        pieces.fold<int>(0, (n, p) => n + p.$2.length),
        0,
        reason: 'a through-cut should open the hole into the exteriors',
      );
    });

    test('a vertical cut through the hole keeps both sides', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(0, -3), Offset(0, 3))],
        holes: const [hole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [hole]);
    });

    test('a cut that misses the hole keeps the hole on one piece', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-1, -3), Offset(-1, 3))],
        holes: const [hole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [hole]);
      expect(pieces.fold<int>(0, (n, p) => n + p.$2.length), 1);
    });

    test('an off-center hole stays on the piece that still contains it', () {
      const cornerHole = [
        Offset(0.6, 0.6),
        Offset(1.4, 0.6),
        Offset(1.4, 1.4),
        Offset(0.6, 1.4),
      ];
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [cornerHole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [cornerHole]);
      expect(pieces.fold<int>(0, (n, p) => n + p.$2.length), 1);
      final host = pieces.singleWhere((p) => p.$2.isNotEmpty);
      expect(isInsidePolygon(const Offset(1, 1), host.$1), isTrue);
    });

    test('a triangular hole is opened by a through-cut, not shredded', () {
      const triangle = [
        Offset(0, 0.6),
        Offset(-0.6, -0.4),
        Offset(0.6, -0.4),
      ];
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [triangle],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [triangle]);
    });

    test('crossing cuts through a hole yield four pieces', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [
          (Offset(-3, 0), Offset(3, 0)),
          (Offset(0, -3), Offset(0, 3)),
        ],
        holes: const [hole],
      );
      expectSplit(pieces, count: 4, original: sheet, holes: const [hole]);
    });
  });

  group('multiple holes', () {
    test('a cut between two holes leaves one hole on each piece', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(0, -3), Offset(0, 3))],
        holes: const [leftHole, rightHole],
      );
      expectSplit(
        pieces,
        count: 2,
        original: sheet,
        holes: const [leftHole, rightHole],
      );
      expect(pieces.fold<int>(0, (n, p) => n + p.$2.length), 2);
      expect(pieces.every((p) => p.$2.length == 1), isTrue);
    });

    test('a cut through both holes opens them and keeps both sides', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [leftHole, rightHole],
      );
      expectSplit(
        pieces,
        count: 2,
        original: sheet,
        holes: const [leftHole, rightHole],
      );
      expect(pieces.fold<int>(0, (n, p) => n + p.$2.length), 0);
    });

    test('a cut through one hole opens only that hole', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-1, -3), Offset(-1, 3))],
        holes: const [leftHole, rightHole],
      );
      expectSplit(
        pieces,
        count: 2,
        original: sheet,
        holes: const [leftHole, rightHole],
      );
      expect(pieces.fold<int>(0, (n, p) => n + p.$2.length), 1);
    });
  });

  group('regression: hole edges are not cutting lines', () {
    test('a through-cut does not shard the sheet into a grid', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [hole],
      );
      expect(pieces, hasLength(2));
      for (final piece in pieces) {
        expect(piece.$1.length, lessThan(20));
      }
    });

    test('hole-boundary segments used only as holes do not pre-slice the sheet',
        () {
      final pieces = splitPaperByCuts(sheet, const [], holes: const [hole]);
      expect(pieces, hasLength(1));
      expect(pieces.single.$1.length, lessThan(8));
      expectArea(pieces, sheet, holes: const [hole]);
    });
  });

  group('regression: no duplicate original', () {
    test('plain through-cut area equals the original, not 1.5x', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
      );
      expect(pieces, hasLength(2));
      expectArea(pieces, sheet);
      expectNoDuplicateOriginal(pieces, sheet);
    });

    test('holed through-cut area equals solid paper, not solid plus original',
        () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [hole],
      );
      expect(pieces, hasLength(2));
      expectArea(pieces, sheet, holes: const [hole]);
      expectNoDuplicateOriginal(pieces, sheet);
    });
  });

  group('regression: both sides of a holed cut survive', () {
    test('a cut through a large hole keeps the C-shaped side', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(0, -3), Offset(0, 3))],
        holes: const [largeHole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [largeHole]);
    });

    test('a cut through a near-edge hole keeps the thin remaining frame', () {
      const edgeHole = [
        Offset(-1.6, -1.6),
        Offset(1.6, -1.6),
        Offset(1.6, 1.6),
        Offset(-1.6, 1.6),
      ];
      final pieces = splitPaperByCuts(
        sheet,
        const [(Offset(-3, 0), Offset(3, 0))],
        holes: const [edgeHole],
      );
      expectSplit(pieces, count: 2, original: sheet, holes: const [edgeHole]);
    });
  });

  group('degenerate input', () {
    test('a two-vertex polygon is returned unchanged', () {
      const line = [Offset(0, 0), Offset(1, 0)];
      final pieces = splitPaperByCuts(
        line,
        const [(Offset(-1, 0), Offset(1, 0))],
      );
      expect(pieces, hasLength(1));
      expect(pieces.single.$1, line);
    });

    test('a two-vertex hole is ignored', () {
      final pieces = splitPaperByCuts(
        sheet,
        const [],
        holes: const [
          [Offset(0, 0), Offset(1, 0)],
        ],
      );
      expect(pieces, hasLength(1));
      expect(pieces.single.$2, isEmpty);
      expectArea(pieces, sheet);
    });
  });

  group('splitPolygonByCuts', () {
    test('returns the same exteriors as splitPaperByCuts', () {
      final cuts = const [(Offset(-3, 0), Offset(3, 0))];
      final withHoles = splitPaperByCuts(sheet, cuts, holes: const [hole]);
      final exteriors = splitPolygonByCuts(sheet, cuts, holes: const [hole]);
      expect(exteriors, hasLength(withHoles.length));
      for (var i = 0; i < exteriors.length; i++) {
        expect(exteriors[i], withHoles[i].$1);
      }
    });
  });
}

double solidArea(
  List<Offset> exterior, [
  List<List<Offset>> holes = const [],
]) {
  var area = polygonSignedArea(exterior).abs();
  for (final hole in holes) {
    area -= polygonSignedArea(hole).abs();
  }
  return area;
}

double piecesArea(List<(List<Offset>, List<List<Offset>>)> pieces) {
  return pieces.fold<double>(0, (n, p) => n + solidArea(p.$1, p.$2));
}

void expectArea(
  List<(List<Offset>, List<List<Offset>>)> pieces,
  List<Offset> original, {
  List<List<Offset>> holes = const [],
}) {
  expect(
    piecesArea(pieces),
    closeTo(solidArea(original, holes), 0.05),
    reason: 'piece areas must cover the solid paper with no extras',
  );
}

void expectDisjoint(List<(List<Offset>, List<List<Offset>>)> pieces) {
  for (var i = 0; i < pieces.length; i++) {
    final sample = _sampleInside(pieces[i].$1);
    if (sample == null) continue;
    for (var j = 0; j < pieces.length; j++) {
      if (i == j) continue;
      expect(
        isInsidePolygon(sample, pieces[j].$1),
        isFalse,
        reason: 'piece $i overlaps piece $j',
      );
    }
  }
}

void expectNoDuplicateOriginal(
  List<(List<Offset>, List<List<Offset>>)> pieces,
  List<Offset> original,
) {
  if (pieces.length < 2) return;
  final full = polygonSignedArea(original).abs();
  for (final piece in pieces) {
    expect(
      polygonSignedArea(piece.$1).abs(),
      lessThan(full * 0.99),
      reason: 'a split piece must not be a copy of the original outline',
    );
  }
}

void expectSplit(
  List<(List<Offset>, List<List<Offset>>)> pieces, {
  required int count,
  required List<Offset> original,
  List<List<Offset>> holes = const [],
}) {
  expect(pieces, hasLength(count));
  expectArea(pieces, original, holes: holes);
  expectDisjoint(pieces);
  expectNoDuplicateOriginal(pieces, original);
  for (final piece in pieces) {
    expect(piece.$1.length, lessThan(32), reason: 'piece was shredded');
    expect(polygonSignedArea(piece.$1).abs(), greaterThan(1e-4));
  }
}

Offset? _sampleInside(List<Offset> polygon) {
  final centroid = polygonCentroid(polygon);
  if (isInsidePolygon(centroid, polygon)) return centroid;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final inward = Offset((centroid.dx + mid.dx) / 2, (centroid.dy + mid.dy) / 2);
    if (isInsidePolygon(inward, polygon)) return inward;
  }
  return null;
}
