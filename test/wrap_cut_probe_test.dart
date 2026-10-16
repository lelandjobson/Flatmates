import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/placement.dart';
import 'package:flatmates/gridcraft/scissor.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

GridStep _level() => GridBlueprint.fromJson(
  jsonDecode(File('levels/boxes/grid-cube.json').readAsStringSync())
      as Map<String, dynamic>,
).steps.single;

FoldedModel _model(GridStep level) => foldedModelFromCraft(
  CraftV1.fromJson(
    jsonDecode(File('$kCubeCraftDirectory/craft.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  1,
  level,
)!;

/// How far [at] lies off the nearest face it is over.
double _offSurface(FoldedModel model, Vector3 at) {
  var best = double.infinity;
  for (var f = 0; f < model.faces.length; f++) {
    final local = Matrix4.inverted(model.faces[f].toWorld).transformed3(at);
    final point = Offset(local.x, local.y);
    final outline = model.faces[f].outline;
    if (!ownsPoint(outline, point) &&
        outline.every((p) => (p - point).distance > 1e-6)) {
      continue;
    }
    final ring = model.faces[f].worldRing();
    best = math.min(best, (at - ring[0]).dot(model.outwardNormal(f)).abs());
  }
  return best;
}

void main() {
  test('random cuts round the cube keep the blade on it, moving on', () {
    final level = _level();
    final model = _model(level);
    final sheet = level.pattern!.sheet;
    final piece = PapercutPiece(
      id: 'sheet',
      color: kPapercutYellow,
      vertices: [
        sheet.topLeft,
        sheet.topRight,
        sheet.bottomRight,
        sheet.bottomLeft,
      ],
    );
    var revisits = 0;
    for (var seed = 0; seed < 400; seed++) {
      final random = math.Random(seed);
      final ring = random.nextInt(model.faces.length);
      final offset = Offset(
        5.0 * random.nextInt(3) - 5,
        5.0 * random.nextInt(3) - 5,
      );
      var cut = WrapCut.start(
        model: model,
        piece: piece,
        placement: PiecePlacement(
          pieceId: piece.id,
          face: model.faceOfRing(ring)!,
          offset: offset,
        ),
        lines: level.pattern!.patternLines(sheet),
        autoFold: true,
      );
      final corners = cut.flaps.single.facePaper;
      final start = Offset.lerp(
        corners[random.nextInt(corners.length)],
        corners[random.nextInt(corners.length)],
        0.5,
      )!;
      final blade = Offset(
        (start.dx / 5).roundToDouble() * 5,
        (start.dy / 5).roundToDouble() * 5,
      );
      if (!ownsPoint(piece.vertices, blade)) continue;
      cut = cut.placedAt(blade);
      final log = ['seed $seed: ring $ring, offset $offset, blade $blade'];
      Vector3? resting;
      for (var step = 0; step < 14 && !cut.finished; step++) {
        final options = cut.options();
        if (options.isEmpty) break;
        final option = options[random.nextInt(options.length)];
        final from = cut.blade!;
        final to = option.end;
        final stroke = cut.stroke(option);
        log.add('$from to $to');
        const samples = 40;
        final reach = (to - from).distance / samples * 1.5 + 1e-6;
        for (var i = 0; i <= samples; i++) {
          final t = i / samples;
          final point = Offset.lerp(from, to, t)!;
          final at = stroke.cut
              .flapToWorld(stroke.flapAt(t))
              .transformed3(Vector3(point.dx, point.dy, 0));
          final where = '${log.join('\n')}\nat $point';
          if (resting != null) {
            expect((at - resting).length, lessThan(reach), reason: where);
          }
          expect(_offSurface(model, at), lessThan(1e-4), reason: where);
          resting = at;
        }
        cut = stroke.cut;
        final faces = [for (final flap in cut.flaps) flap.face];
        if (faces.toSet().length < faces.length) revisits++;
      }
    }
    expect(revisits, greaterThan(50));
  });

  test('random cuts and folds keep the blade on its paper and flaps on '
      'their faces', () {
    final level = _level();
    final model = _model(level);
    final sheet = level.pattern!.sheet;
    final piece = PapercutPiece(
      id: 'sheet',
      color: kPapercutYellow,
      vertices: [
        sheet.topLeft,
        sheet.topRight,
        sheet.bottomRight,
        sheet.bottomLeft,
      ],
    );
    var folded = 0;
    for (var seed = 0; seed < 300; seed++) {
      final random = math.Random(seed);
      final ring = random.nextInt(model.faces.length);
      var cut = WrapCut.start(
        model: model,
        piece: piece,
        placement: PiecePlacement(
          pieceId: piece.id,
          face: model.faceOfRing(ring)!,
        ),
        lines: level.pattern!.patternLines(sheet),
      );
      final corner = cut.flaps.single.facePaper[random.nextInt(4)];
      if (!ownsPoint(piece.vertices, corner)) continue;
      cut = cut.placedAt(corner);
      final log = ['seed $seed: ring $ring, blade $corner'];
      Vector3? resting;
      for (var step = 0; step < 16 && !cut.finished; step++) {
        final edges = cut.foldEdges();
        if (edges.isNotEmpty && random.nextDouble() < 0.4) {
          final edge = edges[random.nextInt(edges.length)];
          final next = cut.foldedAlong(edge);
          final where = '${log.join('\n')}\nfold ${edge.a}–${edge.b}';
          expect(next, isNotNull, reason: where);
          cut = next!;
          folded++;
          log.add('fold ${edge.a}–${edge.b}');
          final on = cut.bladeOn;
          if (on != null) {
            expect(cut.flaps[on].holds(cut.blade!), isTrue, reason: where);
          }
          for (var f = 0; f < cut.flaps.length; f++) {
            final face = cut.flaps[f].face;
            final toWorld = cut.flapToWorld(f);
            final world = model.faces[face].worldRing();
            for (final point in cut.flaps[f].facePaper) {
              final at = toWorld.transformed3(Vector3(point.dx, point.dy, 0));
              expect(
                world.any((corner) => (corner - at).length < 1e-6),
                isTrue,
                reason: '$where\nflap $f',
              );
            }
          }
          resting = null;
          continue;
        }
        final options = cut.options();
        if (options.isEmpty) break;
        final option = options[random.nextInt(options.length)];
        final from = cut.blade!;
        final to = option.end;
        final stroke = cut.stroke(option);
        expect(stroke.folds, isEmpty);
        log.add('$from to $to');
        const samples = 40;
        final reach = (to - from).distance / samples * 1.5 + 1e-6;
        for (var i = 0; i <= samples; i++) {
          final t = i / samples;
          final point = Offset.lerp(from, to, t)!;
          final at = stroke.cut
              .flapToWorld(stroke.flapAt(t))
              .transformed3(Vector3(point.dx, point.dy, 0));
          if (resting != null) {
            expect(
              (at - resting).length,
              lessThan(reach),
              reason: '${log.join('\n')}\nat $point',
            );
          }
          resting = at;
        }
        cut = stroke.cut;
      }
    }
    expect(folded, greaterThan(200));
  });
}
