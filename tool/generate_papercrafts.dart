// Writes each design in papercraftDesigns() to assets/craft_viewer/<craft>/
// and its level to levels/papercraft/<puzzle>.json.
//
// The generator needs dart:ui, so run it through the Flutter test runner:
//   flutter test tool/generate_papercrafts.dart
import 'dart:io';

import 'package:flatmates/gridcraft/papercraft_net.dart';
import 'package:flatmates/gridcraft/papercrafts.dart';
import 'package:flutter_test/flutter_test.dart';

const String kGenerator = 'tool/generate_papercrafts.dart';

void main() {
  for (final design in papercraftDesigns()) {
    test('write ${design.craftId}', () {
      final net = unfoldPapercraft(design);
      final directory = Directory(papercraftDirectory(design))
        ..createSync(recursive: true);
      File(
        '${directory.path}/craft.json',
      ).writeAsStringSync(net.craftJsonText());
      File(
        '${directory.path}/folded.obj',
      ).writeAsStringSync(net.craftObj(kGenerator));
      File(papercraftLevelPath(design))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(net.levelJsonText());
    });
  }
}
