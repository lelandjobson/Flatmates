import 'dart:io';

import 'package:flatmates/asmr/asmr_dev.dart';
import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('curve smoothing is saved and read back', () async {
    final file = File(
      '${Directory.systemTemp.path}/asmr_dev_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final saved = AsmrDevSettings(file: file)
      ..curveSmoothing = 0.4
      ..shadowThrow = 16
      ..shadowSpread = 3
      ..shadowColor = const Color(0xFF3A2418)
      ..shadowOpacity = 0.7
      ..darkOverlay = 0.35;
    final loaded = AsmrDevSettings(file: file);
    await loaded.load();
    expect(loaded.curveSmoothing, closeTo(0.4, 1e-9));
    expect(loaded.shadowThrow, closeTo(16, 1e-9));
    expect(loaded.shadowSpread, closeTo(3, 1e-9));
    expect(loaded.shadowColor.toARGB32(), const Color(0xFF3A2418).toARGB32());
    expect(loaded.shadowOpacity, closeTo(0.7, 1e-9));
    expect(loaded.darkOverlay, closeTo(0.35, 1e-9));
    saved.dispose();
    loaded.dispose();
  });

  testWidgets('the devtools panel sets curve smoothing', (tester) async {
    final file = File(
      '${Directory.systemTemp.path}/asmr_dev_panel_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final settings = AsmrDevSettings(file: file);
    addTearDown(settings.dispose);
    await tester.pumpWidget(MaterialApp(home: AsmrView(settings: settings)));
    await tester.pump();
    expect(find.byKey(const Key('asmr-dev-panel')), findsNothing);
    await tester.tap(find.text('devtools'));
    await tester.pump();
    expect(find.byKey(const Key('asmr-dev-panel')), findsOneWidget);
    tester
        .widget<Slider>(find.byKey(const Key('asmr-curve-smoothing')))
        .onChanged!(0.55);
    await tester.pump();
    expect(settings.curveSmoothing, closeTo(0.55, 1e-9));
    final again = AsmrDevSettings(file: file);
    addTearDown(again.dispose);
    await tester.runAsync(again.load);
    expect(again.curveSmoothing, closeTo(0.55, 1e-9));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the shadow tab sets throw, spread, and color', (tester) async {
    final file = File(
      '${Directory.systemTemp.path}/asmr_dev_shadow_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final settings = AsmrDevSettings(file: file);
    addTearDown(settings.dispose);
    await tester.pumpWidget(MaterialApp(home: AsmrView(settings: settings)));
    await tester.pump();
    await tester.tap(find.text('devtools'));
    await tester.pump();
    expect(find.byKey(const Key('asmr-shadow-throw')), findsNothing);
    await tester.tap(find.byKey(const Key('asmr-dev-tab-shadow')));
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const Key('asmr-shadow-throw')))
        .onChanged!(22);
    tester
        .widget<Slider>(find.byKey(const Key('asmr-shadow-spread')))
        .onChanged!(4);
    tester
        .widget<Slider>(find.byKey(const Key('asmr-dark-overlay')))
        .onChanged!(0.4);
    await tester.tap(find.byKey(const Key('asmr-shadow-color-2')));
    await tester.pump();
    expect(settings.shadowThrow, closeTo(22, 1e-9));
    expect(settings.shadowSpread, closeTo(4, 1e-9));
    expect(settings.darkOverlay, closeTo(0.4, 1e-9));
    expect(settings.shadowColor.toARGB32(), kAsmrShadowColors[2].toARGB32());
    final again = AsmrDevSettings(file: file);
    addTearDown(again.dispose);
    await tester.runAsync(again.load);
    expect(again.shadowThrow, closeTo(22, 1e-9));
    expect(again.shadowSpread, closeTo(4, 1e-9));
    expect(again.darkOverlay, closeTo(0.4, 1e-9));
    expect(again.shadowColor.toARGB32(), kAsmrShadowColors[2].toARGB32());
    await tester.pumpWidget(const SizedBox());
  });
}
