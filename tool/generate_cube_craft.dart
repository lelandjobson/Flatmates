// Writes assets/craft_viewer/craft_Cube from cubeBlueprint(), and
// assets/craft_viewer/craft_BoxStack plus levels/boxes/box-stack.json from
// boxStackBlueprint().
//
// The generator needs dart:ui, so run it through the Flutter test runner:
//   flutter test tool/generate_cube_craft.dart
import 'dart:io';

import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flutter_test/flutter_test.dart';

void _writeCraft(String path, String json, String obj) {
  final directory = Directory(path)..createSync(recursive: true);
  File('${directory.path}/craft.json').writeAsStringSync(json);
  File('${directory.path}/folded.obj').writeAsStringSync(obj);
}

void main() {
  test('write $kCubeCraftId', () {
    _writeCraft(kCubeCraftDirectory, cubeCraftJsonText(), cubeCraftObj());
  });

  test('write $kBoxStackCraftId', () {
    _writeCraft(
      kBoxStackCraftDirectory,
      boxStackCraftJsonText(),
      boxStackCraftObj(),
    );
    File(kBoxStackLevelPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(boxStackLevelJsonText());
  });
}
