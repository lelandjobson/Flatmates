import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'construction_fixture.dart';
import 'release_completion_test.dart' show loop;

void main() {
  test('scissors never fall through to placement on cleared ground', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.selectTool(CraftTool.scissors);
    c.beginGesture();
    loop(c);
    final before = c.toJson();
    expect(c.previewObject, isNull);
    expect(c.drawingReady, isFalse);
    expect(c.create(), isFalse);
    expect(c.completeCraft(), isFalse);
    expect(c.commitDrawing(), isNull);
    expect(c.toJson(), before);
    expect(c.objects, isEmpty);
    c.cancelGesture();
    c.selectTool(CraftTool.place);
    c.beginGesture();
    loop(c);
    expect(c.commitDrawing(), isNotNull);
    expect(c.objects, hasLength(1));
  });
  test(
    'cut and addition colors persist independently with legacy migration',
    () {
      final s = ProtoplaneSettings();
      expect(s.cutLineColor, const Color(0xffff4040));
      expect(s.lineColor, const Color(0xff7fff00));
      s.cutLineColor = Colors.redAccent;
      s.lineColor = Colors.lime;
      final restored = ProtoplaneSettings()..load(s.toJson());
      expect(restored.cutLineColor.toARGB32(), Colors.redAccent.toARGB32());
      expect(restored.lineColor.toARGB32(), Colors.lime.toARGB32());
      final old = s.toJson()..remove('cutLineColor');
      restored.load(old);
      expect(restored.cutLineColor, const Color(0xffff4040));
      expect(restored.lineColor.toARGB32(), Colors.lime.toARGB32());
    },
  );
  for (final scissors in [false, true]) {
    testWidgets(
      'invalid ${scissors ? 'cut' : 'overlapping addition'} fades without a candidate panel',
      (tester) async {
        final c = constructionWorld();
        addTearDown(c.dispose);
        c.enter('ground-starter-paperWhite-0-0');
        c.beginGesture();
        loop(c);
        c.commitDrawing();
        c.leave();
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(animateFog: false, controller: c),
          ),
        );
        await tester.pumpAndSettle();
        c.enter('ground-starter-paperWhite-0-0');
        c.selectTool(scissors ? CraftTool.scissors : CraftTool.place);
        await tester.pumpAndSettle();
        final scene = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene;
        final viewport = tester.getSize(find.byType(SceneView).first);
        Offset point(int i) => scene.camera!.projectToScreen(
          c.activePlane!.point(c.grid!.nodes[i], .008),
          viewport,
        )!;
        final before = c.toJson();
        final finger = await tester.startGesture(point(0));
        for (final i in [2, 8, 6, 0]) {
          await finger.moveTo(point(i));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(c.drawingReady, isFalse);
        expect(find.text('Floor'), findsNothing);
        dynamic painter() => tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('craft-grid-overlay')),
            )
            .painter;
        expect(
          painter().lineColor,
          scissors ? const Color(0xffff4040) : const Color(0xff7fff00),
        );
        await finger.up();
        await tester.pump();
        expect(c.draft.path, isEmpty);
        expect(c.error, isNull);
        expect(c.toJson(), before);
        expect(find.text('Floor'), findsNothing);
        expect(painter().traceOverride, isNotEmpty);
        await tester.pump(const Duration(milliseconds: 375));
        expect(painter().lineOpacity, greaterThan(0));
        expect(painter().lineOpacity, lessThan(1));
        await tester.pump(const Duration(milliseconds: 400));
        expect(painter().lineOpacity, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
