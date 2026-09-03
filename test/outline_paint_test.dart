import 'package:flatmates/gameplay/outlines/outline_paint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ground-plane outlines paint under volumes', () {
    expect(
      outlineDrawPass(groundPlane: true),
      OutlineDrawPass.underVolumes,
    );
    expect(
      outlineDrawPass(groundPlane: false),
      OutlineDrawPass.overScene,
    );
  });

  test('split keeps ground first and preserves depth order', () {
    final items = [
      (id: 'vol-far', ground: false),
      (id: 'path-far', ground: true),
      (id: 'vol-near', ground: false),
      (id: 'path-near', ground: true),
    ];
    final split = splitGroundPass(items, (e) => e.ground);
    expect(split.ground.map((e) => e.id), ['path-far', 'path-near']);
    expect(split.elevated.map((e) => e.id), ['vol-far', 'vol-near']);
  });
}
