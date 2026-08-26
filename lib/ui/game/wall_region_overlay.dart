import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/walls/wall_edge.dart';
import '../../gameplay/walls/wall_regions.dart';
import '../../gameplay/walls/wall_store.dart';
import '../../rendering/scene/camera.dart';

const kWallRegionLiveColor = Color(0xFF40C4FF);
const kWorldBorderColor = Color(0xFF40C4FF);
const kWallRegionFadeColor = Color(0xFFE53935);
const kWallRegionFadeMs = 300;

/// Permanent blue frame around the map tile grid.
class WorldBorderOverlay extends StatelessWidget {
  const WorldBorderOverlay({
    super.key,
    required this.store,
    required this.camera,
    required this.viewport,
    this.listenable,
  });

  final WallStore store;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _WorldBorderPainter(
          store: store,
          camera: camera,
          viewport: viewport,
        ),
      ),
    );
  }
}

class _WorldBorderPainter extends CustomPainter {
  _WorldBorderPainter({
    required this.store,
    required this.camera,
    required this.viewport,
  });

  final WallStore store;
  final Camera camera;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kWorldBorderColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final edge in worldBorderEdges(store.grid)) {
      final a = store.vertexWorld(edge.x0, edge.y0);
      final b = store.vertexWorld(edge.x1, edge.y1);
      final sa = camera.projectToScreen(Vector3(a.x, 0.08, a.z), viewport);
      final sb = camera.projectToScreen(Vector3(b.x, 0.08, b.z), viewport);
      if (sa == null || sb == null) continue;
      canvas.drawLine(sa, sb, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorldBorderPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.viewport != viewport;
}

/// Blue outlines for each DCEL inner face; departed tiles blink red then vanish.
class WallRegionOverlay extends StatefulWidget {
  const WallRegionOverlay({
    super.key,
    required this.regions,
    required this.store,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
  });

  final List<WallRegion> regions;
  final WallStore store;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  State<WallRegionOverlay> createState() => _WallRegionOverlayState();
}

class _WallRegionOverlayState extends State<WallRegionOverlay>
    with SingleTickerProviderStateMixin {
  List<WallRegion> _live = const [];
  Set<(int, int)> _liveTiles = {};
  final List<_FadingTiles> _fading = [];
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _live = List<WallRegion>.from(widget.regions);
    _liveTiles = enclosedTilesOf(_live);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant WallRegionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.regions;
    final nextTiles = enclosedTilesOf(next);
    final removed = _liveTiles.difference(nextTiles);
    if (removed.isNotEmpty) {
      _fading.add(_FadingTiles(removed));
      _ensureTicking();
    }
    _live = List<WallRegion>.from(next);
    _liveTiles = nextTiles;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _ensureTicking() {
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) ticker.start();
  }

  void _onTick(Duration _) {
    _fading.removeWhere((f) => f.t >= 1);
    if (_fading.isEmpty) _ticker?.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    if (_live.isEmpty && _fading.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: widget.viewport,
        painter: _WallRegionPainter(
          live: _live,
          fading: List<_FadingTiles>.from(_fading),
          store: widget.store,
          camera: widget.camera,
          viewport: widget.viewport,
          tileVisible: widget.tileVisible,
        ),
      ),
    );
  }
}

class _FadingTiles {
  _FadingTiles(this.tiles) : started = DateTime.now();

  final Set<(int, int)> tiles;
  final DateTime started;

  double get t =>
      DateTime.now().difference(started).inMilliseconds / kWallRegionFadeMs;

  /// Blink once, then fade out. Total time is [kWallRegionFadeMs].
  double get opacity {
    final u = t.clamp(0.0, 1.0);
    if (u < 0.27) return 1;
    if (u < 0.47) return 0.12;
    if (u < 0.67) return 1;
    return (1 - (u - 0.67) / 0.33).clamp(0.0, 1.0);
  }
}

class _WallRegionPainter extends CustomPainter {
  _WallRegionPainter({
    required this.live,
    required this.fading,
    required this.store,
    required this.camera,
    required this.viewport,
    this.tileVisible,
  });

  final List<WallRegion> live;
  final List<_FadingTiles> fading;
  final WallStore store;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in live) {
      _drawTiles(canvas, region.tiles, kWallRegionLiveColor, 1);
    }
    for (final fade in fading) {
      _drawTiles(
        canvas,
        fade.tiles,
        kWallRegionFadeColor.withValues(alpha: fade.opacity),
        fade.opacity,
      );
    }
  }

  void _drawTiles(
    Canvas canvas,
    Set<(int, int)> tiles,
    Color color,
    double widthScale,
  ) {
    if (tiles.isEmpty) return;
    final visible = tileVisible;
    final shown = {
      for (final tile in tiles)
        if (visible == null || visible(tile.$1, tile.$2)) tile,
    };
    if (shown.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3 * widthScale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final edge in tileSetOutline(shown)) {
      _drawEdge(canvas, edge, paint);
    }
  }

  void _drawEdge(Canvas canvas, WallEdge edge, Paint paint) {
    final a = store.vertexWorld(edge.x0, edge.y0);
    final b = store.vertexWorld(edge.x1, edge.y1);
    // Lift slightly so the stroke sits on top of ground / fence.
    final sa = camera.projectToScreen(Vector3(a.x, 0.08, a.z), viewport);
    final sb = camera.projectToScreen(Vector3(b.x, 0.08, b.z), viewport);
    if (sa == null || sb == null) return;
    canvas.drawLine(sa, sb, paint);
  }

  @override
  bool shouldRepaint(covariant _WallRegionPainter oldDelegate) =>
      oldDelegate.live != live ||
      oldDelegate.fading != fading ||
      oldDelegate.camera != camera ||
      oldDelegate.viewport != viewport;
}
