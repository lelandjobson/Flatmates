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
  };
}

enum GameMode { select, create, edit }

enum GameEditTool { transform, paint, delete }

enum GameCreateTool { volume, path, wall }

enum GameSelectViewFilter { all, program }

extension GameModeX on GameMode {
  IconData get icon => switch (this) {
        GameMode.select => Icons.ads_click,
        GameMode.edit => Icons.tune,
        GameMode.create => Icons.add,
      };

  String get label => switch (this) {
        GameMode.select => 'Select',
        GameMode.edit => 'Edit',
        GameMode.create => 'Create',
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
        GameCreateTool.wall => Icons.fence,
      };

  String get label => switch (this) {
        GameCreateTool.volume => 'Volumes',
        GameCreateTool.path => 'Paths',
        GameCreateTool.wall => 'Walls',
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

List<HudCarouselItem<GameMode>> get kGameModeItems => [
      for (final mode in GameMode.values)
        HudCarouselItem(
          value: mode,
          icon: mode.icon,
          label: mode.label,
          fill: mode.fill,
        ),
    ];

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

/// Center-bottom HUD carousel. The selected icon stays in the middle.
class HudToolCarousel<T> extends StatefulWidget {
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

  @override
  State<HudToolCarousel<T>> createState() => _HudToolCarouselState<T>();
}

class _HudToolCarouselState<T> extends State<HudToolCarousel<T>>
    with SingleTickerProviderStateMixin {
  double get _slot => widget.compact ? 48.0 : 56.0;
  double get _icon => widget.compact ? 20.0 : 24.0;
  double get _button => widget.compact ? 34.0 : 40.0;
  double get _height => widget.compact ? 58.0 : 72.0;

  late final AnimationController _anim;
  late final CurvedAnimation _curve;
  double _from = 0;
  double _to = 0;
  double _dragDx = 0;

  double get _focus => _from + (_to - _from) * _curve.value;

  int get _selectedIndex {
    final selected = widget.selected;
    if (selected == null) return 0;
    final index = widget.items.indexWhere((item) => item.value == selected);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _to = widget.items.isEmpty ? 0 : _selectedIndex.toDouble();
    _from = _to;
    _anim = AnimationController(
      vsync: this,
      duration: kGameToolCarouselDuration,
    )
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _normalizeFocus();
      });
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HudToolCarousel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _anim.duration = kGameToolCarouselDuration;
    if (oldWidget.selected != widget.selected) {
      _animateTo(_selectedIndex);
    }
  }

  void _normalizeFocus() {
    final n = widget.items.length;
    if (n <= 0) return;
    final wrapped = carouselWrapIndex(_to.round(), n).toDouble();
    if ((_to - wrapped).abs() < 0.001) return;
    _from = wrapped;
    _to = wrapped;
  }

  void _animateTo(int index) {
    final target = carouselFocusTarget(
      current: _focus,
      index: index,
      length: widget.items.length,
    );
    if ((target - _focus).abs() < 0.001) return;
    _from = _focus;
    _to = target;
    _anim.forward(from: 0);
  }

  void _swipe(int delta) {
    if (widget.items.isEmpty) return;
    final next = carouselWrapIndex(
      _selectedIndex + delta,
      widget.items.length,
    );
    widget.onSelect(widget.items[next].value);
  }

  double _itemLeft(double center, int i) {
    final slot = carouselItemSlot(i, _focus, widget.items.length);
    return center + (slot - _focus) * _slot;
  }

  void _finishSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -80 || _dragDx < -24) {
      _swipe(1);
    } else if (velocity > 80 || _dragDx > 24) {
      _swipe(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
      onHorizontalDragEnd: _finishSwipe,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final n = widget.items.length;
            final center = constraints.maxWidth / 2 - _slot / 2;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var i = 0; i < n; i++)
                  Positioned(
                    key: ValueKey(i),
                    left: _itemLeft(center, i),
                    top: 0,
                    bottom: 0,
                    width: _slot,
                    child: _CarouselSlot(
                      icon: widget.items[i].icon,
                      label: widget.items[i].label,
                      fill: widget.items[i].fill,
                      selected: widget.selected == widget.items[i].value,
                      iconSize: _icon,
                      buttonSize: _button,
                      onTap: () => widget.onSelect(widget.items[i].value),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CarouselSlot extends StatelessWidget {
  const _CarouselSlot({
    required this.icon,
    required this.label,
    required this.fill,
    required this.selected,
    required this.iconSize,
    required this.buttonSize,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final bool selected;
  final double iconSize;
  final double buttonSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
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
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill.withValues(alpha: selected ? 0.92 : 0.72),
                border: Border.all(
                  color: selected
                      ? Color.lerp(fill, Colors.white, 0.45)!
                      : Colors.white24,
                  width: selected ? 2 : 1,
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
      ),
    );
  }
}
