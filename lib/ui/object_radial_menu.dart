import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Preferred compass slot for a [RadialAction] around the selection.
enum RadialActionSide { top, right, bottom, left, topLeft, bottomLeft }

class RadialAction {
  const RadialAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.side,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  /// When set, this action is pinned to that side of the selection instead
  /// of being evenly distributed with the other actions.
  final RadialActionSide? side;
}

class ObjectRadialMenu extends StatefulWidget {
  const ObjectRadialMenu({
    super.key,
    required this.center,
    required this.actions,
    this.title,
    this.radius = 70.0,
    this.buttonSize = 42.0,
  });

  final Offset center;
  final List<RadialAction> actions;
  final String? title;
  final double radius;
  final double buttonSize;

  @override
  State<ObjectRadialMenu> createState() => _ObjectRadialMenuState();
}

class _ObjectRadialMenuState extends State<ObjectRadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.actions.length;
    final angles = _actionAngles(widget.actions);

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.title != null)
              Positioned(
                left: widget.center.dx - 60,
                top: widget.center.dy -
                    widget.radius -
                    widget.buttonSize -
                    20,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _scaleAnim.value.clamp(0.0, 1.0),
                    child: SizedBox(
                      width: 120,
                      child: Text(
                        widget.title!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            for (int i = 0; i < count; i++)
              _buildButton(widget.actions[i], angles[i]),
          ],
        );
      },
    );
  }

  Widget _buildButton(RadialAction action, double angle) {
    final dx =
        widget.center.dx + math.cos(angle) * widget.radius - widget.buttonSize / 2;
    final dy =
        widget.center.dy + math.sin(angle) * widget.radius - widget.buttonSize / 2;

    final tint = action.tint;
    final bgColor = tint != null
        ? Color.lerp(Colors.black, tint, 0.2)!.withOpacity(0.85)
        : Colors.black.withOpacity(0.85);
    final borderColor = tint?.withOpacity(0.45) ?? Colors.white30;
    final iconColor = tint != null
        ? Color.lerp(Colors.white, tint, 0.35)!
        : Colors.white;
    final labelColor = tint?.withOpacity(0.7) ?? Colors.white60;

    return Positioned(
      left: dx,
      top: dy,
      child: Transform.scale(
        scale: _scaleAnim.value,
        child: GestureDetector(
          onTap: action.onTap,
          child: Container(
            width: widget.buttonSize,
            height: widget.buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: iconColor, size: 16),
                Text(
                  action.label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 8,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Even distribution from the top, unless any action pins a [RadialActionSide].
  /// Sided actions keep their compass slot; remaining actions fill leftover
  /// cardinals (and midpoints when there are more than four actions).
  static List<double> _actionAngles(List<RadialAction> actions) {
    final n = actions.length;
    if (n == 0) return const [];

    final reserved = <int, double>{};
    for (var i = 0; i < n; i++) {
      final side = actions[i].side;
      if (side != null) reserved[i] = _angleForSide(side);
    }

    if (reserved.isEmpty) {
      return [
        for (var i = 0; i < n; i++) -math.pi / 2 + (2 * math.pi / n) * i,
      ];
    }

    final slots = <double>[-math.pi / 2, 0, math.pi / 2, math.pi];
    while (slots.length < n) {
      _insertLargestGapMidpoint(slots, reserved.values);
    }
    if (slots.length > n) {
      _removeLowestPrioritySlots(slots, reserved.values, n);
    }

    final angles = List<double>.filled(n, 0);
    for (final entry in reserved.entries) {
      angles[entry.key] = entry.value;
    }

    final remaining = slots
        .where((slot) => !_isNearAny(slot, reserved.values))
        .toList()
      ..sort(_compareClockwiseFromTop);
    var remainingIndex = 0;
    for (var i = 0; i < n; i++) {
      if (reserved.containsKey(i)) continue;
      angles[i] = remaining[remainingIndex++];
    }
    return angles;
  }

  static double _angleForSide(RadialActionSide side) {
    switch (side) {
      case RadialActionSide.top:
        return -math.pi / 2;
      case RadialActionSide.right:
        return 0;
      case RadialActionSide.bottom:
        return math.pi / 2;
      case RadialActionSide.left:
        return math.pi;
      case RadialActionSide.topLeft:
        return -3 * math.pi / 4;
      case RadialActionSide.bottomLeft:
        return 3 * math.pi / 4;
    }
  }

  static void _insertLargestGapMidpoint(
    List<double> slots,
    Iterable<double> reserved,
  ) {
    final sorted = List<double>.from(slots)..sort();
    var bestIndex = 0;
    var bestGap = -1.0;
    var bestReservedEnd = false;
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      final b = i + 1 < sorted.length ? sorted[i + 1] : sorted[0] + 2 * math.pi;
      final gap = b - a;
      final reservedEnd = _isNearAny(b, reserved);
      if (gap > bestGap + 1e-6 || (gap >= bestGap - 1e-6 && reservedEnd && !bestReservedEnd)) {
        bestGap = gap;
        bestIndex = i;
        bestReservedEnd = reservedEnd;
      }
    }
    slots.add(_normalizeAngle(sorted[bestIndex] + bestGap / 2));
  }

  static void _removeLowestPrioritySlots(
    List<double> slots,
    Iterable<double> reserved,
    int keepCount,
  ) {
    while (slots.length > keepCount) {
      var removeAt = -1;
      var bestPriority = 1 << 30;
      for (var i = 0; i < slots.length; i++) {
        if (_isNearAny(slots[i], reserved)) continue;
        final priority = _keepPriority(slots[i]);
        if (priority < bestPriority) {
          bestPriority = priority;
          removeAt = i;
        }
      }
      if (removeAt < 0) break;
      slots.removeAt(removeAt);
    }
  }

  static int _keepPriority(double angle) {
    if (_anglesNear(angle, -math.pi / 2)) return 4;
    if (_anglesNear(angle, math.pi / 2)) return 3;
    if (_anglesNear(angle, math.pi) || _anglesNear(angle, -math.pi)) return 2;
    if (_anglesNear(angle, 0)) return 1;
    return 0;
  }

  static int _compareClockwiseFromTop(double a, double b) {
    return _fromTop(a).compareTo(_fromTop(b));
  }

  static double _fromTop(double angle) {
    var t = angle + math.pi / 2;
    while (t < 0) {
      t += 2 * math.pi;
    }
    while (t >= 2 * math.pi) {
      t -= 2 * math.pi;
    }
    return t;
  }

  static double _normalizeAngle(double angle) {
    var a = angle;
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    return a;
  }

  static bool _isNearAny(double angle, Iterable<double> others) {
    for (final other in others) {
      if (_anglesNear(angle, other)) return true;
    }
    return false;
  }

  static bool _anglesNear(double a, double b) {
    var d = (a - b).abs();
    if (d > math.pi) d = 2 * math.pi - d;
    return d < 0.05;
  }
}
