import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stepped wraps around the tool row', () {
    expect(GameMapTool.select.stepped(1), GameMapTool.volume);
    expect(GameMapTool.volume.stepped(1), GameMapTool.path);
    expect(GameMapTool.delete.stepped(1), GameMapTool.select);
    expect(GameMapTool.select.stepped(-1), GameMapTool.delete);
    expect(GameMapTool.wall.stepped(-1), GameMapTool.path);
  });
}
