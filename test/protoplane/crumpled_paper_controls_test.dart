import 'package:flatmates/protoplane/crumpled_paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/storage.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('fold controls stage changes and fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final settings = ProtoplaneSettings();
      var updates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showProtoplaneDevTools(
                  context,
                  settings,
                  ProtoplaneStorage(),
                  () => updates++,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Style'));
      await tester.tap(find.text('Style'));
      await tester.pumpAndSettle();
      final stagedValues = <String, double>{};
      for (final label in [
        'Fold density',
        'Fold strength',
        'Fold scale',
        'Baked shadow intensity',
      ]) {
        final slider = find.byKey(ValueKey(label));
        await tester.scrollUntilVisible(
          slider,
          100,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await Scrollable.ensureVisible(tester.element(slider), alignment: .5);
        await tester.pumpAndSettle();
        await tester.drag(slider, const Offset(-30, 0));
        await tester.pumpAndSettle();
        stagedValues[label] = tester.widget<Slider>(slider).value;
        expect(stagedValues[label], isNot(1));
      }
      final distribution = find.text('Scattered patches');
      await tester.scrollUntilVisible(
        distribution,
        -80,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await Scrollable.ensureVisible(
        tester.element(distribution),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(distribution);
      await tester.pumpAndSettle();
      expect(settings.foldDistribution, FoldDistribution.pockets);
      expect(settings.foldDensity, .65);
      expect(settings.foldStrength, 1);
      expect(settings.foldScale, 1);
      expect(settings.bakedShadowIntensity, 1);
      expect(updates, 0);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(settings.foldDistribution, FoldDistribution.scattered);
      expect(settings.foldDensity, stagedValues['Fold density']);
      expect(settings.foldStrength, stagedValues['Fold strength']);
      expect(settings.foldScale, stagedValues['Fold scale']);
      expect(
        settings.bakedShadowIntensity,
        stagedValues['Baked shadow intensity'],
      );
      expect(updates, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    });
  }
}
