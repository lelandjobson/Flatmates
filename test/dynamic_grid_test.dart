import 'package:flatmates/gridcraft/dynamic_grid.dart';
import 'package:flatmates/gridcraft/dynamic_l.dart';
import 'package:flatmates/gridcraft/dynamic_stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dynamic grid', () {
    test('no tangram means no grid', () {
      final graph = buildDynamicGrid(cover: const Rect.fromLTRB(0, 0, 12, 6));
      expect(graph.links, isEmpty);
      expect(graph.vertices, isEmpty);
    });

    test('one square repeats at its own cell size', () {
      final graph = buildDynamicGrid(
        pieces: const [
          TangramPiece(
            id: 's',
            kind: TangramKind.square,
            anchor: Offset(2, 2),
            colorIndex: 0,
          ),
        ],
        cover: const Rect.fromLTRB(0, 0, 8, 8),
      );
      expect(graph.hasSegment(const Offset(2, 2), const Offset(4, 2)), isTrue);
      expect(graph.hasSegment(const Offset(4, 2), const Offset(4, 4)), isTrue);
      expect(graph.hasSegment(const Offset(4, 4), const Offset(2, 4)), isTrue);
      expect(graph.hasSegment(const Offset(2, 4), const Offset(2, 2)), isTrue);
      expect(graph.hasSegment(const Offset(4, 2), const Offset(6, 2)), isTrue);
      expect(graph.hasSegment(const Offset(2, 4), const Offset(4, 4)), isTrue);
      expect(graph.hasSegment(const Offset(3, 2), const Offset(3, 4)), isFalse);
    });

    test('a circle repeats as a full circle on its bounding box', () {
      final graph = buildDynamicGrid(
        pieces: const [
          TangramPiece(
            id: 'c',
            kind: TangramKind.circle,
            anchor: Offset(3, 3),
            colorIndex: 1,
          ),
        ],
        cover: const Rect.fromLTRB(0, 0, 8, 6),
      );
      expect(graph.containsPoint(const Offset(4, 3)), isTrue);
      expect(graph.containsPoint(const Offset(2, 3)), isTrue);
      expect(graph.containsPoint(const Offset(6, 3)), isTrue);
    });

    test('a drawn translation replaces that axis of the period', () {
      const square = TangramPiece(
        id: 's',
        kind: TangramKind.square,
        anchor: Offset(0, 0),
        colorIndex: 0,
      );
      final graph = buildDynamicGrid(
        pieces: const [square],
        tessellation: const DynamicTessellation(horizontal: Offset(4, 0)),
        cover: const Rect.fromLTRB(-1, -1, 8, 6),
      );
      expect(graph.hasSegment(const Offset(0, 0), const Offset(2, 0)), isTrue);
      expect(graph.hasSegment(const Offset(2, 0), const Offset(4, 0)), isFalse);
      expect(graph.hasSegment(const Offset(4, 0), const Offset(6, 0)), isTrue);
      expect(graph.hasSegment(const Offset(0, 2), const Offset(0, 4)), isTrue);
    });
  });

  group('dynamic stroke', () {
    final step = dynamicLBlueprint().steps.single;

    test('a stroke cannot start inside paper', () {
      final sheet = dynamicPaperSheet(step);
      final graph = buildDynamicGrid(
        pieces: const [
          TangramPiece(
            id: 's',
            kind: TangramKind.square,
            anchor: Offset(2, 0),
            colorIndex: 0,
          ),
        ],
        cover: step.paper.inflate(2),
      );
      final session = DynamicStrokeSession(graph: graph);
      expect(session.begin(const Offset(3, 0.2), sheet), isFalse);
      expect(session.active, isFalse);
    });

    test('a stroke that stops inside paper does not split', () {
      final sheet = dynamicPaperSheet(step);
      final next = commitDynamicCut(
        sheet: sheet,
        points: const [Offset(0, -4), Offset(0, -1)],
        step: step,
      );
      expect(next, isNull);
      expect(sheet.pieces, hasLength(1));
    });

    test(
      'a finger walks the grid from outside the paper and splits on release',
      () {
        final sheet = dynamicPaperSheet(step);
        final graph = buildDynamicGrid(
          pieces: const [
            TangramPiece(
              id: 's',
              kind: TangramKind.square,
              anchor: Offset.zero,
              colorIndex: 0,
            ),
          ],
          cover: step.paper.inflate(8),
        );
        final session = DynamicStrokeSession(graph: graph);
        expect(session.begin(const Offset(0, -4), sheet), isTrue);
        session.move(const Offset(0, 8));
        final next = commitDynamicCut(
          sheet: sheet,
          points: session.points,
          step: step,
        );
        expect(next, isNotNull);
        expect(next!.pieces.length, greaterThan(1));
        for (final piece in next.pieces) {
          expect(piece.separation, Offset.zero);
        }
      },
    );

    test('a stroke that enters and exits splits in place', () {
      final sheet = dynamicPaperSheet(step);
      final next = commitDynamicCut(
        sheet: sheet,
        points: const [Offset(0, -4), Offset(0, 8)],
        step: step,
      );
      expect(next, isNotNull);
      expect(next!.pieces.length, greaterThan(1));
      for (final piece in next.pieces) {
        expect(piece.separation, Offset.zero);
      }
    });

    test('a straight through-stroke folds and stays in place', () {
      final sheet = dynamicPaperSheet(step);
      final next = commitDynamicFold(
        sheet: sheet,
        points: const [Offset(-1, -4), Offset(-1, 8)],
        step: step,
      );
      expect(next, isNotNull);
      expect(next!.folds, isNotEmpty);
      for (final piece in next.pieces) {
        expect(piece.separation, Offset.zero);
      }
    });

    test('a path through a blueprint piece is illegal before release', () {
      final sheet = dynamicPaperSheet(step);
      final points = const [Offset(0, 2), Offset(2, 2)];
      final assessment = assessDynamicStroke(points, sheet, step);
      expect(assessment.illegal, isTrue);
      expect(assessment.piercedIndex, 0);
      expect(
        commitDynamicCut(sheet: sheet, points: points, step: step),
        isNull,
      );
    });
  });
}
