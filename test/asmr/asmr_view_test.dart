import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/asmr/asmr_dev.dart';
import 'package:flatmates/asmr/asmr_lens.dart';
import 'package:flatmates/asmr/asmr_straight_edge.dart';
import 'package:flatmates/asmr/hologram_painter.dart';
import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The dealt group whose blueprint is one face, left open on the desk.
  Future<String> openSingleton(WidgetTester tester) async {
    for (final name in ['A', 'B', 'C', 'D']) {
      final chip = find.byKey(Key('asmr-group-$name'));
      if (chip.evaluate().isEmpty) continue;
      await tester.tap(chip);
      await frames(tester, 700);
      if (hologram(tester).faces.length == 1) return name;
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
    }
    fail('expected a single-face group');
  }

  /// Opens the view with four groups and the desk on a group of one face,
  /// still placing the sheet. Returns that group's letter.
  Future<String> pickMiddleFace(
    WidgetTester tester, {
    AsmrDevSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AsmrView(
          settings: settings,
          groupCount: 4,
          random: math.Random(1),
        ),
      ),
    );
    await frames(tester, 300);
    return openSingleton(tester);
  }

  bool onDesk() => find.byTooltip('Look at the cube').evaluate().isNotEmpty;

  /// Puts the paper down where it came up and picks up [tool]. The desk is
  /// already open when a group chip brought it up.
  Future<void> placeAndTake(WidgetTester tester, String tool) async {
    if (!onDesk()) {
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
    }
    await tapAt(tester, const Offset(700, 150));
    await frames(tester, 500);
    await tester.tap(find.byTooltip(tool));
    await frames(tester, 400);
  }

  testWidgets(
    'a close cut stays for cleanup until explicitly sent to the cube',
    (tester) async {
      final group = await pickMiddleFace(tester);
      expect(find.text('Faces filled  0 / 6'), findsOneWidget);
      await placeAndTake(tester, 'Exacto');
      expect(onDesk(), isTrue);
      expect(find.byTooltip('Group $group'), findsOneWidget);
      expect(desk(tester).pieces, hasLength(1));
      expect(cutEdges(tester).every((e) => e.color == null), isTrue);

      await cutSquare(tester, 25.4);
      final judged = cutEdges(tester);
      expect(judged, hasLength(4));
      expect(judged.every((e) => e.color != null), isTrue);
      expect(desk(tester).pieces, hasLength(2));
      expect(find.byKey(const ValueKey('asmr-flights')), findsNothing);
      await frames(tester, 400);
      expect(onDesk(), isTrue);
      final send = find.byKey(const Key('asmr-send-paper'));
      final beforePan = tester.getCenter(send);
      final pan = await tester.startGesture(
        const Offset(100, 400),
        kind: PointerDeviceKind.mouse,
        buttons: 2,
      );
      await tester.pump();
      expect(send, findsOneWidget);
      await pan.moveTo(const Offset(150, 400));
      await tester.pump();
      expect(send, findsOneWidget);
      expect(tester.getCenter(send).dx, closeTo(beforePan.dx + 50, 1e-6));
      await pan.up();
      await tester.pump();
      await tester.tap(send);
      await tester.pump();
      expect(desk(tester).pieces, hasLength(1));
      expect(find.byKey(const ValueKey('asmr-flights')), findsOneWidget);
      expect(find.text('Faces filled  0 / 6'), findsOneWidget);

      await frames(tester, 900);
      expect(find.byKey(const ValueKey('asmr-flights')), findsNothing);
      expect(find.text('Faces filled  1 / 6'), findsOneWidget);
      expect(onDesk(), isFalse);
      expect(find.byTooltip('Group $group'), findsOneWidget);

      final orbit = await tester.startGesture(const Offset(400, 300));
      for (var i = 0; i < 20; i++) {
        await orbit.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await orbit.up();
      await frames(tester, 300);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('completed groups reopen only their cut paper for edits', (
    tester,
  ) async {
    final group = await pickMiddleFace(tester);
    await placeAndTake(tester, 'Exacto');
    await cutSquare(tester, 25.4);
    await frames(tester, 300);
    final cutout = desk(
      tester,
    ).pieces.firstWhere((piece) => piece.holes.isEmpty);
    await tester.tap(find.byKey(const Key('asmr-send-paper')));
    await frames(tester, 900);
    expect(onDesk(), isFalse);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Group $group'));
    await frames(tester, 700);
    expect(onDesk(), isTrue);
    expect(
      find.byTooltip('Straight cut'),
      findsOneWidget,
      reason: 'reopening skips placement',
    );
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.id, cutout.id);
    expect(desk(tester).pieces.single.holes, isEmpty);
    expect(find.byKey(const Key('asmr-send-paper')), findsOneWidget);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(desk(tester).pieces.single.binding, isNull);

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 400);
    await drag(tester, const Offset(300, 300), const Offset(350, 300));
    expect(desk(tester).pieces, hasLength(2));
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.id, cutout.id);
    await tester.tap(find.byKey(const Key('asmr-redo')));
    await tester.pump();
    expect(desk(tester).pieces, hasLength(2));

    await tester.tap(find.byTooltip('Group $group'));
    await frames(tester, 700);
    await tester.tap(find.byTooltip('Group $group'));
    await frames(tester, 700);
    expect(desk(tester).pieces, hasLength(2));
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    // Undo the editing cut, then explicitly send the original piece back.
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(desk(tester).pieces, hasLength(1));
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asmr-send-paper')));
    await frames(tester, 900);
    expect(onDesk(), isFalse);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);
    final other = ['A', 'B', 'C', 'D'].firstWhere((name) => name != group);
    await tester.tap(find.byTooltip('Group $other'));
    await frames(tester, 700);
    expect(desk(tester).pieces, hasLength(1));
    expect(
      desk(tester).pieces.single.holes,
      isNotEmpty,
      reason: 'shared leftovers are preserved for unfinished groups',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a half-correct piece sends on request and the button waits for a cut to end',
    (tester) async {
      await pickMiddleFace(tester);
      await placeAndTake(tester, 'Exacto');
      await cutDeskPolygon(tester, const [
        Offset(-25, -25),
        Offset(25, -25),
        Offset(-25, 25),
      ]);
      await frames(tester, 200);
      expect(desk(tester).pieces, hasLength(2));
      expect(find.byKey(const Key('asmr-send-paper')), findsOneWidget);
      final cutting = await tester.startGesture(
        const Offset(250, 450),
        kind: PointerDeviceKind.mouse,
      );
      await cutting.moveTo(const Offset(280, 450));
      await tester.pump();
      expect(find.byKey(const Key('asmr-send-paper')), findsNothing);
      await cutting.up();
      await frames(tester, 100);
      expect(find.byKey(const Key('asmr-send-paper')), findsOneWidget);
      // Mobile activates the arrow by tapping away from it while the centered
      // reticle lies over the blueprint's middle face.
      await tester.tap(find.byTooltip('Select'));
      await frames(tester, 400);
      final touch = await tester.startGesture(
        const Offset(700, 150),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('asmr-select-reticle'))),
        const Offset(400, 300),
      );
      await touch.up();
      await frames(tester, 900);
      expect(desk(tester).pieces, hasLength(1));
      expect(find.text('Faces filled  0 / 6'), findsOneWidget);
      expect(onDesk(), isTrue);
      await tester.tap(find.byKey(const Key('asmr-undo')));
      await frames(tester, 100);
      expect(desk(tester).pieces, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a cut too far from the blueprint stays on the desk', (
    tester,
  ) async {
    await pickMiddleFace(tester);
    await placeAndTake(tester, 'Exacto');

    await cutSquare(tester, 40);
    await frames(tester, 900);
    expect(desk(tester).pieces, hasLength(2));
    expect(cutEdges(tester).every((e) => e.color == null), isTrue);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(onDesk(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a group chip or its hatched faces open the desk, and undo '
      'lifts the paper', (tester) async {
    final group = await pickMiddleFace(tester);
    await placeAndTake(tester, 'Exacto');
    await cutSquare(tester, 25.4);
    await tester.tap(find.byKey(const Key('asmr-send-paper')));
    await tester.pump();
    await frames(tester, 900);
    expect(onDesk(), isFalse);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Group $group'));
    await frames(tester, 700);
    expect(onDesk(), isTrue);
    expect(hologram(tester).faces, hasLength(1));
    await tester.tap(find.byTooltip('Group $group'));
    await frames(tester, 700);
    expect(onDesk(), isFalse);

    await tester.tap(find.byTooltip('Orbit'));
    await frames(tester, 50);
    await tapAt(tester, const Offset(400, 300));
    await frames(tester, 700);
    expect(onDesk(), isTrue);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);

    await tester.tap(find.byKey(const Key('asmr-undo')));
    await frames(tester, 50);
    expect(
      find.text('Faces filled  1 / 6'),
      findsOneWidget,
      reason: 'undoing the lift restores submitted paper',
    );
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await frames(tester, 50);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(find.byTooltip('Group $group'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a double-tap swaps the cube and the desk, a drag does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);

    double look(String key) =>
        tester.widget<Opacity>(find.byKey(ValueKey(key))).opacity;

    Future<void> tap(Offset at) async {
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(onDesk(), isFalse);
    expect(look('asmr-model'), 1);
    expect(look('asmr-desk'), closeTo(0.33, 1e-9));
    expect(desk(tester).ghost, 1);

    await tap(const Offset(400, 300));
    await frames(tester, 700);
    expect(onDesk(), isTrue);
    final taken = hologram(tester).faces.length;
    expect(taken, greaterThan(0));
    expect(find.byTooltip('Group A'), findsOneWidget);
    expect(look('asmr-desk'), 1);
    expect(look('asmr-model'), closeTo(0.33, 1e-9));
    expect(desk(tester).ghost, 0);

    await tap(const Offset(400, 300));
    await tap(const Offset(400, 300));
    await frames(tester, 700);
    expect(onDesk(), isFalse);

    final orbit = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 6; i++) {
      await orbit.moveTo(Offset(400, 300 + i * 10.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await orbit.up();
    await frames(tester, 100);
    expect(onDesk(), isFalse);

    await tap(const Offset(60, 200));
    await tap(const Offset(62, 202));
    await frames(tester, 700);
    expect(onDesk(), isTrue);
    expect(hologram(tester).faces, hasLength(taken));
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.scores, isEmpty);
    expect(find.byTooltip('Group A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the paper slides under a still blueprint until a tap puts it '
      'down', (tester) async {
    await pickMiddleFace(tester);
    final blueprint = hologram(tester).origin;
    expect(blueprint, const Offset(400, 300));
    expect(find.byKey(const ValueKey('asmr-scissors')), findsNothing);
    expect(find.byTooltip('Exacto'), findsNothing);
    final home = desk(tester).pieces.single.position;

    await drag(tester, const Offset(300, 300), const Offset(346, 254));
    const scale = 600 / 260;
    expect(
      desk(tester).pieces.single.position - home,
      offsetMoreOrLessEquals(const Offset(46, -46) / scale, epsilon: 1e-6),
    );
    expect(hologram(tester).origin, blueprint);

    await tapAt(tester, const Offset(700, 150));
    await frames(tester, 100);
    expect(find.byKey(const ValueKey('asmr-scissors')), findsOneWidget);
    expect(find.byTooltip('Exacto'), findsOneWidget);
    expect(onDesk(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('right-drag rotates placement paper under the fixed blueprint', (
    tester,
  ) async {
    await pickMiddleFace(tester);
    final blueprint = hologram(tester).origin;
    final before = desk(tester).pieces.single;
    final gesture = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset(300 + i * 10, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    expect(desk(tester).pieces.single.angle, closeTo(before.angle + 0.8, 1e-6));
    expect(hologram(tester).origin, blueprint);
    expect(find.byKey(const ValueKey('asmr-scissors')), findsNothing);
    // A right click alone must not confirm placement either.
    final click = await tester.startGesture(
      const Offset(600, 200),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await click.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('asmr-scissors')), findsNothing);
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(desk(tester).pieces.single.angle, before.angle);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'two fingers twist placement paper without turning the blueprint',
    (tester) async {
      await pickMiddleFace(tester);
      final blueprint = hologram(tester).origin;
      final before = desk(tester).pieces.single.angle;
      final a = await tester.startGesture(const Offset(300, 300), pointer: 7);
      final b = await tester.startGesture(const Offset(500, 300), pointer: 8);
      for (var i = 1; i <= 8; i++) {
        final angle = math.pi / 4 * i / 8;
        final arm = Offset(math.cos(angle), math.sin(angle)) * 100;
        await a.moveTo(const Offset(400, 300) - arm);
        await b.moveTo(const Offset(400, 300) + arm);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump();
      expect(
        desk(tester).pieces.single.angle,
        closeTo(before + math.pi / 4, 1e-6),
      );
      expect(hologram(tester).origin, blueprint);
      expect(find.byKey(const ValueKey('asmr-scissors')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dealt groups stay when the desk closes', (tester) async {
    await pickMiddleFace(tester);
    expect(find.byTooltip('Group A'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(tester, 700);
    expect(onDesk(), isFalse);
    expect(find.byTooltip('Group A'), findsOneWidget);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.undo)).color, Colors.white24);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> openDesk(
    WidgetTester tester, {
    AsmrDevSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flat =
        settings ??
        AsmrDevSettings(
          file: File(
            '${Directory.systemTemp.path}/asmr_view_${DateTime.now().microsecondsSinceEpoch}.json',
          ),
          perspectiveness: 0,
        );
    if (settings == null) addTearDown(flat.dispose);
    await pickMiddleFace(tester, settings: flat);
    await placeAndTake(tester, 'Exacto');
  }

  testWidgets(
    'placement flashes and prints on paper; moved fragments still judge and send correctly',
    (tester) async {
      await pickMiddleFace(tester);
      expect(hologram(tester).inkOpacity, greaterThan(0));
      await tapAt(tester, const Offset(700, 150));
      expect(desk(tester).placementGlow, greaterThan(0));
      expect(desk(tester).pieces.single.blueprints, hasLength(1));
      expect(hologram(tester).inkOpacity, 0);
      await frames(tester, 400);
      expect(desk(tester).placementGlow, 0);
      await tester.tap(find.byTooltip('Select'));
      await frames(tester, 400);
      final before = desk(tester).pieces.single;
      final stamp = before.blueprints.single;
      await drag(tester, const Offset(300, 200), const Offset(340, 230));
      final moved = desk(tester).pieces.single;
      expect(moved.position, isNot(before.position));
      expect(moved.blueprints.single, same(stamp));
      final net = desk(tester).affixedNets[stamp.group]!;
      final outline = [
        for (final p in net.faces.single.ring) moved.toDesk(stamp.toPaper(p)),
      ];
      await tester.tap(find.byTooltip('Exacto'));
      await frames(tester, 400);
      await cutDeskPolygon(tester, outline);
      expect(desk(tester).pieces, hasLength(2));
      expect(
        desk(tester).pieces.every((p) => p.blueprints.single == stamp),
        isTrue,
      );
      expect(find.byKey(const Key('asmr-send-paper')), findsOneWidget);
      await tester.tap(find.byKey(const Key('asmr-send-paper')));
      await frames(tester, 900);
      expect(find.text('Faces filled  1 / 6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Select reticle follows the mouse and picks under screen center on touch',
    (tester) async {
      await openDesk(tester);
      await tester.tap(find.byTooltip('Select'));
      await frames(tester, 400);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(const Offset(300, 200));
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('asmr-select-reticle'))),
        const Offset(300, 200),
      );
      expect(desk(tester).hoveredId, desk(tester).pieces.single.id);
      await mouse.moveTo(const Offset(50, 250));
      await tester.pump();
      expect(desk(tester).hoveredId, isNull);
      await mouse.removePointer();
      final touch = await tester.startGesture(
        const Offset(700, 150),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('asmr-select-reticle'))),
        const Offset(400, 300),
      );
      await touch.up();
      await tester.pump();
      expect(desk(tester).selectedIds, contains(desk(tester).pieces.single.id));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('exacto colors separated boundaries only after release', (
    tester,
  ) async {
    await openDesk(tester);
    final gesture = await tester.startGesture(
      const Offset(180, 300),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset(180 + 55.0 * i, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.edgeTone, isNull);
    expect(desk(tester).pieces.single.cutEdges, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(desk(tester).pieces, hasLength(2));
    final tones = desk(tester).pieces.map((p) => p.edgeTone).toList();
    expect(tones.every((tone) => tone != null), isTrue);
    expect(desk(tester).pieces.every((p) => p.cutEdges.isNotEmpty), isTrue);
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(desk(tester).pieces, hasLength(1));
    expect(desk(tester).pieces.single.edgeTone, isNull);
    await tester.tap(find.byKey(const Key('asmr-redo')));
    await tester.pump();
    expect(desk(tester).pieces.map((p) => p.edgeTone), tones);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(tester.widget<Icon>(find.byIcon(Icons.redo)).color, Colors.white);

    await tester.tap(redo);
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(2));
    expect(tester.widget<Icon>(find.byIcon(Icons.redo)).color, Colors.white24);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rotate handle hinges on the edge across from it', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    final pick = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
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

  testWidgets('marquee takes pieces, and they drop into a slot or the trash', (
    tester,
  ) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    await drag(tester, const Offset(380, 200), const Offset(420, 200));
    expect(desk(tester).pieces, hasLength(2));

    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    expect(find.byTooltip('Scrap slot'), findsNothing);

    await drag(tester, const Offset(20, 200), const Offset(180, 400));
    expect(desk(tester).selectedIds, isEmpty);

    await drag(tester, const Offset(700, 80), const Offset(250, 160));
    expect(desk(tester).selectedIds, hasLength(1));
    expect(find.byTooltip('Scrap slot'), findsNWidgets(3));

    final slot = tester.getCenter(find.byTooltip('Scrap slot').first);
    await drag(tester, const Offset(400, 80), slot);
    expect(desk(tester).pieces, hasLength(1));
    expect(find.byKey(const ValueKey('asmr-slot-0')), findsOneWidget);
    expect(find.byTooltip('Scrap slot'), findsNothing);

    await tester.tap(find.byTooltip('Lay the scrap back down'));
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(2));
    expect(find.byKey(const ValueKey('asmr-slot-0')), findsNothing);

    await drag(tester, const Offset(100, 20), const Offset(700, 580));
    expect(desk(tester).selectedIds, hasLength(2));
    final trash = tester.getCenter(find.byTooltip('Trash'));
    await drag(tester, const Offset(400, 400), trash);
    expect(desk(tester).pieces, isEmpty);

    await tester.tap(find.byKey(const Key('asmr-undo')));
    await frames(tester, 50);
    expect(desk(tester).pieces, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // The scissors' blade runs from (400, 450) up to (400, 300) on an 800×600
  // screen, and the circle rests 52 px under the blade. The sheet spans
  // (215, 46) to (585, 554).
  const blade = Offset(400, 502);
  const knob = Offset(400, 502);

  Future<void> openScissors(WidgetTester tester) async {
    await openDesk(tester);
    await tester.tap(find.byTooltip('Scissors'));
    await frames(tester, 400);
    await drag(tester, const Offset(150, 250), const Offset(150, 150));
    await tapAt(tester, scissors(tester).aimPoints.first);
    await frames(tester, 200);
  }

  testWidgets('scissor allowance blocks cuts at zero and undo restores it', (
    tester,
  ) async {
    await openScissors(tester);
    final settings = tester.widget<AsmrView>(find.byType(AsmrView)).settings!;
    settings.scissorCuts = 1;
    await tester.pump();
    expect(find.textContaining('Scissor cuts left: 1'), findsOneWidget);
    await drag(tester, knob, knob + const Offset(0, -5));
    expect(find.textContaining('Scissor cuts left: 1'), findsOneWidget);
    await drag(tester, knob, knob + const Offset(0, -30));
    await frames(tester, 300);
    expect(find.textContaining('Scissor cuts left: 0'), findsOneWidget);
    final before = desk(tester).pieces.single;
    await drag(tester, knob, knob + const Offset(0, -30));
    expect(desk(tester).pieces.single, same(before));
    expect(find.textContaining('Scissor cuts left: 0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(find.textContaining('Scissor cuts left: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asmr-redo')));
    await tester.pump();
    expect(find.textContaining('Scissor cuts left: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> twoFingers(
    WidgetTester tester,
    (Offset, Offset) from,
    (Offset, Offset) to,
  ) async {
    final a = await tester.startGesture(from.$1, pointer: 7);
    final b = await tester.startGesture(from.$2, pointer: 8);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(Offset.lerp(from.$1, to.$1, i / 8)!);
      await b.moveTo(Offset.lerp(from.$2, to.$2, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await frames(tester, 50);
  }

  bool stuck(WidgetTester tester) => scissors(tester).stuck;

  testWidgets(
    'toggling preserves an embedded cut and resumes at its endpoint',
    (tester) async {
      await openScissors(tester);
      await drag(tester, knob, knob + const Offset(0, -40));
      await frames(tester, 200);
      expect(stuck(tester), isTrue);
      final origin = desk(tester).origin;
      final angle = desk(tester).angle;
      final scale = desk(tester).scale;
      final scores = desk(tester).pieces.single.scores.length;
      final last = desk(
        tester,
      ).pieces.single.toDesk(desk(tester).pieces.single.scores.last.last);
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
      expect(onDesk(), isFalse);
      // The double-tap path must resume the same desk as the toggle button.
      await tapAt(tester, const Offset(700, 150));
      await tapAt(tester, const Offset(700, 150));
      await frames(tester, 700);
      expect(onDesk(), isTrue);
      expect(stuck(tester), isTrue);
      expect(desk(tester).origin, origin);
      expect(desk(tester).angle, angle);
      expect(desk(tester).scale, scale);
      expect(desk(tester).pieces.single.scores, hasLength(scores));
      expect(deskAt(desk(tester), knob), offsetMoreOrLessEquals(last));
      await drag(tester, knob, knob + const Offset(0, -20));
      await frames(tester, 200);
      final piece = desk(tester).pieces.single;
      expect(piece.toDesk(piece.scores.last.last).dy, lessThan(last.dy));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'toggling during placement keeps the paper and placement camera',
    (tester) async {
      final group = await pickMiddleFace(tester);
      await drag(tester, const Offset(150, 200), const Offset(200, 220));
      final piece = desk(tester).pieces.single.position;
      final origin = desk(tester).origin;
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await frames(tester, 700);
      await tester.tap(find.byTooltip('Group $group'));
      await frames(tester, 700);
      expect(desk(tester).pieces.single.position, piece);
      expect(desk(tester).origin, origin);
      expect(find.byTooltip('Scissors'), findsNothing);
      await tapAt(tester, const Offset(700, 150));
      await frames(tester, 400);
      expect(find.byKey(const ValueKey('asmr-scissors')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pre-cut pans and tapping a marker smoothly lines up without cutting',
    (tester) async {
      await openDesk(tester);
      await tester.tap(find.byTooltip('Scissors'));
      await frames(tester, 400);
      expect(scissors(tester).aiming, isTrue);
      expect(scissors(tester).aimPoints, hasLength(1));
      final initial = desk(tester).origin;
      await drag(tester, const Offset(150, 250), const Offset(150, 150));
      expect(desk(tester).origin.dy, lessThan(initial.dy - 80));
      expect(desk(tester).pieces.single.scores, isEmpty);
      final candidate = scissors(tester).aimPoints.single;
      final beforeTap = desk(tester).origin;
      await tapAt(tester, candidate);
      expect(scissors(tester).controlsOpacity, 0);
      await frames(tester, 64);
      expect(
        scissors(tester).controlsOpacity,
        allOf(greaterThan(0), lessThan(1)),
      );
      final during = desk(tester).origin;
      expect(during, isNot(beforeTap));
      expect(scissors(tester).circle, knob);
      await frames(tester, 200);
      final after = desk(tester).origin;
      expect(after, isNot(during));
      expect(scissors(tester).aiming, isFalse);
      expect(scissors(tester).controlsOpacity, 1);
      expect(scissors(tester).aimPoints, isEmpty);
      expect(scissors(tester).dial, isNotNull);
      expect(desk(tester).pieces.single.scores, isEmpty);
      await drag(tester, knob, knob + const Offset(0, -30));
      expect(desk(tester).pieces.single.scores, hasLength(1));
      expect(stuck(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pre-cut orbit preserves the edge gap and finishes ahead of the scissors',
    (tester) async {
      await openDesk(tester);
      await tester.tap(find.byTooltip('Scissors'));
      await frames(tester, 400);
      final sheet = desk(tester).pieces.single;
      final edge = (sheet.deskRing[0] + sheet.deskRing[1]) / 2;
      final original = desk(tester);
      final dy = 540 - (original.origin + edge * original.scale).dy;
      final pan = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.mouse,
      );
      await pan.moveTo(Offset(100, 100 + dy));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scissors(tester).aiming, isTrue);
      expect(
        desk(tester).angle.abs(),
        allOf(greaterThan(0), lessThan(math.pi)),
      );
      Offset projectedEdge() {
        final d = desk(tester);
        return d.origin +
            Offset(
                  math.cos(d.angle) * edge.dx - math.sin(d.angle) * edge.dy,
                  math.sin(d.angle) * edge.dx + math.cos(d.angle) * edge.dy,
                ) *
                d.scale;
      }

      final gap = (projectedEdge() - knob).distance;
      expect(gap, closeTo(38, 1e-6));
      await pan.up();
      await frames(tester, 140);
      expect(
        desk(tester).angle.abs(),
        allOf(greaterThan(0.1), lessThan(math.pi)),
      );
      expect((projectedEdge() - knob).distance, closeTo(gap, 1e-6));
      await frames(tester, 400);
      expect(desk(tester).angle.abs(), closeTo(math.pi, 1e-6));
      expect((projectedEdge() - knob).distance, closeTo(gap, 1e-6));
      expect(projectedEdge().dy, closeTo(knob.dy - gap, 1e-6));
      expect(projectedEdge().dx, closeTo(knob.dx, 1e-6));
      final settled = desk(tester).angle;
      await frames(tester, 400);
      expect(desk(tester).angle, settled);
      expect(desk(tester).pieces.single.scores, isEmpty);
      // Committing the start ends auto-orbit and leaves cutting manual.
      await tapAt(tester, scissors(tester).aimPoints.first);
      await frames(tester, 200);
      expect(scissors(tester).aiming, isFalse);
      final ready = desk(tester).angle;
      await frames(tester, 400);
      expect(desk(tester).angle, ready);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tool camera eases from overhead into scissors and back', (
    tester,
  ) async {
    final settings = AsmrDevSettings(
      file: File(
        '${Directory.systemTemp.path}/asmr_camera_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
      perspectiveness: 0.7,
    );
    addTearDown(settings.dispose);
    await openDesk(tester, settings: settings);
    expect(hologram(tester).lens, isNull);
    await tester.tap(find.byTooltip('Scissors'));
    await frames(tester, 100);
    final middle = hologram(tester).lens!.elevation;
    expect(middle, lessThan(math.pi / 2));
    expect(middle, greaterThan(AsmrCutLens.elevationFor(0.7)));
    await frames(tester, 400);
    expect(
      hologram(tester).lens!.elevation,
      closeTo(AsmrCutLens.elevationFor(0.7), 1e-9),
    );
    await tester.tap(find.byTooltip('Exacto'));
    await frames(tester, 100);
    expect(
      hologram(tester).lens!.elevation,
      greaterThan(AsmrCutLens.elevationFor(0.7)),
    );
    await frames(tester, 400);
    expect(hologram(tester).lens, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final vertical in [-30.0, 30.0]) {
      testWidgets(
        '${kind.name} vertical drag $vertical above the reticle starts and continues cuts',
        (tester) async {
          await openScissors(tester);
          expect(stuck(tester), isFalse);
          for (var cut = 1; cut <= 2; cut++) {
            final start = cut == 1
                ? const Offset(200, 350)
                : knob - const Offset(0, 10);
            final gesture = await tester.startGesture(start, kind: kind);
            for (var i = 1; i <= 8; i++) {
              await gesture.moveTo(start + Offset(0, vertical * i / 8));
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(
              scissors(tester).mark,
              offsetMoreOrLessEquals(knob - const Offset(0, 30)),
            );
            await gesture.up();
            await frames(tester, 300);
            expect(stuck(tester), isTrue);
            expect(desk(tester).pieces.single.scores, isNotEmpty);
            expect(
              find.textContaining('Scissor cuts left: ${5 - cut}'),
              findsOneWidget,
            );
          }
          final before = desk(tester).pieces.single;
          final horizontal = await tester.startGesture(
            const Offset(200, 350),
            kind: kind,
          );
          await horizontal.moveTo(const Offset(240, 350));
          await tester.pump(const Duration(milliseconds: 16));
          await horizontal.up();
          await tester.pump();
          expect(desk(tester).pieces.single, same(before));
          expect(find.textContaining('Scissor cuts left: 3'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('a small initial sideways wobble does not steal an upward cut', (
    tester,
  ) async {
    await openScissors(tester);
    final g = await tester.startGesture(knob, kind: PointerDeviceKind.touch);
    for (final offset in [
      const Offset(9, -1),
      const Offset(11, -18),
      const Offset(12, -45),
    ]) {
      await g.moveTo(knob + offset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      scissors(tester).mark,
      offsetMoreOrLessEquals(knob - const Offset(0, 45)),
    );
    expect(desk(tester).angle, closeTo(0, 1e-9));
    await g.up();
    await frames(tester, 200);
    expect(desk(tester).pieces.single.scores, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a touch just below the circle can pull upward to cut', (
    tester,
  ) async {
    await openScissors(tester);
    final start = knob + const Offset(30, 16);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.touch);
    await g.moveTo(start - const Offset(0, 60));
    await tester.pump();
    expect(
      scissors(tester).mark,
      offsetMoreOrLessEquals(knob - const Offset(0, 60)),
    );
    await g.up();
    await frames(tester, 200);
    expect(desk(tester).pieces.single.scores, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a fast swipe uses its release position even without a move sample',
    (tester) async {
      await openScissors(tester);
      await tester.sendEventToBinding(
        const PointerDownEvent(
          pointer: 91,
          device: 91,
          kind: PointerDeviceKind.touch,
          position: knob,
          timeStamp: Duration(seconds: 1),
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(
          pointer: 91,
          device: 91,
          kind: PointerDeviceKind.touch,
          position: knob - const Offset(0, 30),
          timeStamp: const Duration(milliseconds: 1030),
        ),
      );
      await frames(tester, 200);
      expect(desk(tester).pieces.single.scores, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('system cancellation never commits a previewed scissors cut', (
    tester,
  ) async {
    await openScissors(tester);
    final g = await tester.startGesture(knob, kind: PointerDeviceKind.touch);
    await g.moveTo(knob - const Offset(0, 30));
    await tester.pump();
    expect(scissors(tester).mark, isNotNull);
    await g.cancel();
    await frames(tester, 200);
    expect(desk(tester).pieces.single.scores, isEmpty);
    expect(scissors(tester).mark, isNull);
    expect(find.textContaining('Scissor cuts left: 5'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'vertical preview adjustments do not count as a cancellation scrub',
    (tester) async {
      await openScissors(tester);
      final g = await tester.createGesture(kind: PointerDeviceKind.touch);
      await g.down(knob, timeStamp: const Duration(seconds: 1));
      var ms = 1000;
      for (final dy in [-40.0, -90.0, -40.0, -100.0]) {
        ms += 16;
        await g.moveTo(
          knob + Offset(0, dy),
          timeStamp: Duration(milliseconds: ms),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        scissors(tester).mark,
        offsetMoreOrLessEquals(knob - const Offset(0, 100)),
      );
      expect(find.textContaining('Scissor cuts left: 5'), findsOneWidget);
      await g.up(timeStamp: Duration(milliseconds: ms + 16));
      await frames(tester, 200);
      expect(desk(tester).pieces.single.scores, hasLength(1));
      expect(find.textContaining('Scissor cuts left: 4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a second cut can grab the moving circle without snapping the camera',
    (tester) async {
      await openScissors(tester);
      final first = await tester.startGesture(
        knob,
        kind: PointerDeviceKind.touch,
      );
      await first.moveTo(knob - const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      await first.up();
      await tester.pump(const Duration(milliseconds: 16));
      final d = desk(tester);
      final endpoint = d.pieces.single.toDesk(d.pieces.single.scores.last.last);
      final moving = scissors(tester).circle!;
      expect(moving.dy, lessThan(knob.dy - 20));
      final second = await tester.startGesture(
        moving,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(desk(tester).origin, offsetMoreOrLessEquals(d.origin));
      await second.moveTo(moving - const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
      final during = desk(tester);
      expect(
        scissors(tester).mark,
        offsetMoreOrLessEquals(
          during.origin + endpoint * during.scale - const Offset(0, 20),
        ),
      );
      await second.up();
      await frames(tester, 200);
      final piece = desk(tester).pieces.single;
      expect(piece.toDesk(piece.scores.last.last).dy, lessThan(endpoint.dy));
      expect(find.textContaining('Scissor cuts left: 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the ruler does not intercept scissors strokes above the circle',
    (tester) async {
      await openScissors(tester);
      await tester.tap(find.byTooltip('Straight edge'));
      await frames(tester, 500);
      final anchor = straightEdge(tester).anchor;
      final g = await tester.startGesture(
        anchor,
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(anchor - const Offset(0, 30));
      await tester.pump();
      expect(scissors(tester).mark, isNotNull);
      expect(straightEdge(tester).anchor, anchor);
      await g.up();
      await frames(tester, 200);
      expect(desk(tester).pieces.single.scores, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'retracting a tiny cut is a cancellation rather than a double tap',
    (tester) async {
      await openScissors(tester);
      await tapAt(tester, knob);
      final g = await tester.startGesture(knob, kind: PointerDeviceKind.touch);
      await g.moveTo(knob - const Offset(0, 6));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(knob);
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await frames(tester, 200);
      expect(onDesk(), isTrue);
      expect(desk(tester).pieces.single.scores, isEmpty);
      expect(scissors(tester).mark, isNull);
      expect(find.textContaining('Scissor cuts left: 5'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'switching from Exacto ends its pointer gesture before the scissors camera moves',
    (tester) async {
      await openDesk(tester);
      final down = await tester.startGesture(
        const Offset(300, 250),
        kind: PointerDeviceKind.mouse,
      );
      await down.moveTo(const Offset(330, 250));
      await tester.pump();
      expect(desk(tester).stroke, isNotNull);
      await tester.tap(find.byTooltip('Scissors'));
      await frames(tester, 100);
      final before = [for (final p in desk(tester).pieces) p];
      await down.moveTo(const Offset(350, 250));
      await tester.pump();
      await down.up();
      await frames(tester, 400);
      expect(desk(tester).stroke, isNull);
      expect(desk(tester).pieces, orderedEquals(before));
      expect(desk(tester).pieces.every((p) => p.scores.isEmpty), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('scissors cut up the blade as far as the drag', (tester) async {
    await openScissors(tester);
    final before = desk(tester);
    final end = deskAt(before, const Offset(400, 402));

    final gesture = await tester.startGesture(
      knob,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset(400, 502 - 12.5 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      scissors(tester).mark,
      offsetMoreOrLessEquals(const Offset(400, 402)),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    final piece = desk(tester).pieces.single;
    expect(piece.scores, hasLength(1));
    expect(piece.toDesk(piece.scores.single.last), offsetMoreOrLessEquals(end));
    expect(stuck(tester), isTrue);

    // Circle and paper endpoint share the same camera projection at every
    // sampled frame, rather than independently easing toward the bar.
    for (var i = 0; i < 4; i++) {
      final d = desk(tester);
      expect(
        scissors(tester).circle,
        offsetMoreOrLessEquals(d.origin + end * d.scale),
      );
      expect(scissors(tester).circle!.dy, lessThan(knob.dy));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await frames(tester, 200);
    expect(scissors(tester).circle, offsetMoreOrLessEquals(knob));

    await frames(tester, 400);
    final after = desk(tester);
    expect(
      after.origin,
      offsetMoreOrLessEquals(before.origin + const Offset(0, 100)),
    );
    expect(deskAt(after, blade), offsetMoreOrLessEquals(end));

    await twoFingers(
      tester,
      (const Offset(300, 200), const Offset(500, 200)),
      (const Offset(300, 100), const Offset(500, 100)),
    );
    expect(desk(tester).origin, offsetMoreOrLessEquals(after.origin));
    expect(desk(tester).scale, after.scale);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a scissors drag of at most five pixels cuts nothing', (
    tester,
  ) async {
    await openScissors(tester);
    final before = desk(tester).origin;
    await drag(tester, knob, knob + const Offset(0, -5));
    await frames(tester, 400);
    expect(desk(tester).pieces.single.scores, isEmpty);
    expect(desk(tester).origin, before);
    expect(stuck(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('six pixel cuts track the circle and releasing below cancels', (
    tester,
  ) async {
    await openScissors(tester);
    final start = desk(tester).origin;
    final g = await tester.startGesture(knob, kind: PointerDeviceKind.mouse);
    await g.moveTo(knob + const Offset(0, -6));
    await tester.pump();
    expect(scissors(tester).mark, knob + const Offset(0, -6));
    await g.up();
    await frames(tester, 200);
    expect(desk(tester).pieces.single.scores, hasLength(1));
    expect(desk(tester).origin, isNot(start));

    final before = desk(tester).pieces.single.scores.length;
    final cancel = await tester.startGesture(
      knob,
      kind: PointerDeviceKind.mouse,
    );
    await cancel.moveTo(knob + const Offset(0, -30));
    await tester.pump();
    await cancel.moveTo(knob + const Offset(0, 10));
    await tester.pump();
    expect(scissors(tester).mark, isNull);
    await cancel.up();
    await frames(tester, 200);
    expect(desk(tester).pieces.single.scores, hasLength(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scissors go on along the line until the sheet comes apart', (
    tester,
  ) async {
    await openScissors(tester);
    final panFrom = desk(tester).origin;
    await twoFingers(
      tester,
      (const Offset(300, 300), const Offset(500, 300)),
      (const Offset(300, 150), const Offset(500, 150)),
    );
    expect(desk(tester).angle, closeTo(0, 1e-9));
    expect(
      desk(tester).origin,
      offsetMoreOrLessEquals(panFrom + const Offset(0, -150), epsilon: 8),
    );

    await tapAt(tester, scissors(tester).aimPoints.first);
    await frames(tester, 200);
    var strokes = 0;
    while (desk(tester).pieces.length == 1 && strokes < 6) {
      await drag(tester, knob, const Offset(400, 300));
      await frames(tester, 400);
      strokes++;
    }
    expect(strokes, greaterThan(1));
    expect(desk(tester).pieces, hasLength(2));
    expect(stuck(tester), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  Future<TestGesture> holdKnob(WidgetTester tester, Offset to) async {
    final gesture = await tester.startGesture(
      knob,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(knob, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('the dial under the blade turns the paper about the cut', (
    tester,
  ) async {
    await openScissors(tester);
    expect(find.byIcon(Icons.carpenter), findsOneWidget);
    await drag(tester, knob, const Offset(400, 402));
    await frames(tester, 400);
    expect(stuck(tester), isTrue);
    final pivot = deskAt(desk(tester), blade);
    final dial = scissors(tester).dial!;
    expect(dial.center, knob);
    expect(dial.halfLength, closeTo(800 / 3, 1e-9));
    expect(scissors(tester).cruise, isFalse);

    // Over to the pip 30° out from the middle, seen from the pivot. The
    // paper turns as far.
    const turn = math.pi / 6;
    final gesture = await holdKnob(
      tester,
      knob + Offset(dial.halfLength * turn / (math.pi / 2), 0),
    );
    expect(scissors(tester).dialHeld, isTrue);
    expect(
      scissors(tester).knob,
      closeTo(dial.halfLength * turn / (math.pi / 2), 1e-6),
    );
    final turned = desk(tester);
    expect(turned.angle, closeTo(-turn, 1e-3));
    expect(deskAt(turned, blade), offsetMoreOrLessEquals(pivot));

    await frames(tester, 300);
    expect(desk(tester).angle, closeTo(-turn, 1e-3));
    await gesture.up();
    await frames(tester, 160);
    expect(scissors(tester).knob, 0);
    expect(scissors(tester).dialHeld, isFalse);
    expect(desk(tester).angle, closeTo(-turn, 1e-3));
    expect(stuck(tester), isTrue);

    await twoFingers(
      tester,
      (const Offset(300, 200), const Offset(500, 200)),
      (const Offset(300, 100), const Offset(500, 100)),
    );
    expect(desk(tester).angle, closeTo(-turn, 1e-3));
    expect(desk(tester).origin, offsetMoreOrLessEquals(turned.origin));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the circle cuts straight up and turns once the drag swings '
      'out', (tester) async {
    await openScissors(tester);
    await drag(tester, knob, knob + const Offset(0, -80));
    expect(desk(tester).pieces.single.scores, hasLength(1));
    expect(desk(tester).angle, closeTo(0, 1e-9));
    await frames(tester, 400);

    await drag(tester, knob, knob + const Offset(80, -80));
    expect(desk(tester).pieces.single.scores, hasLength(1));
    expect(desk(tester).angle, isNot(closeTo(0, 0.05)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dial reaches a 90 degree turn at the end of its bar', (
    tester,
  ) async {
    await openScissors(tester);
    final gesture = await holdKnob(tester, const Offset(790, 502));
    final reached = scissors(tester).knob;
    expect(reached, greaterThan(800 / 3 * 0.8));
    expect(reached, closeTo(800 / 3, 1e-9));
    final angle = desk(tester).angle;
    expect(angle, closeTo(-math.pi / 2, 1e-3));

    await frames(tester, 500);
    expect(desk(tester).angle, closeTo(angle, 1e-9));
    await gesture.up();
    await frames(tester, 400);
    expect(desk(tester).angle, closeTo(angle, 1e-9));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with cruise on, holding the dial at an end keeps turning', (
    tester,
  ) async {
    final settings = AsmrDevSettings(
      file: File(
        '${Directory.systemTemp.path}/asmr_cruise_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
      perspectiveness: 0,
      dialCruise: true,
    );
    addTearDown(settings.dispose);
    await openDesk(tester, settings: settings);
    await tester.tap(find.byTooltip('Scissors'));
    await frames(tester, 400);
    expect(scissors(tester).cruise, isTrue);
    await drag(tester, const Offset(150, 250), const Offset(150, 150));
    await tapAt(tester, scissors(tester).aimPoints.first);
    await frames(tester, 200);

    final gesture = await holdKnob(tester, const Offset(790, 502));
    final reached = desk(tester).angle;
    final direct = -math.pi / 2 * 0.8;
    expect(
      reached,
      allOf(lessThan(direct), greaterThan(direct - 0.1)),
      reason: 'the ends turn by holding, not by distance',
    );
    await frames(tester, 500);
    final held = desk(tester).angle;
    expect(held, lessThan(reached - 0.4));

    await gesture.moveTo(const Offset(500, 502));
    await tester.pump(const Duration(milliseconds: 16));
    expect(desk(tester).angle, greaterThan(held));
    await frames(tester, 600);
    final middle = desk(tester).angle;
    await frames(tester, 300);
    expect(desk(tester).angle, closeTo(middle, 5e-3));
    await gesture.up();
    await frames(tester, 400);
    expect(desk(tester).angle, closeTo(middle, 5e-3));

    final again = await holdKnob(tester, const Offset(790, 502));
    await frames(tester, 300);
    await again.up();
    final letGo = desk(tester).angle;
    await frames(tester, 100);
    expect(desk(tester).angle, lessThan(letGo - 0.01));
    await frames(tester, 1500);
    final settled = desk(tester).angle;
    await frames(tester, 300);
    expect(desk(tester).angle, closeTo(settled, 5e-3));
    expect(scissors(tester).knob, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cut mode pitches the desk along the blade', (tester) async {
    final settings = AsmrDevSettings(
      file: File(
        '${Directory.systemTemp.path}/asmr_pitch_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
      perspectiveness: 1,
      lensMm: 35,
    );
    addTearDown(settings.dispose);
    await openDesk(tester, settings: settings);
    await tester.tap(find.byTooltip('Scissors'));
    await frames(tester, 400);
    expect(desk(tester).projection, isNotNull);

    final lens = AsmrCutLens(
      pivot: blade,
      focal: AsmrCutLens.focalPixels(35, 600),
      elevation: AsmrCutLens.elevationFor(1),
    );
    final ahead = lens.project(const Offset(400, 300));
    expect(ahead.dx, closeTo(400, 1e-6));
    expect(ahead.dy, greaterThan(300));
    expect(ahead.dy, lessThan(blade.dy));
    expect(lens.project(blade), blade);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hover previews the background blueprint with an optional reticle',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('asmr_hover_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final settings = AsmrDevSettings(file: File('${dir.path}/settings.json'));
      addTearDown(settings.dispose);
      await tester.pumpWidget(MaterialApp(home: AsmrView(settings: settings)));
      await frames(tester, 300);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(60, 200));
      await mouse.moveTo(const Offset(400, 300));
      await frames(tester, 400);
      expect(onDesk(), isFalse);
      expect(hologram(tester).faces, isNotEmpty);
      expect(settings.blueprintReticle, isFalse);
      expect(
        find.byKey(const ValueKey('asmr-reticle-blueprint')),
        findsNothing,
      );
      final preview = hologram(tester).faces;
      settings.blueprintReticle = true;
      await tester.pump();
      expect(
        find.byKey(const ValueKey('asmr-reticle-blueprint')),
        findsOneWidget,
      );
      expect(onDesk(), isFalse);
      await tapAt(tester, const Offset(400, 300));
      await frames(tester, 700);
      expect(onDesk(), isTrue);
      expect(hologram(tester).faces, preview);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  int groupChips(WidgetTester tester) {
    var n = 0;
    for (final name in ['A', 'B', 'C', 'D']) {
      if (find.byKey(Key('asmr-group-$name')).evaluate().isNotEmpty) n++;
    }
    return n;
  }

  testWidgets('the dice deals three cube groups', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    expect(groupChips(tester), 3);
    expect(find.byKey(const Key('asmr-group-E')), findsNothing);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);

    await tester.tap(find.byTooltip('Randomize groups'));
    await tester.pump();
    expect(groupChips(tester), 3);
    expect(find.byKey(const Key('asmr-group-E')), findsNothing);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.undo)).color, Colors.white);

    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(groupChips(tester), 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('devtools loads another object and deals its faces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(tester, 300);
    await tester.tap(find.text('devtools'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('asmr-dev-tab-object')));
    await tester.pump();
    expect(find.text('Cube'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asmr-object')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Double cube'), findsOneWidget);
    expect(find.text('Rocket'), findsOneWidget);
    expect(find.text('Birdhouse'), findsOneWidget);
    expect(find.text('Coffee Cup'), findsOneWidget);

    await tester.tap(find.text('Double cube').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Faces filled  0 / 6'), findsNothing);
    expect(find.textContaining('Faces filled  0 / '), findsOneWidget);
    expect(groupChips(tester), inInclusiveRange(2, 4));

    await tester.tap(find.byKey(const Key('asmr-undo')));
    await tester.pump();
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// The desk point under [screen] in [d]'s view.
Offset deskAt(AsmrDeskPainter d, Offset screen) {
  final v = (screen - d.origin) / d.scale;
  final c = math.cos(-d.angle);
  final s = math.sin(-d.angle);
  return Offset(c * v.dx - s * v.dy, s * v.dx + c * v.dy);
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

Future<void> tapAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 16));
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

/// Cuts a square of [half] desk units about the middle of the desk with the
/// exacto, as the desk first opens.
Future<void> cutSquare(WidgetTester tester, double half) async {
  const center = Offset(400, 300);
  const scale = 600 / 260;
  Offset screen(double x, double y) => center + Offset(x, y) * scale;
  final start = screen(-half, -half);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  var at = start;
  for (final corner in [
    screen(half, -half),
    screen(half, half),
    screen(-half, half),
    screen(-half, -half + 2),
  ]) {
    final delta = corner - at;
    const steps = 30;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(at + delta * (i / steps));
      await tester.pump(const Duration(milliseconds: 8));
    }
    at = corner;
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 16));
}

/// The hologram's edges that are cut lines, not folds.
List<HologramEdgeView> cutEdges(WidgetTester tester) => [
  for (final edge in hologram(tester).edges)
    if (!edge.fold) edge,
];

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

AsmrScissorsPainter scissors(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const ValueKey('asmr-scissors')))
            .painter!
        as AsmrScissorsPainter;

Future<void> cutDeskPolygon(WidgetTester tester, List<Offset> points) async {
  final d = desk(tester);
  Offset screen(Offset p) => d.origin + p * d.scale;
  final gesture = await tester.startGesture(
    screen(points.first),
    kind: PointerDeviceKind.mouse,
  );
  var from = points.first;
  for (final to in [...points.skip(1), points.first]) {
    for (var i = 1; i <= 30; i++) {
      await gesture.moveTo(screen(Offset.lerp(from, to, i / 30)!));
      await tester.pump(const Duration(milliseconds: 8));
    }
    from = to;
  }
  await gesture.up();
  await tester.pump();
}
