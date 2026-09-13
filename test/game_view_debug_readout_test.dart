import 'package:flatmates/ui/game/game_view_debug_readout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readout waits for a wide enough window', () {
    expect(gameViewDebugReadoutFits(const Size(719, 800)), isFalse);
    expect(gameViewDebugReadoutFits(const Size(800, 519)), isFalse);
    expect(gameViewDebugReadoutFits(const Size(720, 520)), isTrue);
  });

  testWidgets('each line is its own row and ignores pointers', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => tapped = true,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
            const GameViewDebugReadout(
              lines: ['map3d', 'unlocked', 'tile (4, 1)'],
            ),
          ],
        ),
      ),
    );
    expect(find.text('map3d'), findsOneWidget);
    expect(find.text('unlocked'), findsOneWidget);
    expect(find.text('tile (4, 1)'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('map3d')));
    expect(tapped, isTrue);
  });
}
