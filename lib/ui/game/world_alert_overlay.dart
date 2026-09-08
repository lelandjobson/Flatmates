import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/alerts/world_alert.dart';
import '../../gameplay/alerts/world_alert_layout.dart';
import '../../rendering/scene/camera.dart';

const kWorldAlertOutline = Color(0xFFE53935);
const kWorldAlertFill = Color(0xFF101010);
const kWorldAlertBlink = Duration(milliseconds: 1000);
const kWorldAlertStretch = Duration(milliseconds: 180);
const kWorldAlertCaret = 8.0;

/// Screen-fixed alert pills. Off-screen hosts become scaled waypoints.
class WorldAlertOverlay extends StatelessWidget {
  const WorldAlertOverlay({
    super.key,
    required this.alerts,
    required this.camera,
    required this.viewport,
    required this.pointer,
    required this.lookAt,
    required this.tileSize,
  });

  final List<WorldAlert> alerts;
  final Camera camera;
  final Size viewport;
  final Offset pointer;
  final Vector3 lookAt;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty || viewport.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final alert in alerts)
            if (placeWorldAlert(
                  alert: alert,
                  camera: camera,
                  viewport: viewport,
                  lookAt: lookAt,
                  tileSize: tileSize,
                )
                case final placed?)
              WorldAlertMarker(
                key: ValueKey(alert.id),
                placement: placed,
                pointer: pointer,
              ),
        ],
      ),
    );
  }
}

class WorldAlertMarker extends StatefulWidget {
  const WorldAlertMarker({
    super.key,
    required this.placement,
    required this.pointer,
  });

  final WorldAlertPlacement placement;
  final Offset pointer;

  @override
  State<WorldAlertMarker> createState() => _WorldAlertMarkerState();
}

class _WorldAlertMarkerState extends State<WorldAlertMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: kWorldAlertBlink,
    )..repeat();
    _expanded = _shouldExpand();
  }

  @override
  void didUpdateWidget(covariant WorldAlertMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _shouldExpand();
    if (next != _expanded) _expanded = next;
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  bool _shouldExpand() {
    if (widget.placement.waypoint) return false;
    return pointerExpandsAlert(
      pointer: widget.pointer,
      screen: widget.placement.screen,
      issueCount: widget.placement.alert.issues.length,
      currentlyExpanded: _expanded,
      scale: widget.placement.scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final placed = widget.placement;
    final issues = placed.alert.issues;
    final scale = placed.scale;
    final showSandwich = _expanded && issues.length > 1 && !placed.waypoint;
    final visualW = sandwichVisualWidth(
          issueCount: issues.length,
          expanded: showSandwich,
        ) *
        scale;
    final visualH = kWorldAlertVisualSize * scale;
    final hit = worldAlertHitRect(
      screen: placed.screen,
      issueCount: issues.length,
      expanded: showSandwich,
      scale: scale,
    );
    final hoverIssue = showSandwich
        ? nearestSandwichBubble(
            pointer: widget.pointer,
            centers: sandwichBubbleCenters(
              screen: placed.screen,
              issueCount: issues.length,
              expanded: true,
              scale: scale,
            ),
          )
        : 0;

    return Positioned(
      left: hit.left,
      top: hit.top,
      width: hit.width,
      height: hit.height,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) {
          final outlineOn = _blink.value < 0.5;
          final outline =
              outlineOn ? kWorldAlertOutline : const Color(0x00000000);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (placed.waypoint)
                Positioned.fill(
                  child: _WaypointCaret(
                    from: placed.screen,
                    toward: placed.raw,
                    radius: visualH * 0.5,
                    caret: kWorldAlertCaret * scale,
                  ),
                ),
              AnimatedScale(
                scale: _expanded && issues.length == 1 ? kWorldAlertGrow : 1,
                duration: kWorldAlertStretch,
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: kWorldAlertStretch,
                  curve: Curves.easeOutCubic,
                  width: visualW,
                  height: visualH,
                  clipBehavior: Clip.antiAlias,
                  padding: showSandwich
                      ? EdgeInsets.symmetric(
                          horizontal: kWorldAlertPillPad * scale,
                        )
                      : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: kWorldAlertFill,
                    borderRadius: BorderRadius.circular(visualH * 0.5),
                    border: Border.all(
                      color: outline,
                      width: kWorldAlertBorder * scale,
                    ),
                  ),
                  child: showSandwich
                      ? OverflowBox(
                          maxWidth: sandwichVisualWidth(
                                issueCount: issues.length,
                                expanded: true,
                              ) *
                              scale,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < issues.length; i++) ...[
                                if (i > 0)
                                  SizedBox(width: kWorldAlertBubbleGap * scale),
                                _AlertGlyph(
                                  icon: issues[i].requirementIcon,
                                  size: kWorldAlertVisualSize * scale,
                                  color: i == hoverIssue
                                      ? kWorldAlertOutline
                                      : Colors.white,
                                ),
                              ],
                            ],
                          ),
                        )
                      : _AlertGlyph(
                          icon: issues.length == 1
                              ? issues.first.requirementIcon
                              : Icons.priority_high,
                          size: kWorldAlertVisualSize * scale,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertGlyph extends StatelessWidget {
  const _AlertGlyph({
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Icon(icon, size: size * 0.56, color: color),
    );
  }
}

class _WaypointCaret extends StatelessWidget {
  const _WaypointCaret({
    required this.from,
    required this.toward,
    required this.radius,
    required this.caret,
  });

  final Offset from;
  final Offset toward;
  final double radius;
  final double caret;

  @override
  Widget build(BuildContext context) {
    var dx = toward.dx - from.dx;
    var dy = toward.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-3) return const SizedBox.shrink();
    dx /= len;
    dy /= len;
    return CustomPaint(
      painter: _CaretPainter(
        direction: Offset(dx, dy),
        radius: radius,
        caret: caret,
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter({
    required this.direction,
    required this.radius,
    required this.caret,
  });

  final Offset direction;
  final double radius;
  final double caret;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final outward = Offset(direction.dx, direction.dy);
    final side = Offset(-outward.dy, outward.dx);
    final base = center + outward * (radius + 1);
    final tip = center + outward * (radius + caret);
    final half = caret * 0.55;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + side.dx * half, base.dy + side.dy * half)
      ..lineTo(base.dx - side.dx * half, base.dy - side.dy * half)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = kWorldAlertOutline
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CaretPainter oldDelegate) {
    return oldDelegate.direction != direction ||
        oldDelegate.radius != radius ||
        oldDelegate.caret != caret;
  }
}
