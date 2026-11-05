import 'dart:math' as math;
import 'package:flutter/material.dart';

String screenCardinal(Offset delta) {
  if (delta.distance < 1) return 'None';
  if (delta.dx.abs() >= delta.dy.abs()) {
    return delta.dx >= 0 ? 'Right / E' : 'Left / W';
  }
  return delta.dy >= 0 ? 'Down / S' : 'Up / N';
}

class DebugContact {
  DebugContact(this.id, this.index, this.start, this.kind, this.buttons)
    : end = start;
  final int id, index, buttons;
  final Offset start;
  final String kind;
  Offset end;
  bool active = true;
  Offset get delta => end - start;
}

/// Read-only gesture telemetry: it never recognizes or redirects app input.
class GestureDebug extends ChangeNotifier {
  final contacts = <int, DebugContact>{};
  final _pairedStarts = <int, Offset>{};
  bool trackpad = false;
  String verdict = 'Pending', phase = 'Ready';
  bool scroll = false;
  Offset? accepted;
  int get activeCount => contacts.values.where((p) => p.active).length;
  bool get multi => trackpad || _pairedStarts.length == 2;
  Offset get centroidDelta {
    if (trackpad) return contacts.values.first.delta;
    if (_pairedStarts.length != 2) return Offset.zero;
    return _pairedStarts.entries
            .map((p) => contacts[p.key]!.end - p.value)
            .reduce((a, b) => a + b) /
        2;
  }

  void clear() {
    contacts.clear();
    _pairedStarts.clear();
    trackpad = false;
    scroll = false;
    accepted = null;
    verdict = 'Pending';
    phase = 'Ready';
    notifyListeners();
  }

  void down(
    int id,
    Offset at, {
    String kind = 'touch',
    int buttons = 0,
    bool nativeTrackpad = false,
  }) {
    if (activeCount == 0) clear();
    trackpad = nativeTrackpad;
    contacts[id] = DebugContact(id, contacts.length, at, kind, buttons);
    if (activeCount == 2) {
      _pairedStarts.clear();
      for (final p in contacts.values.where((p) => p.active)) {
        _pairedStarts[p.id] = p.end;
      }
    }
    phase = 'Active';
    notifyListeners();
  }

  void move(int id, Offset at) {
    final p = contacts[id];
    if (p == null || !p.active) return;
    p.end = at;
    notifyListeners();
  }

  void end(int id, {Offset? at}) {
    final p = contacts[id];
    if (p == null) return;
    if (at != null) p.end = at;
    p.active = false;
    phase = activeCount == 0 ? 'Released' : 'Active';
    notifyListeners();
  }

  void scrollEvent(int id, Offset position, Offset delta) {
    if (activeCount > 0) return;
    down(id, position, kind: 'OS scroll');
    move(id, position + delta);
    end(id);
    scroll = true;
    phase = 'Scroll';
    notifyListeners();
  }

  void cancel() {
    for (final p in contacts.values) {
      p.active = false;
    }
    phase = 'Cancelled';
    notifyListeners();
  }

  void recognition({
    Offset? swipe,
    required bool zooming,
    required bool consumed,
  }) {
    if (accepted != null) return;
    if (swipe != null) {
      accepted = swipe;
      verdict = 'Swipe ${screenCardinal(swipe)}';
    } else if (zooming) {
      verdict = 'Pinch / rotation';
    } else if (consumed) {
      verdict = 'Consumed / blocked';
    } else {
      verdict = 'Pending';
    }
    notifyListeners();
  }

  Offset? get trackpadOrigin => contacts.values.firstOrNull?.start;
}

const _pointerColors = [
  Color(0xff4de1ff),
  Color(0xffff70cf),
  Color(0xffffd36b),
  Color(0xff99f58e),
];
Color _contactColor(DebugContact p) =>
    _pointerColors[p.index % _pointerColors.length];

class GestureDebugOverlay extends StatelessWidget {
  const GestureDebugOverlay({super.key, required this.debug, this.safeZone});
  final GestureDebug debug;
  final Rect? safeZone;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: debug,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final zone =
              (safeZone ??
                      Rect.fromLTRB(
                        12,
                        MediaQuery.paddingOf(context).top + 110,
                        box.maxWidth - 12,
                        box.maxHeight - 90,
                      ))
                  .intersect(Offset.zero & box.biggest);
          String xy(Offset p) =>
              '${p.dx.toStringAsFixed(0)}, ${p.dy.toStringAsFixed(0)}';
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _GesturePainter(debug)),
              ),
              Positioned(
                left: zone.left,
                top: zone.top,
                child: Container(
                  key: const ValueKey('gesture-debug-readout'),
                  width: math.min(350, math.max(120, zone.width)),
                  constraints: BoxConstraints(
                    maxHeight: math.max(80, math.min(210, zone.height)),
                  ),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xe8141821),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestures · ${debug.phase} · ${debug.contacts.length} pointers',
                          ),
                          const Text('○ start   ● end   Δ screen pixels'),
                          for (final p in debug.contacts.values)
                            Text(
                              '${debug.trackpad ? "Trackpad" : "P${p.index + 1}"} (#${p.id}) ${p.kind} · buttons ${p.buttons}\n${xy(p.start)} → ${xy(p.end)} · Δ ${xy(p.delta)}',
                              style: TextStyle(color: _contactColor(p)),
                            ),
                          if (debug.scroll)
                            const Text(
                              'Scroll: delta vector; contact positions unavailable',
                            ),
                          if (debug.multi) ...[
                            Text(
                              'Centroid Δ ${xy(debug.centroidDelta)} · intent ${screenCardinal(debug.centroidDelta)}',
                            ),
                            Text(
                              'Verdict: ${debug.verdict}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (debug.trackpad)
                              const Text(
                                'Trackpad: OS centroid; individual contacts unavailable',
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _GesturePainter extends CustomPainter {
  _GesturePainter(this.debug);
  final GestureDebug debug;
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in debug.contacts.values) {
      final color = _contactColor(p), delta = p.delta;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p.start, p.end, paint);
      canvas.drawCircle(p.start, 8, paint);
      canvas.drawCircle(p.end, 4, Paint()..color = color);
      if (delta.distance > 16) {
        final axis = delta / delta.distance, side = Offset(-axis.dy, axis.dx);
        canvas.drawLine(p.end, p.end - axis * 10 + side * 5, paint);
        canvas.drawLine(p.end, p.end - axis * 10 - side * 5, paint);
      }
      final label = TextPainter(
        text: TextSpan(
          text: 'P${p.index + 1}',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          (p.end.dx + 10).clamp(0, math.max(0, size.width - label.width)),
          (p.end.dy - 18).clamp(0, math.max(0, size.height - label.height)),
        ),
      );
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _GesturePainter old) => true;
}
