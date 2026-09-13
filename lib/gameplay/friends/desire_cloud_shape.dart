import 'dart:math' as math;
import 'dart:ui';

const int kDesireCloudVariationCount = 10;
const int kDesireCloudPuffCount = 8;

/// Circle in a 0–1 box: [center] and [radius] are fractions of width / height.
class CloudCircle {
  const CloudCircle(this.center, this.radius);

  final Offset center;
  final double radius;
}

/// One pre-baked desire-cloud silhouette.
class DesireCloudShape {
  const DesireCloudShape({required this.puffs, required this.tail});

  final List<CloudCircle> puffs;
  final List<CloudCircle> tail;
}

/// Ten fill-only clouds, each a cluster of medium circles plus a small tail.
final kDesireClouds = <DesireCloudShape>[
  for (var i = 0; i < kDesireCloudVariationCount; i++) buildDesireCloud(i),
];

Offset puffCentroid(DesireCloudShape shape) {
  if (shape.puffs.isEmpty) return const Offset(0.5, 0.4);
  var x = 0.0;
  var y = 0.0;
  for (final puff in shape.puffs) {
    x += puff.center.dx;
    y += puff.center.dy;
  }
  return Offset(x / shape.puffs.length, y / shape.puffs.length);
}

DesireCloudShape desireCloudForSeed(String seed) {
  final index = seed.hashCode.abs() % kDesireCloudVariationCount;
  return kDesireClouds[index];
}

DesireCloudShape buildDesireCloud(int variation) {
  final rng = math.Random(variation * 7919 + 104729);
  final puffs = <CloudCircle>[];
  for (var i = 0; i < kDesireCloudPuffCount; i++) {
    final angle = (i / kDesireCloudPuffCount) * math.pi * 2 +
        (rng.nextDouble() - 0.5) * 0.7;
    final dist = 0.06 + rng.nextDouble() * 0.16;
    puffs.add(
      CloudCircle(
        Offset(
          (0.50 + math.cos(angle) * dist * 1.45).clamp(0.16, 0.84),
          (0.36 + math.sin(angle) * dist * 0.9).clamp(0.16, 0.58),
        ),
        0.10 + rng.nextDouble() * 0.055,
      ),
    );
  }
  final tailLean = rng.nextDouble() < 0.5 ? -1.0 : 1.0;
  final tail = <CloudCircle>[
    CloudCircle(Offset(0.50 + tailLean * 0.02, 0.68), 0.055),
    CloudCircle(Offset(0.50 + tailLean * 0.08, 0.80), 0.038),
    CloudCircle(Offset(0.50 + tailLean * 0.13, 0.90), 0.024),
  ];
  return DesireCloudShape(puffs: puffs, tail: tail);
}
