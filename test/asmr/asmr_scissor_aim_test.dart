import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/asmr/asmr_scissor_aim.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Offset identity(Offset p) => p;
  test(
    'nearby hole boundaries are recommended but distant pieces are excluded',
    () {
      final sheet = AsmrPiece(
        id: 'a',
        paper: kAsmrCraftPaper,
        ring: const [
          Offset(-20, -20),
          Offset(20, -20),
          Offset(20, 20),
          Offset(-20, 20),
        ],
        holes: const [
          [Offset(-2, -2), Offset(2, -2), Offset(2, 2), Offset(-2, 2)],
        ],
      );
      final other = AsmrPiece.sheet(
        id: 'b',
        paper: kAsmrCraftPaper,
        at: const Offset(200, 0),
      );
      final points = scissorAimPoints(
        [sheet, other],
        Offset.zero,
        identity,
        identity,
      );
      expect(points, hasLength(1));
      expect(points.first.point.distance, closeTo(2, 1e-9));
      expect(points.single.pieceId, 'a');
    },
  );
  test(
    'perpendicular correction is limited to ten degrees and wraps angles',
    () {
      for (final degrees in [-10.0, -5.0, 0.0, 5.0, 10.0]) {
        final angle = degrees * math.pi / 180;
        expect(scissorAimAngle(angle, const Offset(10, 0)), closeTo(0, 1e-9));
        expect(
          scissorAimAngle(math.pi + angle, const Offset(10, 0)),
          closeTo(math.pi, 1e-9),
        );
      }
      const angle = 11 * math.pi / 180;
      expect(scissorAimAngle(angle, const Offset(10, 0)), angle);
      expect(scissorAimAngle(0, const Offset(0, 10)), 0);
    },
  );
  test('cutoff is half the shorter paper side in desk units', () {
    final sheet = AsmrPiece.sheet(
      id: 'sheet',
      paper: kAsmrCraftPaper,
      at: Offset.zero,
    );
    for (final angle in [0.0, math.pi / 4]) {
      final rotated = sheet.copyWith(angle: angle);
      for (final zoom in [0.5, 3.0]) {
        Offset project(Offset p) => p * zoom;
        Offset unproject(Offset p) => p / zoom;
        for (final gap in [79.0, 80.0, 81.0]) {
          final aim = project(rotated.toDesk(Offset(80 + gap, 0)));
          final points = scissorAimPoints([rotated], aim, project, unproject);
          expect(
            points.length,
            gap <= 80 ? 1 : 0,
            reason: 'angle $angle, zoom $zoom, gap $gap',
          );
        }
      }
    }
  });

  test('small scraps use their own shorter side', () {
    final scrap = AsmrPiece.sheet(
      id: 'scrap',
      paper: kAsmrCraftPaper,
      at: Offset.zero,
      size: const Size(20, 40),
    );
    expect(
      scissorAimPoints([scrap], const Offset(20, 0), identity, identity),
      hasLength(1),
    );
    expect(
      scissorAimPoints([scrap], const Offset(21, 0), identity, identity),
      isEmpty,
    );
  });

  test(
    'pre-cut orbit starts at ninety degrees and faces inward by the shortest turn',
    () {
      expect(scissorPreCutOrbitAngle(0, const Offset(0, -1)), isNull);
      final before = 89.9 * math.pi / 180;
      expect(
        scissorPreCutOrbitAngle(0, Offset(math.sin(before), -math.cos(before))),
        isNull,
      );
      expect(
        scissorPreCutOrbitAngle(0, const Offset(1, 0)),
        closeTo(-math.pi / 2, 1e-9),
      );
      expect(
        scissorPreCutOrbitAngle(0, const Offset(-1, 0)),
        closeTo(math.pi / 2, 1e-9),
      );
      expect(
        scissorPreCutOrbitAngle(0, const Offset(0, 1))!.abs(),
        closeTo(math.pi, 1e-9),
      );
      expect(
        scissorPreCutOrbitAngle(2 * math.pi, const Offset(1, 0)),
        closeTo(1.5 * math.pi, 1e-9),
      );
    },
  );

  test(
    'prospective cuts point into solid paper for either winding and for holes',
    () {
      const ring = [
        Offset(-20, -20),
        Offset(20, -20),
        Offset(20, 20),
        Offset(-20, 20),
      ];
      for (final outline in [ring, ring.reversed.toList()]) {
        final sheet = AsmrPiece(
          id: 'inward',
          paper: kAsmrCraftPaper,
          ring: outline,
          holes: const [
            [Offset(-2, -2), Offset(2, -2), Offset(2, 2), Offset(-2, 2)],
          ],
        );
        for (final reticle in [const Offset(0, -23), Offset.zero]) {
          final aim = scissorAimPoints(
            [sheet],
            reticle,
            identity,
            identity,
          ).single;
          expect(sheet.contains(aim.point + aim.inward * 0.1), isTrue);
          expect(sheet.contains(aim.point - aim.inward * 0.1), isFalse);
        }
      }
    },
  );

  test('distant fragments are rejected before projecting every boundary', () {
    final pieces = [
      for (var x = 0; x < 16; x++)
        for (var y = 0; y < 16; y++)
          AsmrPiece.sheet(
            id: '$x:$y',
            paper: kAsmrCraftPaper,
            at: Offset(x * 30.0, y * 30.0),
            size: const Size(10, 10),
          ),
    ];
    var projections = 0;
    Offset project(Offset p) {
      projections++;
      return p;
    }

    final targets = scissorAimPoints(pieces, Offset.zero, project, identity);
    expect(targets, hasLength(1));
    expect(targets.single.pieceId, '0:0');
    expect(projections, lessThanOrEqualTo(16));
  });

  test('duplicate vertices are skipped', () {
    final p = AsmrPiece(
      id: 'a',
      paper: kAsmrCraftPaper,
      ring: const [Offset.zero, Offset.zero, Offset(10, 0), Offset(0, 10)],
    );
    final points = scissorAimPoints(
      [p],
      const Offset(5, -2),
      identity,
      identity,
    );
    expect(points.single.point, const Offset(5, 0));
  });
}
