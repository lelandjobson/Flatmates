enum GameViewerKind { map3d, plane2d, focus3d }

enum SceneLayer {
  landscape,
  volumes,
  paths,
  walls,
  worldBorder,
  connectionGraph,
  volumeTools,
  streamerCrafts,
  friends,
}

/// Which [SceneLayer]s are drawn. Defaults to everything on.
class SceneLayerMask {
  const SceneLayerMask(this.visible);

  final Set<SceneLayer> visible;

  bool shows(SceneLayer layer) => visible.contains(layer);

  SceneLayerMask hiding(Set<SceneLayer> hidden) {
    if (hidden.isEmpty) return this;
    return SceneLayerMask(visible.difference(hidden));
  }

  static const all = SceneLayerMask({
    SceneLayer.landscape,
    SceneLayer.volumes,
    SceneLayer.paths,
    SceneLayer.walls,
    SceneLayer.worldBorder,
    SceneLayer.connectionGraph,
    SceneLayer.volumeTools,
    SceneLayer.streamerCrafts,
    SceneLayer.friends,
  });

  static const map3d = all;
  static const plane2d = all;

  static const focus3d = all;

  static SceneLayerMask forViewer(GameViewerKind kind) => switch (kind) {
    GameViewerKind.map3d => map3d,
    GameViewerKind.plane2d => plane2d,
    GameViewerKind.focus3d => focus3d,
  };
}
