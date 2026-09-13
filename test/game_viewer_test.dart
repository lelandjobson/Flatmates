import 'package:flatmates/gameplay/viewers/game_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volume interior keeps bedroom friends visible', () {
    final layers = SceneLayerMask.forViewer(GameViewerKind.volumeInterior);
    expect(layers.shows(SceneLayer.friends), isTrue);
    expect(layers.shows(SceneLayer.volumes), isTrue);
    expect(layers.shows(SceneLayer.landscape), isFalse);
  });
}
