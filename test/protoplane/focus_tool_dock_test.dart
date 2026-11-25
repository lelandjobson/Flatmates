import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/drawing_graph.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/focus_tool_dock.dart';
import 'package:flatmates/protoplane/sticker_program.dart';

void main() {
  testWidgets('reduced motion lifts the original sticker immediately', (
    tester,
  ) async {
    StickerKind? primed;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => FocusToolDock(
                card: FocusToolCard.stickerbook,
                implement: DrawingImplement.pencil,
                primed: primed,
                onPrime: (value) => update(() => primed = value),
                onCard: (_) {},
                onImplement: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sticker-card-0')));
    await tester.pump();
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('sticker-lift-0')))
          .transform
          .storage[13],
      -8,
    );
    expect(find.byKey(const ValueKey('sticker-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('primed-sticker')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'vertical implement cycle, horizontal cards, transient names, tilted scrolling and priming',
    (tester) async {
      var card = FocusToolCard.drawing, implement = DrawingImplement.pencil;
      StickerKind? primed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatefulBuilder(
                builder: (context, update) => FocusToolDock(
                  card: card,
                  implement: implement,
                  onCard: (v) => update(() => card = v),
                  onImplement: (v) => update(() => implement = v),
                  primed: primed,
                  onPrime: (v) => update(() => primed = v),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final wheelBounds = tester.getRect(
        find.byKey(const ValueKey('implement-wheel')),
      );
      final visibleImplements = <DrawingImplement>{};
      for (final element
          in find
              .byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is ImplementPicture,
              )
              .evaluate()) {
        final finder = find.byElementPredicate((e) => e == element);
        if (wheelBounds.contains(tester.getCenter(finder))) {
          visibleImplements.add(
            ((element.widget as CustomPaint).painter as ImplementPicture)
                .implement,
          );
        }
      }
      expect(visibleImplements, DrawingImplement.values.toSet());
      for (final expected in [
        DrawingImplement.pen,
        DrawingImplement.marker,
        DrawingImplement.crookedPencil,
        DrawingImplement.eraser,
        DrawingImplement.pencil,
      ]) {
        final drag = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('implement-wheel'))),
          kind: expected.index.isEven
              ? PointerDeviceKind.mouse
              : PointerDeviceKind.touch,
        );
        await drag.moveBy(const Offset(0, -20));
        await drag.moveBy(const Offset(0, -40));
        await tester.pump();
        expect(
          implement,
          expected,
        ); // Selection follows the drag before release.
        await drag.up();
        await tester.pumpAndSettle();
        expect(implement, expected);
      }
      await tester.pump(const Duration(seconds: 2));
      final fade = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text('Pencil'),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(fade.opacity, 0);
      await tester.drag(
        find.byKey(const ValueKey('drawing-tool-card')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(card, FocusToolCard.stickerbook);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byKey(const ValueKey('tilted-stickerbook')), findsOneWidget);
      final origin = tester.getCenter(
        find.byKey(const ValueKey('sticker-card-0')),
      );
      await tester.tap(find.byKey(const ValueKey('sticker-card-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final partial = tester
          .widget<Transform>(find.byKey(const ValueKey('sticker-lift-0')))
          .transform
          .storage[13];
      expect(partial, inExclusiveRange(-8, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('primed-sticker')), findsNothing);
      expect(
        (tester.getCenter(find.byKey(const ValueKey('sticker-card-0'))) -
                origin)
            .distance,
        lessThan(20),
      );
      expect(primed, StickerKind.house);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('sticker-lift-0')))
            .transform
            .storage[13],
        lessThan(0),
      );
      expect(find.text('House'), findsOneWidget);
      // Every card and the blank book area cancel a primed choice.
      await tester.tap(find.byKey(const ValueKey('sticker-card-1')));
      await tester.pumpAndSettle();
      expect(primed, isNull);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('sticker-lift-0')))
            .transform
            .storage[13],
        0,
      );
      await tester.drag(
        find.byKey(const ValueKey('stickerbook-scroll')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(primed, isNull);
      final scroll = tester
          .widget<GridView>(find.byKey(const ValueKey('stickerbook-scroll')))
          .controller!;
      expect(scroll.offset, greaterThan(100));
      expect(find.byKey(const ValueKey('sticker-card-12')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sticker-card-12')));
      await tester.pumpAndSettle();
      expect(primed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('tool choices migrate and persist independently of world history', () {
    final settings = ProtoplaneSettings();
    final old = settings.toJson()
      ..remove('focusToolCard')
      ..remove('drawingImplement');
    settings.load(old);
    expect(settings.focusToolCard, FocusToolCard.drawing);
    expect(settings.drawingImplement, DrawingImplement.pencil);
    settings.focusToolCard = FocusToolCard.stickerbook;
    settings.drawingImplement = DrawingImplement.crookedPencil;
    final saved = ProtoplaneSettings()..load(settings.toJson());
    expect(saved.focusToolCard, FocusToolCard.stickerbook);
    expect(saved.drawingImplement, DrawingImplement.crookedPencil);
  });
}
