import 'dart:math' as math;
import 'dart:ui';

/// Named idle faces that share one closed-blob topology so any pair can blend.
enum FriendExpressionId {
  rest,
  blink,
  happy,
  sad,
  wow,
  sleepy,
  inquisitive,
  glance,
}

/// How many points sit on every eye outline.
const int kEyeRingCount = 8;

/// Rest circles and other eye ovals, relative to the original blob sizes.
const double kEyeBlobScale = 4;

/// One closed eye: a ring of face-plane points, clockwise from +X.
class EyeBlob {
  EyeBlob(List<Offset> ring)
      : assert(ring.length == kEyeRingCount),
        ring = List<Offset>.unmodifiable(ring);

  final List<Offset> ring;

  Offset get center {
    var x = 0.0;
    var y = 0.0;
    for (final p in ring) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / ring.length, y / ring.length);
  }

  EyeBlob shift(Offset delta) =>
      EyeBlob([for (final p in ring) p + delta]);

  static EyeBlob lerp(EyeBlob a, EyeBlob b, double t) {
    return EyeBlob([
      for (var i = 0; i < kEyeRingCount; i++) Offset.lerp(a.ring[i], b.ring[i], t)!,
    ]);
  }

  /// Ellipse warped by [bend] (+ up / happy, − down / sad) and [tilt] radians.
  static EyeBlob oval({
    required Offset center,
    required double width,
    required double height,
    double bend = 0,
    double tilt = 0,
  }) {
    final w = math.max(width, 1e-6);
    final points = <Offset>[];
    final c = math.cos(tilt);
    final s = math.sin(tilt);
    for (var i = 0; i < kEyeRingCount; i++) {
      final a = i * (math.pi * 2 / kEyeRingCount);
      var x = math.cos(a) * width;
      var y = math.sin(a) * height;
      final nx = (x / w).clamp(-1.0, 1.0);
      y += bend * (1 - nx * nx) * w;
      points.add(center + Offset(x * c - y * s, x * s + y * c));
    }
    return EyeBlob(points);
  }
}

/// Body-front face. Units are fractions of eye spacing (X right, Y up).
class FriendExpressionPose {
  const FriendExpressionPose({
    required this.id,
    required this.left,
    required this.right,
  });

  final FriendExpressionId id;
  final EyeBlob left;
  final EyeBlob right;

  static FriendExpressionPose lerp(
    FriendExpressionPose a,
    FriendExpressionPose b,
    double t,
  ) {
    final u = t.clamp(0.0, 1.0);
    return FriendExpressionPose(
      id: u < 0.5 ? a.id : b.id,
      left: EyeBlob.lerp(a.left, b.left, u),
      right: EyeBlob.lerp(a.right, b.right, u),
    );
  }

  static final rest = FriendExpressionPose(
    id: FriendExpressionId.rest,
    left: EyeBlob.oval(
      center: const Offset(-0.46, 0),
      width: 0.16 * kEyeBlobScale,
      height: 0.16 * kEyeBlobScale,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, 0),
      width: 0.16 * kEyeBlobScale,
      height: 0.16 * kEyeBlobScale,
    ),
  );

  static final blink = FriendExpressionPose(
    id: FriendExpressionId.blink,
    left: EyeBlob.oval(
      center: const Offset(-0.46, 0),
      width: 0.18 * kEyeBlobScale,
      height: 0.018 * kEyeBlobScale,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, 0),
      width: 0.18 * kEyeBlobScale,
      height: 0.018 * kEyeBlobScale,
    ),
  );

  /// Thin upward boat — an upside-down smile.
  static final happy = FriendExpressionPose(
    id: FriendExpressionId.happy,
    left: EyeBlob.oval(
      center: const Offset(-0.46, 0.02),
      width: 0.2 * kEyeBlobScale,
      height: 0.04 * kEyeBlobScale,
      bend: 0.16,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, 0.02),
      width: 0.2 * kEyeBlobScale,
      height: 0.04 * kEyeBlobScale,
      bend: 0.16,
    ),
  );

  /// Thin downward boat — a frown.
  static final sad = FriendExpressionPose(
    id: FriendExpressionId.sad,
    left: EyeBlob.oval(
      center: const Offset(-0.46, -0.02),
      width: 0.2 * kEyeBlobScale,
      height: 0.04 * kEyeBlobScale,
      bend: -0.16,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, -0.02),
      width: 0.2 * kEyeBlobScale,
      height: 0.04 * kEyeBlobScale,
      bend: -0.16,
    ),
  );

  static final wow = FriendExpressionPose(
    id: FriendExpressionId.wow,
    left: EyeBlob.oval(
      center: const Offset(-0.48, 0),
      width: 0.22 * kEyeBlobScale,
      height: 0.22 * kEyeBlobScale,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.48, 0),
      width: 0.22 * kEyeBlobScale,
      height: 0.22 * kEyeBlobScale,
    ),
  );

  static final sleepy = FriendExpressionPose(
    id: FriendExpressionId.sleepy,
    left: EyeBlob.oval(
      center: const Offset(-0.46, -0.01),
      width: 0.19 * kEyeBlobScale,
      height: 0.07 * kEyeBlobScale,
      bend: -0.05,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, -0.01),
      width: 0.19 * kEyeBlobScale,
      height: 0.07 * kEyeBlobScale,
      bend: -0.05,
    ),
  );

  /// One eye bigger and cocked; the other smaller — a curious look.
  static final inquisitive = FriendExpressionPose(
    id: FriendExpressionId.inquisitive,
    left: EyeBlob.oval(
      center: const Offset(-0.48, 0.04),
      width: 0.18 * kEyeBlobScale,
      height: 0.2 * kEyeBlobScale,
      tilt: 0.38,
    ),
    right: EyeBlob.oval(
      center: const Offset(0.46, -0.01),
      width: 0.14 * kEyeBlobScale,
      height: 0.13 * kEyeBlobScale,
      tilt: -0.12,
    ),
  );

  /// [gaze] is −1 look left, +1 look right.
  static FriendExpressionPose glance(double gaze) {
    final g = gaze.clamp(-1.0, 1.0);
    final shift = Offset(g * 0.16, 0);
    return FriendExpressionPose(
      id: FriendExpressionId.glance,
      left: rest.left.shift(shift),
      right: rest.right.shift(shift),
    );
  }

  static FriendExpressionPose byId(FriendExpressionId id, {double gaze = 0}) {
    switch (id) {
      case FriendExpressionId.rest:
        return rest;
      case FriendExpressionId.blink:
        return blink;
      case FriendExpressionId.happy:
        return happy;
      case FriendExpressionId.sad:
        return sad;
      case FriendExpressionId.wow:
        return wow;
      case FriendExpressionId.sleepy:
        return sleepy;
      case FriendExpressionId.inquisitive:
        return inquisitive;
      case FriendExpressionId.glance:
        return glance(gaze);
    }
  }
}

/// Smooth closed loop through [ring] as cubics (Catmull-Rom).
Path eyeBlobPath(List<Offset> ring) {
  final path = Path();
  if (ring.length < 3) return path;
  final n = ring.length;
  Offset at(int i) => ring[(i + n) % n];
  path.moveTo(at(0).dx, at(0).dy);
  for (var i = 0; i < n; i++) {
    final p0 = at(i - 1);
    final p1 = at(i);
    final p2 = at(i + 1);
    final p3 = at(i + 2);
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
      p2.dx,
      p2.dy,
    );
  }
  path.close();
  return path;
}
