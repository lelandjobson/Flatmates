import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'construction.dart';

class ConstructionToolbar extends StatelessWidget {
  const ConstructionToolbar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.paper,
    required this.onPaper,
    this.entityName,
    this.stock,
    this.price,
    this.onBuy,
    this.available = const {...ConstructionTool.values},
    this.selectionControls = const [],
  });
  final Set<ConstructionTool> available;
  final List<Widget> selectionControls;
  final ConstructionTool? selected;
  final ValueChanged<ConstructionTool> onSelect;
  final ConstructionPaper paper;
  final ValueChanged<ConstructionPaper> onPaper;
  final String? entityName;
  final int? stock, price;
  final VoidCallback? onBuy;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (entityName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xdd202020),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                entityName!,
                key: const ValueKey('construction-entity-name'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => SizeTransition(
          axis: Axis.horizontal,
          alignment: Alignment.center,
          sizeFactor: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: selected == ConstructionTool.paper
            ? Padding(
                key: const ValueKey('paper-palette'),
                padding: const EdgeInsets.only(bottom: 6),
                child: ConstructionMaterialWheel(
                  selected: paper,
                  onSelected: onPaper,
                  stock: stock,
                  price: price,
                  onBuy: onBuy,
                ),
              )
            : const SizedBox.shrink(key: ValueKey('no-paper-palette')),
      ),
      Material(
        color: const Color(0xdd202020),
        borderRadius: BorderRadius.circular(18),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...selectionControls,
            for (final tool in ConstructionTool.values.where(
              available.contains,
            ))
              Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  key: ValueKey('construction-${tool.name}'),
                  tooltip: switch (tool) {
                    ConstructionTool.pencil => 'Pencil',
                    ConstructionTool.volume => 'Volume',
                    ConstructionTool.paper => 'Paper',
                    ConstructionTool.scissors => 'Scissors',
                    ConstructionTool.fold => 'Fold',
                  },
                  isSelected: selected == tool,
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: selected == tool
                        ? const Color(0xff586a51)
                        : Colors.transparent,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => onSelect(tool),
                  icon: Icon(switch (tool) {
                    ConstructionTool.pencil => Icons.edit,
                    ConstructionTool.volume => Icons.view_in_ar,
                    ConstructionTool.paper => Icons.layers,
                    ConstructionTool.scissors => Icons.content_cut,
                    ConstructionTool.fold => Icons.flip,
                  }),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Five visible slots; short material lists have finite ends.
class ConstructionMaterialWheel extends StatefulWidget {
  const ConstructionMaterialWheel({
    super.key,
    required this.selected,
    required this.onSelected,
    this.stock,
    this.price,
    this.onBuy,
  });
  final ConstructionPaper selected;
  final ValueChanged<ConstructionPaper> onSelected;
  final int? stock, price;
  final VoidCallback? onBuy;
  @override
  State<ConstructionMaterialWheel> createState() =>
      _ConstructionMaterialWheelState();
}

class _ConstructionMaterialWheelState extends State<ConstructionMaterialWheel> {
  bool get wraps => ConstructionPaper.values.length >= 5;
  late final controller = FixedExtentScrollController(
    initialItem:
        (wraps ? ConstructionPaper.values.length * 1000 : 0) +
        widget.selected.index,
  );
  int itemFor(ConstructionPaper paper) {
    if (!wraps) return paper.index;
    final count = ConstructionPaper.values.length;
    final current = controller.selectedItem;
    var delta = (paper.index - current % count) % count;
    if (delta > count / 2) delta -= count;
    return current + delta;
  }

  @override
  void didUpdateWidget(ConstructionMaterialWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.hasClients &&
        controller.selectedItem % ConstructionPaper.values.length !=
            widget.selected.index) {
      controller.jumpToItem(itemFor(widget.selected));
    }
  }

  void centerItem(int index) {
    if (!wraps) index = index.clamp(0, ConstructionPaper.values.length - 1);
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToItem(index);
    } else {
      controller.animateToItem(
        index,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  void cycle(int direction) => centerItem(controller.selectedItem + direction);
  ListWheelChildDelegate materialDelegate(double width) {
    final children = [
      for (final paper in ConstructionPaper.values)
        RotatedBox(
          quarterTurns: 1,
          child: GestureDetector(
            key: ValueKey('paper-material-${paper.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => centerItem(itemFor(paper)),
            child: Center(
              child: Container(
                width: width / 5 - 12,
                height: 30,
                decoration: BoxDecoration(
                  color: paper.material.base,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
    return wraps
        ? ListWheelChildLoopingListDelegate(children: children)
        : ListWheelChildListDelegate(children: children);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xdd202020),
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      height: 64,
      child: Column(
        children: [
          SizedBox(
            height: 24,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.selected == ConstructionPaper.building
                        ? 'Building'
                        : 'Cloth',
                    key: const ValueKey('paper-material-name'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  if (widget.stock != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${widget.stock} units',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      key: const ValueKey('buy-paper'),
                      onTap: widget.onBuy,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          '+16 / ${widget.price} coins',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Semantics(
                label: 'Paper material',
                value: widget.selected == ConstructionPaper.building
                    ? 'Building'
                    : 'Cloth',
                increasedValue: widget.selected == ConstructionPaper.building
                    ? 'Cloth'
                    : 'Building',
                decreasedValue: widget.selected == ConstructionPaper.building
                    ? 'Cloth'
                    : 'Building',
                onIncrease:
                    wraps ||
                        widget.selected.index <
                            ConstructionPaper.values.length - 1
                    ? () => cycle(1)
                    : null,
                onDecrease: wraps || widget.selected.index > 0
                    ? () => cycle(-1)
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotatedBox(
                      quarterTurns: 3,
                      child: ListWheelScrollView.useDelegate(
                        key: const ValueKey('paper-material-wheel'),
                        controller: controller,
                        itemExtent: constraints.maxWidth / 5,
                        diameterRatio: 100,
                        perspective: .001,
                        useMagnifier: true,
                        magnification: 1.1,
                        overAndUnderCenterOpacity: .38,
                        physics: const FixedExtentScrollPhysics(),
                        scrollBehavior: const MaterialScrollBehavior().copyWith(
                          dragDevices: PointerDeviceKind.values.toSet(),
                          scrollbars: false,
                        ),
                        onSelectedItemChanged: (index) => widget.onSelected(
                          ConstructionPaper.values[index %
                              ConstructionPaper.values.length],
                        ),
                        childDelegate: materialDelegate(constraints.maxWidth),
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        width: constraints.maxWidth / 5,
                        height: 38,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white38),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
