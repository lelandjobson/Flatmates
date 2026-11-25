import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'construction_fixture.dart';
import 'release_completion_test.dart' show loop;

void main() {
  test('scissors never fall through to placement on cleared ground', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.selectTool(CraftTool.scissors);
    c.beginGesture();
    loop(c);
    final before = c.toJson();
    expect(c.previewObject, isNull);
    expect(c.drawingReady, isFalse);
    expect(c.create(), isFalse);
    expect(c.completeCraft(), isFalse);
    expect(c.commitDrawing(), isNull);
    expect(c.toJson(), before);
    expect(c.objects, isEmpty);
    c.cancelGesture();
    c.selectTool(CraftTool.place);
    c.beginGesture();
    loop(c);
    expect(c.commitDrawing(), isNotNull);
    expect(c.objects, hasLength(1));
  });
  test(
    'cut and addition colors persist independently with legacy migration',
    () {
      final s = ProtoplaneSettings();
      expect(s.cutLineColor, const Color(0xffff4040));
      expect(s.lineColor, const Color(0xff7fff00));
      s.cutLineColor = Colors.redAccent;
      s.lineColor = Colors.lime;
      final restored = ProtoplaneSettings()..load(s.toJson());
      expect(restored.cutLineColor.toARGB32(), Colors.redAccent.toARGB32());
      expect(restored.lineColor.toARGB32(), Colors.lime.toARGB32());
      final old = s.toJson()..remove('cutLineColor');
      restored.load(old);
      expect(restored.cutLineColor, const Color(0xffff4040));
      expect(restored.lineColor.toARGB32(), Colors.lime.toARGB32());
    },
  );
}
