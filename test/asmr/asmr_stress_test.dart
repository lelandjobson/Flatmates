import 'dart:io';
import 'dart:ui' show PointerDeviceKind, PictureRecorder, Canvas;

import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/asmr/asmr_dev.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/asmr/asmr_session.dart';
import 'package:flatmates/asmr/asmr_theme.dart';
import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/asmr_stress_scene.dart';

void main() {
  test('degenerate folded edges cannot crash a dense paper painter', () {
    final model = asmrCubeModel();
    final base = unfoldSelection(model, faceAdjacency(model), const [
      HologramPick(0),
    ]);
    final net = AsmrNet.fromParts(base.faces, [
      ...base.edges,
      const AsmrNetEdge(
        face: 0,
        edge: 99,
        a: Offset.zero,
        b: Offset.zero,
        fold: true,
      ),
    ]);
    final tiles = AsmrPaperTiles();
    final recorder = PictureRecorder();
    final painter = AsmrDeskPainter(
      pieces: [
        AsmrPiece.sheet(
          id: 'fold',
          paper: kAsmrCraftPaper,
          at: Offset.zero,
        ).affixedTo(0),
      ],
      tiles: tiles,
      origin: const Offset(400, 300),
      scale: 2,
      blueprint: net,
      affixedNets: {0: net},
    );
    expect(
      () => painter.paint(Canvas(recorder), const Size(800, 600)),
      returnsNormally,
    );
    recorder.endRecording().dispose();
    tiles.dispose();
  });

  testWidgets(
    'Exacto to Scissors remains safe with 144 pieces and 2304 cut lines',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('asmr_stress_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pieces = asmrStressScene(side: 12, scoresPerPiece: 16);
      expect(pieces, hasLength(144));
      const picks = [
        HologramPick(0),
        HologramPick(2, from: 0),
        HologramPick(4, from: 0),
      ];
      final file = File('${dir.path}/session.json');
      AsmrSession(
        picks: picks,
        pieces: pieces,
        bindings: [for (final _ in pieces) const []],
        groups: const {0: picks},
        pieceGroups: [for (final _ in pieces) null],
        deskOrigin: const Offset(400, 300),
        deskScale: 600 / 260,
        in3d: false,
        azimuth: 0,
        elevation: 0.6,
        roll: 0,
        lookAt: Offset.zero,
        lookAtZ: 0,
        halfHeight: 8,
        focal: 50,
      ).write(file);
      final settings = AsmrDevSettings(
        file: File('${dir.path}/dev.json'),
        perspectiveness: 1,
        lensMm: 18,
      );
      final theme = AsmrTheme(file: File('${dir.path}/theme.json'));
      addTearDown(settings.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AsmrView(settings: settings, theme: theme, sessionFile: file),
        ),
      );
      await frames(tester, 400);
      await tester.tap(find.byKey(const Key('asmr-load')));
      await frames(tester, 600);
      AsmrDeskPainter desk() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<AsmrDeskPainter>()
          .single;
      expect(desk().pieces, hasLength(144));
      expect(desk().pieces.fold<int>(0, (n, p) => n + p.scores.length), 2304);
      // Continue through the real Exacto input path before switching tools.
      // This catches stale pointer state and geometry updates, not just load.
      for (final y in [140.0, 265.0, 390.0]) {
        final g = await tester.startGesture(
          Offset(235, y),
          kind: PointerDeviceKind.mouse,
        );
        for (var step = 1; step <= 24; step++) {
          await g.moveTo(Offset(235 + 330 * step / 24, y));
          await tester.pump(const Duration(milliseconds: 8));
          expect(tester.takeException(), isNull);
        }
        await g.up();
        await frames(tester, 50);
      }
      final pieceCount = desk().pieces.length;
      final scoreCount = desk().pieces.fold<int>(
        0,
        (n, p) => n + p.scores.length,
      );
      expect(pieceCount, greaterThan(144));
      expect(scoreCount, greaterThan(1000));
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip(i.isEven ? 'Scissors' : 'Exacto'));
        await frames(tester, 400);
        expect(tester.takeException(), isNull, reason: 'tool transition $i');
        expect(desk().pieces, hasLength(pieceCount));
        expect(
          desk().pieces.fold<int>(0, (n, p) => n + p.scores.length),
          scoreCount,
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
