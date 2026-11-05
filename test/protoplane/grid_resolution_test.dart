import 'package:flutter_test/flutter_test.dart';
import 'construction_fixture.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void main() {
  test('resolution changes candidates, retains world and survives reload', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    c.enter('ground-starter-paperWhite-0-0');
    c.beginGesture();
    for (final n in [0, 1, 4, 3, 0]) {
      c.appendNode(n);
    }
    c.finishGesture();
    c.create();
    final object = c.objects.values.single.toJson();
    c.setProtoplaneCells(3);
    expect(
      c.planes['ground-starter-paperWhite-0-0']!.grids.first.nodes.length,
      16,
    );
    expect(
      c.planes.values
          .where((p) => p.wallCandidate)
          .every((p) => p.grids.first.nodes.length == 16),
      isTrue,
    );
    expect(c.objects.values.single.toJson(), object);
    final json = c.toJson();
    c.load(json);
    expect(
      c.planes['ground-starter-paperWhite-0-0']!.grids.first.nodes.length,
      16,
    );
    for (final cells in [1, 2, 4, 5]) {
      c.setProtoplaneCells(cells);
      expect(
        c.planes['ground-starter-paperWhite-0-0']!.grids.first.nodes.length,
        (cells + 1) * (cells + 1),
      );
      expect(c.objects.values.single.toJson(), object);
    }
    expect(() => c.setProtoplaneCells(6), throwsRangeError);
  });
  test('settings default to three cells and validate discrete range', () {
    final settings = ProtoplaneSettings();
    expect(settings.protoplaneCells, 3);
    final json = settings.toJson()..remove('protoplaneCells');
    settings.load(json);
    expect(settings.protoplaneCells, 3);
    settings.load({...json, 'protoplaneCells': 5});
    expect(settings.protoplaneCells, 5);
    expect(
      () => settings.load({...json, 'protoplaneCells': 2.5}),
      throwsFormatException,
    );
  });
}
