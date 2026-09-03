import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const double kPaperFlyAboveCursor = 50;
const double kPaperFlyRise = 46;
const Duration kPaperFlyDuration = Duration(milliseconds: 900);

class PaperFlyEvent {
  PaperFlyEvent({
    required this.id,
    required this.delta,
    required this.cursor,
  });

  final int id;
  final int delta;
  final Offset cursor;
  Duration? startElapsed;
}

/// RCT-style floating +/− paper text that rises and fades above the cursor.
class PaperFlyOverlay extends StatefulWidget {
  const PaperFlyOverlay({
    super.key,
    required this.events,
    required this.onExpired,
  });

  final List<PaperFlyEvent> events;
  final ValueChanged<int> onExpired;

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
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant PaperFlyOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
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
        painter: _PaperFlyPainter(events: widget.events, elapsed: _elapsed),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PaperFlyPainter extends CustomPainter {
  _PaperFlyPainter({required this.events, required this.elapsed});

  final List<PaperFlyEvent> events;
  final Duration elapsed;

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
      final origin = Offset(event.cursor.dx, event.cursor.dy - rise);
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

  @override
  bool shouldRepaint(covariant _PaperFlyPainter oldDelegate) => true;
}
