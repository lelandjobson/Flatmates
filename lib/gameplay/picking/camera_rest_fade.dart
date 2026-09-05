/// When to show program icons relative to camera motion.
///
/// Icons are visible while the camera is moving and for [holdMs] after it
/// has been still for [restMs]. After that they hide. [alwaysOn] skips hide.
class CameraRestFadeLogic {
  CameraRestFadeLogic({
    this.restMs = 100,
    this.holdMs = 1000,
  });

  final int restMs;
  final int holdMs;

  bool alwaysOn = false;
  bool visible = true;
  int _idleMs = 0;

  void cameraMoved() {
    _idleMs = 0;
    visible = true;
  }

  /// Advance [deltaMs] with no camera event. Returns whether icons show.
  bool tick(int deltaMs) {
    if (alwaysOn) {
      visible = true;
      return true;
    }
    _idleMs += deltaMs;
    visible = _idleMs < restMs + holdMs;
    return visible;
  }

  bool evaluateIdle(int idleMs) {
    if (alwaysOn) {
      visible = true;
      return true;
    }
    _idleMs = idleMs;
    visible = idleMs < restMs + holdMs;
    return visible;
  }
}
