import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/construction_toolbar.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'horizontal material wheel selects the center live and wraps ($kind)',
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
          expect(
            selected,
            i.isEven ? ConstructionPaper.cloth : ConstructionPaper.building,
          );
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
