import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'models.dart';
import 'geometry.dart';
import '../rendering/scene/camera.dart';

/// Bounded visual-only particles, with no meshes, textures or inventory state.
class GraphitePops extends ChangeNotifier {
  GraphitePops(TickerProvider provider) {
    _ticker = provider.createTicker(_tick);
  }
  late final Ticker _ticker;
  Duration _time = Duration.zero;
  final List<(CraftPlane, Region, Duration)> _pops = [];
  int get count => _pops.length;
  void add(CraftPlane plane, List<Region> pieces) {
    if (!_ticker.isActive) {
      _time = Duration.zero;
      _ticker.start();
    }
    _pops.addAll(pieces.map((p) => (plane, p, _time)));
    if (_pops.length > 96) _pops.removeRange(0, _pops.length - 96);
    notifyListeners();
  }

  void _tick(Duration time) {
    _time = time;
    _pops.removeWhere((p) => (time - p.$3).inMilliseconds >= 180);
    if (_pops.isEmpty) _ticker.stop();
    notifyListeners();
  }

  void clear() {
    _ticker.stop();
    _pops.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class GraphitePopsPainter extends CustomPainter {
  GraphitePopsPainter(this.effects, this.camera) : super(repaint: effects);
  final GraphitePops effects;
  final Camera camera;
  @override
  void paint(Canvas canvas, Size size) {
    for (final (plane, region, start) in effects._pops) {
      final t = ((effects._time - start).inMicroseconds / 180000).clamp(
        0.0,
        1.0,
      );
      final center = region.bounds.center;
      final angle = math.sin(center.dx * 43 + center.dy * 29) * t * .4;
      final points = <Offset>[];
      for (final p in region.outer) {
        final d = (p - center) * (1 + .22 * t);
        final local =
            center +
            Offset(
              d.dx * math.cos(angle) - d.dy * math.sin(angle),
              d.dx * math.sin(angle) + d.dy * math.cos(angle),
            );
        final screen = camera.projectToScreen(
          plane.point(local, .004 + math.sin(t * math.pi) * .04),
          size,
        );
        if (screen != null) points.add(screen + Offset(0, t * t * 14));
      }
      if (points.length < 3) continue;
      canvas.drawPath(
        Path()..addPolygon(points, true),
        Paint()..color = PaperMaterial.graphite.base.withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(GraphitePopsPainter old) =>
      old.camera != camera || old.effects != effects;
}

class EraserIconPainter extends CustomPainter {
  const EraserIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final outline = Path()
      ..moveTo(3, 13)
      ..lineTo(13, 3)
      ..lineTo(21, 11)
      ..lineTo(11, 21)
      ..lineTo(7, 21)
      ..close();
    final paint = Paint()
      ..color = const Color(0xffffffff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outline, paint);
    canvas.drawLine(const Offset(8, 8), const Offset(16, 16), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(EraserIconPainter old) => false;
}
