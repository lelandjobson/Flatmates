import 'dart:io';

import 'package:flatmates/asmr/asmr_dev.dart';
import 'package:flatmates/asmr/asmr_theme.dart';
import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a theme keeps a paint’s shade, then fades and recolors it', () async {
    final file = File(
      '${Directory.systemTemp.path}/asmr_theme_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final theme = AsmrTheme(file: file);
    addTearDown(theme.dispose);
    final material = theme.paperMaterial;
    theme.setOpacity(AsmrThemeSlot.paper, 0.5);
    expect(theme.paperMaterial, same(material));
    theme.setOpacity(AsmrThemeSlot.paper, 1);
    const blade = Color(0xE6FFFFFF);
    final plain = theme.ink(AsmrThemeSlot.scissors, blade);
    expect(plain.toARGB32(), blade.toARGB32());

    theme.setOpacity(AsmrThemeSlot.scissors, 0.5);
    final faded = theme.ink(AsmrThemeSlot.scissors, blade);
    expect(faded.r, closeTo(blade.r, 1e-6));
    expect(faded.a, closeTo(blade.a * 0.5, 1e-6));

    theme.setColor(AsmrThemeSlot.scissors, const Color(0xFF2266AA));
    final dyed = theme.ink(AsmrThemeSlot.scissors, blade);
    expect(dyed.r, closeTo(0x22 / 255, 1e-6));
    expect(dyed.g, closeTo(0x66 / 255, 1e-6));
    expect(dyed.b, closeTo(0xAA / 255, 1e-6));
    expect(dyed.a, closeTo(blade.a * 0.5, 1e-6));

    theme.save();
    final loaded = AsmrTheme(file: file);
    addTearDown(loaded.dispose);
    await loaded.load();
    expect(
      loaded.colorOf(AsmrThemeSlot.scissors).toARGB32(),
      const Color(0xFF2266AA).toARGB32(),
    );
    expect(loaded.opacityOf(AsmrThemeSlot.scissors), closeTo(0.5, 1e-9));
    expect(loaded.opacityOf(AsmrThemeSlot.desk), closeTo(1, 1e-9));
  });

  testWidgets('the theme tab saves a color the view reads back', (
    tester,
  ) async {
    final settingsFile = File(
      '${Directory.systemTemp.path}/asmr_theme_panel_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final themeFile = File(
      '${Directory.systemTemp.path}/asmr_theme_panel_colors_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      for (final file in [settingsFile, themeFile]) {
        if (file.existsSync()) file.deleteSync();
      }
    });
    final settings = AsmrDevSettings(file: settingsFile);
    final theme = AsmrTheme(file: themeFile);
    addTearDown(settings.dispose);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AsmrView(settings: settings, theme: theme),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('devtools'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('asmr-dev-tab-theme')));
    await tester.pump();
    tester.widget<Slider>(find.byKey(const Key('asmr-theme-red'))).onChanged!(
      1,
    );
    await tester.pump();
    expect(theme.colorOf(AsmrThemeSlot.desk).r, closeTo(1, 1e-6));
    expect(find.text('Save theme'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asmr-theme-save')));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);

    final loaded = AsmrTheme(file: themeFile);
    addTearDown(loaded.dispose);
    await tester.runAsync(loaded.load);
    expect(loaded.colorOf(AsmrThemeSlot.desk).r, closeTo(1, 1e-6));
    expect(
      loaded.colorOf(AsmrThemeSlot.desk).g,
      closeTo(theme.colorOf(AsmrThemeSlot.desk).g, 1e-6),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
