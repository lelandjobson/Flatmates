import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/alerts/world_alert_layout.dart';
import '../../gameplay/flatmates/day_action.dart';
import '../../gameplay/flatmates/world_action_bar_layout.dart';
import '../../rendering/scene/camera.dart';

const kWorldActionBarFill = Color(0xFF101010);
const kWorldActionBarStretch = Duration(milliseconds: 180);

/// World-projected day-action sandwich above each flatmate.
class WorldActionBarOverlay extends StatelessWidget {
  const WorldActionBarOverlay({
    super.key,
    required this.bars,
    required this.camera,
    required this.viewport,
    required this.pointer,
    required this.lookAt,
    required this.tileSize,
  });

  final List<FriendActionBar> bars;
  final Camera camera;
  final Size viewport;
  final Offset pointer;
  final Vector3 lookAt;
  final double tileSize;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || viewport.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final bar in bars)
            if (placeFriendActionBar(
                  bar: bar,
                  camera: camera,
                  viewport: viewport,
                  lookAt: lookAt,
                  tileSize: tileSize,
                )
                case final placed?)
              WorldActionBarMarker(
                key: ValueKey(bar.friendId),
                placement: placed,
                pointer: pointer,
              ),
        ],
      ),
    );
  }
}

class WorldActionBarMarker extends StatefulWidget {
  const WorldActionBarMarker({
    super.key,
    required this.placement,
    required this.pointer,
  });

  final FriendActionBarPlacement placement;
  final Offset pointer;

  @override
  State<WorldActionBarMarker> createState() => _WorldActionBarMarkerState();
}

class _WorldActionBarMarkerState extends State<WorldActionBarMarker> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = _shouldExpand();
  }

  @override
  void didUpdateWidget(covariant WorldActionBarMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _shouldExpand();
    if (next != _expanded) _expanded = next;
  }

  bool _shouldExpand() {
    if (widget.placement.waypoint) return false;
    return pointerExpandsAlert(
      pointer: widget.pointer,
      screen: widget.placement.screen,
      issueCount: widget.placement.bar.slots.length,
      currentlyExpanded: _expanded,
      scale: widget.placement.scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final placed = widget.placement;
    final slots = placed.bar.slots;
    final scale = placed.scale;
    final showSandwich = _expanded && slots.length > 1 && !placed.waypoint;
    final visualW = sandwichVisualWidth(
          issueCount: slots.length,
          expanded: showSandwich,
        ) *
        scale;
    final visualH = kWorldAlertVisualSize * scale;
    final hit = worldAlertHitRect(
      screen: placed.screen,
      issueCount: slots.length,
      expanded: showSandwich,
      scale: scale,
    );
    final hoverSlot = showSandwich
        ? nearestSandwichBubble(
            pointer: widget.pointer,
            centers: sandwichBubbleCenters(
              screen: placed.screen,
              issueCount: slots.length,
              expanded: true,
              scale: scale,
            ),
          )
        : placed.bar.summaryIndex;

    return Positioned(
      left: hit.left,
      top: hit.top,
      width: hit.width,
      height: hit.height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedScale(
            scale: _expanded && slots.length == 1 ? kWorldAlertGrow : 1,
            duration: kWorldActionBarStretch,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: kWorldActionBarStretch,
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
                color: kWorldActionBarFill,
                borderRadius: BorderRadius.circular(visualH * 0.5),
                border: Border.all(
                  width: kWorldAlertBorder * scale,
                  color: Colors.transparent,
                ),
                gradient: LinearGradient(
                  colors: [
                    for (var i = 0; i < slots.length; i++)
                      dayProgressColor(i, count: slots.length),
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kWorldActionBarFill,
                  borderRadius: BorderRadius.circular(visualH * 0.5),
                ),
                child: Padding(
                  padding: EdgeInsets.all(kWorldAlertBorder * scale),
                  child: showSandwich
                      ? OverflowBox(
                          maxWidth: sandwichVisualWidth(
                                issueCount: slots.length,
                                expanded: true,
                              ) *
                              scale,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < slots.length; i++) ...[
                                if (i > 0)
                                  SizedBox(
                                    width: kWorldAlertBubbleGap * scale,
                                  ),
                                _ActionGlyph(
                                  slot: slots[i],
                                  size: kWorldAlertVisualSize * scale,
                                  color: i == hoverSlot
                                      ? dayProgressColor(
                                          i,
                                          count: slots.length,
                                        )
                                      : Colors.white,
                                ),
                              ],
                            ],
                          ),
                        )
                      : _ActionGlyph(
                          slot: slots[placed.bar.summaryIndex.clamp(
                            0,
                            slots.length - 1,
                          )],
                          size: kWorldAlertVisualSize * scale,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph({
    required this.slot,
    required this.size,
    required this.color,
  });

  final DayActionSlot slot;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = slot.kind?.icon;
    return SizedBox(
      width: size,
      height: size,
      child: icon == null
          ? Center(
              child: Container(
                width: size * 0.42,
                height: size * 0.42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.4),
                ),
                child: Center(
                  child: Container(
                    width: size * 0.12,
                    height: size * 0.12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                ),
              ),
            )
          : Icon(icon, size: size * 0.56, color: color),
    );
  }
}