import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../rendering/iso/iso_coordinate.dart';
import '../../rendering/iso/iso_camera.dart';
import 'hud_action.dart';

/// Radial action selector shown when dragging from an entity within the
/// short-drag threshold. Actions are arranged in a circle and the user
/// selects by dragging in the direction of the desired action.
class CircularDragHud extends StatefulWidget {
  const CircularDragHud({
    super.key,
    required this.anchor,
    required this.camera,
    required this.viewport,
    required this.actions,
    this.selectedIndex,
    this.actionLabel,
    this.onActionTap,
  });

  final IsoCoordinate anchor;
  final IsoCamera camera;
  final Size viewport;

  final List<HudAction> actions;

  /// Index into [actions] that is currently highlighted by the drag vector.
  final int? selectedIndex;

  /// Label shown at top of viewport for the currently highlighted action.
  final String? actionLabel;

  /// When non-null, buttons are tappable (for persistent radial mode).
  /// Called with the action index when a button is tapped.
  final void Function(int index)? onActionTap;

  static const double _radius = 80.0;
  static const double _buttonSize = 56.0;
  static const double _selectedScale = 1.4;

  static const Duration _entranceDuration = Duration(milliseconds: 200);

  /// Returns the angular positions (in radians, 0 = top) for [count] actions.
  static List<double> anglesForCount(int count) {
    if (count <= 0) return [];
    if (count == 1) return [0.0];
    if (count == 2) return [-math.pi / 6, math.pi / 6];
    if (count == 3) return [0.0, -2 * math.pi / 3, 2 * math.pi / 3];
    if (count == 4) return [0.0, math.pi, -math.pi / 2, math.pi / 2];
    if (count == 5) {
      return [0.0, -math.pi / 3, math.pi / 3, -2 * math.pi / 3, 2 * math.pi / 3];
    }
    if (count == 6) {
      return [0.0, -math.pi / 3, math.pi / 3, -2 * math.pi / 3, 2 * math.pi / 3, math.pi];
    }
    return List.generate(count, (i) => 2 * math.pi * i / count - math.pi / 2);
  }

  /// Given a drag vector (from center), returns the index of the action closest to that angle.
  static int? indexForDragVector(
    Offset dragVector,
    List<double> angles, {
    double maxAngleDeg = 35.0,
    double minDistanceFraction = 0.75,
  }) {
    final minDistance = minDistanceFraction * _radius;
    if (angles.isEmpty || dragVector.distance < minDistance) return null;
    final dragAngle = math.atan2(dragVector.dx, -dragVector.dy);
    double bestDist = double.infinity;
    int bestIdx = -1;
    for (int i = 0; i < angles.length; i++) {
      double diff = (dragAngle - angles[i]) % (2 * math.pi);
      if (diff > math.pi) diff -= 2 * math.pi;
      final absDiff = diff.abs();
      if (absDiff < bestDist) {
        bestDist = absDiff;
        bestIdx = i;
      }
    }
    if (bestDist > maxAngleDeg * math.pi / 180) return null;
    return bestIdx;
  }

  @override
  State<CircularDragHud> createState() => _CircularDragHudState();
}

class _CircularDragHudState extends State<CircularDragHud>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _entranceScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: CircularDragHud._entranceDuration,
      vsync: this,
    );
    _entranceScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.anchor.toScreen(widget.camera, widget.viewport);
    final actions = widget.actions;
    if (actions.isEmpty) return const SizedBox.shrink();

    final angles = CircularDragHud.anglesForCount(actions.length);
    final children = <Widget>[];

    for (int i = 0; i < actions.length; i++) {
      final angle = angles[i];
      final isSelected = widget.selectedIndex == i;
      final baseScale = isSelected ? CircularDragHud._selectedScale : 1.0;
      final size = CircularDragHud._buttonSize * baseScale;

      final dx = center.dx + CircularDragHud._radius * math.sin(angle) - size / 2;
      final dy = center.dy - CircularDragHud._radius * math.cos(angle) - size / 2;

      final button = _HudButton(
        action: actions[i],
        size: size,
        isSelected: isSelected,
      );
      final wrapped = widget.onActionTap != null
          ? GestureDetector(
              onTap: () {
                if (actions[i].enabled) widget.onActionTap!(i);
              },
              child: button,
            )
          : button;

      children.add(
        Positioned(
          left: dx,
          top: dy,
          child: AnimatedBuilder(
            animation: _entranceScale,
            builder: (context, child) {
              return Transform.scale(
                scale: _entranceScale.value,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: wrapped,
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.action,
    required this.size,
    required this.isSelected,
  });

  final HudAction action;
  final double size;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? (action.enabled ? Colors.white : Colors.grey.shade700)
        : Colors.black.withValues(alpha: 0.7);
    final iconColor = isSelected
        ? (action.enabled ? Colors.black : Colors.grey)
        : (action.enabled ? Colors.white : Colors.grey.shade600);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white38,
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 12)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 6)],
      ),
      child: action.customIcon != null
          ? SizedBox(
              width: size * 0.7,
              height: size * 0.7,
              child: Center(child: action.customIcon),
            )
          : Icon(action.icon, color: iconColor, size: size * 0.5),
    );
  }
}
