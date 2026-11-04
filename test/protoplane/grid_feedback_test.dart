import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/stroke_color_picker.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  test(
    'connection styles restrict neighbor edges and explicitly mark every dot',
    () {
      final orth = lattice('orth', rectangle(1, 1));
      final diagonal = lattice(
        'diagonal',
        rectangle(1, 1),
        connections: GridConnections.diagonal,
      );
      final any = lattice(
        'any',
        rectangle(1, 1),
        connections: GridConnections.arbitrary,
      );
      expect(orth.edges.length, 12);
      expect(diagonal.edges.length, 20);
      expect(any.edges.length, 36);
      expect(orth.connection(0, 4), isNull);
      expect(diagonal.connection(0, 4), isNotNull);
      expect(diagonal.connection(0, 5), isNull);
      expect(any.connection(0, 5), isNotNull);
      expect([
        for (var i = 0; i < 9; i++) diagonal.dotStyle(i),
      ], everyElement('circle'));
      expect(orth.dotStyle(4), 'square');
      expect(any.dotStyle(4), 'star');
      expect(CraftGrid.fromJson(diagonal.toJson()).dotStyle(4), 'circle');
    },
  );
  test(
    'changing default connections keeps node indices and construction, and survives history/load',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final points = c.planes['ground-4-4']!.grids.first.nodes.toList();
      final balances = Map.of(c.balances);
      c.enter('ground-4-4');
      c.beginGesture();
      c.appendNode(0);
      c.appendNode(1);
      c.setProtoplaneConnections(GridConnections.diagonal);
      expect(c.draft.path, isEmpty);
      expect(c.balances, balances);
      expect(c.grid!.nodes, points);
      expect(c.grid!.dotStyle(4), 'circle');
      expect(
        c.grid!.edges.any((e) {
          final d = c.grid!.nodes[e.a] - c.grid!.nodes[e.b];
          return d.dx.abs() > .01 && d.dy.abs() > .01;
        }),
        isTrue,
      );
      c.beginGesture();
      for (final i in [0, 2, 8, 6, 0]) {
        c.appendNode(i);
      }
      c.commitDrawing();
      c.undo();
      expect(c.grid!.dotStyle(4), 'circle');
      c.redo();
      final saved = c.toJson();
      final loaded = ProtoplaneController()..load(saved);
      addTearDown(loaded.dispose);
      expect(loaded.toJson(), saved);
      expect(loaded.planes['ground-4-4']!.grids.first.dotStyle(4), 'circle');
      expect(
        loaded.planes['ground-4-4']!.grids.first.edges.length,
        c.grid!.edges.length,
      );
      c.setProtoplaneConnections(GridConnections.arbitrary);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.grid!.dotStyle(4), 'star');
      expect(c.landscape.depleted('ground-4-4'), isEmpty);
      c.redo();
      expect(c.grid!.dotStyle(4), 'star');
      expect(c.landscape.depleted('ground-4-4'), isNotEmpty);
    },
  );
  test('color and connection preferences migrate and persist', () {
    final settings = ProtoplaneSettings();
    expect(settings.lineColor, const Color(0xff7fff00));
    expect(settings.gridConnections, GridConnections.orthogonal);
    final old = settings.toJson()
      ..remove('lineColor')
      ..remove('gridConnections');
    settings.load(old);
    expect(settings.lineColor, const Color(0xff7fff00));
    settings.lineColor = const Color(0xff123abc);
    settings.gridConnections = GridConnections.arbitrary;
    final loaded = ProtoplaneSettings()..load(settings.toJson());
    expect(loaded.toJson(), settings.toJson());
    expect(() => loaded.load({...old, 'lineColor': 0}), throwsFormatException);
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('dot growth, selected color and arbitrary picker at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final c = ProtoplaneController();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        c.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const ValueKey('dots'),
            child: ProtoplaneConceptView(controller: c),
          ),
        ),
      );
      c.enter('ground-4-4');
      await tester.pumpAndSettle();
      Future<void> capture(String stage) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('dots')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/crafting-dots-${size.width.toInt()}-$stage.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('idle');
      c.beginGesture();
      c.appendNode(0);
      c.appendNode(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await capture('selected');
      final held = c.draft.path.toList();
      await tester.pump(const Duration(seconds: 1));
      expect(c.draft.path, held);
      c.cancelGesture();
      await tester.pumpAndSettle();
      await capture('reset');
      Color selected = const Color(0xff7fff00);
      final context = tester.element(find.byType(ProtoplaneConceptView));
      final dialog = showStrokeColorPicker(
        context,
        selected,
        (color) => selected = color,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3366FF');
      await tester.pump();
      expect(selected, const Color(0xff3366ff));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await dialog;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
