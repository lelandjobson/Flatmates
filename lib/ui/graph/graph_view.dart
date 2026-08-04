import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'graph_controller.dart';
import 'graph_data.dart';
import 'graph_edge_painter.dart';
import 'graph_node_menu.dart';
import 'graph_node_widget.dart';
import 'graph_theme.dart';

class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.controller,
    this.theme = GraphViewTheme.dark,
    this.iconBuilder,
    this.onNodeInfo,
    this.onBackgroundDoubleTap,
    this.transformationController,
  });

  final GraphViewController controller;
  final GraphViewTheme theme;
  final Widget Function(GraphNodeData node, double size)? iconBuilder;
  final void Function(String nodeId)? onNodeInfo;
  final VoidCallback? onBackgroundDoubleTap;

  /// When supplied, the view uses this controller instead of creating its own.
  /// The caller owns disposal.
  final TransformationController? transformationController;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> with TickerProviderStateMixin {
  late final TransformationController _transformController;
  late final bool _ownsTransformController;
  late AnimationController _exitController;
  late Animation<double> _exitAnimation;
  late AnimationController _zoomController;
  Animation<Matrix4>? _zoomAnimation;

  Rect _graphBounds = Rect.zero;
  Size _viewportSize = Size.zero;
  bool _isClamping = false;
  GraphViewMode? _lastViewMode;
  String? _lastRootId;

  GraphViewController get _ctrl => widget.controller;
  GraphViewTheme get _theme => widget.theme;

  @override
  void initState() {
    super.initState();
    if (widget.transformationController != null) {
      _transformController = widget.transformationController!;
      _ownsTransformController = false;
    } else {
      _transformController = TransformationController();
      _ownsTransformController = true;
    }
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _exitAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _ctrl.clearExitingNodes();
        _exitController.reset();
      }
    });

    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _zoomController.addListener(() {
      if (_zoomAnimation != null) {
        _transformController.value = _zoomAnimation!.value;
      }
    });

    _transformController.addListener(_clampTransform);
    _ctrl.addListener(_onControllerChanged);

    if (_ctrl.rootId != null) {
      _zoomToFitAfterBuild();
    }
  }

  @override
  void didUpdateWidget(covariant GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _transformController.removeListener(_clampTransform);
    _exitController.dispose();
    _zoomController.dispose();
    if (_ownsTransformController) _transformController.dispose();
    super.dispose();
  }

  /// Clamps the current transform so the graph bounding box can never fully
  /// leave the viewport: each edge of the bbox stops at the opposite edge of
  /// the screen (e.g. graph-left can't go past viewport-right).
  void _clampTransform() {
    if (_isClamping ||
        _viewportSize == Size.zero ||
        _graphBounds == Rect.zero) {
      return;
    }

    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final tx = matrix[12];
    final ty = matrix[13];

    final b = _graphBounds;
    final vw = _viewportSize.width;
    final vh = _viewportSize.height;

    // Graph right edge (in screen coords) must stay >= 0
    // Graph left edge (in screen coords) must stay <= viewportWidth
    final minTx = -b.right * scale;
    final maxTx = vw - b.left * scale;
    // Same vertically
    final minTy = -b.bottom * scale;
    final maxTy = vh - b.top * scale;

    final clampedTx = tx.clamp(minTx, maxTx);
    final clampedTy = ty.clamp(minTy, maxTy);

    if ((clampedTx - tx).abs() > 0.5 || (clampedTy - ty).abs() > 0.5) {
      _isClamping = true;
      final clamped = matrix.clone();
      clamped[12] = clampedTx;
      clamped[13] = clampedTy;
      _transformController.value = clamped;
      _isClamping = false;
    }
  }

  void _onControllerChanged() {
    if (_ctrl.exitingNodes.isNotEmpty && !_exitController.isAnimating) {
      _exitController.forward(from: 0);
    }
    final modeChanged = _lastViewMode != null && _lastViewMode != _ctrl.viewMode;
    final rootChanged = _ctrl.rootId != null && _lastRootId != _ctrl.rootId;
    if (modeChanged || rootChanged) {
      _zoomToFitAfterBuild();
    }
    _lastViewMode = _ctrl.viewMode;
    _lastRootId = _ctrl.rootId;
    setState(() {});
  }

  void _zoomToFitAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rootId = _ctrl.rootId;
      if (rootId == null) return;
      final visible = _ctrl.buildVisibleGraph();
      if (visible == null) return;
      _animateZoomToFit(rootId, visible.positions);
    });
  }

  void _animateZoomToFit(String nodeId, Map<String, Offset> positions) {
    final viewportSize = (context.findRenderObject() as RenderBox?)?.size;
    if (viewportSize == null) return;

    final targetMatrix = _ctrl.zoomToFitMatrix(
      nodeId: nodeId,
      positions: positions,
      viewportSize: viewportSize,
    );
    if (targetMatrix == null) return;

    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeInOut,
    ));
    _zoomController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _ctrl.buildVisibleGraph();
    if (visible == null) {
      return Center(
        child: Text(
          'No graph data available.',
          style: TextStyle(color: _theme.textMuted),
        ),
      );
    }

    final graph = visible.graph;
    final positions = visible.positions;
    final dimmedNodeIds = visible.dimmedNodeIds;

    if (graph.nodeIds.isEmpty) {
      return Center(
        child: Text(
          'No dependency graph found for this item.',
          style: TextStyle(color: _theme.textMuted),
        ),
      );
    }

    final canvasSize = _canvasSizeForPositions(positions.values);
    _graphBounds = _computeGraphBounds(positions.values);

    final quantityByNode = <String, int>{};
    for (final edge in graph.edges) {
      if (edge.amount <= 1) continue;
      final prev = quantityByNode[edge.sourceId] ?? 1;
      quantityByNode[edge.sourceId] = math.max(prev, edge.amount);
    }

    final selectedId = _ctrl.selectedNodeId;
    final menuSpace = _theme.menuButtonSize + 14.0;

    return GestureDetector(
      onTap: () => _ctrl.deselect(),
      onDoubleTap: widget.onBackgroundDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          return InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            minScale: _theme.minScale,
            maxScale: 2.6,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GraphEdgePainter(
                        edges: graph.edges,
                        positions: positions,
                        colorForNode: (id) =>
                            _ctrl.resolveNode(id)?.color ??
                            _theme.edgeFallbackColor,
                        theme: _theme,
                        dimmedNodeIds: dimmedNodeIds,
                      ),
                    ),
                  ),
                  ...positions.entries.map((entry) {
                    final node = _ctrl.resolveNode(entry.key);
                    if (node == null) return const SizedBox.shrink();
                    final qty = quantityByNode[entry.key] ?? 1;
                    final isRoot = entry.key == graph.rootId;
                    final isSelected = entry.key == selectedId;
                    final isDimmed = dimmedNodeIds.contains(entry.key);
                    final canToggle = node.hasChildren &&
                        _ctrl.isFocusMode;
                    final canExpandMenu = canToggle && !isRoot;

                    void doSmartToggle() {
                      _ctrl.smartToggle(entry.key, positions);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final updated = _ctrl.buildVisibleGraph();
                        if (updated != null) {
                          _animateZoomToFit(entry.key, updated.positions);
                        }
                      });
                    }

                    return Positioned(
                      left: entry.value.dx,
                      top: entry.value.dy - menuSpace,
                      width: _theme.nodeWidth,
                      height: _theme.nodeHeight + menuSpace,
                      child: _InteractiveNode(
                        node: node,
                        theme: _theme,
                        quantity: qty,
                        isRoot: isRoot,
                        isSelected: isSelected,
                        isDimmed: isDimmed,
                        isExpanded: _ctrl.isExpanded(entry.key),
                        isFocusMode: _ctrl.isFocusMode,
                        iconBuilder: widget.iconBuilder,
                        onTap: () => _ctrl.toggleSelect(entry.key),
                        onDoubleTap: canToggle
                            ? doSmartToggle
                            : () {},
                        onInfo: widget.onNodeInfo != null
                            ? () => widget.onNodeInfo!(entry.key)
                            : null,
                        onToggleExpand: canExpandMenu
                            ? doSmartToggle
                            : null,
                      ),
                    );
                  }),
                  if (_ctrl.exitingNodes.isNotEmpty)
                    ..._ctrl.exitingNodes.entries.map((entry) {
                      final node = _ctrl.resolveNode(entry.key);
                      if (node == null) return const SizedBox.shrink();
                      return Positioned(
                        left: entry.value.dx,
                        top: entry.value.dy,
                        width: _theme.nodeWidth,
                        height: _theme.nodeHeight,
                        child: FadeTransition(
                          opacity: _exitAnimation,
                          child: GraphNodeWidget(
                            node: node,
                            theme: _theme,
                            iconBuilder: widget.iconBuilder,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Size _canvasSizeForPositions(Iterable<Offset> positions) {
    if (positions.isEmpty) return const Size(1600, 900);
    var maxX = 0.0;
    var maxY = 0.0;
    for (final p in positions) {
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Size(
      maxX + _theme.nodeWidth + _theme.canvasPadding,
      maxY + _theme.nodeHeight + _theme.canvasPadding,
    );
  }

  Rect _computeGraphBounds(Iterable<Offset> positions) {
    if (positions.isEmpty) return Rect.zero;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in positions) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx + _theme.nodeWidth > maxX) maxX = p.dx + _theme.nodeWidth;
      if (p.dy + _theme.nodeHeight > maxY) maxY = p.dy + _theme.nodeHeight;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Wraps a [GraphNodeWidget] with tap, double-tap, and floating menu.
class _InteractiveNode extends StatelessWidget {
  const _InteractiveNode({
    required this.node,
    required this.theme,
    required this.quantity,
    required this.isRoot,
    required this.isSelected,
    required this.isDimmed,
    required this.isExpanded,
    required this.isFocusMode,
    this.iconBuilder,
    this.onTap,
    this.onDoubleTap,
    this.onInfo,
    this.onToggleExpand,
  });

  final GraphNodeData node;
  final GraphViewTheme theme;
  final int quantity;
  final bool isRoot;
  final bool isSelected;
  final bool isDimmed;
  final bool isExpanded;
  final bool isFocusMode;
  final Widget Function(GraphNodeData node, double size)? iconBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onInfo;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: theme.nodeHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child: GraphNodeWidget(
                node: node,
                theme: theme,
                quantity: quantity,
                isSelected: isSelected || isRoot,
                isDimmed: isDimmed,
                iconBuilder: iconBuilder,
              ),
            ),
          ),
        ),
        if (isSelected)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Center(
              child: GraphNodeMenu(
                theme: theme,
                hasChildren: node.hasChildren && !isRoot,
                isExpanded: isExpanded,
                isFocusMode: isFocusMode,
                onInfo: onInfo,
                onToggleExpand: onToggleExpand,
              ),
            ),
          ),
      ],
    );
  }
}

class GraphViewModeToggle extends StatelessWidget {
  const GraphViewModeToggle({
    super.key,
    required this.controller,
    required this.theme,
  });

  final GraphViewController controller;
  final GraphViewTheme theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfaceColor,
      borderRadius: BorderRadius.circular(10),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeChip(
              label: 'Focus',
              selected: controller.isFocusMode,
              theme: theme,
              onTap: () => controller.setMode(GraphViewMode.focus),
            ),
            const SizedBox(width: 4),
            _ModeChip(
              label: 'All',
              selected: controller.isAllMode,
              theme: theme,
              onTap: () => controller.setMode(GraphViewMode.all),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final GraphViewTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? theme.selectedBorder.withValues(alpha: 0.25)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? theme.selectedBorder : theme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
