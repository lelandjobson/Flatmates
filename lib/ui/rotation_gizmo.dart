import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class RotationGizmo extends StatelessWidget {
  const RotationGizmo({
    super.key,
    required this.center,
    required this.rotationDeg,
    required this.objectName,
    required this.screenRefAngle,
    required this.rotationSign,
    required this.onRotationChanged,
    required this.onDismiss,
  });

  final Offset center;
  final double rotationDeg;
  final String objectName;

  /// Screen-space angle (radians) of the face U-axis, from atan2.
  final double screenRefAngle;

  /// +1 or -1: maps screen-space angular direction to face-plane rotation.
  final double rotationSign;
  final ValueChanged<double> onRotationChanged;
  final VoidCallback onDismiss;

  static const double _ringRadius = 90.0;
  static const double _handleRadius = 12.0;
  static const double _snapIncrement = 5.0;
  static const int _tickCount = 8;
  static const double _dragPad = 30.0;

  double _snapAngle(double deg) {
    var snapped = (deg / _snapIncrement).round() * _snapIncrement;
    snapped = snapped % 360;
    if (snapped < 0) snapped += 360;
    return snapped.toDouble();
  }

  double _toScreenAngle(double deg) =>
      screenRefAngle + rotationSign * deg * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final handleScreenAngle = _toScreenAngle(rotationDeg);
    final handleDx = center.dx + math.cos(handleScreenAngle) * _ringRadius;
    final handleDy = center.dy + math.sin(handleScreenAngle) * _ringRadius;

    const gizmoLocalCenter =
        Offset(_ringRadius + _dragPad, _ringRadius + _dragPad);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: center.dx - _ringRadius - 20,
          top: center.dy - _ringRadius - 20,
          child: IgnorePointer(
            child: CustomPaint(
              size: Size(
                (_ringRadius + 20) * 2,
                (_ringRadius + 20) * 2,
              ),
              painter: RingPainter(
                ringRadius: _ringRadius,
                rotationDeg: rotationDeg,
                tickCount: _tickCount,
                screenRefAngle: screenRefAngle,
                rotationSign: rotationSign,
              ),
            ),
          ),
        ),
        Positioned(
          left: center.dx - 50,
          top: center.dy - _ringRadius - 40,
          child: IgnorePointer(
            child: SizedBox(
              width: 100,
              child: Text(
                '${rotationDeg.round()}°',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: center.dx - 50,
          top: center.dy + _ringRadius + 12,
          child: IgnorePointer(
            child: SizedBox(
              width: 100,
              child: Text(
                objectName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: center.dx - _ringRadius - _dragPad,
          top: center.dy - _ringRadius - _dragPad,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onPanUpdate: (details) {
              final dx = details.localPosition.dx - gizmoLocalCenter.dx;
              final dy = details.localPosition.dy - gizmoLocalCenter.dy;
              final screenAngle = math.atan2(dy, dx);
              var deg =
                  rotationSign * (screenAngle - screenRefAngle) * 180 / math.pi;
              onRotationChanged(_snapAngle(deg));
            },
            child: _CircularHitRegion(
              radius: _ringRadius + _dragPad,
              innerRadius: _ringRadius / 2,
              child: SizedBox(
                width: (_ringRadius + _dragPad) * 2,
                height: (_ringRadius + _dragPad) * 2,
              ),
            ),
          ),
        ),
        Positioned(
          left: handleDx - _handleRadius,
          top: handleDy - _handleRadius,
          child: IgnorePointer(
            child: Container(
              width: _handleRadius * 2,
              height: _handleRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.cyanAccent,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: center.dx + _ringRadius + 8,
          top: center.dy - _ringRadius - 8,
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.85),
                border: Border.all(color: Colors.white30),
              ),
              child: const Icon(Icons.close, color: Colors.white70, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _CircularHitRegion extends SingleChildRenderObjectWidget {
  const _CircularHitRegion({
    required this.radius,
    this.innerRadius = 0,
    super.child,
  });
  final double radius;
  final double innerRadius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCircularHit(radius, innerRadius);

  @override
  void updateRenderObject(
      BuildContext context, _RenderCircularHit renderObject) {
    renderObject.radius = radius;
    renderObject.innerRadius = innerRadius;
  }
}

class _RenderCircularHit extends RenderProxyBox {
  _RenderCircularHit(this._radius, this._innerRadius);
  double _radius;
  double _innerRadius;
  set radius(double v) {
    _radius = v;
    markNeedsPaint();
  }

  set innerRadius(double v) {
    _innerRadius = v;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final center = size.center(Offset.zero);
    final dist = (position - center).distance;
    if (dist > _radius || dist < _innerRadius) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class RingPainter extends CustomPainter {
  RingPainter({
    required this.ringRadius,
    required this.rotationDeg,
    required this.tickCount,
    required this.screenRefAngle,
    required this.rotationSign,
  });

  final double ringRadius;
  final double rotationDeg;
  final int tickCount;
  final double screenRefAngle;
  final double rotationSign;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    final ringPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(c, ringRadius, ringPaint);

    final tickPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.5;
    for (int i = 0; i < tickCount; i++) {
      final faceDeg = i * 360.0 / tickCount;
      final screenAngle =
          screenRefAngle + rotationSign * faceDeg * math.pi / 180;
      final inner = ringRadius - 6;
      final outer = ringRadius + 6;
      canvas.drawLine(
        Offset(c.dx + math.cos(screenAngle) * inner,
            c.dy + math.sin(screenAngle) * inner),
        Offset(c.dx + math.cos(screenAngle) * outer,
            c.dy + math.sin(screenAngle) * outer),
        tickPaint,
      );
    }

    final startAngle = screenRefAngle;
    final sweepRad = rotationSign * rotationDeg * math.pi / 180;
    if (sweepRad.abs() > 0.01) {
      final arcPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: ringRadius),
        startAngle,
        sweepRad,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter oldDelegate) =>
      oldDelegate.rotationDeg != rotationDeg ||
      oldDelegate.screenRefAngle != screenRefAngle ||
      oldDelegate.rotationSign != rotationSign;
}
