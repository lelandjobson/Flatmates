import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/scene/camera.dart';

const double kPaperFlyAboveCursor = 50;
const double kPaperFlyRise = 46;
const Duration kPaperFlyDuration = Duration(milliseconds: 900);

class PaperFlyEvent {
  PaperFlyEvent({
    required this.id,
    required this.delta,
    required this.cursor,
    this.world,
    this.worldScreen0,
  });

  final int id;
  final int delta;
  final Offset cursor;
  final Vector3? world;
  Offset? worldScreen0;
  Duration? startElapsed;
}

/// Screen position of the fly: cursor, plus how far the tile has moved on screen.
Offset paperFlyScreenAnchor({
  required Offset cursor,
  Offset? originWorldScreen,
  Offset? currentWorldScreen,
}) {
  if (originWorldScreen == null || currentWorldScreen == null) return cursor;
  return cursor + (currentWorldScreen - originWorldScreen);
}

/// RCT-style floating +/− paper text that rises and fades above the pointer.
class PaperFlyOverlay extends StatefulWidget {
  const PaperFlyOverlay({
    super.key,
    required this.events,
    required this.onExpired,
    this.camera,
    this.viewport = Size.zero,
    this.listenable,
  });

  final List<PaperFlyEvent> events;
  final ValueChanged<int> onExpired;
  final Camera? camera;
  final Size viewport;
  final Listenable? listenable;

  @override
  State<PaperFlyOverlay> createState() => _PaperFlyOverlayState();
}

class _PaperFlyOverlayState extends State<PaperFlyOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed;
      _expire();
      if (mounted) setState(() {});
    });
    widget.listenable?.addListener(_onCamera);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PaperFlyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_onCamera);
      widget.listenable?.addListener(_onCamera);
    }
    _syncTicker();
  }

  void _onCamera() {
    if (mounted && widget.events.isNotEmpty) setState(() {});
  }

  void _syncTicker() {
    if (widget.events.isEmpty) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_onCamera);
    _ticker.dispose();
    super.dispose();
  }

  void _expire() {
    for (final event in List<PaperFlyEvent>.from(widget.events)) {
      event.startElapsed ??= _elapsed;
      if (_elapsed - event.startElapsed! >= kPaperFlyDuration) {
        widget.onExpired(event.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        painter: _PaperFlyPainter(
          events: widget.events,
          elapsed: _elapsed,
          camera: widget.camera,
          viewport: widget.viewport,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PaperFlyPainter extends CustomPainter {
  _PaperFlyPainter({
    required this.events,
    required this.elapsed,
    this.camera,
    this.viewport = Size.zero,
  });

  final List<PaperFlyEvent> events;
  final Duration elapsed;
  final Camera? camera;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    for (final event in events) {
      final start = event.startElapsed ?? elapsed;
      final t = ((elapsed - start).inMilliseconds /
              kPaperFlyDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      final rise = kPaperFlyAboveCursor + kPaperFlyRise * t;
      final opacity = t < 0.55 ? 1.0 : (1 - (t - 0.55) / 0.45).clamp(0.0, 1.0);
      final color = (event.delta >= 0
              ? const Color(0xFF43A047)
              : const Color(0xFFE53935))
          .withValues(alpha: opacity);
      final label = event.delta > 0 ? '+${event.delta}' : '${event.delta}';
      final anchor = _anchor(event, size);
      if (anchor == null) continue;
      final origin = Offset(anchor.dx, anchor.dy - rise);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: opacity),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, origin - Offset(tp.width / 2, tp.height / 2));
    }
  }

  Offset? _anchor(PaperFlyEvent event, Size size) {
    final world = event.world;
    final camera = this.camera;
    final view = viewport.isEmpty ? size : viewport;
    Offset? current;
    if (world != null && camera != null && !view.isEmpty) {
      current = camera.projectToScreen(world, view);
      if (current != null) event.worldScreen0 ??= current;
    }
    return paperFlyScreenAnchor(
      cursor: event.cursor,
      originWorldScreen: event.worldScreen0,
      currentWorldScreen: current,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperFlyPainter oldDelegate) => true;
}
