import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'surface_fixture.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'Paper drags never place and tools switch without construction for $kind',
      (tester) async {
        final c = surfaceRoomWorld();
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(controller: c, animateFog: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('construction-paper')));
        await tester.pumpAndSettle();
        final before = c.toJson();
        final gesture = await tester.createGesture(kind: kind);
        await gesture.down(const Offset(400, 300));
        await gesture.moveBy(const Offset(80, 0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(c.toJson(), before);
        await tester.tap(find.byKey(const ValueKey('construction-pencil')));
        await tester.pumpAndSettle();
        expect(c.constructionTool, ConstructionTool.pencil);
        await tester.tap(find.byKey(const ValueKey('construction-pencil')));
        await tester.pumpAndSettle();
        expect(c.constructionTool, isNull);
        expect(c.objects, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
