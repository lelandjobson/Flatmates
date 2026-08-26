import 'package:flutter/rendering.dart';

import '../gameplay/viewers/game_viewer.dart';

/// In-game performance toggles. Engine flags are global and must be cleared
/// when the host view is disposed.
class PerfDebugSettings {
  bool showOverlay = false;
  bool repaintRainbow = false;
  bool profilePaints = false;
  bool showDetails = false;
  final Set<SceneLayer> hiddenLayers = {};

  void applyEngineFlags() {
    debugRepaintRainbowEnabled = repaintRainbow;
    debugProfilePaintsEnabled = profilePaints;
  }

  static void resetEngineFlags() {
    debugRepaintRainbowEnabled = false;
    debugProfilePaintsEnabled = false;
  }
}

extension SceneLayerHud on SceneLayer {
  String get shortLabel => switch (this) {
    SceneLayer.landscape => 'land',
    SceneLayer.volumes => 'vols',
    SceneLayer.paths => 'path',
    SceneLayer.walls => 'wall',
    SceneLayer.worldBorder => 'edge',
    SceneLayer.connectionGraph => 'graph',
    SceneLayer.volumeTools => 'tools',
    SceneLayer.streamerCrafts => 'craft',
    SceneLayer.friends => 'friend',
  };
}
