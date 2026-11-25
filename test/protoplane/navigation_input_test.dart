import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

import 'construction_fixture.dart';

void main() {
  testWidgets(
    'trackpad pinch still exits crafting without selecting a neighbor',
    (tester) async {
      final model = constructionWorld();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(animateFog: false, controller: model),
        ),
      );
      await tester.pumpAndSettle();
      model.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      const at = Offset(300, 300);
      await gesture.panZoomStart(at);
      await gesture.panZoomUpdate(at, pan: const Offset(150, 0), scale: .7);
      await tester.pumpAndSettle();
      expect(model.activePlaneId, isNull);
      await gesture.panZoomEnd();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
