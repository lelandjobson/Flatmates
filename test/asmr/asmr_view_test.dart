import 'dart:ui';

import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/asmr/asmr_straight_edge.dart';
import 'package:flatmates/asmr/hologram_painter.dart';
import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cut a face out over the hologram and see it on the cube', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> frames(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(300);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(find.byTooltip('Orbit'), findsOneWidget);

    await tester.tap(find.byTooltip('Select'));
    await frames(50);
    final pick = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(100);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(700);

    await tester.tap(find.byTooltip('Mint dots'));
    await frames(100);

    const center = Offset(400, 300);
    const scale = 600 / 260;
    Offset screen(double x, double y) => center + Offset(x, y) * scale;
    final gesture = await tester.startGesture(
      screen(-35, -35),
      kind: PointerDeviceKind.mouse,
    );
    final corners = [
      screen(35, -35),
      screen(35, 35),
      screen(-35, 35),
      screen(-35, -33),
    ];
    var at = screen(-35, -35);
    for (final corner in corners) {
      final delta = corner - at;
      const steps = 30;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(at + delta * (i / steps));
        await tester.pump(const Duration(milliseconds: 8));
      }
      at = corner;
    }
    await gesture.up();
    await frames(100);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(700);
    expect(tester.takeException(), isNull);

    final orbit = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 20; i++) {
      await orbit.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await orbit.up();
    await frames(300);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'paper on a blueprint edge stays after the faces are deselected',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: AsmrView()));
      await frames(tester, 300);
      await tester.tap(find.byTooltip('Select'));
      await frames(tester, 50);
      final pick = await tester.startGesture(
        const Offset(400, 300),
        kind: PointerDeviceKind.mouse,
      );
      await pick.up();
      await frames(tester, 100);

      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
      await tester.tap(find.byTooltip('Mint dots'));
      await frames(tester, 100);
      expect(find.text('Faces filled  1 / 6'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
      final clear = await tester.startGesture(
        const Offset(40, 220),
        kind: PointerDeviceKind.mouse,
      );
      await clear.up();
      await frames(tester, 100);
      expect(find.text('Faces filled  1 / 6'), findsOneWidget);
      final hologram = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<HologramPainter>()
          .single;
      expect(hologram.faces, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('paper belongs to the selection group it was laid for', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);

    Future<void> box(Offset from, Offset to) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await frames(tester, 100);
    }

    Future<void> tap(Offset at) async {
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await frames(tester, 100);
    }

    Future<void> toggle() async {
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
    }

    await box(const Offset(100, 20), const Offset(700, 580));
    final taken = hologram(tester).faces.length;
    expect(taken, greaterThan(1));

    await toggle();
    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 100);
    expect(desk(tester).pieces, hasLength(1));
    await toggle();
    expect(find.byTooltip('Group A'), findsOneWidget);

    await tap(const Offset(40, 220));
    expect(hologram(tester).faces, isEmpty);
    await toggle();
    expect(desk(tester).pieces, isEmpty);
    await toggle();

    await tap(const Offset(400, 300));
    expect(hologram(tester).faces, hasLength(taken));

    await tap(const Offset(40, 220));
    await tester.tap(find.byTooltip('Group A'));
    await frames(tester, 100);
    expect(hologram(tester).faces, hasLength(taken));
    await toggle();
    expect(desk(tester).pieces, hasLength(1));
    await toggle();

    await tap(const Offset(40, 220));
    await box(const Offset(410, 310), const Offset(390, 290));
    expect(hologram(tester).faces.length, lessThan(taken));
    await toggle();
    expect(desk(tester).pieces, isEmpty);
    await toggle();
    expect(find.byTooltip('Group B'), findsNothing);
    expect(find.byTooltip('Group A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dragging paper onto the desk switches to Select', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    expect(desk(tester).selectedIds, isEmpty);

    final from = tester.getCenter(find.byTooltip('Mint dots'));
    const to = Offset(300, 300);
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester, 50);
    final painter = desk(tester);
    expect(painter.pieces, hasLength(1));
    expect(painter.selectedIds, {painter.pieces.single.id});
    expect(painter.rotateHandle, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a group with no paper on its faces is dropped', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final pick = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(tester, 100);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 100);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    expect(find.byTooltip('Group A'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final trash = tester.getCenter(find.byTooltip('Trash'));
    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(const Offset(400, 300), trash, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester, 50);
    expect(desk(tester).pieces, isEmpty);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    expect(find.byTooltip('Group A'), findsNothing);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> openDesk(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 50);
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester, 50);
  }

  testWidgets('a short straight drag cuts right through the sheet', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(1));
    await drag(tester, const Offset(380, 300), const Offset(420, 300));
    expect(desk(tester).pieces, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the straight edge stops a straight cut and guides the exacto', (
    tester,
  ) async {
    await openDesk(tester);
    final edgeLayer = find.byKey(const Key('asmr-straight-edge'));
    expect(edgeLayer, findsNothing);

    await tester.tap(find.byTooltip('Straight edge'));
    await frames(tester, 600);
    expect(edgeLayer, findsOneWidget);

    await drag(tester, const Offset(200, 300), const Offset(200, 400));
    expect(edgeLayer, findsOneWidget);

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    await drag(tester, const Offset(300, 200), const Offset(300, 220));
    var pieces = desk(tester).pieces;
    expect(pieces, hasLength(1));
    expect(pieces.single.scores, hasLength(1));
    const scale = 600 / 260;
    const edgeTop = (375 - 300) / scale;
    for (final p in pieces.single.scores.single) {
      expect(pieces.single.toDesk(p).dy, lessThanOrEqualTo(edgeTop + 1e-6));
    }

    await tester.tap(find.byTooltip('Exacto'));
    await frames(tester, 50);
    final knife = await tester.startGesture(
      const Offset(500, 300),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 10; i++) {
      await knife.moveTo(Offset(500 + i * 4, 300 + i * 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final stroke = desk(tester).stroke!;
    for (final p in stroke) {
      expect(p.dy, lessThanOrEqualTo(edgeTop + 1e-6));
    }
    expect(stroke.last.dy, closeTo(edgeTop, 0.05));
    await knife.up();
    await frames(tester, 50);

    await tester.tap(find.byTooltip('Straight edge'));
    await frames(tester, 600);
    expect(edgeLayer, findsNothing);

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    final before = desk(tester).pieces.length;
    await drag(tester, const Offset(250, 200), const Offset(250, 220));
    expect(desk(tester).pieces.length, greaterThan(before));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the straight edge rotates from its handle', (tester) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Straight edge'));
    await frames(tester, 600);
    final before = straightEdge(tester).angle;
    await drag(tester, const Offset(400, 353), const Offset(520, 240));
    expect((straightEdge(tester).angle - before).abs(), greaterThan(0.3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scrub eases a picked up piece back home', (tester) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final home = desk(tester).pieces.single.position;

    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset(400 + i * 8.0, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final lifted = desk(tester).pieces.single.position;
    expect((lifted - home).distance, greaterThan(15));

    await scrub(tester, gesture);
    await tester.pump(const Duration(milliseconds: 16));
    final leaving = desk(tester).pieces.single.position;
    final span = (leaving - home).distance;
    expect(span, greaterThan(15));
    await frames(tester, 48);
    final early = desk(tester).pieces.single.position;
    expect((leaving - early).distance, lessThan(span * 0.15));

    await gesture.up();
    await frames(tester, 400);
    expect(
      (desk(tester).pieces.single.position - home).distance,
      lessThan(0.5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a two-finger scrub eases a picked up piece back home', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final home = desk(tester).pieces.single.position;

    final finger = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 10; i++) {
      await finger.moveTo(Offset(400 + i * 8.0, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (desk(tester).pieces.single.position - home).distance,
      greaterThan(15),
    );

    final other = await tester.startGesture(const Offset(460, 360));
    await tester.pump(const Duration(milliseconds: 16));
    await scrub(tester, finger);
    await finger.up();
    await other.up();
    await frames(tester, 400);
    expect(
      (desk(tester).pieces.single.position - home).distance,
      lessThan(0.5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scrub drops a straight cut and an exacto stroke', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    final cut = await tester.startGesture(
      const Offset(360, 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 6; i++) {
      await cut.moveTo(Offset(360 + i * 8.0, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await scrub(tester, cut);
    await cut.up();
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.scores, isEmpty);

    await tester.tap(find.byTooltip('Exacto'));
    await frames(tester, 50);
    final knife = await tester.startGesture(
      const Offset(400, 280),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 6; i++) {
      await knife.moveTo(Offset(400 + i * 6.0, 280));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(desk(tester).stroke, isNotNull);
    await scrub(tester, knife);
    await tester.pump(const Duration(milliseconds: 16));
    expect(desk(tester).stroke, isNull);
    await knife.up();
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.scores, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scrub puts the straight edge back where the drag started', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Straight edge'));
    await frames(tester, 600);
    final home = straightEdge(tester).anchor;

    final gesture = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset(400, 300 + i * 8.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect((straightEdge(tester).anchor - home).distance, greaterThan(20));
    await scrub(tester, gesture);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await frames(tester, 50);
    expect((straightEdge(tester).anchor - home).distance, lessThan(0.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('undo and redo flank the toolbar and step the desk', (
    tester,
  ) async {
    await openDesk(tester);
    final undo = find.byKey(const Key('asmr-undo'));
    final redo = find.byKey(const Key('asmr-redo'));
    expect(undo, findsOneWidget);
    expect(redo, findsOneWidget);
    expect(
      find.descendant(of: undo, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(
      tester.widget<Padding>(undo).padding,
      const EdgeInsets.only(right: 24),
    );
    expect(
      tester.widget<Padding>(redo).padding,
      const EdgeInsets.only(left: 24),
    );
    final undoIcon = tester.getRect(
      find.descendant(of: undo, matching: find.byIcon(Icons.undo)),
    );
    final redoIcon = tester.getRect(
      find.descendant(of: redo, matching: find.byIcon(Icons.redo)),
    );
    final selectIcon = tester.getRect(
      find.descendant(
        of: find.byTooltip('Select'),
        matching: find.byIcon(Icons.open_with),
      ),
    );
    final straightIcon = tester.getRect(
      find.descendant(
        of: find.byTooltip('Straight edge'),
        matching: find.byIcon(Icons.straighten),
      ),
    );
    final fromTools = selectIcon.left - undoIcon.right;
    expect(fromTools, greaterThan(16 * 1.5));
    expect(redoIcon.left - straightIcon.right, closeTo(fromTools, 0.5));
    expect(tester.widget<Icon>(find.byIcon(Icons.undo)).color, Colors.white);
    expect(tester.widget<Icon>(find.byIcon(Icons.redo)).color, Colors.white24);

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    await drag(tester, const Offset(380, 300), const Offset(420, 300));
    expect(desk(tester).pieces, hasLength(2));

    await tester.tap(undo);
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(1));
    await tester.tap(undo);
    await frames(tester, 50);
    expect(desk(tester).pieces, isEmpty);
    expect(tester.widget<Icon>(find.byIcon(Icons.undo)).color, Colors.white24);
    expect(tester.widget<Icon>(find.byIcon(Icons.redo)).color, Colors.white);

    await tester.tap(redo);
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(1));
    await tester.tap(redo);
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rotate handle hinges on the edge across from it', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final handle = desk(tester).rotateHandle!;
    const pivot = Offset(0, -110);
    final before = desk(tester).pieces.single;
    expect(
      (before.toDesk(const Offset(0, -110)) - pivot).distance,
      lessThan(1),
    );

    final gesture = await tester.startGesture(
      handle,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    const turned = Offset(480, 46);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(handle, turned, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester, 50);
    final piece = desk(tester).pieces.single;
    expect(
      (piece.toDesk(const Offset(0, -110)) - pivot).distance,
      lessThan(0.5),
    );
    expect(piece.angle.abs(), greaterThan(0.4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('marquee takes pieces, and they drop into the drawer or trash', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);

    await drag(tester, const Offset(20, 200), const Offset(180, 400));
    expect(desk(tester).selectedIds, isEmpty);

    await drag(tester, const Offset(100, 20), const Offset(700, 580));
    expect(desk(tester).selectedIds, hasLength(1));

    await drag(tester, const Offset(700, 80), const Offset(250, 520));
    expect(desk(tester).selectedIds, hasLength(1));

    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 50);
    await drag(tester, const Offset(100, 20), const Offset(700, 580));
    expect(desk(tester).selectedIds, hasLength(2));

    final trash = tester.getCenter(find.byTooltip('Trash'));
    await drag(tester, const Offset(400, 300), trash);
    expect(desk(tester).pieces, isEmpty);
    expect(find.byTooltip('Lay Mint dots back down'), findsNothing);

    await tester.tap(find.byKey(const Key('asmr-undo')));
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(2));

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    await drag(tester, const Offset(380, 200), const Offset(420, 200));
    expect(desk(tester).pieces.length, greaterThan(2));

    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final drawer = tester.getCenter(find.byKey(const Key('asmr-drawer')));
    await drag(tester, const Offset(400, 80), drawer);
    expect(find.byTooltip('Lay Mint dots back down'), findsOneWidget);
    final onDesk = desk(tester).pieces.length;

    await tester.tap(find.byTooltip('Lay Mint dots back down'));
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(onDesk + 1));
    expect(find.byTooltip('Lay Mint dots back down'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

AsmrStraightEdge straightEdge(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const Key('asmr-straight-edge')),
  );
  return (paint.painter! as AsmrStraightEdgePainter).edge;
}

Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

HologramPainter hologram(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<HologramPainter>()
    .single;

AsmrDeskPainter desk(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<AsmrDeskPainter>()
    .single;

/// A fast back-and-forth, quick enough to count as a scrub.
Future<void> scrub(WidgetTester tester, TestGesture gesture) async {
  const leg = 56.0;
  var time = const Duration(milliseconds: 500);
  Future<void> flick(Offset delta) async {
    time += const Duration(milliseconds: 16);
    await gesture.moveBy(delta, timeStamp: time);
    await tester.pump(const Duration(milliseconds: 16));
  }

  await flick(const Offset(leg, 0));
  await flick(const Offset(-leg * 2, 0));
  await flick(const Offset(leg * 2, 0));
  await flick(const Offset(-leg * 2, 0));
}
