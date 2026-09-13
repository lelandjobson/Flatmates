import 'package:flatmates/gameplay/tiles/tile_event_hub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only subscriptions that watch the tile and kind fire', () {
    final hub = TileEventHub();
    final hit = <String>[];
    hub.subscribe(
      id: 'a',
      tiles: {(1, 1), (2, 2)},
      kinds: {TileEventKind.path},
      onEvent: (_, __) => hit.add('a'),
    );
    hub.subscribe(
      id: 'b',
      tiles: {(9, 9)},
      kinds: {TileEventKind.path},
      onEvent: (_, __) => hit.add('b'),
    );
    hub.subscribe(
      id: 'c',
      tiles: {(1, 1)},
      kinds: {TileEventKind.wall},
      onEvent: (_, __) => hit.add('c'),
    );

    hub.emit({(1, 1)}, TileEventKind.path);
    expect(hit, ['a']);
  });

  test('unsubscribe stops further recomputes', () {
    final hub = TileEventHub();
    var n = 0;
    hub.subscribe(
      id: 'a',
      tiles: {(0, 0)},
      kinds: {TileEventKind.program},
      onEvent: (_, __) => n++,
    );
    hub.emit({(0, 0)}, TileEventKind.program);
    hub.unsubscribe('a');
    hub.emit({(0, 0)}, TileEventKind.program);
    expect(n, 1);
  });
}