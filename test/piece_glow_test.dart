import 'dart:io';

import 'package:flatmates/gridcraft/piece_glow.dart';
import 'package:flatmates/gridcraft/piece_glow_io.dart';
import 'package:flatmates/gridcraft/scrap.dart';
import 'package:flatmates/ui/game/grid_dev_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const paper = Color(0xFFFFF3B0);
  const glow = Color(0xFF69F0AE);

  test(
    'a completed piece blends into the glow and the halo blooms then rests',
    () {
      expect(pieceGlowBlend(0), 0);
      expect(pieceGlowBlend(1), 1);
      final mid = pieceGlowFill(paper: paper, glow: glow, t: 0.5);
      expect(pieceGlowFill(paper: paper, glow: glow, t: 0), paper);
      expect(pieceGlowFill(paper: paper, glow: glow, t: 1), glow);
      expect(mid, isNot(paper));
      expect(mid, isNot(glow));
      expect(pieceGlowHalo(0), 0);
      expect(pieceGlowHalo(1), closeTo(1, 1e-9));
      expect(pieceGlowHalo(0.5), greaterThan(1));
      expect(
        pieceGlowLight(glow).computeLuminance(),
        greaterThan(glow.computeLuminance()),
      );
    },
  );

  test(
    'glow json round-trips and a missing file uses the standard glow',
    () async {
      final directory = await Directory.systemTemp.createTemp('piece-glow');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/piece_glow.json');
      final store = PieceGlowStore(file: file);

      final missing = await store.load();
      expect(missing.color, PieceGlowSettings.standard.color);
      expect(missing.amount, PieceGlowSettings.standard.amount);

      const edited = PieceGlowSettings(color: Color(0xFF00E676), amount: 0.2);
      await store.save(edited);
      final loaded = await store.load();
      expect(loaded.color, edited.color);
      expect(loaded.amount, 0.2);
      expect(file.readAsStringSync(), contains('#00E676'));

      expect(
        PieceGlowSettings.fromJson({'color': 'nope', 'amount': 4}).amount,
        1,
      );
      expect(
        PieceGlowSettings.fromJson({'color': 'nope'}).color,
        PieceGlowSettings.standard.color,
      );
    },
  );

  testWidgets('the dev panel edits glow amount and saves', (tester) async {
    var saved = 0;
    PieceGlowSettings? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GridDevPanel(
            glow: PieceGlowSettings.standard,
            onGlowChanged: (glow) => edited = glow,
            onSave: () async => saved++,
            showTapDebug: false,
            onShowTapDebugChanged: (_) {},
            tallyStyle: ScrapTallyStyle.shrink,
            onTallyStyleChanged: (_) {},
            cameraFollowsTool: false,
            onCameraFollowsToolChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Completed piece'), findsOneWidget);
    expect(find.text('Glow color'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('grid-glow-amount')),
    );
    slider.onChanged!(0.25);
    expect(edited?.amount, 0.25);

    await tester.tap(find.byKey(const Key('grid-glow-save')));
    await tester.pump();
    expect(saved, 1);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('camera follow starts off and can be turned on', (tester) async {
    var follows = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GridDevPanel(
            glow: PieceGlowSettings.standard,
            onGlowChanged: (_) {},
            onSave: () async {},
            showTapDebug: false,
            onShowTapDebugChanged: (_) {},
            tallyStyle: ScrapTallyStyle.shrink,
            onTallyStyleChanged: (_) {},
            cameraFollowsTool: follows,
            onCameraFollowsToolChanged: (value) => follows = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('grid-dev-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera').last);
    await tester.pumpAndSettle();

    final box = tester.widget<Checkbox>(
      find.byKey(const Key('grid-camera-follow')),
    );
    expect(box.value, isFalse);
    await tester.tap(find.text('Follow tool'));
    expect(follows, isTrue);
  });
}
