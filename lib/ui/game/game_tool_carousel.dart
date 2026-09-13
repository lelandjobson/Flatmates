import 'package:flutter/material.dart';

const kGameToolCarouselDuration = Duration(milliseconds: 300);
const kGameToolCarouselScale = 1.33;

int carouselWrapIndex(int index, int length) {
  if (length <= 0) return 0;
  return (index % length + length) % length;
}

/// Next focus, unwrapped so last↔first is one adjacent step (2→3 or 0→-1).
double carouselFocusTarget({
  required double current,
  required int index,
  required int length,
}) {
  if (length <= 0) return 0;
  final dest = index.clamp(0, length - 1);
  var target = dest.toDouble();
  if ((target - current).abs() <= length / 2) return target;
  return target < current ? target + length : target - length;
}

/// Slot for [index] on the replica nearest [focus], so wrap items stay on-screen.
double carouselItemSlot(int index, double focus, int length) {
  if (length <= 0) return index.toDouble();
  var slot = index.toDouble();
  var best = (slot - focus).abs();
  for (final k in [-1, 1]) {
    final candidate = index + k * length.toDouble();
    final d = (candidate - focus).abs();
    if (d < best - 1e-9) {
      slot = candidate;
      best = d;
    }
  }
  return slot;
}

const kHudSelectFill = Color(0xFF141414);
const kHudGold = Color(0xFFC9A227);
const kHudBlue = Color(0xFF3D7CC9);
const kHudSunset = Color(0xFF7A4E9E);

/// Near-black with a slight gold or blue wash. [lift] 0.10 is ~10% less black.
Color hudTintedBlack(Color tint, {double amount = 0.20, double lift = 0}) {
  return Color.lerp(const Color(0xFF101010), tint, amount + lift)!;
}

Color gameModeFill(GameMode mode, {bool submenu = false}) {
  final lift = submenu ? 0.10 : 0.0;
  return switch (mode) {
    GameMode.select => Color.lerp(kHudSelectFill, Colors.white, lift)!,
    GameMode.edit => hudTintedBlack(kHudGold, amount: 0.20, lift: lift),
    GameMode.create => hudTintedBlack(kHudBlue, amount: 0.24, lift: lift),
    GameMode.action => hudTintedBlack(kHudSunset, amount: 0.44, lift: lift),
  };
}

enum GameMode { select, create, edit, action }

enum GameEditTool { transform, paint, delete }

enum GameCreateTool { volume, path, region }

enum GameSelectViewFilter { all, program }

extension GameModeX on GameMode {
  IconData get icon => switch (this) {
        GameMode.select => Icons.ads_click,
        GameMode.edit => Icons.tune,
        GameMode.create => Icons.add,
        GameMode.action => Icons.route,
      };

  String get label => switch (this) {
        GameMode.select => 'Select',
        GameMode.edit => 'Edit',
        GameMode.create => 'Create',
        GameMode.action => 'Actions',
      };

  Color get fill => gameModeFill(this);

  GameMode stepped(int delta) {
    final n = GameMode.values.length;
    return GameMode.values[(index + delta % n + n) % n];
  }
}

extension GameEditToolX on GameEditTool {
  IconData get icon => switch (this) {
        GameEditTool.transform => Icons.open_with,
        GameEditTool.paint => Icons.format_color_fill,
        GameEditTool.delete => Icons.delete_outline,
      };

  String get label => switch (this) {
        GameEditTool.transform => 'Transform',
        GameEditTool.paint => 'Paint',
        GameEditTool.delete => 'Delete',
      };

  GameEditTool stepped(int delta) {
    final n = GameEditTool.values.length;
    return GameEditTool.values[(index + delta % n + n) % n];
  }
}

extension GameSelectViewFilterX on GameSelectViewFilter {
  IconData get icon => switch (this) {
        GameSelectViewFilter.all => Icons.layers,
        GameSelectViewFilter.program => Icons.weekend_outlined,
      };

  String get label => switch (this) {
        GameSelectViewFilter.all => 'All',
        GameSelectViewFilter.program => 'Program',
      };

  GameSelectViewFilter stepped(int delta) {
    final n = GameSelectViewFilter.values.length;
    return GameSelectViewFilter.values[(index + delta % n + n) % n];
  }
}

extension GameCreateToolX on GameCreateTool {
  IconData get icon => switch (this) {
        GameCreateTool.volume => Icons.add_box,
        GameCreateTool.path => Icons.add_road,
        GameCreateTool.region => Icons.grid_on,
      };

  String get label => switch (this) {
        GameCreateTool.volume => 'Volumes',
        GameCreateTool.path => 'Paths',
        GameCreateTool.region => 'Regions',
      };

  GameCreateTool stepped(int delta) {
    final n = GameCreateTool.values.length;
    return GameCreateTool.values[(index + delta % n + n) % n];
  }
}

class HudCarouselItem<T> {
  const HudCarouselItem({
    required this.value,
    required this.icon,
    required this.label,
    required this.fill,
  });

  final T value;
  final IconData icon;
  final String label;
  final Color fill;
}

List<HudCarouselItem<GameMode>> gameModeItems({required bool showAction}) => [
      for (final mode in GameMode.values)
        if (mode != GameMode.action || showAction)
          HudCarouselItem(
            value: mode,
            icon: mode.icon,
            label: mode.label,
            fill: mode.fill,
          ),
    ];

List<HudCarouselItem<GameMode>> get kGameModeItems =>
    gameModeItems(showAction: false);

List<HudCarouselItem<GameEditTool>> get kGameEditToolItems => [
      for (final tool in GameEditTool.values)
        HudCarouselItem(
          value: tool,
          icon: tool.icon,
          label: tool.label,
          fill: gameModeFill(GameMode.edit, submenu: true),
        ),
    ];

List<HudCarouselItem<GameSelectViewFilter>> get kGameSelectViewFilterItems => [
      for (final filter in GameSelectViewFilter.values)
        HudCarouselItem(
          value: filter,
          icon: filter.icon,
          label: filter.label,
          fill: gameModeFill(GameMode.select, submenu: true),
        ),
    ];

List<HudCarouselItem<GameCreateTool>> get kGameCreateToolItems => [
      for (final tool in GameCreateTool.values)
        HudCarouselItem(
          value: tool,
          icon: tool.icon,
          label: tool.label,
          fill: gameModeFill(GameMode.create, submenu: true),
        ),
    ];

Widget hudCarouselSubmenuTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.35),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}

/// Center-bottom HUD tool row. The group stays centered; slots stay fixed.
class HudToolCarousel<T> extends StatelessWidget {
  const HudToolCarousel({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.compact = false,
  });

  final List<HudCarouselItem<T>> items;
  final T? selected;
  final ValueChanged<T> onSelect;
  final bool compact;

  double get _slot => compact ? 48.0 : 56.0;
  double get _icon => compact ? 20.0 : 24.0;
  double get _button => compact ? 34.0 : 40.0;
  double get _height => compact ? 58.0 : 72.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Align(
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              SizedBox(
                key: ValueKey(item.value),
                width: _slot,
                child: HudToolButton(
                  icon: item.icon,
                  label: item.label,
                  fill: item.fill,
                  selected: selected == item.value,
                  iconSize: _icon,
                  buttonSize: _button,
                  onTap: () => onSelect(item.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Round HUD tool used by the mode carousel and its submenus.
class HudToolButton extends StatelessWidget {
  const HudToolButton({
    super.key,
    required this.icon,
    required this.fill,
    required this.selected,
    required this.onTap,
    this.label,
    this.iconSize = 24,
    this.buttonSize = 40,
    this.enabled = true,
    this.borderColor,
  });

  final IconData icon;
  final Color fill;
  final bool selected;
  final VoidCallback? onTap;
  final String? label;
  final double iconSize;
  final double buttonSize;
  final bool enabled;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ??
        (selected ? Color.lerp(fill, Colors.white, 0.45)! : Colors.white24);
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Center(
        child: AnimatedScale(
          scale: selected ? kGameToolCarouselScale : 1,
          duration: kGameToolCarouselDuration,
          curve: Curves.easeInOutCubic,
          child: AnimatedContainer(
            duration: kGameToolCarouselDuration,
            curve: Curves.easeInOutCubic,
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill.withValues(alpha: selected ? 0.92 : 0.72),
              border: Border.all(
                color: border,
                width: selected || borderColor != null ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
    final label = this.label;
    if (label == null) return button;
    return Tooltip(message: label, child: button);
  }
}
