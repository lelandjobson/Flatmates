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
    final saved = AsmrDevSettings(file: file)..curveSmoothing = 0.4;
    final loaded = AsmrDevSettings(file: file);
    await loaded.load();
    expect(loaded.curveSmoothing, closeTo(0.4, 1e-9));
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
}
