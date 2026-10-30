@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/asmr/asmr_judge.dart';
import 'package:flatmates/asmr/asmr_lens.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_scissor_aim.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asmr_stress_scene.dart';

// Run with flutter test test/asmr/asmr_benchmark_test.dart -r expanded.
// Optional ASMR_BENCHMARK_OUTPUT writes JSON for before/after comparisons.
// Timings are host/debug CPU measurements, not device GPU frame-rate claims.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('benchmark dense cut scenes through the scissors camera', () async {
    final model = asmrCubeModel();
    final net = unfoldSelection(model, faceAdjacency(model), const [
      HologramPick(0),
      HologramPick(2, from: 0),
      HologramPick(4, from: 0),
    ]);
    final results = <Map<String, Object>>[];
    for (final (side, lines) in [(1, 256), (8, 16), (16, 8)]) {
      final build = Stopwatch()..start();
      final pieces = asmrStressScene(side: side, scoresPerPiece: lines);
      build.stop();
      final judge = AsmrJudge();
      final judgeCold = Stopwatch()..start();
      judge.update(net, pieces);
      judgeCold.stop();
      final tiles = AsmrPaperTiles();
      final aim = <int>[], paint = <int>[], steadyJudge = <int>[];
      ui.Picture? picture;
      for (var frame = 0; frame < 20; frame++) {
        final lens = AsmrCutLens(
          pivot: const Offset(400, 502),
          focal: AsmrCutLens.focalPixels(18, 600),
          elevation: AsmrCutLens.elevationFor(frame / 19),
        );
        const origin = Offset(400, 300), scale = 600 / 260;
        ui.Offset project(ui.Offset p) => lens.project(origin + p * scale);
        ui.Offset unproject(ui.Offset p) =>
            (lens.unproject(p) - origin) / scale;
        final clock = Stopwatch()..start();
        final targets = scissorAimPoints(
          pieces,
          const Offset(400, 502),
          project,
          unproject,
        );
        clock.stop();
        aim.add(clock.elapsedMicroseconds);
        expect(
          targets.every((t) => t.point.dx.isFinite && t.point.dy.isFinite),
          isTrue,
        );
        clock.reset();
        clock.start();
        expect(judge.update(net, pieces), isEmpty);
        clock.stop();
        steadyJudge.add(clock.elapsedMicroseconds);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final painter = AsmrDeskPainter(
          pieces: pieces,
          tiles: tiles,
          origin: origin,
          scale: scale,
          projection: lens.deskMatrix(origin: origin, scale: scale, angle: 0),
          blueprint: net,
          affixedNets: {0: net},
        );
        clock.reset();
        clock.start();
        painter.paint(canvas, const ui.Size(800, 600));
        clock.stop();
        paint.add(clock.elapsedMicroseconds);
        picture?.dispose();
        picture = recorder.endRecording();
      }
      // Also exercise rasterization: recording alone does not catch native
      // failures caused by a pitched scene with many blurred cut paths.
      final raster = Stopwatch()..start();
      final image = await picture!.toImage(800, 600);
      raster.stop();
      expect(image.width, 800);
      image.dispose();
      picture.dispose();
      tiles.dispose();
      final row = <String, Object>{
        'pieces': pieces.length,
        'lines': pieces.fold<int>(0, (n, p) => n + p.scores.length),
        'fixtureUs': build.elapsedMicroseconds,
        'judgeColdUs': judgeCold.elapsedMicroseconds,
        'aim': stats(aim),
        'paintRecord': stats(paint),
        'steadyJudge': stats(steadyJudge),
        'rasterUs': raster.elapsedMicroseconds,
      };
      results.add(row);
    }
    final report = {
      'mode': 'flutter_test debug CPU; 800x600; 18mm lens; pitch 0..1',
      'scenes': results,
    };
    // ignore: avoid_print
    print('ASMR_BENCHMARK ${jsonEncode(report)}');
    final output = Platform.environment['ASMR_BENCHMARK_OUTPUT'];
    if (output != null) {
      File(
        output,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Map<String, int> stats(List<int> values) {
  final sorted = List<int>.of(values)..sort();
  return {
    'medianUs': sorted[sorted.length ~/ 2],
    'p95Us':
        sorted[math.min(sorted.length - 1, (sorted.length * .95).ceil() - 1)],
    'maxUs': sorted.last,
  };
}
