import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/storage.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1100, 800),
  ]) {
    testWidgets(
      'readable devtools retains accessible tabs and footer at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final settings = ProtoplaneSettings();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showProtoplaneDevTools(
                    context,
                    settings,
                    ProtoplaneStorage(),
                    () {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const ValueKey('protoplane-devtools-panel')),
        );
        expect(rect.width, lessThanOrEqualTo(420));
        expect(rect.height, lessThanOrEqualTo(460));
        expect(rect.left, greaterThanOrEqualTo(20));
        expect(rect.right, lessThanOrEqualTo(size.width - 20));
        for (final tab in ['Lighting', 'Camera', 'Style', 'Crafting']) {
          await tester.ensureVisible(find.text(tab));
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(rect.contains(tester.getCenter(find.text('Save'))), isTrue);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('protoplane-devtools-panel')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/devtools-readable-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('protoplane-devtools-panel')),
          findsNothing,
        );
      },
    );
  }
}
