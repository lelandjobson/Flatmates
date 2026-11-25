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
  });
  final ConstructionTool? selected;
  final ValueChanged<ConstructionTool> onSelect;
  final ConstructionPaper paper;
  final ValueChanged<ConstructionPaper> onPaper;
  final String? entityName;
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
                ),
              )
            : const SizedBox.shrink(key: ValueKey('no-paper-palette')),
      ),
      Material(
        color: const Color(0xdd202020),
        borderRadius: BorderRadius.circular(18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final tool in ConstructionTool.values)
              Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  key: ValueKey('construction-${tool.name}'),
                  tooltip: switch (tool) {
                    ConstructionTool.pencil => 'Pencil',
                    ConstructionTool.volume => 'Inflate',
                    ConstructionTool.paper => 'Paper',
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
                  }),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// Five visible slots, fixed height, and an infinite looping center selection.
class ConstructionMaterialWheel extends StatefulWidget {
  const ConstructionMaterialWheel({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final ConstructionPaper selected;
  final ValueChanged<ConstructionPaper> onSelected;
  @override
  State<ConstructionMaterialWheel> createState() =>
      _ConstructionMaterialWheelState();
}

class _ConstructionMaterialWheelState extends State<ConstructionMaterialWheel> {
  late final controller = FixedExtentScrollController(
    initialItem: ConstructionPaper.values.length * 1000 + widget.selected.index,
  );
  @override
  void didUpdateWidget(ConstructionMaterialWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.hasClients &&
        controller.selectedItem % ConstructionPaper.values.length !=
            widget.selected.index) {
      final current = controller.selectedItem;
      final delta =
          (widget.selected.index - current % ConstructionPaper.values.length) %
          ConstructionPaper.values.length;
      controller.jumpToItem(current + delta);
    }
  }

  void cycle(int direction) => controller.animateToItem(
    controller.selectedItem + direction,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    curve: Curves.easeOut,
  );
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
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              widget.selected == ConstructionPaper.building
                  ? 'Building'
                  : 'Cloth',
              key: const ValueKey('paper-material-name'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
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
                onIncrease: () => cycle(1),
                onDecrease: () => cycle(-1),
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
                        childDelegate: ListWheelChildLoopingListDelegate(
                          children: [
                            for (final paper in ConstructionPaper.values)
                              RotatedBox(
                                quarterTurns: 1,
                                child: Center(
                                  child: Container(
                                    width: constraints.maxWidth / 5 - 12,
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
                          ],
                        ),
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
