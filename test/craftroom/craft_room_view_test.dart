import 'dart:io';
import 'dart:ui';

import 'package:flatmates/asmr/hologram_painter.dart';
import 'package:flatmates/craftroom/craft_bench_painter.dart';
import 'package:flatmates/craftroom/craft_theme.dart';
import 'package:flatmates/craftroom/room_crafts.dart';
import 'package:flatmates/craftroom/snap_rules.dart';
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/screens/craft_room_view.dart';
import 'package:flatmates/ui/game/dev_tools_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// 800 by 600 with a 16 pixel divider: with the bench open each pane is 292
/// tall, the desk from 308 down.
const double _paneHeight = 292;
const Offset _screenMiddle = Offset(400, 300);
const Offset _modelMiddle = Offset(400, 146);

/// One 3x3 cube in the middle of an empty room, the camera aimed at it.
final _room = CraftCollection(
  id: 'test-room',
  name: 'Test room',
  crafts: const [CraftSpot(puzzleId: kRoomCubeId, at: Offset.zero)],
  camera: CollectionCamera(at: Vector3(0, 0, 1.5), halfHeight: 8),
);

void main() {
  testWidgets('the divider rises after the orbit, once the level has loaded, '
      'and drops before the fly out', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('craft-room-divider')), findsNothing);
    await enterCube(tester);

    // Still inside the 800 ms orbit.
    await frames(tester, 736);
    expect(find.byKey(const Key('craft-room-divider')), findsNothing);
    expect(find.byKey(const Key('craft-room-room')), findsOneWidget);
    expect(topHeight(tester), 600);

    // Orbit done, the level load still running.
    await frames(tester, 128);
    expect(find.byKey(const Key('craft-room-model')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-divider')), findsNothing);
    expect(topHeight(tester), 600);

    await frames(tester, 640);
    expect(find.byKey(const Key('craft-room-divider')), findsNothing);
    expect(topHeight(tester), 600);

    // The load has finished and the divider is on its way up.
    await frames(tester, 192);
    expect(find.byKey(const Key('craft-room-divider')), findsOneWidget);
    final rising = topHeight(tester);
    expect(rising, lessThan(590));
    expect(rising, greaterThan(_paneHeight + 20));

    await frames(tester, 400);
    expect(find.byKey(const Key('craft-room-model')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-desk')), findsOneWidget);
    expect(topHeight(tester), closeTo(_paneHeight, 0.5));

    await tester.tap(find.byKey(const Key('craft-room-back')));
    await frames(tester, 16 * 5);
    expect(find.byKey(const Key('craft-room-desk')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-room')), findsNothing);
    final falling = topHeight(tester);
    expect(falling, greaterThan(_paneHeight));
    expect(falling, lessThan(600));

    await frames(tester, 16 * 25);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);
    expect(find.byKey(const Key('craft-room-room')), findsOneWidget);

    await frames(tester, 900);
    expect(find.byKey(const Key('craft-room-divider')), findsNothing);
    expect(topHeight(tester), 600);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paper cut out exactly to a net island folds onto the cube '
      'with no drag', (tester) async {
    await open(tester);
    await reachBench(tester);

    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    final pick = await tester.startGesture(
      _modelMiddle,
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(tester, 300);
    final face = hologram(tester).faces.single;
    expect(face, hasLength(4));

    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 50);
    expect(bench(tester).papers, hasLength(1));
    expect(bench(tester).papers.single.area, closeTo(17 * 22, 1e-6));

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    Offset screen(Offset desk) =>
        bench(tester).origin + desk * bench(tester).scale;
    for (var i = 0; i < 4; i++) {
      await drag(tester, [screen(face[i]), screen(face[(i + 1) % 4])]);
    }
    expect(find.byKey(const ValueKey('craft-room-flight')), findsOneWidget);
    expect(hologram(tester).faces, isEmpty);
    expect(stowIcons(tester), inInclusiveRange(1, kScrapSlots));

    await frames(tester, 800);
    expect(find.byKey(const ValueKey('craft-room-flight')), findsNothing);
    expect(stowIcons(tester), 0);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);
    for (var i = 0; i < kScrapSlots; i++) {
      expect(
        find.descendant(
          of: find.byKey(Key('craft-room-slot-$i')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    await click(tester, _offCube);
    expect(hologram(tester).faces, isEmpty);
    await click(tester, _modelMiddle);
    expect(hologram(tester).faces, isEmpty);

    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 50);
    for (var i = 0; i < kScrapSlots; i++) {
      expect(
        find.descendant(
          of: find.byKey(Key('craft-room-slot-$i')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a saved group opens, inverts and goes to the trash, and the '
      'Snap tab switches a rule', (tester) async {
    final file = File(
      '${Directory.systemTemp.path}/craft_room_snap_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final snap = SnapSettings(file: file);
    addTearDown(snap.dispose);
    await open(tester, snap: snap);
    await reachBench(tester);

    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    final pick = await tester.startGesture(
      _modelMiddle,
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(tester, 300);
    expect(find.byKey(const Key('craft-room-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('craft-room-save')));
    await frames(tester, 50);
    expect(find.byKey(const Key('craft-room-save')), findsNothing);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsOneWidget);
    expect(find.text('Group A'), findsOneWidget);
    expect(find.byTooltip('Arrange'), findsOneWidget);

    final chip = find.byKey(const ValueKey('craft-room-group-A'));
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(chip);
    await frames(tester, 400);
    expect(hologram(tester).faces, hasLength(5));
    expect(find.byKey(const Key('craft-room-save')), findsOneWidget);

    await tester.tap(chip);
    await frames(tester, 400);
    expect(hologram(tester).faces, hasLength(1));
    await drag(tester, [
      tester.getCenter(chip),
      tester.getCenter(find.byKey(const Key('craft-room-trash'))),
    ]);
    await frames(tester, 50);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsNothing);
    expect(hologram(tester).faces, isEmpty);

    await tester.tap(find.byType(DevToolsButton));
    await frames(tester, 50);
    await tester.tap(find.byKey(const Key('craft-room-dev-tab-snap')));
    await frames(tester, 50);
    expect(
      tester.widget<Slider>(find.byKey(const Key('paper-grid-opacity'))).value,
      kPaperGridOpacity,
    );
    expect(
      snap.rules[SnapUser.straightCut].allows(SnapTarget.craftGrid),
      isTrue,
    );
    await tester.tap(find.byKey(const Key('snap-straightCut-craftGrid')));
    await frames(tester, 50);
    expect(
      snap.rules[SnapUser.straightCut].allows(SnapTarget.craftGrid),
      isFalse,
    );
    expect(file.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each group keeps its own desk, and acting on a selection '
      'makes it a group', (tester) async {
    await open(tester);
    await reachBench(tester);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);

    expect(find.byKey(const Key('craft-room-slot-0')), findsNothing);
    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 50);
    expect(paperIds(tester), ['paper-0']);
    expect(find.byKey(const Key('craft-room-slot-1')), findsOneWidget);
    final slot = tester.getCenter(find.byKey(const Key('craft-room-slot-1')));
    expect(slot.dx, greaterThan(700));
    expect(slot.dy, closeTo(_paneHeight + 16 + _paneHeight / 2, 24));
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsNothing);

    final pick = await tester.startGesture(
      _modelMiddle,
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(paperIds(tester), isEmpty);
    expect(find.byKey(const Key('craft-room-save')), findsOneWidget);
    expect(bench(tester).theme.desk, kCraftNoneTheme.desk);
    expect(bench(tester).theme.line, kCraftGroupAccents[0]);
    expect(hologram(tester).line, kCraftGroupAccents[0]);
    expect(hologram(tester).glow, craftGroupTheme(0).glow);

    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 400);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-save')), findsNothing);
    expect(paperIds(tester), ['paper-1']);
    expect(bench(tester).theme.accent, kCraftGroupAccents[0]);
    final chipAt = tester.getCenter(
      find.byKey(const ValueKey('craft-room-group-A')),
    );
    expect(chipAt.dx, greaterThan(700));
    expect(chipAt.dy, closeTo(_paneHeight / 2, 40));

    await click(tester, _offCube);
    expect(paperIds(tester), ['paper-0']);
    expect(hologram(tester).faces, isEmpty);
    await frames(tester, 400);
    expect(bench(tester).theme.desk, kCraftNoneTheme.desk);
    expect(hologram(tester).line, kCraftNoneTheme.line);

    await click(tester, _modelMiddle);
    expect(paperIds(tester), ['paper-1']);
    expect(find.byKey(const Key('craft-room-save')), findsNothing);
    expect(find.text('Group A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

int stowIcons(WidgetTester tester) => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('craft-room-stow-');
    })
    .evaluate()
    .length;

/// Empty sky beside the cube in the model's pane.
const Offset _offCube = Offset(140, 110);

Future<void> click(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await gesture.up();
  await frames(tester, 300);
}

List<String> paperIds(WidgetTester tester) => [
  for (final paper in bench(tester).papers) paper.id,
];

Future<void> open(WidgetTester tester, {SnapSettings? snap}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CraftRoomView(collection: _room, snapSettings: snap),
    ),
  );
  await frames(tester, 100);
}

Future<void> enterCube(WidgetTester tester) async {
  final tap = await tester.startGesture(
    _screenMiddle,
    kind: PointerDeviceKind.mouse,
  );
  await tap.up();
}

/// The orbit, the level load, and the divider's rise.
Future<void> reachBench(WidgetTester tester) async {
  await enterCube(tester);
  await frames(
    tester,
    kCraftFlyDuration.inMilliseconds +
        kLevelLoadDelay.inMilliseconds +
        kBenchTravelDuration.inMilliseconds +
        200,
  );
}

/// Height of the top pane: the room, or the craft once in it.
double topHeight(WidgetTester tester) {
  final room = find.byKey(const Key('craft-room-room'));
  final model = find.byKey(const Key('craft-room-model'));
  return tester.getSize(room.evaluate().isEmpty ? model : room).height;
}

Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> drag(WidgetTester tester, List<Offset> path) async {
  final gesture = await tester.startGesture(
    path.first,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  for (var leg = 1; leg < path.length; leg++) {
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(path[leg - 1], path[leg], i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await gesture.up();
  await frames(tester, 50);
}

CraftBenchPainter bench(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<CraftBenchPainter>()
    .single;

HologramPainter hologram(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<HologramPainter>()
    .single;
