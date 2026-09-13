import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/gameplay/friends/friend_overlay_visibility.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed roofs hide indoor overlays; open interiors do not', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final inside = volumes.grid.tileCenter(2, 2)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: volumes.grid.tileSize);
    final outside = volumes.grid.tileCenter(5, 5)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: volumes.grid.tileSize);

    expect(hideFriendOverlay(position: outside, volumes: volumes), isFalse);
    expect(hideFriendOverlay(position: inside, volumes: volumes), isTrue);
    expect(
      hideFriendOverlay(
        position: inside,
        volumes: volumes,
        interiorOpen: (tx, ty) => tx == 2 && ty == 2,
      ),
      isFalse,
    );
    expect(
      hideFriendOverlay(
        position: inside,
        volumes: volumes,
        interiorOpen: (tx, ty) => tx == 0 && ty == 0,
      ),
      isTrue,
    );
  });
}
