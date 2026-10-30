import 'dart:ui';

/// Camera pose owned by a desk tool. All tools use the same transition path,
/// including changes from DevTools while a tool is active.
class AsmrToolCamera {
  const AsmrToolCamera({this.pitch = 0, this.lensMm = 50});

  final double pitch;
  final double lensMm;

  static const transitionSeconds = 0.32;

  static AsmrToolCamera lerp(AsmrToolCamera a, AsmrToolCamera b, double t) =>
      AsmrToolCamera(
        pitch: lerpDouble(a.pitch, b.pitch, t)!,
        lensMm: lerpDouble(a.lensMm, b.lensMm, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AsmrToolCamera && other.pitch == pitch && other.lensMm == lensMm;

  @override
  int get hashCode => Object.hash(pitch, lensMm);
}
