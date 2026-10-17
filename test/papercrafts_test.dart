import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/papercraft_net.dart';
import 'package:flatmates/gridcraft/papercrafts.dart';
import 'package:flatmates/gridcraft/placement.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import '../tool/generate_papercrafts.dart' show kGenerator;

GridStep _level(PapercraftDesign design) => GridBlueprint.fromJson(
  jsonDecode(File(papercraftLevelPath(design)).readAsStringSync())
      as Map<String, dynamic>,
).steps.single;

FoldedModel _model(PapercraftDesign design, GridStep level) =>
    foldedModelFromCraft(
      CraftV1.fromJson(
        jsonDecode(
              File(
                '${papercraftDirectory(design)}/craft.json',
              ).readAsStringSync(),
            )
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

/// Strokes from the blade to each of [corners] in turn along the pattern.
WrapCut _cutThrough(WrapCut cut, List<Offset> corners) {
  for (final corner in corners) {
    for (var guard = 0; guard < 40 && !cut.finished; guard++) {
      final at = cut.blade!;
      if ((at - corner).distance < 1e-6) break;
      final heading = corner - at;
      final options = cut.options().where((option) {
        final d = option.direction;
        return (d.dx * heading.dy - d.dy * heading.dx).abs() < 1e-6 &&
            d.dx * heading.dx + d.dy * heading.dy > 0;
      });
      expect(options, isNotEmpty, reason: 'no cut from $at toward $corner');
      cut = cut.stroke(options.first).cut;
    }
    expect((cut.blade! - corner).distance, lessThan(1e-6));
  }
  return cut;
}

/// True when [at] lies on [face], edges included.
bool _onFace(FoldedModel model, int face, Vector3 at) {
  final local = Matrix4.inverted(model.faces[face].toWorld).transformed3(at);
  if (local.z.abs() > 1e-6) return false;
  final outline = model.faces[face].outline;
  var sign = 0;
  for (var i = 0; i < outline.length; i++) {
    final a = outline[i];
    final edge = outline[(i + 1) % outline.length] - a;
    final cross = edge.dx * (local.y - a.dy) - edge.dy * (local.x - a.dx);
    if (cross.abs() <= 1e-6 * edge.distance) continue;
    final side = cross.sign.toInt();
    if (sign != 0 && side != sign) return false;
    sign = side;
  }
  return true;
}

void main() {
  for (final design in papercraftDesigns()) {
    group(design.name, () {
      final net = unfoldPapercraft(design);

      test('its craft and level are what the generator writes', () {
        final directory = papercraftDirectory(design);
        expect(
          File('$directory/craft.json').readAsStringSync(),
          net.craftJsonText(),
        );
        expect(
          File('$directory/folded.obj').readAsStringSync(),
          net.craftObj(kGenerator),
        );
        expect(
          File(papercraftLevelPath(design)).readAsStringSync(),
          net.levelJsonText(),
        );
      });

      test('the model folds every face to its place in the design', () {
        final level = _level(design);
        final model = _model(design, level);
        expect(model.faces, hasLength(net.pieces.length));
        final designMin = Vector3.all(double.infinity);
        for (final piece in net.pieces) {
          for (final corner in piece.corners) {
            Vector3.min(designMin, corner, designMin);
          }
        }
        final shift = model.bounds.min - designMin;
        for (var ring = 0; ring < net.pieces.length; ring++) {
          final world = model.faces[model.faceOfRing(ring)!].worldRing();
          for (final corner in net.pieces[ring].corners) {
            expect(
              world.any((p) => (p - corner - shift).length < 1e-6),
              isTrue,
              reason: '${net.pieces[ring].name} at $corner',
            );
          }
        }
      });

      test('each island cut out along its outline folds on at the finish', () {
        final level = _level(design);
        final model = _model(design, level);
        final sheet = level.pattern!.sheet;
        var progress = const WrapProgress();
        for (var island = 0; island < net.islandCount; island++) {
          final rings = [
            for (var i = 0; i < net.pieces.length; i++)
              if (net.pieces[i].island == island) i,
          ];
          final root = rings.firstWhere((i) => net.pieces[i].parent == null);
          final outline = net.islandOutline(island);
          final piece = _sheet(sheet);
          var cut = WrapCut.start(
            model: model,
            piece: piece,
            placement: PiecePlacement(
              pieceId: piece.id,
              face: model.faceOfRing(root)!,
            ),
            lines: level.pattern!.patternLines(sheet),
          ).placedAt(outline.first);
          cut = _cutThrough(cut, [...outline.skip(1), outline.first]);
          expect(cut.finished, isTrue, reason: 'island $island');

          final finish = cut.finish(progress);
          final faces = {for (final i in rings) model.faceOfRing(i)!};
          expect(
            {for (final flap in finish.cut.flaps) flap.face},
            faces,
            reason: 'island $island',
          );
          for (var flap = 0; flap < finish.cut.flaps.length; flap++) {
            final face = finish.cut.flaps[flap].face;
            expect(
              (finish.cut.flapNormal(flap) - model.outwardNormal(face)).length,
              lessThan(1e-6),
              reason:
                  'island $island, ${net.pieces[model.faces[face].ring].name}',
            );
          }
          progress = finish.progress;
          for (final face in faces) {
            expect(
              progress.fraction(model, face),
              greaterThan(1 - 1e-3),
              reason: net.pieces[model.faces[face].ring].name,
            );
          }
        }
        expect(progress.complete(model), isTrue);
      });

      test('random cuts and folds keep flaps on their faces', () {
        final level = _level(design);
        final model = _model(design, level);
        final sheet = level.pattern!.sheet;
        final piece = _sheet(sheet);
        var folded = 0;
        for (var seed = 0; seed < 80; seed++) {
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
          final corners = cut.flaps.single.facePaper;
          cut = cut.placedAt(corners[random.nextInt(corners.length)]);
          final log = ['seed $seed: ring $ring, blade ${cut.blade}'];
          for (var step = 0; step < 16 && !cut.finished; step++) {
            final edges = cut.foldEdges();
            if (edges.isNotEmpty && random.nextDouble() < 0.4) {
              final edge = edges[random.nextInt(edges.length)];
              final where = '${log.join('\n')}\nfold ${edge.a}–${edge.b}';
              final next = cut.foldedAlong(edge);
              expect(next, isNotNull, reason: where);
              cut = next!;
              folded++;
              log.add('fold ${edge.a}–${edge.b}');
              for (var f = 0; f < cut.flaps.length; f++) {
                final toWorld = cut.flapToWorld(f);
                for (final point in cut.flaps[f].facePaper) {
                  final at = toWorld.transformed3(
                    Vector3(point.dx, point.dy, 0),
                  );
                  expect(
                    _onFace(model, cut.flaps[f].face, at),
                    isTrue,
                    reason: '$where\nflap $f at $point',
                  );
                }
              }
              continue;
            }
            final options = cut.options();
            if (options.isEmpty) break;
            final option = options[random.nextInt(options.length)];
            log.add('${cut.blade} to ${option.end}');
            cut = cut.stroke(option).cut;
          }
          if (cut.finished) cut.finish(const WrapProgress());
        }
        expect(folded, greaterThan(20));
      });
    });
  }
}
