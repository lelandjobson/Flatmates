import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first volume commits with no door', () {
    final volumes = VolumeStore();
    expect(volumes.requiresAccessibleSide, isFalse);
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.accessibleSides, isEmpty);
    expect(volumes.confirmAccess(), isTrue);
  });

  test('confirmAccess after idle succeeds', () {
    final volumes = VolumeStore();
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.volumes, hasLength(1));
  });

  test('later volumes can commit with no door', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.confirmAccess(), isTrue);

    expect(volumes.requiresAccessibleSide, isFalse);
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.volumes.last.accessibleSides, isEmpty);
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.volumes, hasLength(2));
  });
}
