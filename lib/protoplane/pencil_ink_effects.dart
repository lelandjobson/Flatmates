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
  final _fills = <_PencilTrail>[];
  static const fillDuration = Duration(milliseconds: 75);
  int get activeFillCount => _fills.length;
  void playFill(
    CraftPlane plane,
    List<PencilSegment> segments, {
    bool reducedMotion = false,
  }) {
    if (segments.isEmpty || reducedMotion) return;
    if (!_ticker.isActive) {
      _time = Duration.zero;
      _ticker.start();
    }
    if (_fills.length >= 8) _fills.removeAt(0);
    _fills.add(_PencilTrail(plane, List.of(segments), _time, false));
    notifyListeners();
  }

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
    _fills.removeWhere((t) => elapsed - t.start >= fillDuration);
    if (_trails.isEmpty && _fills.isEmpty) _ticker.stop();
    notifyListeners();
  }

  void clear() {
    _ticker.stop();
    _trails.clear();
    _fills.clear();
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
    this.dwellProgress,
  }) : super(repaint: effects);
  final PencilInkEffects effects;
  final Camera camera;
  final CraftPlane? plane;
  final List<PencilSegment> live;
  final bool enabled;
  final double? dwellProgress;
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
    void fill(
      CraftPlane plane,
      List<PencilSegment> segments,
      double progress, {
      bool swipe = false,
    }) {
      final total = segments.fold<double>(0, (sum, s) => sum + s.length);
      var remaining = total * progress;
      for (final segment in segments) {
        final a = camera.projectToScreen(plane.point(segment.a, .009), size);
        final b = camera.projectToScreen(plane.point(segment.b, .009), size);
        if (a == null || b == null) continue;
        final t = segment.length == 0
            ? 0.0
            : (remaining / segment.length).clamp(0.0, 1.0);
        remaining -= segment.length;
        final tip = Offset.lerp(a, b, t)!;
        canvas.drawLine(
          tip,
          b,
          Paint()
            ..color = const Color(0x5500cfee)
            ..strokeWidth = 8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          tip,
          b,
          Paint()
            ..color = const Color(0xff00cfee)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        if (swipe && t > 0 && t < 1) {
          canvas.drawCircle(
            tip,
            7,
            Paint()
              ..color = const Color(0xaa00e5ff)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
          canvas.drawCircle(tip, 2.5, Paint()..color = const Color(0xffe7fcff));
        }
        if (t > 0) {
          canvas.drawLine(
            a,
            tip,
            Paint()
              ..color = const Color(0xff383838)
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    for (final trail in effects._fills) {
      final t =
          ((effects._time - trail.start).inMicroseconds /
                  PencilInkEffects.fillDuration.inMicroseconds)
              .clamp(0.0, 1.0);
      fill(
        trail.plane,
        trail.segments,
        Curves.easeOutCubic.transform(t),
        swipe: true,
      );
    }
    if (plane != null && dwellProgress != null) {
      fill(plane!, live, dwellProgress!);
    } else if (plane != null) {
      draw(plane!, live, 0, false);
    }
  }

  @override
  bool shouldRepaint(covariant PencilInkPainter old) => true;
}
