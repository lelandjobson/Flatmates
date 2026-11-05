import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/storage.dart';

void main() {
  test(
    'gradient and independent grain settings round trip with old defaults',
    () {
      final settings = ProtoplaneSettings();
      expect(settings.backgroundGradient.begin, Alignment.bottomCenter);
      expect(settings.backgroundGradient.end, Alignment.topCenter);
      expect(settings.backgroundGradient.stops, [0, .5, 1]);
      settings.backgroundColors = [Colors.blue, Colors.purple, Colors.orange];
      settings.paperTextureStrength = .4;
      settings.paperTextureRepeat = 3;
      settings.paperTextureAppearance.contrast = 1.3;
      settings.landscapeAppearance.contrast = .5;
      final restored = ProtoplaneSettings()..load(settings.toJson());
      expect(
        restored.backgroundColors.map((c) => c.toARGB32()),
        settings.backgroundColors.map((c) => c.toARGB32()),
      );
      expect(restored.paperTextureStrength, .4);
      expect(restored.paperTextureRepeat, 3);
      expect(restored.paperTextureAppearance.contrast, 1.3);
      expect(restored.landscapeAppearance.contrast, .5);
      final legacy = settings.toJson()
        ..remove('backgroundColors')
        ..remove('paperTextureAppearance')
        ..remove('paperTextureStrength')
        ..remove('paperTextureRepeat');
      restored.load(legacy);
      expect(
        restored.backgroundColors,
        ProtoplaneSettings.defaultBackgroundColors,
      );
      expect(restored.paperTextureStrength, .6);
      expect(restored.paperTextureRepeat, 2);
      expect(
        () => restored.load({
          ...legacy,
          'backgroundColors': [0xff000000],
        }),
        throwsFormatException,
      );
      expect(
        () => restored.load({...legacy, 'paperTextureRepeat': 0}),
        throwsFormatException,
      );
    },
  );
  testWidgets('landscape texture controls stage changes until Update', (
    tester,
  ) async {
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
    final slider = find.byKey(const ValueKey('Texture strength'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(settings.paperTextureStrength, .6);
    expect(updates, 0);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    final applied = settings.paperTextureStrength;
    expect(applied, lessThan(.6));
    expect(updates, 1);
    await tester.drag(slider, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(settings.paperTextureStrength, applied);
    expect(updates, 1);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(settings.paperTextureStrength, applied);
    expect(tester.takeException(), isNull);
  });
  testWidgets('gradient stop picker updates only selected stop', (
    tester,
  ) async {
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
    final middle = settings.backgroundColors[1],
        top = settings.backgroundColors[2];
    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    expect(find.text('Background Bottom'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '214365');
    await tester.pump();
    expect(settings.backgroundColors, [const Color(0xff214365), middle, top]);
    expect(updates, greaterThan(0));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
