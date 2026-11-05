import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'construction_fixture.dart';

void main() {
  testWidgets(
    'safe zone fill adjusts the focused camera live without changing world',
    (tester) async {
      const size = Size(900, 700);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final c = constructionWorld();
      addTearDown(() {
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(home: ProtoplaneConceptView(controller: c)),
      );
      await tester.pumpAndSettle();
      c.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Camera'));
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      final fill = find.byKey(const ValueKey('Safe zone fill'));
      await tester.scrollUntilVisible(
        fill,
        70,
        scrollable: find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text('Safe zone'),
                    matching: find.byType(ListView),
                  )
                  .first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Rect bounds() {
        final points = c.activePlane!.region.outer
            .map((p) => camera.projectToScreen(c.activePlane!.point(p), size)!)
            .toList();
        var r = Rect.fromPoints(points.first, points.first);
        for (final p in points) {
          r = r.expandToInclude(Rect.fromPoints(p, p));
        }
        return r;
      }

      final before = bounds(), world = c.toJson();
      await tester.tapAt(tester.getRect(fill).centerLeft + const Offset(1, 0));
      await tester.pumpAndSettle();
      final settings = tester
          .widget<ProtoplaneDevToolsPanel>(find.byType(ProtoplaneDevToolsPanel))
          .settings;
      final after = bounds();
      expect(settings.safeZoneFill, closeTo(.5, .02));
      expect(after.width / before.width, closeTo(settings.safeZoneFill, .01));
      expect(after.height / before.height, closeTo(settings.safeZoneFill, .01));
      expect((after.center - before.center).distance, lessThan(.1));
      expect(c.toJson(), world);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
