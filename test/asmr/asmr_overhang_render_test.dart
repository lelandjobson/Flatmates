import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_flight.dart';
import 'package:flatmates/asmr/asmr_model_paper.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  final model = asmrCubeModel();
  final adjacency = faceAdjacency(model);
  final b = adjacency[2].whereType<FaceNeighbor>().first.face;
  final c = adjacency[b]
      .whereType<FaceNeighbor>()
      .firstWhere((n) => n.face != 2)
      .face;
  final net = unfoldSelection(model, adjacency, [
    const HologramPick(2),
    HologramPick(b, from: 2),
    HologramPick(c, from: b),
  ]);
  const size = Size(400, 400);
  final camera = PapercutCamera()..setFocal(35);
  camera.beginFly(camera.frameSphere(model.center, model.radius * 2.2, size));
  camera.setFly(1);
  camera.orbitTo(Vector3(1, -1, 1));
  final oversized = AsmrPiece.sheet(
    id: 'oversized',
    paper: kAsmrCraftPaper,
    at: Offset.zero,
    size: const Size(240, 240),
  ).copyWith(binding: net);
  final fitted = AsmrPiece(
    id: 'fitted',
    paper: kAsmrCraftPaper,
    ring: net.outlines.single,
    binding: net,
  );

  test(
    'paper across two folds submits only face slices to the 3D renderer',
    () {
      final tiles = AsmrPaperTiles();
      addTearDown(tiles.dispose);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      for (final piece in [oversized, fitted]) {
        var surfaces = 0;
        addBoundPaper(
          canvas: canvas,
          size: size,
          camera: camera,
          model: model,
          pieces: [piece],
          tiles: tiles,
          add: (_, paint) {
            surfaces++;
            paint();
          },
        );
        expect(
          surfaces,
          3,
          reason: 'No extra flat overhang surfaces at either fold',
        );
      }
      recorder.endRecording().dispose();
      expect(
        oversized.area,
        240 * 240,
        reason: 'The editable paper is unchanged',
      );
    },
  );

  test(
    'sending oversized paper has the same silhouette as fitted paper',
    () async {
      final tiles = AsmrPaperTiles();
      addTearDown(tiles.dispose);
      Future<Rect> silhouette(AsmrPiece piece, double progress) async {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        final flight = AsmrFlight(
          piece: piece,
          from: deskPaperToScreen(piece, const Offset(200, 200), 1),
        )..t = progress;
        AsmrFlightPainter(
          flights: [flight],
          camera: camera,
          model: model,
          modelSize: size,
          tiles: tiles,
        ).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final bytes = (await image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!;
        var left = 400, top = 400, right = -1, bottom = -1;
        for (var y = 0; y < 400; y++) {
          for (var x = 0; x < 400; x++) {
            if (bytes.getUint8((y * 400 + x) * 4 + 3) < 32) continue;
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
        image.dispose();
        picture.dispose();
        expect(right, greaterThan(left));
        return Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right.toDouble(),
          bottom.toDouble(),
        );
      }

      for (final progress in [0.0, 0.5, 1.0]) {
        final actual = await silhouette(oversized, progress);
        final expected = await silhouette(fitted, progress);
        expect(actual.left, closeTo(expected.left, 1));
        expect(actual.top, closeTo(expected.top, 1));
        expect(actual.right, closeTo(expected.right, 1));
        expect(actual.bottom, closeTo(expected.bottom, 1));
      }
    },
  );
}
