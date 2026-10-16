import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/placement.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

const _levelPath = 'levels/boxes/grid-cube.json';

GridStep _level() => GridBlueprint.fromJson(
  jsonDecode(File(_levelPath).readAsStringSync()) as Map<String, dynamic>,
).steps.single;

FoldedModel _model(GridStep level) => foldedModelFromCraft(
  CraftV1.fromJson(
    jsonDecode(File('$kCubeCraftDirectory/craft.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  1,
  level,
)!;

PapercutPiece _sheet(Rect rect) => PapercutPiece(
  id: 'sheet',
  color: kPapercutYellow,
  vertices: [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft],
);

WrapCut _start(GridStep level, FoldedModel model, Rect rect, int ring) {
  final piece = _sheet(rect);
  return WrapCut.start(
    model: model,
    piece: piece,
    placement: PiecePlacement(pieceId: piece.id, face: model.faceOfRing(ring)!),
    lines: level.pattern!.patternLines(rect),
  );
}

/// Strokes from the blade to each of [corners] in turn along the pattern.
WrapCut _cutThrough(WrapCut cut, List<Offset> corners) {
  for (final corner in corners) {
    for (var guard = 0; guard < 20 && !cut.finished; guard++) {
      final at = cut.blade!;
      if ((at - corner).distance < 1e-6) break;
      final heading = corner - at;
      final options = cut.options();
      final cut0 = options.where((option) {
        final d = option.direction;
        return (d.dx * heading.dy - d.dy * heading.dx).abs() < 1e-6 &&
            d.dx * heading.dx + d.dy * heading.dy > 0;
      });
      expect(cut0, isNotEmpty, reason: 'no cut from $at toward $corner');
      cut = cut.stroke(cut0.first).cut;
    }
    expect(cut.blade, corner);
  }
  return cut;
}

void _expectNear(Vector3 actual, Vector3 expected) {
  expect((actual - expected).length, lessThan(1e-6), reason: '$actual');
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-6));
  expect(actual.top, closeTo(expected.top, 1e-6));
  expect(actual.right, closeTo(expected.right, 1e-6));
  expect(actual.bottom, closeTo(expected.bottom, 1e-6));
}

void main() {
  test('grid-cube is a pattern level on craft_Cube', () {
    final level = _level();
    expect(level.craft?.id, kCubeCraftId);
    final pattern = level.pattern!;
    expect(pattern.period, const Offset(5, 5));
    expect(pattern.sheet, const Rect.fromLTWH(-2, -2, 24, 19));
    final again = CutPattern.fromJson(pattern.toJson())!;
    expect(again.segments, pattern.segments);
    expect(again.sheet, pattern.sheet);
    final lines = pattern.patternLines(const Rect.fromLTWH(0, 0, 10, 5));
    expect(lines, contains((const Offset(5, 0), const Offset(5, 5))));
    expect(lines, contains((const Offset(0, 5), const Offset(5, 5))));
  });

  test('faceAdjacency pairs every cube edge, cut or hinged', () {
    final model = _model(_level());
    final adjacency = faceAdjacency(model);
    for (var face = 0; face < model.faces.length; face++) {
      expect(adjacency[face], hasLength(4));
      for (final neighbor in adjacency[face]) {
        expect(neighbor, isNotNull);
        expect(adjacency[neighbor!.face][neighbor.edge]!.face, face);
      }
    }
  });

  test('snapToPattern prefers pattern vertices, then lines', () {
    final level = _level();
    final piece = _sheet(level.pattern!.sheet);
    final tree = patternQuadtree(
      level.pattern!.patternLines(level.pattern!.sheet),
      piece,
    );
    expect(
      snapToPattern(tree, piece, const Offset(5.3, 4.8), 0.6),
      const Offset(5, 5),
    );
    expect(
      snapToPattern(tree, piece, const Offset(7.2, 5.3), 0.6),
      const Offset(7.2, 5),
    );
    expect(snapToPattern(tree, piece, const Offset(7.5, 7.5), 0.6), isNull);
  });

  test('a face lined up with the pattern is an aligned cell', () {
    final level = _level();
    final model = _model(level);
    final cut = _start(level, model, level.pattern!.sheet, 0);
    final cell = alignedCell(cut, 0);
    expect(cell, cut.flaps.single.facePaper);
    for (final corner in cell!) {
      expect(corner.dx / 5, closeTo((corner.dx / 5).roundToDouble(), 1e-9));
      expect(corner.dy / 5, closeTo((corner.dy / 5).roundToDouble(), 1e-9));
    }

    // One cell off the lines, nothing lines up.
    final piece = _sheet(level.pattern!.sheet);
    final shifted = WrapCut.start(
      model: model,
      piece: piece,
      placement: PiecePlacement(
        pieceId: piece.id,
        face: model.faceOfRing(0)!,
        offset: const Offset(1, 0),
      ),
      lines: level.pattern!.patternLines(level.pattern!.sheet),
    );
    expect(alignedCell(shifted, 0), isNull);

    // Paper short of the face does not cover it.
    final face = pointBounds(cell);
    final short = _start(
      level,
      model,
      Rect.fromLTRB(face.left, face.top, face.right, face.center.dy),
      0,
    );
    expect(alignedCell(short, 0), isNull);
  });

  test('cuts can start mid-way along each pattern line on a face edge', () {
    final level = _level();
    final model = _model(level);
    final cut = _start(level, model, level.pattern!.sheet, 0);
    final ring = cut.flaps.single.facePaper;
    final starts = faceEdgeStarts(cut);
    expect(starts, hasLength(4));
    for (var i = 0; i < ring.length; i++) {
      final middle = Offset.lerp(ring[i], ring[(i + 1) % ring.length], 0.5)!;
      expect(starts.any((s) => (s - middle).distance < 1e-6), isTrue);
    }

    // Paper short of the face has no starts along the edge it misses.
    final face = pointBounds(ring);
    final short = _start(
      level,
      model,
      Rect.fromLTRB(
        face.left - 1,
        face.top - 1,
        face.right + 1,
        face.center.dy,
      ),
      0,
    );
    expect(
      faceEdgeStarts(short).where((s) => s.dy > face.center.dy + 1e-6),
      isEmpty,
    );
  });

  test('cutting the cross net out folds it around the cube for 600', () {
    final level = _level();
    final model = _model(level);
    var cut = _start(level, model, level.pattern!.sheet, 0);
    cut = cut.placedAt(const Offset(5, 5));
    cut = _cutThrough(cut, const [
      Offset(5, 0),
      Offset(10, 0),
      Offset(10, 5),
      Offset(20, 5),
      Offset(20, 10),
      Offset(10, 10),
      Offset(10, 15),
      Offset(5, 15),
      Offset(5, 10),
      Offset(0, 10),
      Offset(0, 5),
      Offset(5, 5),
    ]);
    expect(cut.finished, isTrue);
    expect(cut.result!.pieces, hasLength(2));

    for (var flap = 0; flap < cut.flaps.length; flap++) {
      final face = cut.flaps[flap].face;
      _expectNear(cut.flapNormal(flap), model.outwardNormal(face));
      final toWorld = cut.flapToWorld(flap);
      final world = model.faces[face].worldRing();
      for (final corner in cut.flaps[flap].facePaper) {
        final at = toWorld.transformed3(Vector3(corner.dx, corner.dy, 0));
        expect(
          world.any((point) => (point - at).length < 1e-6),
          isTrue,
          reason: 'flap $flap corner $corner',
        );
      }
    }

    final finish = cut.finish(const WrapProgress());
    expect(finish.patches, hasLength(6));
    expect({for (final patch in finish.patches) patch.face}, hasLength(6));
    expect(finish.points, 600);
    expect(finish.progress.complete(model), isTrue);
    expect(finish.scraps, isEmpty);
    expect(finish.leftover, isNotNull);
    expect(finish.leftover!.holes, hasLength(1));
  });

  test('a strip cut along one line keeps its folds and sheds overhang', () {
    final level = _level();
    final model = _model(level);
    const rect = Rect.fromLTRB(-2, 5, 7, 25);
    var cut = _start(level, model, rect, 1);
    cut = cut.placedAt(const Offset(0, 5));
    cut = _cutThrough(cut, const [Offset(0, 25)]);
    expect(cut.finished, isTrue);
    expect(cut.folds, hasLength(3));
    final finish = cut.finish(const WrapProgress());
    expect(finish.points, 400);
    expect(finish.keptFolds, {0, 1, 2});
    expect(
      pointBounds(finish.kept!.vertices),
      const Rect.fromLTRB(0, 5, 7, 25),
    );
    expect(
      pointBounds(finish.leftover!.vertices),
      const Rect.fromLTRB(-2, 5, 0, 25),
    );
    expect(finish.scraps, hasLength(1));
    _expectRect(
      pointBounds(finish.scraps.single.vertices),
      const Rect.fromLTRB(5, 5, 7, 25),
    );
  });

  test('a peninsula keeps the fold between its two crossings', () {
    final level = _level();
    final model = _model(level);
    const rect = Rect.fromLTRB(-2, 5, 7, 25);
    var cut = _start(level, model, rect, 1);
    cut = cut.placedAt(const Offset(0, 5));
    cut = _cutThrough(cut, const [Offset(0, 15), Offset(5, 15), Offset(5, 5)]);
    expect(cut.finished, isTrue);
    final fold = cut.folds.first;
    expect(
      fold.crossings.map(fold.at),
      containsAll([const Offset(0, 10), const Offset(5, 10)]),
    );
    final finish = cut.finish(const WrapProgress());
    expect(finish.points, 200);
    expect(finish.keptFolds, {0});
    final kept = finish.relief[0].single;
    final ends = [fold.at(kept.$1), fold.at(kept.$2)]
      ..sort((a, b) => a.dx.compareTo(b.dx));
    expect(ends.first.dx, closeTo(0, 1e-9));
    expect(ends.last.dx, closeTo(5, 1e-9));
  });

  test('relieveFolds discards a fold the kept piece only touches', () {
    const fold = WrapFold(
      a: Offset(0, 10),
      b: Offset(5, 10),
      near: 0,
      far: 1,
      angle: 1,
      extent: [],
      crossings: [0, 1],
    );
    final sheet = _sheet(const Rect.fromLTRB(-2, 5, 7, 25));
    final below = _sheet(const Rect.fromLTRB(0, 5, 5, 10));
    final across = _sheet(const Rect.fromLTRB(0, 5, 5, 15));
    expect(relieveFolds([fold], sheet, below).single, isEmpty);
    expect(relieveFolds([fold], sheet, across).single, [(0.0, 1.0)]);
    expect(relieveFolds([fold], sheet, null).single, isEmpty);
  });

  test('a cut back onto a face it went round keeps the blade on the paper', () {
    final level = _level();
    final model = _model(level);
    var cut = _start(
      level,
      model,
      level.pattern!.sheet,
      0,
    ).placedAt(const Offset(10, 10));
    Vector3? resting;
    for (final corner in const [
      Offset(15, 10),
      Offset(15, 15),
      Offset(10, 15),
      Offset(5, 15),
      Offset(5, 10),
    ]) {
      final at = cut.blade!;
      final heading = (corner - at) / (corner - at).distance;
      final option = cut.options().singleWhere(
        (option) => (option.direction - heading).distance < 1e-6,
      );
      expect(option.end, corner);
      final stroke = cut.stroke(option);
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        final point = Offset.lerp(at, corner, t)!;
        final world = stroke.cut
            .flapToWorld(stroke.flapAt(t))
            .transformed3(Vector3(point.dx, point.dy, 0));
        if (resting != null) {
          expect(
            (world - resting).length,
            lessThan((corner - at).distance / 20 + 1e-6),
            reason: 'jump at $point toward $corner',
          );
        }
        resting = world;
      }
      cut = stroke.cut;
    }
    expect(cut.flaps[cut.bladeOn!].face, model.faceOfRing(0));

    // Paper past the tear at (5, 10) lies on another corner of this face.
    expect(
      cut.options().where(
        (option) => (option.direction - const Offset(0, -1)).distance < 1e-6,
      ),
      isEmpty,
    );
  });

  test('the blade travels along the paper edge between cuts', () {
    final level = _level();
    final model = _model(level);
    var cut = _start(
      level,
      model,
      level.pattern!.sheet,
      0,
    ).placedAt(const Offset(0, 5));
    cut = _cutThrough(cut, const [Offset(-2, 5), Offset(-2, 10)]);
    expect(cut.travels(0), isFalse);
    expect(cut.travels(1), isTrue);
    expect(cut.finished, isFalse);
    cut = _cutThrough(cut, const [Offset(0, 10), Offset(0, 5)]);
    expect(cut.finished, isTrue);
    final areas = [
      for (final piece in cut.result!.pieces)
        polygonSignedArea(piece.vertices).abs(),
    ]..sort();
    expect(areas.first, closeTo(10, 1e-6));

    // Back along the cut is travel too.
    final back = _cutThrough(
      _start(level, model, level.pattern!.sheet, 0).placedAt(Offset.zero),
      const [Offset(5, 0), Offset.zero],
    );
    expect(back.travels(1), isTrue);
  });

  test('undo walks back through the strokes', () {
    final level = _level();
    final model = _model(level);
    var cut = _start(level, model, level.pattern!.sheet, 0);
    cut = cut.placedAt(const Offset(5, 5));
    final placed = cut;
    cut = _cutThrough(cut, const [Offset(5, 0), Offset(10, 0)]);
    expect(cut.previous!.previous, same(placed));
    expect(cut.previous!.path, hasLength(2));
  });
}
