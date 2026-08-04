import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadialAction {
  const RadialAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
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
    final startAngle = -math.pi / 2;

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
              _buildButton(widget.actions[i], i, count, startAngle),
          ],
        );
      },
    );
  }

  Widget _buildButton(
    RadialAction action,
    int index,
    int count,
    double startAngle,
  ) {
    final angle = startAngle + (2 * math.pi / count) * index;
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
}
