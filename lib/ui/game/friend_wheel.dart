import 'package:flutter/material.dart';

import '../../gameplay/friends/friend_instance.dart';
import 'friend_portrait.dart';
import 'game_tool_carousel.dart';

/// Vertical center-select list of flatmates.
class FriendWheel extends StatefulWidget {
  const FriendWheel({
    super.key,
    required this.friends,
    required this.selectedId,
    required this.onSelect,
  });

  final List<FriendInstance> friends;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<FriendWheel> createState() => _FriendWheelState();
}

class _FriendWheelState extends State<FriendWheel>
    with SingleTickerProviderStateMixin {
  static const _slot = 56.0;
  static const _width = 64.0;

  late final AnimationController _anim;
  late final CurvedAnimation _curve;
  double _from = 0;
  double _to = 0;
  double _dragDy = 0;

  double get _focus => _from + (_to - _from) * _curve.value;

  int get _selectedIndex {
    final id = widget.selectedId;
    if (id == null) return 0;
    final index = widget.friends.indexWhere((f) => f.id == id);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _to = widget.friends.isEmpty ? 0 : _selectedIndex.toDouble();
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
  void didUpdateWidget(covariant FriendWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _animateTo(_selectedIndex);
    }
  }

  void _normalizeFocus() {
    final n = widget.friends.length;
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
      length: widget.friends.length,
    );
    if ((target - _focus).abs() < 0.001) return;
    _from = _focus;
    _to = target;
    _anim.forward(from: 0);
  }

  void _swipe(int delta) {
    if (widget.friends.isEmpty) return;
    final next = carouselWrapIndex(
      _selectedIndex + delta,
      widget.friends.length,
    );
    widget.onSelect(widget.friends[next].id);
  }

  void _finishSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -80 || _dragDy < -24) {
      _swipe(1);
    } else if (velocity > 80 || _dragDy > 24) {
      _swipe(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.friends.length;
    if (n == 0) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragDy = 0,
      onVerticalDragUpdate: (details) => _dragDy += details.delta.dy,
      onVerticalDragEnd: _finishSwipe,
      child: SizedBox(
        width: _width,
        height: _slot * 3.4,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            IgnorePointer(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1.4),
                ),
              ),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                top: _slot * 1.7 +
                    (carouselItemSlot(i, _focus, n) - _focus) * _slot -
                    22,
                child: GestureDetector(
                  onTap: () => widget.onSelect(widget.friends[i].id),
                  child: FriendPortrait(
                    friend: widget.friends[i].friend,
                    selected: widget.friends[i].id == widget.selectedId,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}