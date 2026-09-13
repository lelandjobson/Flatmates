import 'package:flatmates/gameplay/friends/desire_cloud_shape.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ten pre-generated clouds each have eight medium puffs', () {
    expect(kDesireClouds, hasLength(kDesireCloudVariationCount));
    for (final cloud in kDesireClouds) {
      expect(cloud.puffs, hasLength(kDesireCloudPuffCount));
      expect(cloud.tail, hasLength(3));
      for (final puff in cloud.puffs) {
        expect(puff.radius, greaterThan(0.09));
        expect(puff.radius, lessThan(0.17));
      }
    }
  });

  test('variations differ and a seed always picks the same one', () {
    final first = kDesireClouds.first.puffs.first.center;
    final other = kDesireClouds
        .skip(1)
        .any((cloud) => cloud.puffs.first.center != first);
    expect(other, isTrue);
    expect(desireCloudForSeed('alpha'), same(desireCloudForSeed('alpha')));
  });

  test('puff centroid sits inside the cloud mass', () {
    final center = puffCentroid(kDesireClouds.first);
    expect(center.dx, inInclusiveRange(0.2, 0.8));
    expect(center.dy, inInclusiveRange(0.15, 0.55));
  });
}
