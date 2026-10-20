import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flatmates/asmr/asmr_desk_painter.dart';
import 'package:flatmates/screens/asmr_split_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 800 by 600 with a 16 pixel divider: each pane starts 292 tall, the desk
/// pane from 308 down, with its middle, desk point (0, 0), at (400, 454).
const double _splitHeight = 584;
const Offset _deskMiddle = Offset(400, 454);
const Offset _modelMiddle = Offset(400, 146);

void main() {
  test('neither pane goes under 15% of the split', () {
    expect(asmrSplitFraction(0.02), kAsmrSplitMin);
    expect(asmrSplitFraction(0.98), 1 - kAsmrSplitMin);
    expect(asmrSplitFraction(0.4), 0.4);
  });

  testWidgets('the handle slides the divider and stops at 15%', (tester) async {
    await open(tester);
    final model = find.byKey(const Key('asmr-split-model'));
    expect(tester.getSize(model).height, closeTo(_splitHeight / 2, 0.5));

    final handle = find.byKey(const Key('asmr-split-handle'));
    await slide(tester, tester.getCenter(handle), const Offset(0, -500));
    expect(
      tester.getSize(model).height,
      closeTo(_splitHeight * kAsmrSplitMin, 0.5),
    );
    await slide(tester, tester.getCenter(handle), const Offset(0, 900));
    expect(
      tester.getSize(model).height,
      closeTo(_splitHeight * (1 - kAsmrSplitMin), 0.5),
    );
    await slide(tester, tester.getCenter(handle), const Offset(0, -200));
    expect(
      tester.getSize(model).height,
      closeTo(_splitHeight * (1 - kAsmrSplitMin) - 200, 0.5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cut over the guide stays on the desk', (tester) async {
    await open(tester);
    await pickFace(tester);
    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 50);
    await tester.tap(find.byTooltip('Straight cut'));
    await frames(tester, 50);
    await drag(tester, [const Offset(300, 454), const Offset(500, 454)]);
    expect(desk(tester).pieces, hasLength(2));
    for (final piece in desk(tester).pieces) {
      expect(piece.binding, isNull);
    }
    await frames(tester, 500);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('asmr-flight')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a piece dragged across flies to where it lay when it was picked up',
    (tester) async {
      final file = File(
        '${Directory.systemTemp.path}/asmr_split_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      await open(tester, sessionFile: file);
      await pickFace(tester);
      await tester.tap(find.byTooltip('Mint dots'));
      await frames(tester, 50);
      await tester.tap(find.byTooltip('Select'));
      await frames(tester, 50);

      final gesture = await tester.startGesture(
        _deskMiddle,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset.lerp(_deskMiddle, const Offset(150, 454), i / 10)!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(desk(tester).pieces.single.position.dx, lessThan(-150));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          Offset.lerp(const Offset(150, 454), const Offset(150, 150), i / 10)!,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(desk(tester).pieces, isEmpty);
      expect(find.byKey(const ValueKey('asmr-flight')), findsOneWidget);
      await gesture.up();
      await frames(tester, 600);
      expect(find.byKey(const ValueKey('asmr-flight')), findsNothing);
      expect(find.text('Faces filled  1 / 6'), findsOneWidget);

      await tester.tap(find.byKey(const Key('asmr-save')));
      await frames(tester, 50);
      final saved = jsonDecode(file.readAsStringSync()) as Map;
      final piece = (saved['pieces'] as List).single as Map;
      expect(piece['binding'], isNotEmpty);
      final position = piece['position'] as List;
      expect((position[0] as num).abs(), lessThan(1e-6));
      expect((position[1] as num).abs(), lessThan(1e-6));

      await tester.tap(find.byKey(const Key('asmr-undo')));
      await frames(tester, 50);
      expect(desk(tester).pieces, hasLength(1));
      expect(desk(tester).pieces.single.binding, isNull);
      expect(find.text('Faces filled  0 / 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a piece that missed the guide goes back to the desk', (
    tester,
  ) async {
    await open(tester);
    await pickFace(tester);
    await tester.tap(find.byTooltip('Mint dots'));
    await frames(tester, 50);
    await tester.tap(find.byTooltip('Select'));
    await frames(tester, 50);
    const aside = Offset(240, 454);
    await drag(tester, [_deskMiddle, aside]);
    final home = desk(tester).pieces.single.position;
    expect(home.dx, lessThan(-120));

    await drag(tester, [aside, const Offset(240, 150)]);
    await frames(tester, 500);
    final piece = desk(tester).pieces.single;
    expect(piece.binding, isNull);
    expect((piece.position - home).distance, lessThan(0.5));
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('asmr-flight')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> open(WidgetTester tester, {File? sessionFile}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AsmrSplitView(sessionFile: sessionFile)),
  );
  await frames(tester, 300);
}

/// Takes the face in the middle of the model pane.
Future<void> pickFace(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Select faces'));
  await frames(tester, 50);
  final pick = await tester.startGesture(
    _modelMiddle,
    kind: PointerDeviceKind.mouse,
  );
  await pick.up();
  await frames(tester, 300);
  final reticle = find.byKey(const ValueKey('asmr-crosshair'));
  expect(tester.getCenter(reticle), _modelMiddle);
  final net = desk(tester).blueprint!;
  expect(net.faces, hasLength(1));
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

Future<void> slide(WidgetTester tester, Offset from, Offset by) async {
  final gesture = await tester.startGesture(from);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(from + by * (i / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await frames(tester, 50);
}

AsmrDeskPainter desk(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<AsmrDeskPainter>()
    .single;
