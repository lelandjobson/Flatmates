import 'package:flutter/material.dart';

import '../geometry/geometry_algorithms.dart';
import '../gestures/gesture_system.dart';
import '../ui/fm_dev_back_button.dart';

const _pointerColors = [
  Color(0xFF00E5FF), // cyan
  Color(0xFFFF4081), // pink
  Color(0xFFFFD740), // amber
  Color(0xFF69F0AE), // green
  Color(0xFFB388FF), // purple
];

class GestureSystemView extends StatefulWidget {
  const GestureSystemView({super.key});

  @override
  State<GestureSystemView> createState() => _GestureSystemViewState();
}

class _GestureSystemViewState extends State<GestureSystemView> {
  GestureState _gesture = GestureState.idle;

  void _onGestureUpdate(GestureState state) {
    setState(() => _gesture = state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureClassifier(
        onGestureUpdate: _onGestureUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _GesturePainter(_gesture),
            ),
            _InfoPanel(gesture: _gesture),
            const FmDevBackButton(),
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.gesture});

  final GestureState gesture;

  @override
  Widget build(BuildContext context) {
    final type = gesture.type;
    final count = gesture.pointerCount;
    final focal = gesture.focalPoint;
    final delta = gesture.focalDelta;

    final typeColor = switch (type) {
      GestureType.idle => Colors.white38,
      _ when type.isClick => const Color(0xFFFFD740),
      _ when type.isDrag => const Color(0xFFFF4081),
      _ => const Color(0xFF00E5FF),
    };

    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: typeColor,
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    type.label,
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow('Pointers', '$count'),
              _infoRow(
                'Focal',
                count > 0
                    ? '(${focal.dx.toStringAsFixed(1)}, ${focal.dy.toStringAsFixed(1)})'
                    : '—',
              ),
              _infoRow(
                'Delta',
                count > 0
                    ? '(${delta.dx.toStringAsFixed(1)}, ${delta.dy.toStringAsFixed(1)})'
                    : '—',
              ),
              if (gesture.pointers.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final p in gesture.pointers)
                  _infoRow(
                    'P${p.pointerId}',
                    '(${p.position.dx.toStringAsFixed(0)}, '
                        '${p.position.dy.toStringAsFixed(0)})  '
                        'disp: ${p.displacement.toStringAsFixed(1)}  '
                        'dist: ${p.totalDistance.toStringAsFixed(1)}'
                        '${p.hasMoved ? '  MOVED' : ''}',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GesturePainter extends CustomPainter {
  _GesturePainter(this.gesture);

  final GestureState gesture;

  @override
  void paint(Canvas canvas, Size size) {
    final pointers = gesture.pointers;
    if (pointers.isEmpty) return;

    final positions = gesture.positions;

    if (positions.length >= 2) {
      _drawHull(canvas, positions);
    }

    for (var i = 0; i < pointers.length; i++) {
      _drawPointer(canvas, pointers[i], i);
    }

    if (positions.length >= 2) {
      _drawFocalPoint(canvas, gesture.focalPoint);
    }
  }

  void _drawHull(Canvas canvas, List<Offset> positions) {
    final hull = convexHull(positions);
    if (hull.length < 2) return;

    final hullColor = Colors.white.withValues(alpha: 0.06);
    final edgeColor = Colors.white.withValues(alpha: 0.25);

    if (hull.length == 2) {
      canvas.drawLine(
        hull[0],
        hull[1],
        Paint()
          ..color = edgeColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      return;
    }

    final path = Path()..moveTo(hull[0].dx, hull[0].dy);
    for (var i = 1; i < hull.length; i++) {
      path.lineTo(hull[i].dx, hull[i].dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = hullColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = edgeColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawPointer(Canvas canvas, PointerSnapshot pointer, int index) {
    final color = _pointerColors[index % _pointerColors.length];
    final pos = pointer.position;
    const radius = 28.0;

    // Outer glow
    canvas.drawCircle(
      pos,
      radius * 1.8,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Inner glow
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Solid circle
    canvas.drawCircle(
      pos,
      12,
      Paint()..color = color.withValues(alpha: 0.8),
    );

    // Center dot
    canvas.drawCircle(
      pos,
      4,
      Paint()..color = Colors.white,
    );

    // Trail from initial position
    if (pointer.hasMoved) {
      canvas.drawLine(
        pointer.initialPosition,
        pos,
        Paint()
          ..color = color.withValues(alpha: 0.2)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        pointer.initialPosition,
        4,
        Paint()..color = color.withValues(alpha: 0.3),
      );
    }
  }

  void _drawFocalPoint(Canvas canvas, Offset focal) {
    // Crosshair at the focal point
    const crossSize = 8.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    canvas.drawLine(
      focal + const Offset(-crossSize, 0),
      focal + const Offset(crossSize, 0),
      paint,
    );
    canvas.drawLine(
      focal + const Offset(0, -crossSize),
      focal + const Offset(0, crossSize),
      paint,
    );
    canvas.drawCircle(
      focal,
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_GesturePainter oldDelegate) => true;
}
