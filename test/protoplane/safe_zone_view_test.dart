import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'construction_fixture.dart';

void main() {
  for (final size in [
    const Size(900, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'safe zone toggle draws measured rectangle without intercepting input at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final c = constructionWorld();
        addTearDown(() {
          c.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: ProtoplaneConceptView(animateFog: false, controller: c),
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.enter('ground-starter-paperWhite-0-0');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('craft-safe-zone')), findsNothing);
        await tester.tap(find.text('devtools'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Camera'));
        await tester.tap(find.text('Camera'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Safe zone'),
          100,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.tap(find.text('Safe zone'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const ValueKey('craft-safe-zone')),
        );
        final dock = tester.getRect(
          find.byKey(ValueKey('focus-tools-${c.activePlaneId}')),
        );
        expect(rect.bottom, lessThanOrEqualTo(dock.top));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          await File(
            '/tmp/flatmates-safe-zone-${size.width.toInt()}.png',
          ).writeAsBytes(
            (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List(),
          );
          image.dispose();
        });
        expect(find.byTooltip('3D'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
