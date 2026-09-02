import 'package:flutter/material.dart';

const kGameToolCarouselDuration = Duration(milliseconds: 600);
const kGameToolCarouselScale = 1.33;

enum GameMapTool { select, volume, path, wall, delete }

extension GameMapToolX on GameMapTool {
  IconData get icon => switch (this) {
        GameMapTool.select => Icons.ads_click,
        GameMapTool.volume => Icons.add_box,
        GameMapTool.path => Icons.add_road,
        GameMapTool.wall => Icons.fence,
        GameMapTool.delete => Icons.delete_outline,
      };

  String get tooltip => switch (this) {
        GameMapTool.select => 'Select',
        GameMapTool.volume => 'Volumes',
        GameMapTool.path => 'Paths',
        GameMapTool.wall => 'Walls',
        GameMapTool.delete => 'Delete',
      };

  GameMapTool stepped(int delta) {
    final n = GameMapTool.values.length;
    return GameMapTool.values[(index + delta) % n];
  }
}

/// Center-bottom map tools. The selected icon stays in the middle, 33% larger
/// with a white outline. Swipe or tap another icon to change tools (600ms).
class GameToolCarousel extends StatefulWidget {
  const GameToolCarousel({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final GameMapTool? selected;
  final ValueChanged<GameMapTool> onSelect;

  @override
  State<GameToolCarousel> createState() => _GameToolCarouselState();
}

class _GameToolCarouselState extends State<GameToolCarousel> {
  static const _slot = 56.0;
  static const _icon = 24.0;

  late double _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.selected?.index.toDouble() ??
        (GameMapTool.values.length - 1) / 2;
  }

  @override
  void didUpdateWidget(covariant GameToolCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.selected?.index.toDouble();
    if (next != null && next != _focus) {
      setState(() => _focus = next);
    }
  }

  void _swipe(int delta) {
    final current = widget.selected ??
        GameMapTool.values[_focus.round().clamp(0, GameMapTool.values.length - 1)];
    widget.onSelect(current.stepped(delta));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -180) {
          _swipe(1);
        } else if (velocity > 180) {
          _swipe(-1);
        }
      },
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _focus),
              duration: kGameToolCarouselDuration,
              curve: Curves.easeInOutCubic,
              builder: (context, focus, _) {
                final origin = constraints.maxWidth / 2 - (focus + 0.5) * _slot;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final tool in GameMapTool.values)
                      Positioned(
                        left: origin + tool.index * _slot,
                        top: 0,
                        bottom: 0,
                        width: _slot,
                        child: _CarouselSlot(
                          tool: tool,
                          selected: widget.selected == tool,
                          iconSize: _icon,
                          onTap: () => widget.onSelect(tool),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CarouselSlot extends StatelessWidget {
  const _CarouselSlot({
    required this.tool,
    required this.selected,
    required this.iconSize,
    required this.onTap,
  });

  final GameMapTool tool;
  final bool selected;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tool.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            scale: selected ? kGameToolCarouselScale : 1,
            duration: kGameToolCarouselDuration,
            curve: Curves.easeInOutCubic,
            child: AnimatedContainer(
              duration: kGameToolCarouselDuration,
              curve: Curves.easeInOutCubic,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: selected ? 0.78 : 0.55),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Icon(
                tool.icon,
                size: iconSize,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
