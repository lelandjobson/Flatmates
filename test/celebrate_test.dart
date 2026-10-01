import 'dart:ui';

import 'package:flatmates/gridcraft/celebrate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the fill holds, then the burst starts', () {
    expect(Celebration.fillSeconds, 0.25);
    expect(Celebration.glowSeconds, 0.48);
    expect(Celebration.holdSeconds, 0.25);
    expect(Celebration.totalSeconds, 1.3);
    expect(Celebration.duration, const Duration(milliseconds: 1300));
  });

  const square = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

  test('a unit square raster is 2 by 2 and the waves are mixed', () {
    final celebration = prepareCelebration(square);
    expect(celebration.cells, hasLength(4));
    expect(celebration.cellSize, 0.5);
    expect(celebration.rowCount, 1);
    final counts = [0, 0, 0, 0];
    for (final cell in celebration.cells) {
      counts[cell.wave]++;
    }
    expect(counts, [1, 1, 1, 1]);

    final byIndex = <(int, int), int>{};
    for (final cell in celebration.cells) {
      final ix = (cell.at.dx * 2).floor();
      final iy = (cell.at.dy * 2).floor();
      byIndex[(ix, iy)] = cell.wave;
    }
    for (final entry in byIndex.entries) {
      final right = byIndex[(entry.key.$1 + 1, entry.key.$2)];
      final below = byIndex[(entry.key.$1, entry.key.$2 + 1)];
      if (right != null) expect(right, isNot(entry.value));
      if (below != null) expect(below, isNot(entry.value));
    }
  });

  test('preparing a ring twice keeps the wave, row, and kick', () {
    const ring = [Offset(0, 0), Offset(6, 0), Offset(6, 4), Offset(0, 4)];
    final first = prepareCelebration(ring);
    final again = prepareCelebration(ring);
    expect(again.cells, hasLength(first.cells.length));
    for (var i = 0; i < first.cells.length; i++) {
      expect(again.cells[i].wave, first.cells[i].wave);
      expect(again.cells[i].row, first.cells[i].row);
      expect(again.cells[i].direction, first.cells[i].direction);
      expect(again.cells[i].reach, first.cells[i].reach);
    }
  });

  test(
    'thirty percent of sparks travel twice as far, and thirty percent four times',
    () {
      final celebration = prepareCelebration(const [
        Offset(0, 0),
        Offset(8, 0),
        Offset(8, 8),
        Offset(0, 8),
      ]);
      var twice = 0;
      var four = 0;
      for (final cell in celebration.cells) {
        if (cell.reach == 2) twice++;
        if (cell.reach == 4) four++;
        expect(cell.reach, isIn([1, 2, 4]));
      }
      expect(twice / celebration.cells.length, closeTo(0.3, 0.05));
      expect(four / celebration.cells.length, closeTo(0.3, 0.05));
      final base = sparkPosition(
        const SparkCell(
          at: Offset.zero,
          wave: 0,
          row: 0,
          direction: Offset(1, 0),
        ),
        0.4,
        speed: 3.2,
      ).distance;
      final doubled = sparkPosition(
        const SparkCell(
          at: Offset.zero,
          wave: 0,
          row: 0,
          direction: Offset(1, 0),
          reach: 2,
        ),
        0.4,
        speed: 3.2 * 2,
      ).distance;
      final quadrupled = sparkPosition(
        const SparkCell(
          at: Offset.zero,
          wave: 0,
          row: 0,
          direction: Offset(1, 0),
          reach: 4,
        ),
        0.4,
        speed: 3.2 * 4,
      ).distance;
      expect(doubled, closeTo(base * 2, 1e-6));
      expect(quadrupled, closeTo(base * 4, 1e-6));
    },
  );

  test('rows march inward and follow the short side', () {
    const ring = [Offset(0, 0), Offset(6, 0), Offset(6, 4), Offset(0, 4)];
    final celebration = prepareCelebration(ring);
    expect(celebration.rowCount, 2);
    expect(celebrationRowCount(3), 2);
    final center = const Offset(3, 2);
    SparkCell? inner;
    SparkCell? outer;
    var bestInner = double.infinity;
    var bestOuter = double.infinity;
    for (final cell in celebration.cells) {
      final toCenter = (cell.at - center).distance;
      if (toCenter < bestInner) {
        bestInner = toCenter;
        inner = cell;
      }
      final toEdge = [
        cell.at.dx,
        cell.at.dy,
        6 - cell.at.dx,
        4 - cell.at.dy,
      ].reduce((a, b) => a < b ? a : b);
      if (toEdge < bestOuter) {
        bestOuter = toEdge;
        outer = cell;
      }
    }
    expect(outer!.row, lessThan(inner!.row));
  });

  test('a finished piece is not a leftover scrap', () {
    expect(leftoverScrapIds(const ['done', 'scrap', 'also'], const {'done'}), [
      'scrap',
      'also',
    ]);
    expect(leftoverScrapIds(const ['done'], const {'done'}), isEmpty);
  });

  test('leftover bursts stagger by 150 ms and keep the paper color', () {
    expect(Celebration.scrapStaggerSeconds, 0.15);
    expect(scrapDelay(0, afterSuccess: true), 0.15);
    expect(scrapDelay(1, afterSuccess: true), 0.30);
    expect(scrapDelay(0, afterSuccess: false), 0);
    expect(scrapDelay(2, afterSuccess: false), 0.30);

    const ink = Color(0xFFFFF3B0);
    final scrap = CelebrationPlayback(
      pieceId: 'scrap',
      celebration: prepareCelebration(square),
      delay: scrapDelay(0, afterSuccess: true),
      ink: ink,
      burst: true,
    );
    expect(scrap.burst, isTrue);
    expect(scrap.span, closeTo(0.15 + Celebration.totalSeconds, 1e-9));
    expect(scrap.local(0.15), 0);
    expect(scrap.fillColors.first, ink);
    expect(scrap.fillColors, isNot(Celebration.successFill));
    expect(scrap.sparkColors.first, isNot(Celebration.successSpark.first));
    final success = CelebrationPlayback(
      pieceId: 'piece',
      celebration: scrap.celebration,
    );
    expect(success.burst, isFalse);
    expect(success.span, Celebration.glowSeconds);
    expect(success.fillColors, Celebration.successFill);
    expect(success.sparkColors, Celebration.successSpark);
  });

  test('a hole drops the cells inside it', () {
    const ring = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    const hole = [
      Offset(0.5, 0.5),
      Offset(1.5, 0.5),
      Offset(1.5, 1.5),
      Offset(0.5, 1.5),
    ];
    final solid = prepareCelebration(ring);
    final opened = prepareCelebration(ring, holes: const [hole]);
    expect(solid.cells, hasLength(4 * 4));
    expect(opened.cells.length, lessThan(solid.cells.length));
    for (final cell in opened.cells) {
      expect(
        cell.at.dx <= 0.5 ||
            cell.at.dx >= 1.5 ||
            cell.at.dy <= 0.5 ||
            cell.at.dy >= 1.5,
        isTrue,
      );
    }
  });
}
