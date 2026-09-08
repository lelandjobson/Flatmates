import 'package:flatmates/ui/game/view_crosshair.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crosshair painter repaints when morph changes', () {
    final circle = CrosshairPainter(
      diameter: 14,
      strokeWidth: 3.5,
      color: const Color(0xF2FFFFFF),
      morph: 0,
    );
    final cross = CrosshairPainter(
      diameter: 14,
      strokeWidth: 3.5,
      color: const Color(0xF2FFFFFF),
      morph: 1,
    );
    expect(cross.shouldRepaint(circle), isTrue);
    expect(circle.shouldRepaint(circle), isFalse);
  });

  testWidgets('crosshair animates toward an X when not selectable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ViewCrosshair(selectable: true),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ViewCrosshair(selectable: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(ViewCrosshair), findsOneWidget);
  });
}
