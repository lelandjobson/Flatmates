import 'dart:ui' show Offset, Size;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

enum ReticleMode { centered, cursor }

enum WorldDrag { pan, rotate }

/// The two input paths share gesture meanings; only world aiming differs.
/// Keep platform/device decisions here rather than in gameplay screens.
class GameControlProfile {
  const GameControlProfile(this.reticle);
  final ReticleMode reticle;
  static const mobile = GameControlProfile(ReticleMode.centered);
  static const desktop = GameControlProfile(ReticleMode.cursor);

  WorldDrag worldDrag({required int pointers, required int buttons}) =>
      pointers > 1 ||
          (buttons & (kSecondaryMouseButton | kMiddleMouseButton)) != 0
      ? WorldDrag.rotate
      : WorldDrag.pan;

  bool canActivate(int buttons) => buttons == kPrimaryMouseButton;
}

GameControls loadGameControls({TargetPlatform? platform}) => GameControls(
  initialProfile: switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => GameControlProfile.mobile,
    _ => GameControlProfile.desktop,
  },
);

/// Pointer-driven switching supports laptops with touch screens and tablets
/// with mice. Merely moving another device during a gesture does not steal it.
class GameControls extends ChangeNotifier {
  GameControls({required GameControlProfile initialProfile})
    : profile = initialProfile;
  GameControlProfile profile;
  Offset? _cursor;
  bool _inside = false;
  int _contacts = 0;
  PointerDeviceKind? _gestureKind;

  bool get showReticle => profile.reticle == ReticleMode.centered || _inside;
  bool get hidesSystemCursor =>
      profile.reticle == ReticleMode.cursor && _inside;

  Offset worldAim(Size viewport) {
    final p = profile.reticle == ReticleMode.cursor ? _cursor : null;
    return p == null
        ? viewport.center(Offset.zero)
        : Offset(
            p.dx.clamp(0.0, viewport.width),
            p.dy.clamp(0.0, viewport.height),
          );
  }

  /// Crafting always uses direct manipulation, regardless of world reticle.
  Offset craftingAim(Offset position) => position;

  void hover(PointerDeviceKind kind, Offset position) {
    if (_contacts > 0) return;
    _adopt(kind, position);
  }

  void begin(PointerDeviceKind kind, Offset position) {
    if (_contacts == 0) _gestureKind = kind;
    _contacts++;
    if (kind == _gestureKind) _adopt(kind, position);
  }

  void move(PointerDeviceKind kind, Offset position) {
    if (_contacts > 0 && kind != _gestureKind) return;
    _adopt(kind, position, enters: false);
  }

  void end() {
    if (_contacts > 0) _contacts--;
    if (_contacts == 0) _gestureKind = null;
  }

  void cancel() {
    _contacts = 0;
    _gestureKind = null;
  }

  void exit() {
    _inside = false;
    notifyListeners();
  }

  void _adopt(PointerDeviceKind kind, Offset position, {bool enters = true}) {
    if (kind == PointerDeviceKind.unknown) return;
    profile = kind == PointerDeviceKind.touch
        ? GameControlProfile.mobile
        : GameControlProfile.desktop;
    _cursor = position;
    if (enters) _inside = true;
    notifyListeners();
  }
}
