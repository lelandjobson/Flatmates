import 'package:flatmates/gridcraft/piece_quadtree.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a query skips pieces whose bounds miss the rectangle', () {
    final bounds = [
      const Rect.fromLTWH(0, 0, 1, 1),
      const Rect.fromLTWH(10, 10, 1, 1),
      const Rect.fromLTWH(40, 0, 1, 1),
      const Rect.fromLTWH(0, 40, 1, 1),
      const Rect.fromLTWH(80, 80, 1, 1),
    ];
    final hits = PieceQuadtree(bounds).query(const Rect.fromLTWH(9.5, 9.5, 2, 2));
    expect(hits, [1]);
  });

  test('a press on paper picks that piece', () {
    final pieces = [
      _square('a', 0),
      _square('b', 3),
    ];
    expect(
      closestPieceIndex(point: const Offset(3.2, 0.4), pieces: pieces, unit: 1),
      1,
    );
  });

  test('a press within half a unit picks the closest piece', () {
    final pieces = [
      _square('a', 0),
      _square('b', 4),
    ];
    expect(
      closestPieceIndex(point: const Offset(1.4, 0.5), pieces: pieces, unit: 1),
      0,
    );
    expect(
      closestPieceIndex(point: const Offset(1.6, 0.5), pieces: pieces, unit: 1),
      isNull,
    );
  });

  test('a moved piece is picked where it is drawn', () {
    final pieces = [
      _square('a', 0, separation: const Offset(10, 0)),
    ];
    expect(
      closestPieceIndex(point: const Offset(0.5, 0.5), pieces: pieces, unit: 1),
      isNull,
    );
    expect(
      closestPieceIndex(point: const Offset(10.5, 0.5), pieces: pieces, unit: 1),
      0,
    );
  });

  test('the middle of a hole is not the frame', () {
    final frame = PapercutPiece(
      id: 'frame',
      color: const Color(0xFFFFF3B0),
      vertices: const [
        Offset(0, 0),
        Offset(6, 0),
        Offset(6, 6),
        Offset(0, 6),
      ],
      holes: const [
        [Offset(1, 1), Offset(5, 1), Offset(5, 5), Offset(1, 5)],
      ],
    );
    expect(
      closestPieceIndex(point: const Offset(3, 3), pieces: [frame], unit: 1),
      isNull,
    );
    expect(
      closestPieceIndex(point: const Offset(0.7, 3), pieces: [frame], unit: 1),
      0,
    );
  });
}

PapercutPiece _square(String id, double x, {Offset separation = Offset.zero}) {
  return PapercutPiece(
    id: id,
    color: const Color(0xFFFFF3B0),
    vertices: [
      Offset(x, 0),
      Offset(x + 1, 0),
      Offset(x + 1, 1),
      Offset(x, 1),
    ],
    separation: separation,
  );
}
