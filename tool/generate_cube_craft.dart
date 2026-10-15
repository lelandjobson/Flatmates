// Writes assets/craft_viewer/craft_Cube from cubeBlueprint().
//
// The generator needs dart:ui, so run it through the Flutter test runner:
//   flutter test tool/generate_cube_craft.dart
import 'dart:io';

import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('write $kCubeCraftId', () {
    final directory = Directory(kCubeCraftDirectory)
      ..createSync(recursive: true);
    File('${directory.path}/craft.json').writeAsStringSync(cubeCraftJsonText());
    File('${directory.path}/folded.obj').writeAsStringSync(cubeCraftObj());
  });
}
