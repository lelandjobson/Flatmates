import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flatmates/asmr/hologram_painter.dart';
import 'package:flatmates/craftroom/craft_bench_painter.dart';
import 'package:flatmates/craftroom/craft_theme.dart';
import 'package:flatmates/craftroom/room_crafts.dart';
import 'package:flatmates/craftroom/selection_group.dart';
import 'package:flatmates/craftroom/snap_rules.dart';
import 'package:flatmates/craftroom/workview.dart';
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/gridcraft/craft_collection_painter.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flatmates/gridcraft/model_painter.dart';
import 'package:flatmates/screens/craft_room_view.dart';
import 'package:flatmates/ui/game/dev_tools_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// 800 by 600. Both workviews fill the screen; the cube is in the middle.
const Offset _screenMiddle = Offset(400, 300);
const Offset _modelMiddle = _screenMiddle;

/// The inactive workview's opacity in these tests.
const double _inactive = 0.33;

/// One 3x3 cube in the middle of an empty room, the camera aimed at it.
final _room = CraftCollection(
  id: 'test-room',
  name: 'Test room',
  crafts: const [CraftSpot(puzzleId: kRoomCubeId, at: Offset.zero)],
  camera: CollectionCamera(at: Vector3(0, 0, 1.5), halfHeight: 8),
);

void main() {
  testWidgets('the desk workview fades in after the orbit, once the level has '
      'loaded, and fades out before the fly out', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);
    await enterCube(tester);

    // Still inside the 800 ms orbit.
    await frames(tester, 736);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);
    expect(find.byKey(const Key('craft-room-room')), findsOneWidget);

    // Orbit done, the level load still running.
    await frames(tester, 128);
    expect(find.byKey(const Key('craft-room-model')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);

    await frames(tester, 640);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);

    // The load has finished and the desk is fading in, under the model.
    await frames(tester, 192);
    expect(find.byKey(const Key('craft-room-desk')), findsOneWidget);
    final rising = look(tester, Workview.desk);
    expect(rising, greaterThan(0));
    expect(rising, lessThan(_inactive - 0.02));

    await frames(tester, 400);
    expect(find.byKey(const Key('craft-room-model')), findsOneWidget);
    expect(look(tester, Workview.desk), closeTo(_inactive, 1e-6));
    expect(look(tester, Workview.model), 1);
    expect(find.byTooltip('Select faces'), findsOneWidget);
    expect(find.byTooltip('Straight cut'), findsNothing);

    await tester.tap(find.byKey(const Key('craft-room-back')));
    await frames(tester, 16 * 5);
    expect(find.byKey(const Key('craft-room-desk')), findsOneWidget);
    expect(find.byKey(const Key('craft-room-room')), findsNothing);
    final falling = look(tester, Workview.desk);
    expect(falling, greaterThan(0));
    expect(falling, lessThan(_inactive));

    await frames(tester, 16 * 25);
    expect(find.byKey(const Key('craft-room-desk')), findsNothing);
    expect(find.byKey(const Key('craft-room-room')), findsOneWidget);

    await frames(tester, 900);
    expect(look(tester, Workview.model), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pinch in the room zooms and does not pan when a finger lifts', (
    tester,
  ) async {
    await open(tester);
    final before = roomCamera(tester);
    final lookAt = before.lookAt;
    final height = before.framedHalfHeightMm;

    final first = await tester.startGesture(const Offset(120, 300), pointer: 1);
    final second = await tester.startGesture(
      const Offset(520, 300),
      pointer: 2,
    );
    await second.moveTo(const Offset(200, 300));
    await second.up();
    // The finger still down drifts as the pinch lets go.
    await first.moveBy(const Offset(24, 16));
    await first.up();
    await frames(tester, 50);

    final after = roomCamera(tester);
    expect(after.lookAt, lookAt);
    expect(after.framedHalfHeightMm, greaterThan(height + 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pinch zooms about the middle and leaves the pan where it is', (
    tester,
  ) async {
    await open(tester);
    await reachBench(tester);
    final before = modelPainter(tester).camera;
    final lookAt = before.lookAt;
    final height = before.framedHalfHeightMm;

    final still = await tester.startGesture(const Offset(40, 200), pointer: 1);
    final moving = await tester.startGesture(
      const Offset(440, 200),
      pointer: 2,
    );
    await moving.moveTo(const Offset(120, 200));
    await moving.up();
    await still.up();
    await frames(tester, 50);

    final after = modelPainter(tester).camera;
    expect(after.lookAt, lookAt);
    expect(after.lookAtZ, before.lookAtZ);
    expect(after.framedHalfHeightMm, greaterThan(height + 1));

    await doubleTap(tester, _offCube);
    final origin = bench(tester).origin;
    final scale = bench(tester).scale;
    final center = (const Offset(400, 300) - origin) / scale;
    final held = await tester.startGesture(const Offset(120, 400), pointer: 1);
    final spreading = await tester.startGesture(
      const Offset(200, 400),
      pointer: 2,
    );
    await spreading.moveTo(const Offset(360, 400));
    await spreading.up();
    await held.up();
    await frames(tester, 50);

    final zoomed = bench(tester);
    expect(zoomed.scale, greaterThan(scale + 1));
    expect((const Offset(400, 300) - zoomed.origin) / zoomed.scale, center);

    final panned = zoomed.origin;
    final a = await tester.startGesture(const Offset(200, 400), pointer: 1);
    final b = await tester.startGesture(const Offset(280, 400), pointer: 2);
    await a.moveBy(const Offset(0, 40));
    await b.moveBy(const Offset(0, 40));
    await a.up();
    await b.up();
    await frames(tester, 50);
    expect(bench(tester).origin.dy, closeTo(panned.dy + 40, 0.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selecting a face zooms the inactive desk onto its blueprint', (
    tester,
  ) async {
    await open(tester);
    await reachBench(tester);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    final before = bench(tester).scale;

    final pick = await tester.startGesture(
      _modelMiddle,
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(tester, 96);
    final mid = bench(tester).scale;
    expect(mid, greaterThan(before + 1));
    expect(look(tester, Workview.desk), closeTo(_inactive, 1e-6));

    await frames(tester, 250);
    final holo = hologram(tester);
    final box = _screenBox(holo);
    const pad = kBlueprintFramePad;
    expect(box.left, greaterThanOrEqualTo(pad - 1.5));
    expect(box.top, greaterThanOrEqualTo(pad - 1.5));
    expect(box.right, lessThanOrEqualTo(800 - pad + 1.5));
    expect(box.bottom, lessThanOrEqualTo(600 - pad + 1.5));
    expect(box.height, closeTo(600 - 2 * pad, 1.5));
    expect(box.width, closeTo(box.height, 1.5));
    expect(box.center.dx, closeTo(400, 1.5));
    expect(box.center.dy, closeTo(300, 1.5));
    expect(holo.scale, greaterThan(mid));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a double-tap on empty space switches the active workview', (
    tester,
  ) async {
    await open(tester);
    await reachBench(tester);
    expect(look(tester, Workview.model), 1);

    // On the cube: geometry, not empty space.
    await doubleTap(tester, _modelMiddle);
    expect(look(tester, Workview.model), 1);

    // Too far apart.
    await doubleTap(tester, _offCube, second: const Offset(60, 0));
    expect(look(tester, Workview.model), 1);

    // Too slow.
    await doubleTap(tester, _offCube, gapMs: 520);
    expect(look(tester, Workview.model), 1);

    // Two fingers at once, twice.
    for (var i = 0; i < 2; i++) {
      final a = await tester.startGesture(_offCube, pointer: 7);
      final b = await tester.startGesture(
        _offCube + const Offset(4, 0),
        pointer: 8,
      );
      await a.up();
      await b.up();
      await frames(tester, 48);
    }
    await frames(tester, 400);
    expect(look(tester, Workview.model), 1);

    await doubleTap(tester, _offCube);
    expect(look(tester, Workview.desk), 1);
    expect(look(tester, Workview.model), closeTo(_inactive, 1e-6));
    expect(find.byTooltip('Straight cut'), findsOneWidget);
    expect(find.byTooltip('Select faces'), findsNothing);
    expect(find.byKey(const Key('craft-room-paper')), findsOneWidget);

    await doubleTap(tester, _offCube);
    expect(look(tester, Workview.model), 1);
    expect(look(tester, Workview.desk), closeTo(_inactive, 1e-6));
    expect(find.byKey(const Key('craft-room-paper')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Workviews tab sets how the inactive workview is drawn', (
    tester,
  ) async {
    final looks = workviews();
    await open(tester, looks: looks);
    await reachBench(tester);

    await tester.tap(find.byType(DevToolsButton));
    await frames(tester, 50);
    await tester.tap(find.byKey(const Key('craft-room-dev-tab-workviews')));
    await frames(tester, 50);
    final opacity = find.byKey(const Key('workview-opacity'));
    expect(tester.widget<Slider>(opacity).value, closeTo(_inactive, 1e-6));
    tester.widget<Slider>(opacity).onChanged!(0.6);
    tester.widget<Slider>(find.byKey(const Key('workview-blur'))).onChanged!(8);
    await frames(tester, 50);
    expect(looks.opacity, 0.6);
    expect(looks.blur, 8);
    expect(look(tester, Workview.desk), closeTo(0.6, 1e-6));
    final filtered = tester.widget<ImageFiltered>(
      find.descendant(
        of: find.byKey(const ValueKey('craft-room-workview-desk')),
        matching: find.byType(ImageFiltered),
      ),
    );
    expect(filtered.enabled, isTrue);
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

    // A tap on the sky with Select faces would clear the selection, so
    // switch to the desk from Orbit.
    await tester.tap(find.byTooltip('Orbit'));
    await frames(tester, 50);
    await doubleTap(tester, _offCube);
    expect(hologram(tester).faces, hasLength(1));

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
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsNothing);

    await frames(tester, 800);
    expect(find.byKey(const ValueKey('craft-room-flight')), findsNothing);
    expect(stowIcons(tester), 0);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);
    expect(look(tester, Workview.model), 1);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    await click(tester, _offCube);
    expect(hologram(tester).faces, isEmpty);
    await click(tester, _modelMiddle);
    expect(hologram(tester).faces, isEmpty);

    await frames(tester, 400);
    await doubleTap(tester, _offCube);
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
    await frames(tester, 400);
    expect(find.byKey(const Key('craft-room-save')), findsNothing);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsOneWidget);
    expect(look(tester, Workview.desk), 1);
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

    // The open group's chip hides it and returns to the model. From the
    // model, the same chip brings the desk back with that group showing.
    await tester.tap(chip);
    await frames(tester, 800);
    expect(look(tester, Workview.model), 1);
    expect(hologram(tester).faces, isEmpty);
    await tester.tap(chip);
    await frames(tester, 800);
    expect(look(tester, Workview.desk), 1);
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
    await doubleTap(tester, _offCube);

    expect(find.byKey(const Key('craft-room-slot-0')), findsNothing);
    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 50);
    expect(paperIds(tester), ['paper-0']);
    expect(find.byKey(const Key('craft-room-slot-1')), findsOneWidget);
    final slot = tester.getCenter(find.byKey(const Key('craft-room-slot-1')));
    expect(slot.dx, greaterThan(700));
    expect(slot.dy, closeTo(408, 24));
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsNothing);

    await doubleTap(tester, _offCube);
    final pick = await tester.startGesture(
      _modelMiddle,
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(paperIds(tester), isEmpty);
    expect(find.byKey(const Key('craft-room-save')), findsOneWidget);
    expect(bench(tester).theme.desk, kCraftNoneTheme.desk);
    expect(bench(tester).theme.line, kCraftNoneTheme.line);
    expect(hologram(tester).line, kCraftNoneTheme.line);
    expect(hologram(tester).glow, kCraftNoneTheme.glow);
    expect(hologram(tester).vertex, kCraftGroupAccents[0]);

    await tester.tap(find.byTooltip('Orbit'));
    await frames(tester, 50);
    await doubleTap(tester, _offCube);
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
    expect(chipAt.dy, closeTo(170, 40));

    // The sheet fills the screen once the blueprint is framed, so pull back
    // until empty desk shows before switching workviews.
    await zoomDeskOut(tester);
    await doubleTap(tester, _offCube);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    await click(tester, _offCube);
    expect(paperIds(tester), ['paper-0']);
    expect(hologram(tester).faces, isEmpty);
    await frames(tester, 400);
    expect(bench(tester).theme.desk, kCraftNoneTheme.desk);
    expect(hologram(tester).line, kCraftNoneTheme.line);
    expect(hologram(tester).vertex.a, 0);

    await click(tester, _modelMiddle);
    expect(paperIds(tester), ['paper-1']);
    expect(find.byKey(const Key('craft-room-save')), findsNothing);
    await tester.tap(find.byTooltip('Orbit'));
    await frames(tester, 50);
    await doubleTap(tester, _offCube);
    expect(find.text('Group A'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tools sit above undo, paper is a centered plus, and the '
      'trash follows the selection', (tester) async {
    await open(tester);
    await reachBench(tester);
    expect(find.textContaining('Cut freely'), findsNothing);
    expect(find.textContaining('Drag to turn'), findsNothing);

    final select = tester.getCenter(find.byTooltip('Select faces'));
    final undo = tester.getCenter(find.byKey(const Key('craft-room-undo')));
    expect(select.dy, lessThan(undo.dy - 8));
    expect(trashColor(tester), Colors.white24);

    await doubleTap(tester, _offCube);
    expect(find.textContaining('Cut freely'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('craft-room-paper')),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byKey(const Key('craft-room-paper'))).dx,
      closeTo(400, 12),
    );
    final exacto = tester.getCenter(find.byTooltip('Exacto'));
    expect(exacto.dy, lessThan(undo.dy - 8));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('craft-room-tools-desk')),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(trashColor(tester), Colors.white24);

    await tester.tap(find.byKey(const Key('craft-room-paper')));
    await frames(tester, 50);
    expect(trashColor(tester), Colors.white);
    await tester.tap(find.byKey(const Key('craft-room-trash')));
    await frames(tester, 50);
    expect(paperIds(tester), isEmpty);
    expect(trashColor(tester), Colors.white24);

    await tester.tap(find.byTooltip('Exacto'));
    await frames(tester, 50);
    expect(find.textContaining('Cut freely'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('portrait tools wrap from the top left and grow downward', (
    tester,
  ) async {
    const size = Size(400, 800);
    await open(tester, size: size);
    final middle = size.center(Offset.zero);
    final tap = await tester.startGesture(
      middle,
      kind: PointerDeviceKind.mouse,
    );
    await tap.up();
    await frames(
      tester,
      kCraftFlyDuration.inMilliseconds +
          kLevelLoadDelay.inMilliseconds +
          kDeskFadeDuration.inMilliseconds +
          200,
    );
    await doubleTap(tester, const Offset(24, 180));

    final select = tester.getCenter(find.byTooltip('Select'));
    final folder = tester.getCenter(find.byTooltip('Folder'));
    expect(folder.dy, greaterThan(select.dy + 24));
    expect(folder.dx, closeTo(select.dx, 4));
    final edge = tester.getCenter(find.byTooltip('Straight edge'));
    expect(edge.dy, closeTo(folder.dy, 4));
    expect(edge.dx, greaterThan(folder.dx + 20));
    expect(
      tester.getCenter(find.byKey(const Key('craft-room-paper'))).dx,
      closeTo(size.width / 2, 12),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a quick double-tap saves the selection and opens the desk', (
    tester,
  ) async {
    await open(tester);
    await reachBench(tester);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    await click(tester, _modelMiddle);
    expect(hologram(tester).faces, hasLength(1));

    await doubleTap(tester, _offCube);
    expect(look(tester, Workview.desk), 1);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsOneWidget);
    expect(hologram(tester).faces, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a slow second tap clears the selection, and Save opens the desk', (
    tester,
  ) async {
    await open(tester);
    await reachBench(tester);
    await tester.tap(find.byTooltip('Select faces'));
    await frames(tester, 50);
    await click(tester, _modelMiddle);

    await doubleTap(tester, _offCube, gapMs: 520);
    expect(look(tester, Workview.model), 1);
    expect(hologram(tester).faces, isEmpty);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsNothing);

    await click(tester, _modelMiddle);
    await tester.tap(find.byKey(const Key('craft-room-save')));
    await frames(tester, 400);
    expect(look(tester, Workview.desk), 1);
    expect(find.byKey(const ValueKey('craft-room-group-A')), findsOneWidget);
    expect(hologram(tester).faces, hasLength(1));
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

/// Empty sky beside the cube, and empty desk beside the paper.
const Offset _offCube = Offset(140, 110);

Color trashColor(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('craft-room-trash')),
        matching: find.byIcon(Icons.delete_outline),
      ),
    )
    .color!;

Future<void> click(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await gesture.up();
  await frames(tester, 300);
}

/// Two clicks [gapMs] apart, the second [second] from the first, then
/// time for the switch to finish.
Future<void> doubleTap(
  WidgetTester tester,
  Offset at, {
  Offset second = Offset.zero,
  int gapMs = 48,
}) async {
  final first = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await first.up();
  await frames(tester, gapMs);
  final next = await tester.startGesture(
    at + second,
    kind: PointerDeviceKind.mouse,
  );
  await next.up();
  await frames(tester, 400);
}

/// The opacity [view] is drawn at.
double look(WidgetTester tester, Workview view) => tester
    .widget<Opacity>(find.byKey(ValueKey('craft-room-workview-${view.name}')))
    .opacity;

List<String> paperIds(WidgetTester tester) => [
  for (final paper in bench(tester).papers) paper.id,
];

WorkviewSettings workviews() {
  final file = File(
    '${Directory.systemTemp.path}/craft_room_workviews_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  final looks = WorkviewSettings(file: file, opacity: _inactive);
  addTearDown(looks.dispose);
  return looks;
}

Future<void> open(
  WidgetTester tester, {
  SnapSettings? snap,
  WorkviewSettings? looks,
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CraftRoomView(
        collection: _room,
        snapSettings: snap,
        workviewSettings: looks ?? workviews(),
      ),
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

/// The orbit, the level load, and the desk's fade in.
Future<void> reachBench(WidgetTester tester) async {
  await enterCube(tester);
  await frames(
    tester,
    kCraftFlyDuration.inMilliseconds +
        kLevelLoadDelay.inMilliseconds +
        kDeskFadeDuration.inMilliseconds +
        200,
  );
}

/// Pinches the desk down so a sheet framed on a face no longer covers
/// the corner used as empty space.
Future<void> zoomDeskOut(WidgetTester tester) async {
  final held = await tester.startGesture(const Offset(200, 280), pointer: 1);
  final closing = await tester.startGesture(const Offset(600, 280), pointer: 2);
  await closing.moveTo(const Offset(230, 280));
  await closing.up();
  await held.up();
  await frames(tester, 50);
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

PapercutCamera roomCamera(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<CraftCollectionPainter>()
    .single
    .camera;

ModelPainter modelPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<ModelPainter>()
    .single;

CraftBenchPainter bench(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<CraftBenchPainter>()
    .single;

Rect _screenBox(HologramPainter holo) {
  var left = double.infinity;
  var top = double.infinity;
  var right = -double.infinity;
  var bottom = -double.infinity;
  for (final ring in holo.faces) {
    for (final point in ring) {
      final screen = holo.origin + point * holo.scale;
      left = math.min(left, screen.dx);
      top = math.min(top, screen.dy);
      right = math.max(right, screen.dx);
      bottom = math.max(bottom, screen.dy);
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

HologramPainter hologram(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<HologramPainter>()
    .single;
