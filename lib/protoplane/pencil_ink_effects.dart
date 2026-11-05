import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../rendering/scene/camera.dart';
import 'models.dart';
import 'pencil.dart';

/// Presentation only: committed graphite and its accounting live in the controller.
class PencilInkEffects extends ChangeNotifier {
  PencilInkEffects(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }
  late final Ticker _ticker;
  Duration _time = Duration.zero;
  final _trails = <_PencilTrail>[];
  static const duration = Duration(milliseconds: 360);
  int get activeCount => _trails.length;
  void play(
    CraftPlane plane,
    List<PencilSegment> segments, {
    bool reducedMotion = false,
  }) {
    if (segments.isEmpty) return;
    if (!_ticker.isActive) {
      _time = Duration.zero;
      _ticker.start();
    }
    if (_trails.length >= 8) _trails.removeAt(0);
    _trails.add(_PencilTrail(plane, List.of(segments), _time, reducedMotion));
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _time = elapsed;
    _trails.removeWhere((t) => elapsed - t.start >= duration);
    if (_trails.isEmpty) _ticker.stop();
    notifyListeners();
  }

  void clear() {
    _ticker.stop();
    _trails.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class _PencilTrail {
  _PencilTrail(this.plane, this.segments, this.start, this.reduced);
  final CraftPlane plane;
  final List<PencilSegment> segments;
  final Duration start;
  final bool reduced;
}

class PencilInkPainter extends CustomPainter {
  PencilInkPainter(
    this.effects,
    this.camera, {
    this.plane,
    this.live = const [],
    this.enabled = true,
  }) : super(repaint: effects);
  final PencilInkEffects effects;
  final Camera camera;
  final CraftPlane? plane;
  final List<PencilSegment> live;
  final bool enabled;
  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    void draw(
      CraftPlane plane,
      List<PencilSegment> segments,
      double t,
      bool reduced,
    ) {
      final core = Paint()
        ..color = const Color(0xff909090)
        ..strokeCap = StrokeCap.round;
      final glow = Paint()
        ..color = const Color(0x408f8f8f)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      for (final (segmentIndex, s) in segments.indexed) {
        final a = camera.projectToScreen(plane.point(s.a, .009), size),
            b = camera.projectToScreen(plane.point(s.b, .009), size);
        if (a == null || b == null) continue;
        final count = t == 0 || reduced
            ? 1
            : math.max(1, ((b - a).distance / 12).ceil());
        for (var i = 0; i < count; i++) {
          final seed = ((segmentIndex * 31 + i * 17) % 23) / 23;
          final p = reduced ? t : ((t - seed * .18) / .82).clamp(0.0, 1.0);
          final opacity = 1 - Curves.easeIn.transform(p);
          final width = 6.0 * (1 - (reduced ? 0.0 : p));
          final drop = Offset(0, reduced ? 0 : p * p * 4);
          final from = a + (b - a) * (i / count) + drop,
              to = a + (b - a) * ((i + 1) / count) + drop;
          if (opacity <= 0 || width <= 0) continue;
          glow
            ..strokeWidth = width + 4
            ..color = Color.fromRGBO(143, 143, 143, .25 * opacity);
          core
            ..strokeWidth = width
            ..color = Color.fromRGBO(144, 144, 144, opacity);
          canvas.drawLine(from, to, glow);
          canvas.drawLine(from, to, core);
        }
      }
    }

    for (final trail in effects._trails) {
      final t =
          ((effects._time - trail.start).inMicroseconds /
                  PencilInkEffects.duration.inMicroseconds)
              .clamp(0.0, 1.0);
      draw(trail.plane, trail.segments, t, trail.reduced);
    }
    if (plane != null) draw(plane!, live, 0, false);
  }

  @override
  bool shouldRepaint(covariant PencilInkPainter old) => true;
}
