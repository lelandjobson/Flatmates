import 'package:flutter/material.dart';

import '../../gameplay/flatmates/day_action.dart';
import '../../gameplay/flatmates/day_action_store.dart';
import 'game_tool_carousel.dart';

/// Submenu-slot widget: play sits left of a centered, gradient-framed day row.
class ActionDayStrip extends StatelessWidget {
  const ActionDayStrip({
    super.key,
    required this.plan,
    required this.playing,
    required this.onPlay,
    required this.onSlotTap,
    this.selectedSlot,
  });

  final FlatmateDayPlan? plan;
  final bool playing;
  final VoidCallback onPlay;
  final ValueChanged<int> onSlotTap;
  final int? selectedSlot;

  @override
  Widget build(BuildContext context) {
    final slots = plan?.slots ?? emptyDaySlots(null);
    final fill = gameModeFill(GameMode.action, submenu: true);
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: HudToolButton(
                    icon: playing ? Icons.stop : Icons.play_arrow,
                    label: playing ? 'Stop' : 'Play',
                    fill: fill,
                    selected: playing,
                    iconSize: 18,
                    buttonSize: 34,
                    onTap: onPlay,
                  ),
                ),
              ),
            ),
          ),
          _ActionSlotsFrame(
            fill: fill,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < slots.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: HudToolButton(
                      icon: slots[i].locked
                          ? Icons.bed_outlined
                          : (slots[i].kind?.icon ?? Icons.add),
                      label: slots[i].locked
                          ? 'Sleep'
                          : (slots[i].kind?.label ?? 'Program action'),
                      fill: fill,
                      selected: selectedSlot == i,
                      enabled: !slots[i].locked,
                      iconSize: 16,
                      buttonSize: 34,
                      borderColor: plan?.firstBrokenHop != null &&
                              i >= plan!.firstBrokenHop!
                          ? const Color(0xFFE53935)
                          : null,
                      onTap: () => onSlotTap(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _ActionSlotsFrame extends StatelessWidget {
  const _ActionSlotsFrame({
    required this.fill,
    required this.child,
  });

  final Color fill;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [kDayStartYellow, kDayEndMidnight],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }
}
