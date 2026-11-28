import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/construction_toolbar.dart';

void main() {
  testWidgets('material taps center immediately with reduced motion', (
    tester,
  ) async {
    var selected = ConstructionPaper.building;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (context, update) => ConstructionMaterialWheel(
                selected: selected,
                onSelected: (paper) => update(() => selected = paper),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-material-cloth')));
    await tester.pump();
    expect(selected, ConstructionPaper.cloth);
    final wheel = tester.widget<ListWheelScrollView>(
      find.byKey(const ValueKey('paper-material-wheel')),
    );
    expect((wheel.controller! as FixedExtentScrollController).selectedItem, 1);
    expect(tester.takeException(), isNull);
  });
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'horizontal material wheel selects the center live without repeating ($kind)',
      (tester) async {
        var selected = ConstructionPaper.building;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: StatefulBuilder(
                    builder: (context, update) => ConstructionMaterialWheel(
                      selected: selected,
                      onSelected: (p) => update(() => selected = p),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final wheel = find.byKey(const ValueKey('paper-material-wheel'));
        expect(
          tester.getSize(find.byType(ConstructionMaterialWheel)).height,
          64,
        );
        for (var i = 0; i < 6; i++) {
          final gesture = await tester.startGesture(
            tester.getCenter(wheel),
            kind: kind,
          );
          await gesture.moveBy(const Offset(-20, 0));
          await gesture.moveBy(const Offset(-44, 0));
          await tester.pump();
          expect(selected, ConstructionPaper.cloth);
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const ValueKey('paper-material-building')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('paper-material-cloth')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('paper-material-building')));
        await tester.pumpAndSettle();
        expect(selected, ConstructionPaper.building);
        final view = tester.widget<ListWheelScrollView>(wheel);
        expect(
          (view.controller! as FixedExtentScrollController).selectedItem,
          0,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
