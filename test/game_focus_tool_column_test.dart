import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/picking/focus_sticker.dart';
import 'package:flatmates/ui/game/game_focus_tool_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed paint column shows a colored brush', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameFocusToolColumn(
            surface: FocusWorkSurface.facade,
            paintExpanded: false,
            onTogglePaintGroup: () {},
            stickerExpanded: false,
            onToggleStickerGroup: () {},
            paintActive: false,
            onTogglePaint: () {},
            fillActive: false,
            onToggleFill: () {},
            eraseActive: false,
            onToggleErase: () {},
            paintColor: PaperColor.pink,
            onPaintColor: (_) {},
            selectedSticker: null,
            onSelectSticker: (_) {},
            telephoto: false,
            onToggleTelephoto: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.brush), findsOneWidget);
    expect(find.byIcon(Icons.format_color_fill), findsNothing);
    expect(find.byIcon(Icons.door_front_door_outlined), findsNothing);
  });

  testWidgets('expanded wall tools hide the sticker column', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameFocusToolColumn(
            surface: FocusWorkSurface.facade,
            paintExpanded: false,
            onTogglePaintGroup: () {},
            stickerExpanded: true,
            onToggleStickerGroup: () {},
            paintActive: false,
            onTogglePaint: () {},
            fillActive: false,
            onToggleFill: () {},
            eraseActive: false,
            onToggleErase: () {},
            paintColor: PaperColor.green,
            onPaintColor: (_) {},
            selectedSticker: null,
            onSelectSticker: (_) {},
            telephoto: false,
            onToggleTelephoto: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.door_front_door_outlined), findsNothing);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsNothing);
  });

  testWidgets('expanded paint column shows fill, erase, and colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameFocusToolColumn(
            surface: FocusWorkSurface.floor,
            paintExpanded: true,
            onTogglePaintGroup: () {},
            stickerExpanded: true,
            onToggleStickerGroup: () {},
            paintActive: true,
            onTogglePaint: () {},
            fillActive: false,
            onToggleFill: () {},
            eraseActive: false,
            onToggleErase: () {},
            paintColor: PaperColor.yellow,
            onPaintColor: (_) {},
            selectedSticker: null,
            onSelectSticker: (_) {},
            telephoto: false,
            onToggleTelephoto: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.format_color_fill), findsOneWidget);
    expect(find.byIcon(Icons.auto_fix_off), findsOneWidget);
    expect(find.byIcon(Icons.bed_outlined), findsNothing);
    expect(find.byIcon(Icons.weekend_outlined), findsNothing);
  });
}
