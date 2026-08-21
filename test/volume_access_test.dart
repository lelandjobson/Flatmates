import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first volume cannot commit without a door', () {
    final volumes = VolumeStore();
    expect(volumes.requiresAccessibleSide, isTrue);
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.confirmAccess(), isFalse);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.volumes, hasLength(1));
  });

  test('later volumes can commit with no door', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);

    expect(volumes.requiresAccessibleSide, isFalse);
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.draftCell!.accessibleSides, isEmpty);
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.volumes, hasLength(2));
    expect(volumes.volumes.last.accessibleSides, isEmpty);
  });
}
