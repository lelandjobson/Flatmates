/// Last-frame cost of a [CustomPainter], for the in-game HUD.
///
/// Written from the painter (raster-recording thread) and read by the HUD
/// on the next [FrameTiming] tick. Not a [Listenable] — the HUD already
/// rebuilds from frame timings.
class ScenePaintStats {
  const ScenePaintStats({
    this.source = 'scene',
    this.meshes = 0,
    this.visibleMeshes = 0,
    this.faces = 0,
    this.drawCalls = 0,
    this.paintMs = 0,
  });

  final String source;
  final int meshes;
  final int visibleMeshes;
  final int faces;
  final int drawCalls;
  final double paintMs;
}

/// Process-wide last paint snapshots. Debug-only; reset on GameView dispose.
class PaintStatsProbe {
  PaintStatsProbe._();

  static ScenePaintStats? scene;
  static ScenePaintStats? landscape;

  static void reset() {
    scene = null;
    landscape = null;
  }
}
