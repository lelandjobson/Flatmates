import 'dart:ui' as ui;

import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edge spectra vary continuously and follow the paper material', () {
    for (final paper in kAsmrCraftPalette) {
      expect(paper.cutEdgeColor(0), isNot(paper.cutEdgeColor(1)));
      final left = paper.cutEdgeColor(0.4999);
      final right = paper.cutEdgeColor(0.5001);
      expect((left.r - right.r).abs(), lessThan(0.002));
      expect((left.g - right.g).abs(), lessThan(0.002));
      expect((left.b - right.b).abs(), lessThan(0.002));
    }
    expect(
      kAsmrCraftPalette[0].cutEdgeColor(0.3),
      isNot(kAsmrCraftPalette[2].cutEdgeColor(0.3)),
    );
  });

  test(
    'active stroke and straight preview have white cores and halos',
    () async {
      final tiles = AsmrPaperTiles();
      addTearDown(tiles.dispose);
      for (final preview in [false, true]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xFF000000), BlendMode.src);
        AsmrDeskPainter(
          pieces: const [],
          tiles: tiles,
          origin: Offset.zero,
          scale: 1,
          paintBackground: false,
          stroke: preview ? null : const [Offset(20, 50), Offset(80, 50)],
          reach: preview
              ? const [
                  [Offset(20, 50), Offset(80, 50)],
                ]
              : const [],
        ).paint(canvas, const Size(100, 100));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final y in [50, 54]) {
          final at = (y * 100 + 50) * 4;
          final r = bytes.getUint8(at);
          expect(r, greaterThan(0));
          expect(bytes.getUint8(at + 1), r);
          expect(bytes.getUint8(at + 2), r);
        }
        image.dispose();
        picture.dispose();
      }
    },
  );
}
