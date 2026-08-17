import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/crafting_blueprint.dart';
import '../crafting/crafting_history.dart';
import '../crafting/crafting_material.dart';
import '../crafting/craft_manifest.dart';
import '../crafting/blueprint_set.dart';
import '../crafting/placed_paper.dart';
import '../data/crafting_state.dart';
import '../crafting/paper_splitting.dart';
import '../gameplay/inventory.dart';
import '../geometry/polygon_union.dart';
import '../geometry/geometry.dart';
import '../geometry/geometry_2d.dart';
import '../geometry/geometry_algorithms.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/friend_expression.dart';
import '../rendering/lights.dart';
import '../rendering/scene/camera.dart' as scene_camera;
import '../tiles/tiles.dart';
import '../gestures/gesture_system.dart';
import 'fm_haptics.dart';
import 'fm_safe_area.dart';
import 'object_radial_menu.dart';
import 'rotation_gizmo.dart';
import 'wipe_animation.dart';

/// Paper resize controls in the radial menu (disabled for now).
const _kPaperSizeControlsEnabled = false;

/// Inventory sheet half-extent as a fraction of one major grid cell.
/// 0.5 = 50% of the original size-1 sheet (was a full major cell).
const _kPaperHalfExtentPerLevel = 0.5;

/// Dots inside a blueprint: grid-fit quality at the current zoom spacing.
const _kGridFitMisaligned = Color(0xFFFF5252);
const _kGridFitPartial = Color(0xFFFFD54F);
const _kGridFitAligned = Color(0xFF69F0AE);
const _kGridOriginDot = Color(0xFFFFFFFF);

/// Friend walk animation during cut (disabled for now; logic preserved).
const _kCutFriendAnimationEnabled = false;

/// Space reserved above the centered bottom control column so side chrome
/// (tools, snap, close) does not overlap Fill All / undo / paper slots.
const _kBottomControlColumnClearance = 176.0;

const _noOpUndoLabels = {'Select', 'Deselect', 'Invert'};

/// Target number of grid cells visible across the viewport short axis.
const _targetCellsAcross = 32;

/// Finest LOD: -1 subdivides once more (64 cells across the plane). Each +1 coarsens.
const _minGridLod = -1;

/// Max LOD levels (each level doubles spacing by removing every other line).
const _maxGridLod = 6;

const _gridLodFadeDuration = Duration(milliseconds: 200);

// ---------------------------------------------------------------------------
// Blueprint check (runs in isolate)
// ---------------------------------------------------------------------------

class _CheckCoverageParams {
  const _CheckCoverageParams({
    required this.blueprintPolygons,
    required this.paperPolygons,
    required this.tolerance,
    this.blueprintHoles = const [],
    this.paperHoles = const [],
  });

  final List<List<Offset>> blueprintPolygons;
  final List<List<List<Offset>>> blueprintHoles;
  final List<List<Offset>> paperPolygons;
  final List<List<List<Offset>>> paperHoles;
  final double tolerance;
}

class _AABB {
  const _AABB(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;

  bool overlaps(_AABB o) =>
      maxX >= o.minX && minX <= o.maxX && maxY >= o.minY && minY <= o.maxY;
}

_AABB _aabb(List<Offset> poly) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final v in poly) {
    if (v.dx < minX) minX = v.dx;
    if (v.dy < minY) minY = v.dy;
    if (v.dx > maxX) maxX = v.dx;
    if (v.dy > maxY) maxY = v.dy;
  }
  return _AABB(minX, minY, maxX, maxY);
}

/// 2D spatial hash for fast broad-phase AABB overlap queries.
class _SpatialHash {
  _SpatialHash(this._cellSize);
  final double _cellSize;
  final Map<int, List<int>> _cells = {};

  int _key(int cx, int cy) => cx * 73856093 ^ cy * 19349663;

  void insert(int index, _AABB box) {
    final x0 = (box.minX / _cellSize).floor();
    final y0 = (box.minY / _cellSize).floor();
    final x1 = (box.maxX / _cellSize).floor();
    final y1 = (box.maxY / _cellSize).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        (_cells[_key(x, y)] ??= []).add(index);
      }
    }
  }

  Set<int> query(_AABB box) {
    final result = <int>{};
    final x0 = (box.minX / _cellSize).floor();
    final y0 = (box.minY / _cellSize).floor();
    final x1 = (box.maxX / _cellSize).floor();
    final y1 = (box.maxY / _cellSize).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final items = _cells[_key(x, y)];
        if (items != null) result.addAll(items);
      }
    }
    return result;
  }
}

/// Remove consecutive near-duplicate vertices.
List<Offset> _dedup(List<Offset> poly, double tol) {
  if (poly.length <= 1) return poly;
  final tolSq = tol * tol;
  final result = <Offset>[poly[0]];
  for (var i = 1; i < poly.length; i++) {
    final dx = poly[i].dx - result.last.dx;
    final dy = poly[i].dy - result.last.dy;
    if (dx * dx + dy * dy > tolSq) result.add(poly[i]);
  }
  if (result.length > 1) {
    final dx = result.last.dx - result.first.dx;
    final dy = result.last.dy - result.first.dy;
    if (dx * dx + dy * dy <= tolSq) result.removeLast();
  }
  return result.length >= 3 ? result : poly;
}

/// Strip vertices whose turn angle is below [angleTol] (nearly collinear).
List<Offset> _removeCollinears(List<Offset> poly, double angleTol) {
  if (poly.length <= 3) return poly;
  final result = <Offset>[];
  final n = poly.length;
  for (var i = 0; i < n; i++) {
    final prev = poly[(i - 1 + n) % n];
    final curr = poly[i];
    final next = poly[(i + 1) % n];
    final dx1 = curr.dx - prev.dx, dy1 = curr.dy - prev.dy;
    final dx2 = next.dx - curr.dx, dy2 = next.dy - curr.dy;
    final cross = dx1 * dy2 - dy1 * dx2;
    final dot = dx1 * dx2 + dy1 * dy2;
    if (math.atan2(cross.abs(), dot) > angleTol) {
      result.add(curr);
    }
  }
  return result.length >= 3 ? result : poly;
}

double _polyArea(List<Offset> p) {
  double a = 0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].dx * p[j].dy - p[j].dx * p[i].dy;
  }
  return a / 2;
}

Offset _polyCentroid(List<Offset> p) {
  double cx = 0, cy = 0;
  for (final v in p) {
    cx += v.dx;
    cy += v.dy;
  }
  return Offset(cx / p.length, cy / p.length);
}

/// Min distance from point [p] to line segment [a]-[b].
double _distToEdge(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx, aby = b.dy - a.dy;
  final lenSq = abx * abx + aby * aby;
  if (lenSq < 1e-20) {
    final dx = p.dx - a.dx, dy = p.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }
  final t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / lenSq).clamp(
    0.0,
    1.0,
  );
  final dx = p.dx - (a.dx + t * abx), dy = p.dy - (a.dy + t * aby);
  return math.sqrt(dx * dx + dy * dy);
}

/// Max distance from any vertex in [from] to the nearest edge of [to].
double _hausdorff(List<Offset> from, List<Offset> to) {
  double worst = 0;
  for (final v in from) {
    double best = double.infinity;
    for (var i = 0; i < to.length; i++) {
      final d = _distToEdge(v, to[i], to[(i + 1) % to.length]);
      if (d < best) best = d;
    }
    if (best > worst) worst = best;
  }
  return worst;
}

bool _compoundShapesMatch(
  List<Offset> paper,
  List<List<Offset>> paperHoles,
  List<Offset> blueprint,
  List<List<Offset>> blueprintHoles,
  double tol,
) {
  if (!_shapesMatch(paper, blueprint, tol)) return false;
  if (paperHoles.length != blueprintHoles.length) return false;
  if (paperHoles.isEmpty) return true;
  final used = <int>{};
  for (final hole in paperHoles) {
    var matched = false;
    for (var i = 0; i < blueprintHoles.length; i++) {
      if (used.contains(i)) continue;
      if (_shapesMatch(hole, blueprintHoles[i], tol)) {
        used.add(i);
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}

/// Peg-in-hole shape match: area + centroid pre-check, then symmetric
/// Hausdorff vertex-to-edge distance. Works regardless of vertex count,
/// vertex order, or winding direction.
bool _shapesMatch(List<Offset> paper, List<Offset> blueprint, double tol) {
  if (paper.length < 3 || blueprint.length < 3) return false;

  final aP = _polyArea(paper).abs();
  final aB = _polyArea(blueprint).abs();
  final aAvg = (aP + aB) / 2;
  if (aAvg < 1e-10) return false;
  if ((aP - aB).abs() / aAvg > 0.15) return false;

  final cP = _polyCentroid(paper);
  final cB = _polyCentroid(blueprint);
  if ((cP - cB).distance > tol * 5) return false;

  return _hausdorff(paper, blueprint) <= tol &&
      _hausdorff(blueprint, paper) <= tol;
}

/// Runs in an isolate via [compute]. For each blueprint polygon, determines
/// whether any placed paper piece's boundary matches it (peg-in-hole test).
Set<int> _checkCoverage(_CheckCoverageParams params) {
  final filled = <int>{};
  if (params.blueprintPolygons.isEmpty || params.paperPolygons.isEmpty) {
    return filled;
  }

  final tol = params.tolerance;
  final dedupTol = tol * 0.01;
  const angularTolDeg = 3.0;
  final angularTolRad = angularTolDeg * math.pi / 180;

  // Pre-process blueprint polygons (dedup only).
  final bpClean = [
    for (final bp in params.blueprintPolygons) _dedup(bp, dedupTol),
  ];

  // Build spatial hash from blueprint AABBs (expanded by tolerance).
  final bpBoxes = <_AABB>[];
  double maxDim = 0;
  for (final bp in bpClean) {
    final b = _aabb(bp);
    bpBoxes.add(b);
    maxDim = math.max(maxDim, math.max(b.maxX - b.minX, b.maxY - b.minY));
  }
  final cellSize = math.max(maxDim * 0.5, tol * 10);
  final hash = _SpatialHash(cellSize);
  for (var i = 0; i < bpBoxes.length; i++) {
    final b = bpBoxes[i];
    hash.insert(
      i,
      _AABB(b.minX - tol, b.minY - tol, b.maxX + tol, b.maxY + tol),
    );
  }

  for (var pi = 0; pi < params.paperPolygons.length; pi++) {
    final paper = params.paperPolygons[pi];
    if (paper.length < 3) continue;
    final cleaned = _removeCollinears(_dedup(paper, dedupTol), angularTolRad);
    final pHoles = pi < params.paperHoles.length
        ? [
            for (final h in params.paperHoles[pi])
              _removeCollinears(_dedup(h, dedupTol), angularTolRad),
          ]
        : const <List<Offset>>[];
    final pBox = _aabb(cleaned);
    final candidates = hash.query(
      _AABB(pBox.minX - tol, pBox.minY - tol, pBox.maxX + tol, pBox.maxY + tol),
    );
    if (candidates.isEmpty) continue;

    for (final bpIdx in candidates) {
      if (filled.contains(bpIdx)) continue;
      final bHoles = bpIdx < params.blueprintHoles.length
          ? [
              for (final h in params.blueprintHoles[bpIdx])
                _dedup(h, dedupTol),
            ]
          : const <List<Offset>>[];
      if (_compoundShapesMatch(cleaned, pHoles, bpClean[bpIdx], bHoles, tol)) {
        filled.add(bpIdx);
      }
    }
  }

  return filled;
}

// ---------------------------------------------------------------------------
// Canvas display mode
// ---------------------------------------------------------------------------

enum CanvasDisplayMode { grid, dot, none }

enum CraftingMode {
  pan,
  select,
  drawLine,
  cutting,
  paint,
  magnet,
  mirror,
  rotationCopy,
  erase,
  alignGrid,
  stencil,
}

enum StencilShape { rectangle, circle }

class ToolpathSegment {
  const ToolpathSegment(this.start, this.end, this.isCutting);
  final Offset start;
  final Offset end;
  final bool isCutting;
  double get length => (end - start).distance;
}

List<ToolpathSegment> buildToolpath(List<(Offset, Offset)> lines) {
  if (lines.isEmpty) return [];
  final result = <ToolpathSegment>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) {
      final prevEnd = lines[i - 1].$2;
      final currStart = lines[i].$1;
      if ((prevEnd - currStart).distance > 1e-4) {
        result.add(ToolpathSegment(prevEnd, currStart, false));
      }
    }
    result.add(ToolpathSegment(lines[i].$1, lines[i].$2, true));
  }
  return result;
}

/// Extends a line segment in both directions by [extension] world-units.
(Offset, Offset) extendLineSegment(Offset a, Offset b, double extension) {
  final dir = b - a;
  final len = dir.distance;
  if (len < 1e-6) return (a, b);
  final unit = dir / len;
  return (a - unit * extension, b + unit * extension);
}

class _BpVertexRef {
  const _BpVertexRef(this.polyIndex, this.vertexIndex, this.point);
  final int polyIndex;
  final int vertexIndex;
  final Offset point;
}

// ---------------------------------------------------------------------------
// Completion animation
// ---------------------------------------------------------------------------

enum CompletionPhase { none, dissolveReveal, fold, done }

class _FoldNodeState {
  _FoldNodeState({
    required this.nodeId,
    required this.localId,
    required this.islandIndex,
    required this.node,
    required this.tree,
    required this.unfoldedVertices3D,
    required this.originOffset,
    required this.foldedOffset,
  });

  final int nodeId;
  final int localId;
  final int islandIndex;
  final TransformTreeNode node;
  final TransformTree tree;
  final List<Vector3> unfoldedVertices3D;
  final Vector3 originOffset;
  final Vector3 foldedOffset;
  Matrix4 cumulativeMatrix = Matrix4.identity();
}

// PlacedPaper and PaperColor are in '../crafting/placed_paper.dart'

// ---------------------------------------------------------------------------
// Locked paper snapshot (for persisting progress across blueprint switches)
// ---------------------------------------------------------------------------

class _LockedPaperSnapshot {
  _LockedPaperSnapshot({
    required this.id,
    required this.paperColor,
    required this.position,
    required this.rotationDeg,
    required this.sizeLevel,
    required this.localVertices,
    required this.localHoles,
    required this.lockedBlueprintIndex,
    this.materialId,
    this.stackOrder = 0,
  });

  final String id;
  final PaperColor paperColor;
  final Vector3 position;
  final double rotationDeg;
  final int sizeLevel;
  final List<Offset>? localVertices;
  final List<List<Offset>> localHoles;
  final int lockedBlueprintIndex;
  final String? materialId;
  final double stackOrder;

  PlacedPaper toPaper() {
    final p = PlacedPaper(
      id: id,
      paperColor: paperColor,
      position: position.clone(),
      stackOrder: stackOrder,
      rotationDeg: rotationDeg,
      sizeLevel: sizeLevel,
      localVertices: localVertices,
      localHoles: localHoles,
      materialId: materialId,
    );
    p.locked = true;
    p.lockedBlueprintIndex = lockedBlueprintIndex;
    return p;
  }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

class CraftingTestView extends StatefulWidget {
  const CraftingTestView({
    super.key,
    this.onDismiss,
    this.canvasSize,
    this.structureFootprint,
    this.structureId,
    this.stateStore,
    this.hideDrawingPlane = true,
    this.showDotWipe = false,
    this.initialBlueprintSet,
    this.defaultBlueprintName,
    this.initialCanvasDisplayMode,
    this.initialOrthoScale,
    this.structureInventory,
    this.materialRegistry,
    this.onCraftCompleted,
    this.onCraftFoldComplete,
  });

  final VoidCallback? onDismiss;

  /// Overrides the default 400.0 drawing plane size.
  final double? canvasSize;

  /// The structure's XZ bounding rect in crafting local coords, drawn as a
  /// dashed non-selectable rectangle on the canvas.
  final Rect? structureFootprint;

  /// Identifier for the structure, used to key persisted crafting state.
  final String? structureId;

  /// In-memory store for persisting paper state across mode switches.
  final CraftingStateStore? stateStore;

  /// When true, the drawing-plane outline (the large grey square) is hidden.
  /// Defaults to hidden; pass `false` to show it.
  final bool hideDrawingPlane;

  /// When true, plays a horizontal dot-wipe reveal on entry.
  final bool showDotWipe;

  /// Optional initial [BlueprintSet] / craft selection after assets load.
  ///
  /// Matches a set [BlueprintSet.name], a group craft folder, or a single
  /// blueprint craft name (case-insensitive). When null (default), no
  /// blueprint is pre-selected.
  final String? initialBlueprintSet;

  /// Legacy alias for [initialBlueprintSet] (single-blueprint craft name).
  final String? defaultBlueprintName;

  /// Initial canvas backdrop (grid / dot / none). When null, defaults to dot.
  final CanvasDisplayMode? initialCanvasDisplayMode;

  /// Sets the initial orthographic scale (e.g. to match the room editor's
  /// final camera so the house and dashed footprint align perfectly).
  final double? initialOrthoScale;

  /// Structure inventory for material consumption/return. When non-null, paper
  /// placement draws from this inventory instead of the fixed 5/5/5 pool.
  final Inventory? structureInventory;

  /// Registry to resolve material IDs to colors/labels.
  final CraftingMaterialRegistry? materialRegistry;

  /// Called when a blueprint craft is fully completed with locked papers.
  final void Function(
    List<CraftingPaperState> papers,
    String blueprintName,
    CraftingBlueprint blueprint,
  )?
  onCraftCompleted;

  /// Called when the completion fold animation finishes. Used by the host to
  /// auto-enter placement mode for the freshly crafted object.
  final void Function(
    List<CraftingPaperState> papers,
    String blueprintName,
    CraftingBlueprint blueprint,
  )?
  onCraftFoldComplete;

  @override
  State<CraftingTestView> createState() => CraftingTestViewState();
}

class CraftingTestViewState extends State<CraftingTestView>
    with TickerProviderStateMixin {
  // Friend state (used only during cut animation)
  Quaternion _objectRotation = Quaternion.identity();
  final Vector3 _objectPosition = Vector3.zero();
  late Geometry _geometry;
  Color _objectColor = Colors.tealAccent.shade200;

  // Line drawing / cut animation
  CraftingMode _craftingMode = CraftingMode.pan;
  final List<(Offset, Offset)> _drawnCutLines = [];
  Offset? _lineDrawStart;
  Offset? _lineDrawPreview;
  List<_BpVertexRef> _cutStartVertexRefs = const [];
  List<(Offset, Offset)> _cutHighlightEdges = [];
  late final AnimationController _cutEdgeGlowController;
  Offset? _panDragLastScreen;

  // Paint tool
  bool _paintFusionEnabled = false;
  PaperColor _paintColor = PaperColor.values.first;
  String? _paintMaterialId;
  Set<(int, int)> _paintedCells = {};
  (int, int)? _lastPaintCell;
  String? _paintDragPaperId;
  Offset? _paintDragLastScreen;
  bool _paintHadSelection = false;
  (int, int)? _paintDeferredCell;
  Set<String> _paintSelectionIds = {};

  // Erase tool
  Set<(int, int)> _erasedCells = {};
  (int, int)? _lastEraseCell;

  // Pan-mode double-tap selection: allows selecting & dragging a single paper
  // while staying in pan mode.
  String? _panModeSelectedPaperId;
  DateTime? _lastPanTapTime;
  Offset? _lastPanTapPos;
  bool _panModeDragging = false;
  Offset? _panModeDragLastScreen;
  List<ToolpathSegment> _activeToolpath = [];
  double _toolpathTotalDist = 0;
  double _cutSpeed = 10.0; // minor grid cells per second
  late final AnimationController _cutAnimController;
  bool _friendVisible = false;

  // Marquee dash animation
  late final AnimationController _marqueeDashController;

  // Shared handle-box follow (stencil + stretch)
  late final Ticker _handleFollowTicker;
  Duration? _handleFollowLast;
  Rect? _handleFollowDisplay;
  Rect? _handleFollowTarget;
  void Function(Rect display)? _handleFollowApply;
  VoidCallback? _handleFollowOnSettled;
  bool _handleFollowSettling = false;

  // Lock animation
  late final AnimationController _lockAnimController;
  late final CurvedAnimation _lockAnimCurve;

  // Progress bar animation
  late final AnimationController _progressAnimController;
  double _progressAnimFrom = 0;
  double _progressAnimTo = 0;

  // Paper inventory
  final Map<PaperColor, int> _inventory = {
    PaperColor.pink: 5,
    PaperColor.yellow: 5,
    PaperColor.green: 5,
  };

  /// Whether to consume/return material from the structure inventory.
  bool get _useStructureInventory => widget.structureInventory != null;

  Inventory? get _structureInventory => widget.structureInventory;

  CraftingMaterialRegistry get _materialRegistry =>
      widget.materialRegistry ?? CraftingMaterialRegistry();

  // Undo / redo
  final CraftingHistory _history = CraftingHistory();

  // Placed papers
  final List<PlacedPaper> _placedPapers = [];
  int _nextPaperId = 0;
  int _nextStackMajor = 1;

  // Mirror tool
  Offset? _mirrorLineStart;
  Offset? _mirrorLinePreview;

  // Rotation copy tool
  Offset? _rotCopyCenterWorld;
  bool _rotCopyGizmoActive = false;
  double _rotCopyAngleDeg = 0;

  // Selection copy: last source pose, reused while the new copies stay selected.
  Offset? _copyMemorySourceCentroid;
  double _copyMemorySourceRotationDeg = 0;
  Set<String>? _copyMemorySourceIds;
  Set<String>? _copyMemoryResultIds;
  bool _suppressCopyMemorySync = false;

  // Selection & interaction
  Set<String> _selectedPaperIdsRaw = {};
  Set<String> get _selectedPaperIds => _selectedPaperIdsRaw;
  set _selectedPaperIds(Set<String> ids) {
    if (_stretchPaperId != null && !ids.contains(_stretchPaperId)) {
      _bakeStretch();
      _stretchPaperId = null;
      _clearStretchBox();
      _stopHandleFollow();
    }
    _selectedPaperIdsRaw = ids;
    if (!_suppressCopyMemorySync) {
      _syncCopyMemoryWithSelection();
    }
  }
  bool _isRotationGizmoActive = false;
  String? _dragPaperId;
  Offset? _pointerDownPos;
  String? _pointerDownPaperId;
  bool _isDragging = false;
  final GlobalKey _canvasKey = GlobalKey();

  // Marquee selection
  bool _isMarquee = false;
  Offset? _marqueeStartScreen;
  Offset? _marqueeCurrentScreen;

  // Groups
  int _nextGroupId = 0;

  // Multi-select rotation state
  double _multiRotationBaseDeg = 0;
  Map<String, double> _baseRotations = {};
  Map<String, Vector3> _basePositions = {};

  // Crafting blueprints
  List<CraftingBlueprint> _blueprints = [];
  CraftingBlueprint? _selectedBlueprint;
  List<List<Offset>> _blueprintWorldPolygons = [];
  List<List<List<Offset>>> _blueprintWorldHoles = [];
  /// All rings used for vertex / edge / ray snap (current step + holes +
  /// underlying parts on applique steps).
  List<(List<Offset> ring, bool isHole)> _snapWorldLoops = [];
  List<List<List<Offset>>> _underlyingWorldHoles = [];
  /// Blueprint edge whose infinite ray the current cut is locked to.
  (Offset, Offset)? _cutSnapRay;
  bool _blueprintUnionMode = false;
  List<List<Offset>> _blueprintUnionPolygons = [];

  // Blueprint sets
  List<BlueprintSet> _blueprintSets = [];
  BlueprintSet? _selectedSet;
  int _currentStepIndex = 0;
  final Set<int> _completedStepIndices = {};

  /// Guards against double-advance while a step completion is in flight.
  bool _fillCompleteLatched = false;

  /// Non-active group step polygons drawn grey/green behind the editable step.
  List<List<Offset>> _groupOverlayPolygons = [];
  List<Color> _groupOverlayColors = [];

  /// Active-step outline highlight (0 = grey → 1 = yellow) and early glow.
  double _activeHighlightT = 1.0;
  double _activeGlow = 0.0;

  /// 0 = unlocked look, 1 = fully locked look (keepCanvas color fade).
  double _lockFadeT = 1.0;
  Set<String> _lockFadingPaperIds = {};
  late final AnimationController _lockFadeController;

  /// Extra papers fading out after a fill completes (not in undo history).
  List<String> _discardOrder = [];
  double _discardElapsedMs = 0;
  late final AnimationController _discardController;

  /// Blueprint/applique intro: 0 = start of two white flashes, 1 = settled yellow.
  double _loadAnimT = 1.0;
  bool _hideUnfilledBlueprint = false;
  late final AnimationController _loadAnimController;

  // Camera ease-in-out transitions (group overview → step, step → step).
  late final AnimationController _cameraAnimController;
  Offset _camPanFrom = Offset.zero;
  Offset _camPanTo = Offset.zero;
  double _camOrthoFrom = 300;
  double _camOrthoTo = 300;
  double _camRotFrom = 0;
  double _camRotTo = 0;
  bool _cameraIntroHighlight = false;
  bool _pendingCameraFit = false;

  // Check mode & locking
  bool _checkMode = true;
  Set<int> _filledBlueprintIndices = {};
  Timer? _checkTimer;
  int _checkGeneration = 0;

  // Per-blueprint locked-paper persistence
  final Map<String, List<_LockedPaperSnapshot>> _blueprintProgress = {};

  // Lock animation
  Set<String> _lockAnimatingPaperIds = {};
  double _lockAnimProgress = 0;

  // Magnet tool
  late final AnimationController _magnetAnimController;
  int? _magnetTargetBpIndex;
  Offset? _magnetTargetPosition;
  double? _magnetTargetRotation;
  Offset? _magnetFreePosition;
  double? _magnetFreeRotation;
  int? _magnetPrevBpIndex;
  double get _magnetDistance => 2 * _majorGridSpacing;

  // Stretch tool (same handle-box model as the stencil)
  String? _stretchPaperId;
  int? _stretchHandleIndex; // 0-3 edges (T,R,B,L), 4-7 corners (TL,TR,BR,BL)
  Rect? _stretchStartLocal;
  Rect? _stretchDisplayLocal;

  // Stencil tool (widget, not a paper piece)
  StencilShape _stencilShape = StencilShape.rectangle;
  Offset _stencilPosition = Offset.zero;
  double _stencilHalfW = 1;
  double _stencilHalfH = 1;
  bool _stencilSelected = false;
  bool _stencilDragging = false;
  Offset? _stencilDragStartWorld;
  Offset? _stencilDragStartPos;
  int? _stencilHandleIndex;
  Rect? _stencilResizeStart;

  // Blueprint progress tracking
  double _blueprintTotalArea = 0;
  double _blueprintLockedArea = 0;

  // Completion animation
  CompletionPhase _completionPhase = CompletionPhase.none;
  // Drives the 0.5s dot-dissolve + geometry fade-in reveal.
  late final AnimationController _dissolveController;
  // Drives the ~4s accelerating fold.
  late final AnimationController _foldController;
  Map<int, _FoldNodeState> _foldNodeStates = {};
  List<(int nodeId, double startT, double endT)> _foldSchedule = [];
  Vector3 _foldOriginOffset = Vector3.zero();
  Vector3 _foldFoldedOffset = Vector3.zero();
  Matrix4 _foldDisplacementMatrix = Matrix4.identity();
  Offset _foldRawCentroid = Offset.zero;
  double _foldRawOrthoScale = 100;
  Map<int, String> _polyIndexToRegion = {};
  double _foldColorProgress = 0;

  /// Progress (0..1) of the random dot-dissolve during dissolveReveal.
  double _dotDissolveProgress = 0;

  /// Opacity (0..1) of the folding geometry as it fades in during reveal.
  double _foldOpacity = 0;

  /// Papers matched to blueprint regions at craft time, forwarded to the host
  /// once the fold animation completes.
  List<CraftingPaperState> _completedPapers = [];

  double _orthoScale = 300.0;
  Offset _panOffset = Offset.zero;

  /// In-plane camera roll (radians). 0 = world +Y is screen up.
  double _viewRotation = 0.0;
  Size _viewportSize = Size.zero;
  late double _drawingPlaneSize;
  double get _majorGridSpacing => _drawingPlaneSize / 4;
  double get _minorGridSpacing => _drawingPlaneSize / 32;
  static const int _gridDivisions = 32;

  /// Offset applied to the grid origin. Grid intersections are at
  /// `origin + i * spacing * xDir + j * spacing * yDir`.
  Offset _gridOriginOffset = Offset.zero;

  /// World angle (radians) of the grid's +Y axis. Default π/2 = world +Y.
  /// Align Grid sets this from a press-and-drag (down = origin, up = +Y).
  double _gridRotation = math.pi / 2;

  int? _alignGridHoveredPolyIndex;
  Offset? _alignGridPreviewVertex;
  Offset? _alignGridSecondPreview;
  Offset? _alignGridPointerDown;
  bool _alignGridDidDrag = false;

  /// Progressive grid LOD: 0 = base (32 divisions), -1 = subdivided (64), +N coarsens.
  int _gridLodLevel(Size viewport) {
    final shorter = math.min(viewport.width, viewport.height);
    if (shorter < 1) return 0;
    final visibleWorld = 2 * _orthoScale;

    var bestLevel = 0;
    var bestDiff = double.infinity;
    for (var level = _minGridLod; level <= _maxGridLod; level++) {
      final spacing = _gridSpacingForLevel(level);
      final cellsAcross = visibleWorld / spacing;
      final diff = (cellsAcross - _targetCellsAcross).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestLevel = level;
      }
    }
    return bestLevel;
  }

  double _gridSpacingForLevel(int level) =>
      _minorGridSpacing * math.pow(2, level).toDouble();

  int get _gridLod => _gridLodLevel(_viewportSize);

  double get _activeGridSpacing => _gridSpacingForLevel(_gridLod);

  // Grid LOD crossfade
  late final AnimationController _gridLodAnimController;
  int _gridLodRendered = 0;
  int _gridLodFrom = 0;
  int _gridLodTo = 0;
  bool _gridLodSyncScheduled = false;

  void _scheduleGridLodSync() {
    if (_gridLodSyncScheduled) return;
    _gridLodSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gridLodSyncScheduled = false;
      if (!mounted) return;
      _syncGridLodTransition();
    });
  }

  void _syncGridLodTransition() {
    final target = _gridLod;
    if (_gridLodAnimController.isAnimating) {
      if (target != _gridLodTo) {
        _gridLodFrom = _gridLodTo;
        _gridLodTo = target;
        _gridLodAnimController.forward(from: _gridLodAnimController.value);
      }
      return;
    }
    if (target == _gridLodRendered) return;
    _gridLodFrom = _gridLodRendered;
    _gridLodTo = target;
    _gridLodAnimController.forward(from: 0);
  }

  double get _friendScale => _minorGridSpacing / 120.0;
  static const double _paperZ = 1.0;
  WipeAnimation? _dotWipeAnimation;
  static const double _dragThreshold = 4.0;
  static const double _inventoryReturnZoneFraction = 0.85;
  double get _minOrthoScale => 10 * _minorGridSpacing / 2;
  double get _maxOrthoScale => 200 * _minorGridSpacing / 2;

  // Canvas display & snap config
  CanvasDisplayMode _canvasDisplayMode = CanvasDisplayMode.dot;
  bool _showMinorLines = true;
  bool _gridRegionAssist = true;
  bool _snapGrid = true;
  bool _snapPaper = true;
  bool _snapBlueprint = true;
  static const double _snapPixelTolerance = 12.0;

  // Gesture tracking for two-finger pan/zoom (via GestureClassifier).
  bool _isMultiTouch = false;

  /// Trackpad / Magic Mouse pinch (PointerPanZoom) is active.
  bool _panZoomActive = false;

  /// Set for the whole pinch/pan-zoom episode. Tools stay dead until every
  /// pointer is up *and* pan-zoom has ended.
  bool _pinchEpisode = false;

  /// Once multitouch is seen, tools stay dead until *every* finger lifts.
  /// Prevents the last finger-up from committing paint/erase/cut/etc.
  bool _toolsSuppressedUntilPointersUp = false;
  int _canvasPointerCount = 0;
  Offset? _pinchStartPan;
  double? _pinchStartOrtho;
  Offset? _pinchAnchorWorld;

  /// Pointer-down is deferred until slop or a clean tap so a trackpad pinch
  /// never starts a tool (and never looks like undo).
  Offset? _pendingToolDown;
  Size? _pendingToolViewport;

  /// Grid pose at gesture start (align-grid mutates without undo).
  Offset _preGestureGridOrigin = Offset.zero;
  double _preGestureGridRotation = math.pi / 2;

  double _computeDrawingPlaneSize() {
    return widget.canvasSize ?? 400.0;
  }

  void _clampPanOffset() {
    // No clamping – canvas is infinite.
  }

  bool get _toolsBlocked =>
      _toolsSuppressedUntilPointersUp ||
      _isMultiTouch ||
      _panZoomActive ||
      _pinchEpisode ||
      _canvasPointerCount >= 2;

  /// History rewind is button-only. Block only while a pinch is in flight so
  /// a trackpad pinch that starts on the undo button cannot fire it.
  bool get _historyRewindAllowed => !_pinchEpisode && !_panZoomActive;

  void _clearPinchBaseline() {
    _pinchStartPan = null;
    _pinchStartOrtho = null;
    _pinchAnchorWorld = null;
  }

  void _beginToolGestureBaseline() {
    _preGestureGridOrigin = _gridOriginOffset;
    _preGestureGridRotation = _gridRotation;
  }

  void _lockToolsForMultiTouch() {
    _toolsSuppressedUntilPointersUp = true;
  }

  void _maybeUnlockToolsAfterPointersUp() {
    if (_canvasPointerCount <= 0 && !_panZoomActive) {
      _canvasPointerCount = 0;
      _toolsSuppressedUntilPointersUp = false;
      _isMultiTouch = false;
      _pinchEpisode = false;
      _clearPinchBaseline();
    }
  }

  void _cancelPendingToolDown() {
    _pendingToolDown = null;
    _pendingToolViewport = null;
  }

  void _queueToolPointerDown(Offset localPos, Size viewportSize) {
    _pendingToolDown = localPos;
    _pendingToolViewport = viewportSize;
  }

  void _flushPendingToolDown() {
    final pos = _pendingToolDown;
    final vp = _pendingToolViewport;
    if (pos == null || vp == null) return;
    _pendingToolDown = null;
    _pendingToolViewport = null;
    if (_toolsBlocked) return;
    _beginToolGestureBaseline();
    _handlePointerDown(pos, vp);
  }

  /// Keep an in-progress paint/erase stroke instead of discarding it. Pinch
  /// must never look like undo of the last cells the user just drew.
  void _commitInProgressStroke() {
    if (_paintedCells.isNotEmpty) _fusePaintedCells();
    if (_erasedCells.isNotEmpty) _applyErase();
  }

  /// Stop live pointer tracking so pinch deltas cannot move papers or commit
  /// a cut. Does not revert papers, grid, or history.
  void _haltTransientPointersForPinch() {
    final midAlignGrid = _alignGridPointerDown != null;
    final gridChanged = midAlignGrid &&
        (_gridOriginOffset != _preGestureGridOrigin ||
            _gridRotation != _preGestureGridRotation);

    setState(() {
      if (gridChanged) {
        _gridOriginOffset = _preGestureGridOrigin;
        _gridRotation = _preGestureGridRotation;
      }

      _pointerDownPos = null;
      _pointerDownPaperId = null;
      _isDragging = false;
      _dragPaperId = null;
      _isMarquee = false;
      _marqueeStartScreen = null;
      _marqueeCurrentScreen = null;
      _resetCutStroke();
      // Pan tool one-finger camera drag — must clear or a later move applies a
      // huge stale delta against the pre-pinch finger position (pinch jitter).
      _panDragLastScreen = null;
      _panModeDragging = false;
      _panModeDragLastScreen = null;
      _paintDragPaperId = null;
      _paintDragLastScreen = null;
      _paintHadSelection = false;
      _paintDeferredCell = null;
      _paintSelectionIds = {};
      _mirrorLineStart = null;
      _mirrorLinePreview = null;
      _alignGridPointerDown = null;
      _alignGridDidDrag = false;
      _alignGridHoveredPolyIndex = null;
      _alignGridPreviewVertex = null;
      _alignGridSecondPreview = null;
      _clearStretchBox();
      _stencilHandleIndex = null;
      _stencilResizeStart = null;
      _stencilDragging = false;
      _stencilDragStartWorld = null;
      _stencilDragStartPos = null;
      _stopHandleFollow();
    });

    if (gridChanged) _scheduleGridLodSync();
  }

  /// Pinch / second finger: lock tools, keep finished work, never rewind.
  void _enterPinchExclusiveMode() {
    _lockToolsForMultiTouch();
    if (!_pinchEpisode) {
      _commitInProgressStroke();
    }
    _pinchEpisode = true;
    _cancelPendingToolDown();
    _haltTransientPointersForPinch();
  }

  /// Stable two-finger pan/zoom from [GestureClassifier] (span from gesture start).
  void _onCraftGesture(GestureState state, Size viewportSize) {
    if (_completionPhase != CompletionPhase.none) return;

    // Real two-finger touch, or trackpad pan-zoom (synthetic twoFingerDrag).
    final isTwoFinger = state.pointerCount >= 2 ||
        (state.type == GestureType.twoFingerDrag && state.pointers.isEmpty);

    if (isTwoFinger) {
      // Trackpad pan-zoom reports twoFingerDrag with no pointer ids.
      if (state.pointers.isEmpty) {
        _panZoomActive = true;
      }
      // Child Listener may have already flagged multitouch to suppress tools;
      // still (re)capture baselines if missing so pinch can run.
      final needsBaseline = _pinchStartOrtho == null ||
          _pinchStartPan == null ||
          _pinchAnchorWorld == null;
      if (!_isMultiTouch) {
        _isMultiTouch = true;
        _enterPinchExclusiveMode();
      }
      if (needsBaseline) {
        _pinchStartPan = _panOffset;
        _pinchStartOrtho = _orthoScale;
        final anchor = craftingScreenToWorldOnPlane(
          state.focalPoint,
          viewportSize,
          _orthoScale,
          _paperZ,
          panOffset: _panOffset,
          viewRotation: _viewRotation,
        );
        _pinchAnchorWorld = Offset(anchor.x, anchor.y);
      }

      final startOrtho = _pinchStartOrtho;
      final startPan = _pinchStartPan;
      final anchorWorld = _pinchAnchorWorld;
      if (startOrtho == null || startPan == null || anchorWorld == null) {
        return;
      }

      final scale = state.spanScale;
      if (scale <= 1e-6 || !scale.isFinite) return;

      final newOrtho =
          (startOrtho / scale).clamp(_minOrthoScale, _maxOrthoScale);

      // Keep the world point that was under the focal at pinch-start glued to
      // the current focal — handles pan + zoom without frame-to-frame jitter.
      final now = craftingScreenToWorldOnPlane(
        state.focalPoint,
        viewportSize,
        newOrtho,
        _paperZ,
        panOffset: startPan,
        viewRotation: _viewRotation,
      );

      setState(() {
        _orthoScale = newOrtho;
        _panOffset = Offset(
          startPan.dx + (anchorWorld.dx - now.x),
          startPan.dy + (anchorWorld.dy - now.y),
        );
        _clampPanOffset();
      });
      _scheduleGridLodSync();
      return;
    }

    if (_isMultiTouch) {
      // Leave pinch camera mode when fingers drop below 2, but keep tools
      // locked until every pointer is up and pan-zoom has ended.
      _isMultiTouch = false;
      _panZoomActive = false;
      _clearPinchBaseline();
      _panDragLastScreen = null;
      _panModeDragging = false;
      _panModeDragLastScreen = null;
      _pointerDownPos = null;
      _maybeUnlockToolsAfterPointersUp();
    }
  }

  @override
  void initState() {
    super.initState();
    _canvasDisplayMode =
        widget.initialCanvasDisplayMode ?? CanvasDisplayMode.dot;
    if (_canvasDisplayMode == CanvasDisplayMode.none) {
      _gridRegionAssist = false;
    }
    _drawingPlaneSize = _computeDrawingPlaneSize();
    if (widget.canvasSize != null) {
      _orthoScale = widget.initialOrthoScale ?? _drawingPlaneSize * 1.1;
    }
    _geometry = _buildGeometry();

    _handleFollowTicker = createTicker(_onHandleFollowTick);

    _cutAnimController = AnimationController(vsync: this)
      ..addListener(_onCutAnimTick)
      ..addStatusListener(_onCutAnimStatus);

    _cutEdgeGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(() => setState(() {}));
    _cutEdgeGlowController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (_cutHighlightEdges.isNotEmpty) {
          setState(() => _cutHighlightEdges = []);
        }
      }
    });

    _marqueeDashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    _marqueeDashController.addListener(() => setState(() {}));

    _lockAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _lockAnimCurve = CurvedAnimation(
      parent: _lockAnimController,
      curve: Curves.easeIn,
    );
    _lockAnimController.addListener(() {
      setState(() => _lockAnimProgress = _lockAnimCurve.value);
    });
    _lockAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finalizeLock();
      }
    });

    _lockFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addListener(() {
        setState(() => _lockFadeT = _lockFadeController.value);
      });
    _lockFadeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        final shouldLoad = _hideUnfilledBlueprint;
        setState(() {
          _lockFadingPaperIds = {};
          _lockFadeT = 1.0;
        });
        if (shouldLoad) _playBlueprintLoadAnim();
      }
    });

    _discardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onDiscardTick);
    _discardController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _onDiscardDone();
    });

    _loadAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addListener(() {
        setState(() => _loadAnimT = _loadAnimController.value);
      });
    _loadAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _loadAnimT = 1.0);
      }
    });

    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(() => setState(() {}));

    _dissolveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_onDissolveTick);
    _dissolveController.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onDissolveDone();
    });

    _foldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(_onFoldTick);
    _foldController.addStatusListener((s) {
      if (s == AnimationStatus.completed) _onFoldComplete();
    });

    _magnetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onMagnetAnimTick);

    _gridLodAnimController = AnimationController(
      vsync: this,
      duration: _gridLodFadeDuration,
    )..addListener(() => setState(() {}));
    _gridLodAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _gridLodRendered = _gridLodTo;
        _scheduleGridLodSync();
      }
    });

    _cameraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_onCameraAnimTick);
    _cameraAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _panOffset = _camPanTo;
          _orthoScale = _camOrthoTo;
          _viewRotation = _camRotTo;
          if (_cameraIntroHighlight) {
            _activeHighlightT = 1.0;
            _activeGlow = 0.0;
            _cameraIntroHighlight = false;
          }
        });
        _scheduleGridLodSync();
      }
    });

    _loadBlueprints();
    _loadCraftingState();

    if (widget.showDotWipe) {
      _dotWipeAnimation = WipeAnimation(
        direction: WipeDirection.horizontal,
        mode: WipeMode.show,
        duration: const Duration(milliseconds: 500),
        vsync: this,
      );
      _dotWipeAnimation!.controller.addListener(() => setState(() {}));
      _dotWipeAnimation!.forward();
    }
  }

  void _loadCraftingState() {
    final store = widget.stateStore;
    final id = widget.structureId;
    if (store == null || id == null) return;
    final state = store.getState(id);
    if (state == null) return;
    _placedPapers.clear();
    _placedPapers.addAll(state.papers.map((s) => s.toPaper()));
    _nextPaperId = state.nextPaperId;
    _ensureStackOrders();
  }

  void _saveCraftingState() {
    final store = widget.stateStore;
    final id = widget.structureId;
    if (store == null || id == null) return;
    store.savePapers(id, _placedPapers, _nextPaperId);
  }

  @override
  void dispose() {
    _saveCraftingState();
    _dotWipeAnimation?.dispose();
    _checkTimer?.cancel();
    _cutAnimController.dispose();
    _cutEdgeGlowController.dispose();
    _marqueeDashController.dispose();
    _lockAnimController.dispose();
    _lockFadeController.dispose();
    _discardController.dispose();
    _loadAnimController.dispose();
    _progressAnimController.dispose();
    _dissolveController.dispose();
    _foldController.dispose();
    _magnetAnimController.dispose();
    _gridLodAnimController.dispose();
    _cameraAnimController.dispose();
    _handleFollowTicker.dispose();
    super.dispose();
  }

  Geometry _buildGeometry() {
    return ensureOutwardFacingGeometry(
      buildGeometry(
        GeometryFeature(
          id: 'shadow-obj',
          geometry: GeometryPrefabs.cube,
          scale: _friendScale,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Blueprint loading
  // ---------------------------------------------------------------------------

  Future<void> _loadBlueprints() async {
    final manifests = await CraftManifest.loadAll();
    final loaded = <CraftingBlueprint>[];
    final sets = <BlueprintSet>[];
    for (final manifest in manifests) {
      loaded.addAll(manifest.toFillBlueprints());
      sets.add(manifest.toBlueprintSet());
    }
    if (mounted) {
      setState(() {
        _blueprints = loaded;
        _blueprintSets = sets;
      });
      final wanted = widget.initialBlueprintSet ?? widget.defaultBlueprintName;
      if (wanted != null && _selectedSet == null && _selectedBlueprint == null) {
        _selectInitialBlueprint(wanted);
      }
    }
  }

  void _selectInitialBlueprint(String wanted) {
    final key = wanted.trim().toLowerCase();
    if (key.isEmpty) return;

    final bpMatch =
        _blueprints.where((b) => b.craft.toLowerCase() == key).firstOrNull;
    if (bpMatch != null) {
      _selectBlueprint(bpMatch);
      return;
    }

    final setMatch = _blueprintSets.where((s) {
      if (s.name.toLowerCase() == key) return true;
      return s.steps.any((st) => st.craft.toLowerCase() == key);
    }).firstOrNull;
    if (setMatch != null) {
      final first = _findBlueprintForStep(setMatch.steps.first);
      if (first != null) {
        _selectBlueprint(first);
        return;
      }
    }

    if (_blueprints.isNotEmpty) {
      debugPrint(
        '[craft] initial "$wanted" not found; using ${_blueprints.first.displayName}',
      );
      _selectBlueprint(_blueprints.first);
    } else {
      debugPrint('[craft] no blueprints loaded; cannot select "$wanted"');
    }
  }

  CraftingBlueprint? _findBlueprintForStep(BlueprintStep step) {
    return _blueprints.where((b) => b.fillKey == step.fillKey).firstOrNull;
  }

  void _selectBlueprintSet(BlueprintSet? set) {
    _fillCompleteLatched = false;
    if (set == null) {
      _selectedSet = null;
      _currentStepIndex = 0;
      _completedStepIndices.clear();
      _groupOverlayPolygons = [];
      _groupOverlayColors = [];
      _activeHighlightT = 1.0;
      _activeGlow = 0.0;
      _selectBlueprint(null);
      return;
    }

    setState(() {
      _selectedSet = set;
      _currentStepIndex = 0;
      _completedStepIndices.clear();
      _wipeCanvasPapers();
      _blueprintProgress.clear();
    });

    final bp = _findBlueprintForStep(set.steps[0]);
    _selectBlueprint(bp);
  }

  /// Apply a single fill blueprint. Hosts that sequence steps (assembly view)
  /// call this once per beat; the workstation no longer advances a set.
  ///
  /// When [keepCanvas] is true, committed papers stay (parts → applique /
  /// next q-layer). The camera and grid pose are left alone; papers lock
  /// immediately and fade into the locked look, then the new outlines play
  /// the load animation.
  void applyBlueprint(
    CraftingBlueprint blueprint, {
    Offset? panOffset,
    double? orthoScale,
    double? viewRotation,
    bool keepCanvas = false,
  }) {
    if (!mounted) return;
    _blueprints = [
      ..._blueprints.where((b) => b.fillKey != blueprint.fillKey),
      blueprint,
    ];
    _selectedSet = BlueprintSet.single(blueprint);
    _currentStepIndex = 0;
    _fillCompleteLatched = false;

    final justLocked = <String>{};
    if (keepCanvas) {
      for (final paper in _placedPapers) {
        if (paper.lockedBlueprintIndex != null) {
          paper.locked = true;
          justLocked.add(paper.id);
        }
      }
      _deselectLockedPapers();
    } else {
      // New assembly step (not a same-step applique): drop every paper
      // and saved fill, including unlocked leftovers from the last beat.
      _wipeCanvasPapers();
      _blueprintProgress.clear();
    }

    _selectBlueprint(
      blueprint,
      keepCanvas: keepCanvas,
      keepCamera: keepCanvas,
    );

    setState(() {
      _craftingMode = CraftingMode.pan;
      _drawnCutLines.clear();
      _resetCutStroke();
      _panModeSelectedPaperId = null;
      _paintedCells = {};
      _lastPaintCell = null;
      _erasedCells = {};
      _lastEraseCell = null;
      _stretchPaperId = null;
      _clearStretchBox();
      _stencilSelected = false;
      _stencilHandleIndex = null;
      _stopHandleFollow();
      _mirrorLineStart = null;
      _mirrorLinePreview = null;
      _rotCopyGizmoActive = false;
      _rotCopyCenterWorld = null;
      _clearAlignGridTransient();
      if (!keepCanvas) {
        if (panOffset != null) _panOffset = panOffset;
        if (orthoScale != null) _orthoScale = orthoScale;
        if (viewRotation != null) _viewRotation = viewRotation;
      }
      _canvasDisplayMode = CanvasDisplayMode.dot;
    });
    _scheduleGridLodSync();
    _scheduleCheck();

    if (keepCanvas && justLocked.isNotEmpty) {
      _startLockFadeThenLoad(justLocked);
    } else {
      _playBlueprintLoadAnim();
    }
  }

  void _startLockFadeThenLoad(Set<String> paperIds) {
    _lockFadeController.stop();
    _loadAnimController.stop();
    setState(() {
      _lockFadingPaperIds = paperIds;
      _lockFadeT = 0;
      _hideUnfilledBlueprint = true;
      _loadAnimT = 0;
    });
    _lockFadeController.forward(from: 0);
  }

  void _playBlueprintLoadAnim() {
    setState(() {
      _hideUnfilledBlueprint = false;
      _loadAnimT = 0;
    });
    _loadAnimController.forward(from: 0);
  }

  /// Clear the active blueprint (used when reversing a 3D handoff).
  void clearBlueprint() {
    if (!mounted) return;
    _selectBlueprintSet(null);
  }

  void _selectBlueprint(
    CraftingBlueprint? blueprint, {
    bool animateCameraToStep = false,
    bool keepCanvas = false,
    bool keepCamera = false,
  }) {
    setState(() {
      if (_selectedBlueprint != null && !keepCanvas) {
        final outKey = _progressKey(_selectedBlueprint!);
        final locked = _placedPapers
            .where((p) => p.locked && p.lockedBlueprintIndex != null)
            .toList();
        if (locked.isNotEmpty) {
          _blueprintProgress[outKey] = locked
              .map(
                (p) => _LockedPaperSnapshot(
                  id: p.id,
                  paperColor: p.paperColor,
                  position: p.position.clone(),
                  rotationDeg: p.rotationDeg,
                  sizeLevel: p.sizeLevel,
                  localVertices: p.localVertices,
                  localHoles: p.localHoles,
                  lockedBlueprintIndex: p.lockedBlueprintIndex!,
                  materialId: p.materialId,
                  stackOrder: p.stackOrder,
                ),
              )
              .toList();
        } else {
          _blueprintProgress.remove(outKey);
        }
        _wipeCanvasPapers();
      }
      _lockAnimatingPaperIds = {};
      _lockAnimProgress = 0;

      _fillCompleteLatched = false;
      _selectedBlueprint = blueprint;
      _blueprintWorldPolygons = [];
      _blueprintWorldHoles = [];
      _blueprintUnionPolygons = [];
      _blueprintTotalArea = 0;
      _blueprintLockedArea = 0;
      _alignGridPreviewVertex = null;
      _alignGridSecondPreview = null;
      _alignGridHoveredPolyIndex = null;
      _alignGridDidDrag = false;
      if (blueprint == null) {
        _gridOriginOffset = Offset.zero;
        _gridRotation = math.pi / 2;
        _groupOverlayPolygons = [];
        _groupOverlayColors = [];
        _underlyingWorldHoles = [];
        _snapWorldLoops = [];
        return;
      }

      final allScaled = _scaleBlueprintPolygons(blueprint);

      _completionPhase = CompletionPhase.none;
      _dissolveController.reset();
      _foldController.reset();
      _dotDissolveProgress = 0;
      _foldOpacity = 0;
      _foldColorProgress = 0;
      _foldNodeStates = {};
      _foldSchedule = [];

      _polyIndexToRegion = {};
      final layers = blueprint.fillPolygonLayers();
      for (var i = 0; i < layers.length && i < allScaled.length; i++) {
        _polyIndexToRegion[i] = layers[i];
      }
      _applyBlueprintPolygons(
        allScaled,
        blueprint.unfoldedFillHoles(
          scale: blueprint.worldScale(_minorGridSpacing),
        ),
      );
      if (!keepCamera) {
        final gridFrame = _computeDominantGridFrame(allScaled);
        if (gridFrame != null) {
          _gridOriginOffset = gridFrame.anchor;
          _gridRotation = gridFrame.yAngle;
        } else {
          _gridOriginOffset = Offset.zero;
          _gridRotation = math.pi / 2;
        }
      }

      _blueprintTotalArea = 0;
      for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
        var area = _polyArea(_blueprintWorldPolygons[i]).abs();
        if (i < _blueprintWorldHoles.length) {
          for (final hole in _blueprintWorldHoles[i]) {
            area -= _polyArea(hole).abs();
          }
        }
        _blueprintTotalArea += area;
      }

      _blueprintUnionPolygons = _blueprintWorldPolygons;
      _filledBlueprintIndices = {};

      if (!keepCanvas) {
        final saved = _blueprintProgress[_progressKey(blueprint)];
        if (saved != null) {
          for (final snap in saved) {
            _placedPapers.add(snap.toPaper());
            _filledBlueprintIndices.add(snap.lockedBlueprintIndex);
            if (snap.lockedBlueprintIndex < allScaled.length) {
              var area = _polyArea(
                allScaled[snap.lockedBlueprintIndex],
              ).abs();
              if (snap.lockedBlueprintIndex < _blueprintWorldHoles.length) {
                for (final hole
                    in _blueprintWorldHoles[snap.lockedBlueprintIndex]) {
                  area -= _polyArea(hole).abs();
                }
              }
              _blueprintLockedArea += area;
            }
          }
        }
      } else {
        _filledBlueprintIndices = {};
        _blueprintLockedArea = 0;
      }

      _rebuildStepOverlays();
      _ensureStackOrders();

      if (!keepCamera &&
          !animateCameraToStep &&
          allScaled.isNotEmpty &&
          blueprint.foldedGeometryId == null) {
        if (_viewportSize.width < 1 || _viewportSize.height < 1) {
          _pendingCameraFit = true;
        } else {
          final cam = _cameraForPolygons(allScaled);
          _orthoScale = cam.ortho;
          _panOffset = cam.pan;
          _viewRotation = cam.rotation;
        }
      }
    });

    if (animateCameraToStep && _blueprintWorldPolygons.isNotEmpty) {
      final cam = _cameraForPolygons(_blueprintWorldPolygons);
      _animateCameraTo(cam.pan, cam.ortho, rotation: cam.rotation);
    }

    _scheduleCheck();
    _scheduleGridLodSync();
  }

  String _progressKey(CraftingBlueprint bp) => bp.fillKey;

  List<List<Offset>> _scaleBlueprintPolygons(CraftingBlueprint blueprint) {
    return blueprint.unfoldedFillPolygons(
      scale: blueprint.worldScale(_minorGridSpacing),
    );
  }

  /// Store unfolded exteriors and the hole rings authored on each node.
  void _applyBlueprintPolygons(
    List<List<Offset>> raw,
    List<List<List<Offset>>> holes,
  ) {
    _blueprintWorldPolygons = raw;
    _blueprintWorldHoles = [
      for (var i = 0; i < raw.length; i++)
        i < holes.length ? holes[i] : const <List<Offset>>[],
    ];
    _rebuildSnapGeometry();
  }

  void _rebuildSnapGeometry() {
    _snapWorldLoops = [
      for (final poly in _blueprintWorldPolygons) (poly, false),
      for (var i = 0; i < _blueprintWorldPolygons.length; i++)
        if (i < _blueprintWorldHoles.length)
          for (final hole in _blueprintWorldHoles[i]) (hole, true),
      for (final poly in _groupOverlayPolygons) (poly, false),
      for (var i = 0; i < _groupOverlayPolygons.length; i++)
        if (i < _underlyingWorldHoles.length)
          for (final hole in _underlyingWorldHoles[i]) (hole, true),
    ];
  }

  Rect? _boundsOfPolygons(List<List<Offset>> polygons) {
    if (polygons.isEmpty) return null;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final poly in polygons) {
      for (final v in poly) {
        minX = math.min(minX, v.dx);
        minY = math.min(minY, v.dy);
        maxX = math.max(maxX, v.dx);
        maxY = math.max(maxY, v.dy);
      }
    }
    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Fits [polygons] in the current viewport, optionally rolling the camera so a
  /// wide island sits better in portrait. Candidate rolls come from undirected
  /// edge directions (180° flips count as the same axis).
  ({Offset pan, double ortho, double rotation}) _cameraForPolygons(
    List<List<Offset>> polygons, {
    double padding = 0.7,
  }) {
    final points = <Offset>[
      for (final poly in polygons)
        for (final v in poly) v,
    ];
    if (points.isEmpty) {
      return (pan: _panOffset, ortho: _orthoScale, rotation: _viewRotation);
    }

    final vp = _viewportSize;
    final aspect = (vp.width > 1 && vp.height > 1) ? vp.width / vp.height : 1.0;
    final cover = 2 * padding;

    double orthoForSize(double width, double height) {
      final halfW = math.max(width / 2, 1e-6);
      final halfH = math.max(height / 2, 1e-6);
      return math.max(halfH * cover, halfW * cover / aspect);
    }

    final candidates = _viewOrientationCandidates(polygons);
    var bestOrtho = double.infinity;
    var bestRot = 0.0;
    var bestPan = points.first;
    var bestUpDot = -double.infinity;

    for (final rot in candidates) {
      final obb = _orientedBounds(points, rot);
      final ortho = orthoForSize(obb.width, obb.height);
      // Prefer upright-ish rolls when fits are nearly equal.
      final upDot = math.cos(rot);
      final betterFit = ortho < bestOrtho * 0.98;
      final similarFit = ortho <= bestOrtho * 1.02;
      final betterUp = upDot > bestUpDot;
      final smallerRoll =
          rot.abs() < bestRot.abs() - 1e-6 ||
          (rot.abs() - bestRot.abs()).abs() < 1e-6 && upDot > bestUpDot;
      if (betterFit ||
          (similarFit && betterUp) ||
          (similarFit && !betterUp && smallerRoll && ortho <= bestOrtho)) {
        bestOrtho = ortho;
        bestRot = rot;
        bestPan = obb.center;
        bestUpDot = upDot;
      }
    }

    return (
      pan: bestPan,
      ortho: bestOrtho.clamp(_minOrthoScale, _maxOrthoScale),
      rotation: bestRot,
    );
  }

  /// Axis-aligned fallback used only when no polygon list is available.
  ({Offset pan, double ortho, double rotation}) _cameraForBounds(
    Rect bounds, {
    double padding = 0.7,
  }) {
    return _cameraForPolygons([
      [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft],
    ], padding: padding);
  }

  void _rebuildStepOverlays() {
    _groupOverlayPolygons = [];
    _groupOverlayColors = [];
    _underlyingWorldHoles = [];
    final bp = _selectedBlueprint;
    if (bp == null || !bp.isApplique) {
      _activeHighlightT = 1.0;
      _activeGlow = 0.0;
      _rebuildSnapGeometry();
      return;
    }
    const overlay = Color(0xFFFF88CC);
    final scale = bp.worldScale(_minorGridSpacing);
    for (final poly in bp.partOverlayPolygons(scale: scale)) {
      _groupOverlayPolygons.add(poly);
      _groupOverlayColors.add(overlay.withValues(alpha: 0.18));
    }
    _underlyingWorldHoles = bp.partOverlayHoles(scale: scale);
    _activeHighlightT = 1.0;
    _activeGlow = 0.0;
    _rebuildSnapGeometry();
  }

  void _animateCameraTo(
    Offset pan,
    double ortho, {
    double? rotation,
    bool introHighlight = false,
    Duration duration = const Duration(milliseconds: 900),
  }) {
    _camPanFrom = _panOffset;
    _camOrthoFrom = _orthoScale;
    _camRotFrom = _viewRotation;
    _camPanTo = pan;
    _camOrthoTo = ortho;
    _camRotTo = rotation ?? _viewRotation;
    // Pick the equivalent roll (±π) closest to the current view.
    final alt = _camRotTo + (_camRotTo >= 0 ? -math.pi : math.pi);
    if ((alt - _camRotFrom).abs() < (_camRotTo - _camRotFrom).abs()) {
      _camRotTo = alt;
    }
    _cameraIntroHighlight = introHighlight;
    if (introHighlight) {
      _activeHighlightT = 0;
      _activeGlow = 0;
    }
    _cameraAnimController.duration = duration;
    _cameraAnimController.forward(from: 0);
  }

  void _onCameraAnimTick() {
    final raw = _cameraAnimController.value;
    final t = Curves.easeInOut.transform(raw);
    setState(() {
      _panOffset = Offset.lerp(_camPanFrom, _camPanTo, t)!;
      _orthoScale = _camOrthoFrom + (_camOrthoTo - _camOrthoFrom) * t;
      _viewRotation = _camRotFrom + (_camRotTo - _camRotFrom) * t;
      if (_cameraIntroHighlight) {
        _activeHighlightT = t;
        // Quick yellow glow early while easing into the zoom.
        const glowPeak = 0.18;
        if (raw <= glowPeak) {
          _activeGlow = (raw / glowPeak).clamp(0.0, 1.0);
        } else {
          _activeGlow =
              (1.0 - (raw - glowPeak) / (1.0 - glowPeak)).clamp(0.0, 1.0) *
              0.45;
        }
      }
    });
    _scheduleGridLodSync();
  }

  // ---------------------------------------------------------------------------
  // Check mode
  // ---------------------------------------------------------------------------

  void _scheduleCheck() {
    if (!_checkMode || _blueprintWorldPolygons.isEmpty) return;
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(milliseconds: 80), _runCheck);
  }

  Future<void> _runCheck() async {
    final generation = ++_checkGeneration;
    final bpPolygons = List<List<Offset>>.from(_blueprintWorldPolygons);

    final paperPolys = <List<Offset>>[];
    final paperHoles = <List<List<Offset>>>[];
    final paperIds = <String>[];
    for (final paper in _placedPapers) {
      // Papers committed to a finished step stay out of the active match.
      if (paper.locked || _isDiscardingPaper(paper.id)) continue;
      final corners = _paperWorldCorners(paper);
      paperPolys.add(corners.map((v) => Offset(v.x, v.y)).toList());
      paperHoles.add(_paperWorldHoles2D(paper));
      paperIds.add(paper.id);
    }

    final tolerance = 0.1 * _minorGridSpacing;

    final params = _CheckCoverageParams(
      blueprintPolygons: bpPolygons,
      blueprintHoles: _blueprintWorldHoles,
      paperPolygons: paperPolys,
      paperHoles: paperHoles,
      tolerance: tolerance,
    );

    try {
      final result = await compute(_checkCoverage, params);
      if (!mounted || generation != _checkGeneration) return;
      final previouslyFilled = _filledBlueprintIndices;
      final newlyFilled = result.difference(previouslyFilled);

      debugPrint(
        '[craft-group] check step=$_currentStepIndex '
        'filled=${result.length}/${bpPolygons.length} '
        'new=${newlyFilled.length} papers=${paperIds.length}',
      );

      if (newlyFilled.isNotEmpty && _lockAnimatingPaperIds.isEmpty) {
        _startLockAnimation(
          newlyFilled,
          bpPolygons,
          paperPolys,
          paperHoles,
          paperIds,
        );
      }

      // Only clear match indices on unlocked papers for the active step.
      for (final paper in _placedPapers) {
        if (paper.locked) continue;
        if (paper.lockedBlueprintIndex != null &&
            !result.contains(paper.lockedBlueprintIndex!)) {
          paper.lockedBlueprintIndex = null;
        }
      }

      setState(() {
        _filledBlueprintIndices = result;
        _exitTransformIfPieceFitted();
      });
      _recomputeLockedArea();
    } catch (e, st) {
      debugPrint('Check coverage failed: $e\n$st');
    }
  }

  void _startLockAnimation(
    Set<int> newlyFilled,
    List<List<Offset>> bpPolygons,
    List<List<Offset>> paperPolys,
    List<List<List<Offset>>> paperHoles,
    List<String> paperIds,
  ) {
    final tolerance = 0.1 * _minorGridSpacing;
    final dedupTol = tolerance * 0.01;
    const angularTolDeg = 3.0;
    final angularTolRad = angularTolDeg * math.pi / 180;

    final animating = <String>{};
    final paperToBpIndex = <String, int>{};

    for (final bpIdx in newlyFilled) {
      if (bpIdx >= bpPolygons.length) continue;
      final bpClean = _removeCollinears(
        _dedup(bpPolygons[bpIdx], dedupTol),
        angularTolRad,
      );
      final bHoles = bpIdx < _blueprintWorldHoles.length
          ? [
              for (final h in _blueprintWorldHoles[bpIdx])
                _dedup(h, dedupTol),
            ]
          : const <List<Offset>>[];

      for (var pi = 0; pi < paperPolys.length; pi++) {
        final pid = paperIds[pi];
        if (animating.contains(pid)) continue;
        final cleaned = _removeCollinears(
          _dedup(paperPolys[pi], dedupTol),
          angularTolRad,
        );
        final pHoles = pi < paperHoles.length
            ? [
                for (final h in paperHoles[pi])
                  _removeCollinears(_dedup(h, dedupTol), angularTolRad),
              ]
            : const <List<Offset>>[];
        if (_compoundShapesMatch(
          cleaned,
          pHoles,
          bpClean,
          bHoles,
          tolerance,
        )) {
          animating.add(pid);
          paperToBpIndex[pid] = bpIdx;
          break;
        }
      }
    }

    if (animating.isEmpty) return;

    setState(() {
      _lockAnimatingPaperIds = animating;
      _lockAnimProgress = 0;
      for (final entry in paperToBpIndex.entries) {
        final paper = _placedPapers.where((p) => p.id == entry.key).firstOrNull;
        if (paper != null) {
          paper.lockedBlueprintIndex = entry.value;
          paper.opsLocked = true;
        }
      }
      _exitTransformIfPieceFitted();
    });
    _lockAnimController.forward(from: 0);
  }

  void _finalizeLock() {
    setState(() {
      _lockAnimatingPaperIds = {};
      _lockAnimProgress = 0;
    });
    // _recomputeLockedArea already calls _maybeCompleteFill.
    _recomputeLockedArea();
    _scheduleCheck();
  }

  bool _isCraftComplete() {
    if (_fillCompleteLatched) return false;
    return _blueprintTotalArea > 0 &&
        _blueprintLockedArea >= _blueprintTotalArea * 0.999 &&
        _completionPhase == CompletionPhase.none;
  }

  /// 100% geometry fill is the only completion trigger. Latch before notifying
  /// so a second check in the same frame cannot fire twice; [applyBlueprint]
  /// clears the latch for the next fill. Do not run the legacy fold/dismiss
  /// sequence here — that would re-latch the newly loaded fill.
  void _maybeCompleteFill() {
    if (!_isCraftComplete()) return;

    debugPrint(
      '[craft] fill complete '
      '(locked=$_blueprintLockedArea / total=$_blueprintTotalArea, '
      'filled=${_filledBlueprintIndices.length})',
    );
    _fillCompleteLatched = true;
    fmHapticBigClick();
    _beginExtraPaperDiscard();
  }

  static const _kDiscardStaggerMs = 50.0;
  static const _kDiscardFadeMs = 280.0;

  bool _isDiscardingPaper(String id) => _discardOrder.contains(id);

  Map<String, double> _discardOpacities() {
    if (_discardOrder.isEmpty) return const {};
    final out = <String, double>{};
    for (var i = 0; i < _discardOrder.length; i++) {
      final t = ((_discardElapsedMs - i * _kDiscardStaggerMs) / _kDiscardFadeMs)
          .clamp(0.0, 1.0);
      out[_discardOrder[i]] = 1.0 - t;
    }
    return out;
  }

  void _stopExtraPaperDiscard() {
    _discardController.stop();
    _discardOrder = [];
    _discardElapsedMs = 0;
  }

  void _beginExtraPaperDiscard() {
    final extras = _placedPapers
        .where((p) => !p.locked && p.lockedBlueprintIndex == null)
        .toList();
    extras.sort((a, b) {
      if (_viewportSize.width < 1 || _viewportSize.height < 1) {
        return b.position.y.compareTo(a.position.y);
      }
      final sa = _worldToScreen(a.position, _viewportSize);
      final sb = _worldToScreen(b.position, _viewportSize);
      return sa.dy.compareTo(sb.dy);
    });

    if (extras.isEmpty) {
      _notifyCraftCompleted();
      return;
    }

    _discardOrder = extras.map((p) => p.id).toList();
    _discardElapsedMs = 0;
    _selectedPaperIds.removeWhere(_isDiscardingPaper);
    _syncCopyMemoryWithSelection();
    if (_panModeSelectedPaperId != null &&
        _isDiscardingPaper(_panModeSelectedPaperId!)) {
      _panModeSelectedPaperId = null;
    }
    final totalMs =
        ((_discardOrder.length - 1) * _kDiscardStaggerMs + _kDiscardFadeMs)
            .round();
    _discardController.duration = Duration(milliseconds: totalMs);
    _discardController.forward(from: 0);
  }

  void _onDiscardTick() {
    final dur = _discardController.duration;
    if (dur == null || dur.inMilliseconds <= 0) return;
    _discardElapsedMs = dur.inMilliseconds * _discardController.value;
    final gone = <String>{};
    for (var i = 0; i < _discardOrder.length; i++) {
      if (_discardElapsedMs >= i * _kDiscardStaggerMs + _kDiscardFadeMs) {
        gone.add(_discardOrder[i]);
      }
    }
    if (gone.isEmpty) {
      setState(() {});
      return;
    }
    setState(() {
      _placedPapers.removeWhere((p) => gone.contains(p.id));
    });
  }

  void _onDiscardDone() {
    if (!mounted) return;
    setState(() {
      _placedPapers.removeWhere((p) => _discardOrder.contains(p.id));
      _discardOrder = [];
      _discardElapsedMs = 0;
    });
    _notifyCraftCompleted();
  }

  void _recomputeLockedArea() {
    if (_blueprintTotalArea <= 0) return;
    final oldProgress = _blueprintLockedArea / _blueprintTotalArea;
    double area = 0;
    for (final idx in _filledBlueprintIndices) {
      if (idx < _blueprintWorldPolygons.length) {
        area += _polyArea(_blueprintWorldPolygons[idx]).abs();
      }
    }
    _blueprintLockedArea = area;
    final newProgress = (_blueprintLockedArea / _blueprintTotalArea).clamp(
      0.0,
      1.0,
    );
    if ((newProgress - oldProgress).abs() > 1e-6) {
      _progressAnimFrom = oldProgress;
      _progressAnimTo = newProgress;
      _progressAnimController.forward(from: 0);
    }
    _maybeCompleteFill();
  }

  void _notifyCraftCompleted() {
    if (_selectedBlueprint == null) return;
    final matchedPapers = _placedPapers
        .where((p) => p.lockedBlueprintIndex != null)
        .map((p) => CraftingPaperState.fromPaper(p))
        .toList();
    _completedPapers = matchedPapers;
    widget.onCraftCompleted?.call(
      matchedPapers,
      _selectedBlueprint!.craft,
      _selectedBlueprint!,
    );
  }

  // ---------------------------------------------------------------------------
  // Completion (fold/dissolve animations currently disabled)
  // ---------------------------------------------------------------------------

  void _startCompletionSequence() {
    if (_selectedBlueprint == null ||
        _completionPhase != CompletionPhase.none) {
      return;
    }
    if (_fillCompleteLatched) return;

    debugPrint(
      '[craft] completion for ${_selectedBlueprint!.displayName}',
    );

    _fillCompleteLatched = true;
    fmHapticBigClick();

    // Skip dissolve/fold for now — finish immediately.
    if (_completedPapers.isNotEmpty) {
      widget.onCraftFoldComplete?.call(
        _completedPapers,
        _selectedBlueprint!.craft,
        _selectedBlueprint!,
      );
    }

    widget.onDismiss?.call();
  }

  void _onDissolveTick() {
    setState(() {
      final t = _dissolveController.value;
      _dotDissolveProgress = t;
      _foldOpacity = Curves.easeIn.transform(t);
    });
  }

  void _onDissolveDone() {
    setState(() {
      _dotDissolveProgress = 1;
      _foldOpacity = 1;
      _completionPhase = CompletionPhase.fold;
    });
    _foldController.forward(from: 0);
  }

  void _onFoldTick() {
    final eased = Curves.easeInCubic.transform(_foldController.value);
    _updateFoldAnimation(eased);
    setState(() {
      _foldColorProgress = (_foldController.value / 0.33).clamp(0.0, 1.0);
    });
  }

  void _onFoldComplete() {
    setState(() => _completionPhase = CompletionPhase.done);
    if (_selectedBlueprint != null && _completedPapers.isNotEmpty) {
      widget.onCraftFoldComplete?.call(
        _completedPapers,
        _selectedBlueprint!.craft,
        _selectedBlueprint!,
      );
    }

    widget.onDismiss?.call();
  }

  void _buildFoldGeometry() {
    if (_selectedBlueprint == null) return;
    final bp = _selectedBlueprint!;
    const stride = 100000;

    _foldNodeStates = {};
    _foldSchedule = [];
    final scheduled = <TransformTreeNode>[];

    for (var i = 0; i < bp.islands.length; i++) {
      final island = bp.islands[i];
      final tree = island.transformTree;
      final origin = Vector3(
        island.originOffset.dx,
        island.originOffset.dy + island.unfoldedYDisplacement,
        0,
      );
      for (final node in tree.nodes) {
        final id = i * stride + node.id;
        _foldNodeStates[id] = _FoldNodeState(
          nodeId: id,
          localId: node.id,
          islandIndex: i,
          node: node,
          tree: tree,
          unfoldedVertices3D: node.unfoldedVertices.map((v) => v.clone()).toList(),
          originOffset: origin,
          foldedOffset: island.foldedOffset.clone(),
        );
      }
      scheduled.addAll(tree.leafToRootOrder());
    }

    final count = scheduled.length;
    if (count > 0) {
      const overlap = 0.7;
      final slotDuration = count > 1
          ? 1.0 / (1.0 + (count - 1) * (1.0 - overlap))
          : 1.0;
      var i = 0;
      for (var islandI = 0; islandI < bp.islands.length; islandI++) {
        for (final node in bp.islands[islandI].transformTree.leafToRootOrder()) {
          final startT = i * slotDuration * (1.0 - overlap);
          final endT = (startT + slotDuration).clamp(0.0, 1.0);
          _foldSchedule.add((islandI * stride + node.id, startT, endT));
          i++;
        }
      }
    }

    _foldOriginOffset = bp.islands.isEmpty
        ? Vector3.zero()
        : Vector3(
            bp.originOffset.dx,
            bp.originOffset.dy + bp.unfoldedYDisplacement,
            0,
          );
    _foldFoldedOffset =
        bp.islands.isEmpty ? Vector3.zero() : bp.foldedOffset.clone();
    _foldDisplacementMatrix = Matrix4.identity();

    double rMinX = double.infinity, rMinY = double.infinity;
    double rMaxX = double.negativeInfinity, rMaxY = double.negativeInfinity;
    for (final state in _foldNodeStates.values) {
      for (final v in state.unfoldedVertices3D) {
        final wx = v.x + state.originOffset.x;
        final wy = v.y + state.originOffset.y;
        rMinX = math.min(rMinX, wx);
        rMinY = math.min(rMinY, wy);
        rMaxX = math.max(rMaxX, wx);
        rMaxY = math.max(rMaxY, wy);
      }
    }
    _foldRawCentroid = Offset((rMinX + rMaxX) / 2, (rMinY + rMaxY) / 2);
    final rawBboxSpan = math.max(rMaxX - rMinX, rMaxY - rMinY);
    _foldRawOrthoScale = (rawBboxSpan * 0.75).clamp(1.0, 10000.0);
  }

  static double _smoothstep(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  void _updateFoldAnimation(double globalT) {
    if (_foldNodeStates.isEmpty) return;

    for (final state in _foldNodeStates.values) {
      state.cumulativeMatrix = Matrix4.identity();
    }

    const stride = 100000;
    for (final (nodeId, startT, endT) in _foldSchedule) {
      final state = _foldNodeStates[nodeId];
      if (state == null) continue;

      final span = endT - startT;
      final localT = span > 1e-9
          ? ((globalT - startT) / span).clamp(0.0, 1.0)
          : (globalT >= endT ? 1.0 : 0.0);
      final eased = _smoothstep(localT);

      final xform = state.node.transform;
      Matrix4 stepMatrix;

      if (xform is RotationTransform) {
        stepMatrix = xform.buildMatrix(-xform.angleRadians * eased);
      } else if (xform is MovementTransform) {
        stepMatrix = lerpMatrix4(Matrix4.identity(), xform.inverse, eased);
      } else {
        continue;
      }

      final affected = <int>{
        nodeId,
        for (final d in state.tree.descendants(state.localId))
          state.islandIndex * stride + d,
      };
      for (final id in affected) {
        final s = _foldNodeStates[id];
        if (s != null) {
          s.cumulativeMatrix = stepMatrix * s.cumulativeMatrix;
        }
      }
    }

    for (final state in _foldNodeStates.values) {
      final dispPos = state.originOffset +
          (state.foldedOffset - state.originOffset) * globalT;
      final disp = Matrix4.identity()..setTranslation(dispPos);
      state.cumulativeMatrix = disp * state.cumulativeMatrix;
    }
    _foldDisplacementMatrix = Matrix4.identity();
    if (_foldNodeStates.isNotEmpty) {
      final first = _foldNodeStates.values.first;
      _foldOriginOffset = first.originOffset;
      _foldFoldedOffset = first.foldedOffset;
    }
  }

  /// View-projection for the fold. The camera does NOT orbit: it stays at a
  /// fixed azimuth and only tilts from straight-down (during the reveal, so the
  /// flat geometry overlays the 2D regions) into a gentle isometric angle as
  /// the fold progresses, keeping the model centered over its regions.
  Matrix4? _computeFoldVP(Size viewportSize) {
    if (_completionPhase != CompletionPhase.dissolveReveal &&
        _completionPhase != CompletionPhase.fold &&
        _completionPhase != CompletionPhase.done) {
      return null;
    }

    final foldT = _completionPhase == CompletionPhase.fold
        ? Curves.easeInOut.transform(_foldController.value)
        : (_completionPhase == CompletionPhase.done ? 1.0 : 0.0);

    // Track the fold geometry centroid as it displaces from unfolded to folded.
    final dispPos =
        _foldOriginOffset + (_foldFoldedOffset - _foldOriginOffset) * foldT;
    final centroid = Offset(
      _foldRawCentroid.dx - _foldOriginOffset.x + dispPos.x,
      _foldRawCentroid.dy - _foldOriginOffset.y + dispPos.y,
    );

    final azimuth = 5 * math.pi / 4; // fixed viewing direction
    // 90deg (top-down) eases to 60deg as folding proceeds.
    final elevation = math.pi / 2 - foldT * (math.pi / 2 - math.pi / 3);

    final r = 500.0;
    final camX = centroid.dx + r * math.cos(elevation) * math.cos(azimuth);
    final camY = centroid.dy + r * math.cos(elevation) * math.sin(azimuth);
    final camZ = r * math.sin(elevation);

    final forward = Vector3(centroid.dx - camX, centroid.dy - camY, -camZ)
      ..normalize();
    final worldUp = Vector3(0, 0, 1);
    var right = forward.cross(worldUp);
    if (right.length < 1e-4) {
      // Degenerate when perfectly top-down; pick a stable +X right vector.
      right = Vector3(1, 0, 0);
    }
    right.normalize();
    final up = right.cross(forward)..normalize();

    final cam = scene_camera.Camera(
      name: 'fold-cam',
      position: Vector3(camX, camY, camZ),
      target: Vector3(centroid.dx, centroid.dy, 0),
      up: up,
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: _foldRawOrthoScale,
      near: 0.1,
      far: 1500,
    );

    final aspect = viewportSize.width / viewportSize.height;
    return cam.projectionMatrix(aspect) * cam.viewMatrix;
  }

  // ---------------------------------------------------------------------------
  // Cut animation
  // ---------------------------------------------------------------------------

  /// Intersects the infinite line through [la]-[lb] with segment [sa]-[sb].
  static Offset? _lineCrossesSegment(
    Offset la,
    Offset lb,
    Offset sa,
    Offset sb,
  ) {
    final dxa = lb.dx - la.dx;
    final dya = lb.dy - la.dy;
    final dxb = sb.dx - sa.dx;
    final dyb = sb.dy - sa.dy;
    final denom = dxa * dyb - dya * dxb;
    if (denom.abs() < 1e-10) return null;
    final wx = la.dx - sa.dx;
    final wy = la.dy - sa.dy;
    final u = (dxa * wy - dya * wx) / denom;
    if (u < -1e-10 || u > 1 + 1e-10) return null;
    return Offset(sa.dx + u * dxb, sa.dy + u * dyb);
  }

  void _startCutAnimation() {
    if (_drawnCutLines.isEmpty) return;

    final drawStart = _drawnCutLines.first.$1;
    final drawEnd = _drawnCutLines.last.$2;
    final dir = drawEnd - drawStart;
    final dirLen = dir.distance;
    if (dirLen < 1e-6) return;
    final unitDir = dir / dirLen;

    // Find all intersection points between cut line(s) and paper edges.
    final allIntersections = <Offset>[];
    for (final line in _drawnCutLines) {
      for (final paper in _placedPapers) {
        if (_isToolProtected(paper)) continue;
        final worldCorners = _paperWorldCorners(paper);
        final poly = worldCorners.map((v) => Offset(v.x, v.y)).toList();
        for (var i = 0; i < poly.length; i++) {
          final pt = _lineCrossesSegment(
            line.$1,
            line.$2,
            poly[i],
            poly[(i + 1) % poly.length],
          );
          if (pt != null) allIntersections.add(pt);
        }
      }
    }

    if (allIntersections.isEmpty) {
      setState(() {
        _drawnCutLines.clear();
        _fadeCutHighlights();
      });
      return;
    }

    // Project intersections onto the line direction to find outermost points.
    double minProj = double.infinity;
    double maxProj = -double.infinity;
    Offset nearStart = allIntersections.first;
    Offset nearEnd = allIntersections.first;
    for (final pt in allIntersections) {
      final proj =
          (pt - drawStart).dx * unitDir.dx + (pt - drawStart).dy * unitDir.dy;
      if (proj < minProj) {
        minProj = proj;
        nearStart = pt;
      }
      if (proj > maxProj) {
        maxProj = proj;
        nearEnd = pt;
      }
    }

    final gridOffset = 2 * _minorGridSpacing;
    final friendStart = nearStart - unitDir * gridOffset;
    final friendEnd = nearEnd + unitDir * gridOffset;

    _activeToolpath = [ToolpathSegment(friendStart, friendEnd, true)];
    final totalDist = (friendEnd - friendStart).distance;
    _toolpathTotalDist = totalDist;
    if (_toolpathTotalDist < 1e-6) return;

    _cutAnimController.duration = const Duration(seconds: 1);

    _objectPosition.x = friendStart.dx;
    _objectPosition.y = friendStart.dy;
    _objectPosition.z = _friendScale * 60;
    final angle = math.atan2(unitDir.dy, unitDir.dx);
    _objectRotation = Quaternion.axisAngle(Vector3(0, 0, 1), angle);
    _friendVisible = true;

    setState(() => _craftingMode = CraftingMode.cutting);
    _cutAnimController.forward(from: 0);
  }

  void _onCutAnimTick() {
    final t = _cutAnimController.value;
    if (_activeToolpath.isEmpty) return;

    final easedT = Curves.easeInOut.transform(t);
    final start = _activeToolpath.first.start;
    final end = _activeToolpath.last.end;
    final pos = Offset.lerp(start, end, easedT)!;

    final dir = end - start;
    if (dir.distance > 1e-6) {
      final angle = math.atan2(dir.dy, dir.dx);
      _objectRotation = Quaternion.axisAngle(Vector3(0, 0, 1), angle);
    }

    setState(() {
      _objectPosition.x = pos.dx;
      _objectPosition.y = pos.dy;
    });
  }

  void _onCutAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _applyCuts();
      setState(() {
        _friendVisible = false;
        _drawnCutLines.clear();
        _activeToolpath = [];
        _toolpathTotalDist = 0;
        _fadeCutHighlights();
        _craftingMode = CraftingMode.drawLine;
      });
      _scheduleCheck();
    }
  }

  void _executeCut() {
    if (_drawnCutLines.isEmpty) return;
    _applyCuts();
    setState(() {
      _friendVisible = false;
      _drawnCutLines.clear();
      _activeToolpath = [];
      _toolpathTotalDist = 0;
      _resetCutStroke();
      _craftingMode = CraftingMode.drawLine;
    });
    _scheduleCheck();
  }

  // ---------------------------------------------------------------------------
  // Grid snapping
  // ---------------------------------------------------------------------------

  /// Returns the XY offset to snap the vertex closest to a grid intersection
  /// point onto that point. Grid lines start at -half and repeat every
  /// Unconditional grid snap: finds the vertex nearest to a grid intersection
  /// and returns the offset to move it there.
  Offset _gridSnapFallback(List<Vector3> worldVertices) {
    double bestDist = double.infinity;
    Offset bestOffset = Offset.zero;

    final spacing = _activeGridSpacing;
    for (final v in worldVertices) {
      final world = Offset(v.x, v.y);
      final snapped = _snapPointToGrid(world, spacing);
      final dx = snapped.dx - v.x;
      final dy = snapped.dy - v.y;
      final dist = dx * dx + dy * dy;
      if (dist < bestDist) {
        bestDist = dist;
        bestOffset = Offset(dx, dy);
      }
    }
    return bestOffset;
  }

  /// Snap radius in world units derived from a fixed screen-pixel tolerance,
  /// so snapping feels consistent regardless of zoom level.
  double get _snapWorldRadius {
    final h = _viewportSize.height;
    if (h < 1) return _minorGridSpacing * 0.5;
    return _snapPixelTolerance * (2 * _orthoScale / h);
  }

  /// Priority-weighted snap across multiple target categories.
  ///
  /// Priority (ascending): grid=0, friend=1, paper=2, blueprint=3.
  /// Within equal priority the closest match wins. If nothing is in range
  /// and grid snap is enabled, falls back to unconditional grid snap.
  /// Returns [Offset.zero] (freehand) when all snap toggles are off.
  Offset _computeSnap(
    List<Vector3> movingVertices, {
    Set<String>? excludePaperIds,
  }) {
    if (!_snapGrid && !_snapPaper && !_snapBlueprint) return Offset.zero;

    final radius = _snapWorldRadius;

    double bestDist = double.infinity;
    Offset bestOffset = Offset.zero;
    int bestPriority = -1;

    void consider(double dx, double dy, double dist, int priority) {
      if (priority > bestPriority ||
          (priority == bestPriority && dist < bestDist)) {
        bestPriority = priority;
        bestDist = dist;
        bestOffset = Offset(dx, dy);
      }
    }

    List<Offset>? otherPaperVerts;
    if (_snapPaper) {
      otherPaperVerts = [];
      for (final p in _placedPapers) {
        if (excludePaperIds != null && excludePaperIds.contains(p.id)) {
          continue;
        }
        for (final c in _paperWorldCorners(p)) {
          otherPaperVerts.add(Offset(c.x, c.y));
        }
      }
    }

    List<Offset>? bpVerts;
    if (_snapBlueprint && _snapWorldLoops.isNotEmpty) {
      bpVerts = [
        for (final (ring, _) in _snapWorldLoops) ...ring,
      ];
    }

    for (final v in movingVertices) {
      final vx = v.x;
      final vy = v.y;

      if (bpVerts != null) {
        for (final bp in bpVerts) {
          final dx = bp.dx - vx;
          final dy = bp.dy - vy;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist <= radius) {
            consider(dx, dy, dist, 3);
          }
        }
      }

      if (otherPaperVerts != null) {
        for (final pv in otherPaperVerts) {
          final dx = pv.dx - vx;
          final dy = pv.dy - vy;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist <= radius) {
            consider(dx, dy, dist, 2);
          }
        }
      }

      if (_snapGrid) {
        final spacing = _activeGridSpacing;
        final world = Offset(vx, vy);
        final snapped = _snapPointToGrid(world, spacing);
        final dx = snapped.dx - vx;
        final dy = snapped.dy - vy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          consider(dx, dy, dist, 0);
        }
      }
    }

    if (bestPriority < 0 && _snapGrid) {
      return _gridSnapFallback(movingVertices);
    }

    return bestOffset;
  }

  /// Snap a single world-space point using the same priority logic.
  Offset _snapWorldPoint(Offset worldPt) {
    final v = Vector3(worldPt.dx, worldPt.dy, 0);
    final snap = _computeSnap([v]);
    return Offset(worldPt.dx + snap.dx, worldPt.dy + snap.dy);
  }

  static const _kCutBlueprintSnapScale = 2.6;
  static const _kCutAdjacentDistScale = 0.62;
  static const _kCutParallelDot = 0.99; // ~8°; 180° counts as the same direction
  static const _kCutRayAngleDeg = 5.0;

  /// Cut-line snap: blueprint vertices beat the grid whenever they are nearby.
  /// If the stroke started on a blueprint vertex, adjacent vertices (the other
  /// ends of edges that share that vertex) get a slight extra pull.
  /// When the drag angle matches an incident edge within [_kCutRayAngleDeg],
  /// the end point locks to that edge's infinite ray.
  ({Offset point, List<_BpVertexRef> refs, (Offset, Offset)? ray}) _snapCutPoint(
    Offset worldPt, {
    List<_BpVertexRef> fromVertexRefs = const [],
  }) {
    final gridRadius = _snapWorldRadius;
    final bpRadius = gridRadius * _kCutBlueprintSnapScale;
    final ray = fromVertexRefs.isEmpty
        ? null
        : _bestCutRay(fromVertexRefs.first.point, worldPt, fromVertexRefs);

    _BpVertexRef? bestRef;
    var bestScore = double.infinity;
    if (_snapBlueprint && _snapWorldLoops.isNotEmpty) {
      for (var pi = 0; pi < _snapWorldLoops.length; pi++) {
        final ring = _snapWorldLoops[pi].$1;
        for (var vi = 0; vi < ring.length; vi++) {
          final dist = (ring[vi] - worldPt).distance;
          if (dist > bpRadius) continue;
          var score = dist;
          if (fromVertexRefs.isNotEmpty &&
              fromVertexRefs.any(
                (start) => _isAdjacentBlueprintVertex(start, pi, vi),
              )) {
            score *= _kCutAdjacentDistScale;
          }
          if (score < bestScore) {
            bestScore = score;
            bestRef = _BpVertexRef(pi, vi, ring[vi]);
          }
        }
      }
    }
    if (bestRef != null) {
      final onRay = ray == null ||
          _distanceToLine(bestRef.point, ray.$1, ray.$2) <=
              math.max(1e-4, gridRadius * 0.15);
      return (
        point: bestRef.point,
        refs: _blueprintVertexRefsAt(bestRef.point),
        ray: onRay ? ray : null,
      );
    }

    if (ray != null) {
      return (
        point: _projectOntoLine(worldPt, ray.$1, ray.$2),
        refs: const [],
        ray: ray,
      );
    }

    if (_snapPaper) {
      Offset? bestPaper;
      var bestPaperDist = gridRadius;
      for (final paper in _placedPapers) {
        if (paper.locked) continue;
        for (final corner in _paperWorldCorners(paper)) {
          final pt = Offset(corner.x, corner.y);
          final dist = (pt - worldPt).distance;
          if (dist < bestPaperDist) {
            bestPaperDist = dist;
            bestPaper = pt;
          }
        }
      }
      if (bestPaper != null) {
        return (point: bestPaper, refs: const [], ray: null);
      }
    }

    if (_snapGrid) {
      return (point: _snapPointToGrid(worldPt), refs: const [], ray: null);
    }
    return (point: worldPt, refs: const [], ray: null);
  }

  (Offset, Offset)? _bestCutRay(
    Offset start,
    Offset pointer,
    List<_BpVertexRef> refs,
  ) {
    if (!_snapBlueprint) return null;
    final drag = pointer - start;
    final dragLen = drag.distance;
    if (dragLen < 1e-6) return null;
    final dragUnit = drag / dragLen;
    final minDot = math.cos(_kCutRayAngleDeg * math.pi / 180);
    (Offset, Offset)? best;
    var bestDot = minDot;
    for (final (a, b) in _incidentSnapEdges(refs)) {
      final edge = b - a;
      final edgeLen = edge.distance;
      if (edgeLen < 1e-6) continue;
      final edgeUnit = edge / edgeLen;
      final aligned =
          (dragUnit.dx * edgeUnit.dx + dragUnit.dy * edgeUnit.dy).abs();
      if (aligned >= bestDot) {
        bestDot = aligned;
        best = (a, b);
      }
    }
    return best;
  }

  Iterable<(Offset, Offset)> _incidentSnapEdges(List<_BpVertexRef> refs) sync* {
    for (final ref in refs) {
      if (ref.polyIndex < 0 || ref.polyIndex >= _snapWorldLoops.length) {
        continue;
      }
      final ring = _snapWorldLoops[ref.polyIndex].$1;
      final n = ring.length;
      if (n < 2) continue;
      final i = ref.vertexIndex;
      if (i < 0 || i >= n) continue;
      yield (ring[i], ring[(i + 1) % n]);
      yield (ring[i], ring[(i + n - 1) % n]);
    }
  }

  static Offset _projectOntoLine(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) return a;
    final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
    return Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  }

  List<_BpVertexRef> _blueprintVertexRefsAt(Offset point) {
    const eps2 = 1e-8;
    final refs = <_BpVertexRef>[];
    for (var pi = 0; pi < _snapWorldLoops.length; pi++) {
      final ring = _snapWorldLoops[pi].$1;
      for (var vi = 0; vi < ring.length; vi++) {
        if ((ring[vi] - point).distanceSquared <= eps2) {
          refs.add(_BpVertexRef(pi, vi, ring[vi]));
        }
      }
    }
    return refs;
  }

  bool _isAdjacentBlueprintVertex(
    _BpVertexRef start,
    int polyIndex,
    int vertexIndex,
  ) {
    if (start.polyIndex != polyIndex) return false;
    if (polyIndex < 0 || polyIndex >= _snapWorldLoops.length) return false;
    final n = _snapWorldLoops[polyIndex].$1.length;
    if (n < 2) return false;
    final d = (vertexIndex - start.vertexIndex).abs();
    return d == 1 || d == n - 1;
  }

  void _resetCutStroke({bool fadeHighlights = true}) {
    _lineDrawStart = null;
    _lineDrawPreview = null;
    _cutStartVertexRefs = const [];
    _cutSnapRay = null;
    if (fadeHighlights) {
      _fadeCutHighlights();
    }
  }

  void _fadeCutHighlights() {
    if (_cutHighlightEdges.isEmpty) {
      _cutEdgeGlowController.value = 0;
      return;
    }
    if (_cutEdgeGlowController.value > 0) {
      _cutEdgeGlowController.reverse();
    }
  }

  void _updateCutHighlights(Offset start, Offset end) {
    if ((end - start).distance < 1e-4) {
      _cutHighlightEdges = [];
      _cutEdgeGlowController.value = 0;
      return;
    }
    _cutHighlightEdges = _parallelIntersectingBlueprintEdges(start, end);
    if (_cutHighlightEdges.isEmpty) {
      _cutEdgeGlowController.value = 0;
      return;
    }
    _cutEdgeGlowController.value = 1;
  }

  /// Blueprint edges parallel to [start]-[end] (180° = same) that also
  /// intersect or overlap the extended cut line.
  List<(Offset, Offset)> _parallelIntersectingBlueprintEdges(
    Offset start,
    Offset end,
  ) {
    final cut = end - start;
    final cutLen = cut.distance;
    if (cutLen < 1e-6) return const [];
    final cutUnit = cut / cutLen;
    final (extA, extB) = extendLineSegment(start, end, _drawingPlaneSize);
    final hits = <(Offset, Offset)>[];
    for (final (poly, _) in _snapWorldLoops) {
      if (poly.length < 2) continue;
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final edge = b - a;
        final edgeLen = edge.distance;
        if (edgeLen < 1e-6) continue;
        final edgeUnit = edge / edgeLen;
        final aligned = (cutUnit.dx * edgeUnit.dx + cutUnit.dy * edgeUnit.dy)
            .abs();
        if (aligned < _kCutParallelDot) continue;
        if (!_edgeOverlapsCutLine(a, b, extA, extB)) continue;
        hits.add((a, b));
      }
    }
    return hits;
  }

  bool _edgeOverlapsCutLine(
    Offset a,
    Offset b,
    Offset cutA,
    Offset cutB,
  ) {
    final hit = segmentIntersection(cutA, cutB, a, b);
    if (hit.type != IntersectionType.none) return true;
    final tol = math.max(_snapWorldRadius * 0.3, 1e-4);
    if (_distanceToLine(a, cutA, cutB) > tol) return false;
    if (_distanceToLine(b, cutA, cutB) > tol) return false;
    return _projectionsOverlap(a, b, cutA, cutB);
  }

  static double _distanceToLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distance;
    if (len < 1e-9) return (p - a).distance;
    return ((p.dx - a.dx) * ab.dy - (p.dy - a.dy) * ab.dx).abs() / len;
  }

  static bool _projectionsOverlap(Offset a, Offset b, Offset c, Offset d) {
    final axis = d - c;
    final len2 = axis.dx * axis.dx + axis.dy * axis.dy;
    if (len2 < 1e-12) return false;
    double proj(Offset p) =>
        ((p.dx - c.dx) * axis.dx + (p.dy - c.dy) * axis.dy) / len2;
    final pa = proj(a), pb = proj(b), pc = 0.0, pd = 1.0;
    final minE = math.min(pa, pb);
    final maxE = math.max(pa, pb);
    final minC = math.min(pc, pd);
    final maxC = math.max(pc, pd);
    return maxE >= minC - 1e-6 && minE <= maxC + 1e-6;
  }

  // ---------------------------------------------------------------------------
  // Shared handle-box (stencil + stretch)
  // ---------------------------------------------------------------------------

  static const _kHandleFollowRate = 18.0;

  /// 0=top, 1=right, 2=bottom, 3=left, 4=TL, 5=TR, 6=BR, 7=BL (Y-up).
  ({bool left, bool right, bool top, bool bottom}) _handleMoves(
    int handleIndex,
  ) {
    return (
      left: handleIndex == 3 || handleIndex == 4 || handleIndex == 7,
      right: handleIndex == 1 || handleIndex == 5 || handleIndex == 6,
      top: handleIndex == 0 || handleIndex == 4 || handleIndex == 5,
      bottom: handleIndex == 2 || handleIndex == 6 || handleIndex == 7,
    );
  }

  Rect _resizeHandleBox({
    required Rect start,
    required int handleIndex,
    required Offset pointer,
    bool uniformCorners = false,
    double minSize = 0.01,
  }) {
    var minX = start.left;
    var maxX = start.right;
    var minY = start.top;
    var maxY = start.bottom;
    final moves = _handleMoves(handleIndex);
    if (moves.left) minX = pointer.dx;
    if (moves.right) maxX = pointer.dx;
    if (moves.bottom) minY = pointer.dy;
    if (moves.top) maxY = pointer.dy;
    if (uniformCorners && handleIndex >= 4) {
      final fixedX = moves.left ? start.right : start.left;
      final fixedY = moves.bottom ? start.bottom : start.top;
      final s = math.max(
        (pointer.dx - fixedX).abs(),
        (pointer.dy - fixedY).abs(),
      );
      minX = moves.left ? fixedX - s : fixedX;
      maxX = moves.left ? fixedX : fixedX + s;
      minY = moves.bottom ? fixedY - s : fixedY;
      maxY = moves.bottom ? fixedY : fixedY + s;
    }
    if (maxX < minX) {
      final t = minX;
      minX = maxX;
      maxX = t;
    }
    if (maxY < minY) {
      final t = minY;
      minY = maxY;
      maxY = t;
    }
    if (maxX - minX < minSize) {
      if (moves.left) {
        minX = maxX - minSize;
      } else if (moves.right) {
        maxX = minX + minSize;
      } else {
        final mid = (minX + maxX) / 2;
        minX = mid - minSize / 2;
        maxX = mid + minSize / 2;
      }
    }
    if (maxY - minY < minSize) {
      if (moves.bottom) {
        minY = maxY - minSize;
      } else if (moves.top) {
        maxY = minY + minSize;
      } else {
        final mid = (minY + maxY) / 2;
        minY = mid - minSize / 2;
        maxY = mid + minSize / 2;
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect _snapHandleBox(
    Rect r,
    int handleIndex, {
    Iterable<(Offset a, Offset b, bool isHole)>? edges,
    Iterable<(Offset p, bool isHole)>? vertices,
    Offset Function(Offset point)? snapGridPoint,
  }) {
    final moves = _handleMoves(handleIndex);
    var minX = r.left;
    var maxX = r.right;
    var minY = r.top;
    var maxY = r.bottom;
    var snappedX = false;
    var snappedY = false;

    ({double value, double score})? axis({
      required double value,
      required bool isX,
      required double spanMin,
      required double spanMax,
    }) {
      return _snapStencilAxis(
        value: value,
        isX: isX,
        spanMin: spanMin,
        spanMax: spanMax,
        edges: edges,
      );
    }

    if (moves.left) {
      final s = axis(value: minX, isX: true, spanMin: minY, spanMax: maxY);
      if (s != null) {
        minX = s.value;
        snappedX = true;
      }
    }
    if (moves.right) {
      final s = axis(value: maxX, isX: true, spanMin: minY, spanMax: maxY);
      if (s != null) {
        maxX = s.value;
        snappedX = true;
      }
    }
    if (moves.bottom) {
      final s = axis(value: minY, isX: false, spanMin: minX, spanMax: maxX);
      if (s != null) {
        minY = s.value;
        snappedY = true;
      }
    }
    if (moves.top) {
      final s = axis(value: maxY, isX: false, spanMin: minX, spanMax: maxX);
      if (s != null) {
        maxY = s.value;
        snappedY = true;
      }
    }

    final verts = vertices ?? _blueprintSnapVertices();
    if (_snapBlueprint && handleIndex >= 4) {
      final corner = Offset(
        moves.left ? minX : maxX,
        moves.bottom ? minY : maxY,
      );
      final vertRadius = _snapWorldRadius * _kStencilBlueprintSnapScale;
      double bestScore = double.infinity;
      Offset? best;
      for (final (p, isHole) in verts) {
        final dist = (p - corner).distance;
        if (dist > vertRadius) continue;
        final score = isHole ? dist * _kStencilHoleScoreScale : dist;
        if (score < bestScore) {
          bestScore = score;
          best = p;
        }
      }
      if (best != null) {
        if (moves.left) minX = best.dx;
        if (moves.right) maxX = best.dx;
        if (moves.bottom) minY = best.dy;
        if (moves.top) maxY = best.dy;
        snappedX = true;
        snappedY = true;
      }
    }

    if (_snapGrid && snapGridPoint != null) {
      if ((moves.left || moves.right) && !snappedX) {
        final x = moves.left ? minX : maxX;
        final g = snapGridPoint(Offset(x, (minY + maxY) / 2));
        if (moves.left) minX = g.dx;
        if (moves.right) maxX = g.dx;
      }
      if ((moves.top || moves.bottom) && !snappedY) {
        final y = moves.bottom ? minY : maxY;
        final g = snapGridPoint(Offset((minX + maxX) / 2, y));
        if (moves.bottom) minY = g.dy;
        if (moves.top) maxY = g.dy;
      }
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _beginHandleFollow(Rect current, void Function(Rect) apply) {
    _handleFollowDisplay = current;
    _handleFollowTarget = current;
    _handleFollowApply = apply;
    _handleFollowOnSettled = null;
    _handleFollowSettling = false;
    apply(current);
    _ensureHandleFollowTicker();
  }

  void _setHandleFollowTarget(Rect target) {
    _handleFollowTarget = target;
    _handleFollowDisplay ??= target;
    _ensureHandleFollowTicker();
  }

  void _settleHandleFollow({VoidCallback? onSettled}) {
    _handleFollowSettling = true;
    _handleFollowOnSettled = onSettled;
    _ensureHandleFollowTicker();
  }

  void _stopHandleFollow() {
    _handleFollowTicker.stop();
    _handleFollowLast = null;
    _handleFollowDisplay = null;
    _handleFollowTarget = null;
    _handleFollowApply = null;
    _handleFollowOnSettled = null;
    _handleFollowSettling = false;
  }

  void _ensureHandleFollowTicker() {
    if (!_handleFollowTicker.isActive) {
      _handleFollowLast = null;
      _handleFollowTicker.start();
    }
  }

  void _onHandleFollowTick(Duration elapsed) {
    final last = _handleFollowLast;
    _handleFollowLast = elapsed;
    if (last == null) return;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.1) return;
    final display = _handleFollowDisplay;
    final target = _handleFollowTarget;
    final apply = _handleFollowApply;
    if (display == null || target == null || apply == null) return;

    final t = 1 - math.exp(-_kHandleFollowRate * dt);
    final next = Rect.lerp(display, target, t)!;
    final close = (next.left - target.left).abs() < 1e-4 &&
        (next.right - target.right).abs() < 1e-4 &&
        (next.top - target.top).abs() < 1e-4 &&
        (next.bottom - target.bottom).abs() < 1e-4;
    final settled = close ? target : next;
    _handleFollowDisplay = settled;
    if (!mounted) return;
    setState(() => apply(settled));
    if (close) {
      if (_handleFollowSettling) {
        final done = _handleFollowOnSettled;
        _handleFollowSettling = false;
        _handleFollowOnSettled = null;
        done?.call();
      }
      if (_stencilHandleIndex == null &&
          _stretchHandleIndex == null &&
          !_handleFollowSettling) {
        _handleFollowTicker.stop();
        _handleFollowLast = null;
      }
    }
  }

  Offset _mapBoxPoint(Offset v, Rect from, Rect to) {
    final w = from.width.abs() < 1e-9 ? 1.0 : from.width;
    final h = from.height.abs() < 1e-9 ? 1.0 : from.height;
    return Offset(
      to.left + (v.dx - from.left) / w * to.width,
      to.top + (v.dy - from.top) / h * to.height,
    );
  }

  /// True when [verts] have collapsed to a point, a line, or zero area.
  bool _isDegenerateXformPolygon(List<Offset> verts) {
    if (verts.length < 3) return true;
    if (_polyArea(verts).abs() <= 1e-6) return true;
    var minX = verts[0].dx, maxX = verts[0].dx;
    var minY = verts[0].dy, maxY = verts[0].dy;
    for (final v in verts) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    return (maxX - minX) <= 1e-6 || (maxY - minY) <= 1e-6;
  }

  bool _stretchBoundsAreDegenerate(PlacedPaper paper, Rect from, Rect to) {
    if (to.width.abs() <= 1e-6 || to.height.abs() <= 1e-6) return true;
    final mapped = [
      for (final v in _paperLocalVertices(paper)) _mapBoxPoint(v, from, to),
    ];
    return _isDegenerateXformPolygon(mapped);
  }

  // ---------------------------------------------------------------------------
  // Stretch tool helpers
  // ---------------------------------------------------------------------------

  /// Local-space AABB of a paper's vertices.
  Rect _paperLocalBounds(PlacedPaper paper) {
    final verts = _paperLocalVertices(paper);
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final v in verts) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _paperLocalToWorld(Offset local, PlacedPaper paper) {
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return Offset(
      paper.position.x + local.dx * cosA - local.dy * sinA,
      paper.position.y + local.dx * sinA + local.dy * cosA,
    );
  }

  List<Offset> _stretchHandleWorldPositions(PlacedPaper paper, Rect bounds) {
    Offset toWorld(double lx, double ly) =>
        _paperLocalToWorld(Offset(lx, ly), paper);
    final l = bounds.left, r = bounds.right;
    final t = bounds.top, b = bounds.bottom;
    final mx = (l + r) / 2, my = (t + b) / 2;
    return [
      toWorld(mx, b),
      toWorld(r, my),
      toWorld(mx, t),
      toWorld(l, my),
      toWorld(l, b),
      toWorld(r, b),
      toWorld(r, t),
      toWorld(l, t),
    ];
  }

  int? _hitTestStretchHandle(
    Offset screenPos,
    Size viewportSize,
    PlacedPaper paper,
  ) {
    final bounds =
        _stretchDisplayLocal ?? _stretchStartLocal ?? _paperLocalBounds(paper);
    final handles = _stretchHandleWorldPositions(paper, bounds);
    const hitRadius = 20.0;
    int? best;
    var bestDist = hitRadius;
    for (final i in const [4, 5, 6, 7, 0, 1, 2, 3]) {
      final sp = _worldToScreen(
        Vector3(handles[i].dx, handles[i].dy, _paperZ),
        viewportSize,
      );
      final dist = (sp - screenPos).distance;
      if (dist <= bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  Iterable<(Offset a, Offset b, bool isHole)> _stretchLocalSnapEdges(
    PlacedPaper paper,
  ) sync* {
    for (final (a, b, isHole) in _blueprintSnapEdges()) {
      yield (
        _worldToPaperLocal(Vector3(a.dx, a.dy, 0), paper),
        _worldToPaperLocal(Vector3(b.dx, b.dy, 0), paper),
        isHole,
      );
    }
  }

  Iterable<(Offset p, bool isHole)> _stretchLocalSnapVertices(
    PlacedPaper paper,
  ) sync* {
    for (final (p, isHole) in _blueprintSnapVertices()) {
      yield (_worldToPaperLocal(Vector3(p.dx, p.dy, 0), paper), isHole);
    }
  }

  Rect _stretchTargetFromPointer(
    PlacedPaper paper,
    int handleIndex,
    Offset world,
  ) {
    final start = _stretchStartLocal ?? _paperLocalBounds(paper);
    final local = _worldToPaperLocal(Vector3(world.dx, world.dy, 0), paper);
    final raw = _resizeHandleBox(
      start: start,
      handleIndex: handleIndex,
      pointer: local,
    );
    return _snapHandleBox(
      raw,
      handleIndex,
      edges: _stretchLocalSnapEdges(paper),
      vertices: _stretchLocalSnapVertices(paper),
      snapGridPoint: (p) {
        final g = _snapPointToGrid(_paperLocalToWorld(p, paper));
        return _worldToPaperLocal(Vector3(g.dx, g.dy, 0), paper);
      },
    );
  }

  void _clearStretchBox() {
    _stretchStartLocal = null;
    _stretchDisplayLocal = null;
    _stretchHandleIndex = null;
  }

  void _startTransform(PlacedPaper paper) {
    if (paper.locked) return;
    setState(() {
      _craftingMode = CraftingMode.select;
      _isRotationGizmoActive = false;
      _stretchPaperId = paper.id;
      _clearStretchBox();
      _selectedPaperIds = {paper.id};
    });
  }

  void _endTransform({bool deselect = false}) {
    _bakeStretch();
    _stretchPaperId = null;
    _clearStretchBox();
    _stopHandleFollow();
    if (deselect) {
      _selectedPaperIds = {};
      _isRotationGizmoActive = false;
    }
  }

  /// Leave xform for a piece that just fitted a blueprint slot (green edges).
  void _exitTransformIfPieceFitted() {
    final id = _stretchPaperId;
    if (id == null || _stretchHandleIndex != null) return;
    final paper = _placedPapers.where((p) => p.id == id).firstOrNull;
    if (paper == null || !paper.isBlueprintMatched) return;
    _endTransform();
  }

  void _bakeStretch() {
    final paperId = _stretchPaperId;
    final from = _stretchStartLocal;
    final to = _stretchDisplayLocal;
    if (paperId == null || from == null || to == null) {
      _clearStretchBox();
      _stopHandleFollow();
      return;
    }
    final unchanged = (from.left - to.left).abs() < 1e-6 &&
        (from.right - to.right).abs() < 1e-6 &&
        (from.top - to.top).abs() < 1e-6 &&
        (from.bottom - to.bottom).abs() < 1e-6;
    if (unchanged) {
      _clearStretchBox();
      _stopHandleFollow();
      return;
    }
    final paper = _placedPapers.where((p) => p.id == paperId).firstOrNull;
    if (paper == null) {
      _clearStretchBox();
      _stopHandleFollow();
      return;
    }

    if (_stretchBoundsAreDegenerate(paper, from, to)) {
      _stretchDisplayLocal = from;
      _handleFollowDisplay = from;
      _handleFollowTarget = from;
      _stopHandleFollow();
      return;
    }

    Offset xformOff(Offset v) => _mapBoxPoint(v, from, to);
    final verts = _paperLocalVertices(paper);
    final scaled = verts.map(xformOff).toList();
    final scaledHoles =
        paper.localHoles.map((h) => h.map(xformOff).toList()).toList();
    final scaledCuts =
        paper.cutSegments.map((s) => (xformOff(s.$1), xformOff(s.$2))).toList();

    var cxLocal = 0.0, cyLocal = 0.0;
    for (final v in scaled) {
      cxLocal += v.dx;
      cyLocal += v.dy;
    }
    cxLocal /= scaled.length;
    cyLocal /= scaled.length;
    final recentered =
        scaled.map((v) => Offset(v.dx - cxLocal, v.dy - cyLocal)).toList();
    final recenteredHoles = scaledHoles
        .map((h) => h.map((v) => Offset(v.dx - cxLocal, v.dy - cyLocal)).toList())
        .toList();
    final recenteredCuts = scaledCuts
        .map(
          (s) => (
            Offset(s.$1.dx - cxLocal, s.$1.dy - cyLocal),
            Offset(s.$2.dx - cxLocal, s.$2.dy - cyLocal),
          ),
        )
        .toList();

    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final newPosX = paper.position.x + cxLocal * cosA - cyLocal * sinA;
    final newPosY = paper.position.y + cxLocal * sinA + cyLocal * cosA;

    final idx = _placedPapers.indexOf(paper);
    final replacement = PlacedPaper(
      id: paper.id,
      paperColor: paper.paperColor,
      position: Vector3(newPosX, newPosY, paper.position.z),
      stackOrder: paper.stackOrder,
      rotationDeg: paper.rotationDeg,
      sizeLevel: paper.sizeLevel,
      localVertices: recentered,
      localHoles: recenteredHoles,
      groupId: paper.groupId,
      materialId: paper.materialId,
    );
    replacement.cutSegments.addAll(recenteredCuts);
    replacement.locked = paper.locked;
    replacement.lockedBlueprintIndex = paper.lockedBlueprintIndex;
    replacement.opsLocked = paper.opsLocked;
    _placedPapers[idx] = replacement;
    _stretchPaperId = replacement.id;
    _stretchStartLocal = _paperLocalBounds(replacement);
    _stretchDisplayLocal = _stretchStartLocal;
    _stretchHandleIndex = null;
    _stopHandleFollow();
    _scheduleCheck();
  }

  // ---------------------------------------------------------------------------
  // Stencil tool
  // ---------------------------------------------------------------------------

  double get _stencilUnit => _minorGridSpacing;

  void _enterStencilMode() {
    _endTransform();
    _craftingMode = CraftingMode.stencil;
    _selectedPaperIds = {};
    _isRotationGizmoActive = false;
    _panModeSelectedPaperId = null;
    _drawnCutLines.clear();
    _resetCutStroke();
    _paintedCells = {};
    _lastPaintCell = null;
    _resetStencilTransform();
    _stencilSelected = true;
  }

  void _resetStencilTransform() {
    _stencilPosition = _panOffset;
    _applyStencilDefaultSize();
    _stencilHandleIndex = null;
    _stencilResizeStart = null;
    _stencilDragging = false;
    _stopHandleFollow();
  }

  void _applyStencilDefaultSize() {
    switch (_stencilShape) {
      case StencilShape.rectangle:
        // 4 units wide × 2 units tall
        _stencilHalfW = 2 * _stencilUnit;
        _stencilHalfH = 1 * _stencilUnit;
      case StencilShape.circle:
        // 2×2 bounding box (diameter 2)
        _stencilHalfW = _stencilUnit;
        _stencilHalfH = _stencilUnit;
    }
  }

  Rect _stencilWorldRect() => Rect.fromLTRB(
        _stencilPosition.dx - _stencilHalfW,
        _stencilPosition.dy - _stencilHalfH,
        _stencilPosition.dx + _stencilHalfW,
        _stencilPosition.dy + _stencilHalfH,
      );

  Offset _stencilLocalToWorld(Offset local) =>
      Offset(_stencilPosition.dx + local.dx, _stencilPosition.dy + local.dy);

  List<Offset> _stencilLocalPolygon() {
    final hw = _stencilHalfW;
    final hh = _stencilHalfH;
    if (_stencilShape == StencilShape.circle) {
      const n = 32;
      return [
        for (var i = 0; i < n; i++)
          Offset(
            hw * math.cos(2 * math.pi * i / n),
            hh * math.sin(2 * math.pi * i / n),
          ),
      ];
    }
    return [
      Offset(-hw, -hh),
      Offset(hw, -hh),
      Offset(hw, hh),
      Offset(-hw, hh),
    ];
  }

  List<Offset> _stencilWorldPolygon() =>
      _stencilLocalPolygon().map(_stencilLocalToWorld).toList();

  /// 0=top, 1=right, 2=bottom, 3=left, 4=TL, 5=TR, 6=BR, 7=BL (Y-up).
  List<Offset> _stencilHandleWorldPositions() {
    final hw = _stencilHalfW, hh = _stencilHalfH;
    return [
      _stencilLocalToWorld(Offset(0, hh)),
      _stencilLocalToWorld(Offset(hw, 0)),
      _stencilLocalToWorld(Offset(0, -hh)),
      _stencilLocalToWorld(Offset(-hw, 0)),
      _stencilLocalToWorld(Offset(-hw, hh)),
      _stencilLocalToWorld(Offset(hw, hh)),
      _stencilLocalToWorld(Offset(hw, -hh)),
      _stencilLocalToWorld(Offset(-hw, -hh)),
    ];
  }

  int? _hitTestStencilHandle(Offset screenPos, Size viewportSize) {
    final handles = _stencilHandleWorldPositions();
    const hitRadius = 20.0;
    int? best;
    var bestDist = hitRadius;
    // Corners first so they win over nearby edge midpoints.
    for (final i in const [4, 5, 6, 7, 0, 1, 2, 3]) {
      final sp = _worldToScreen(
        Vector3(handles[i].dx, handles[i].dy, _paperZ),
        viewportSize,
      );
      final dist = (sp - screenPos).distance;
      if (dist <= bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  bool _hitTestStencilBody(Offset screenPos, Size viewportSize) {
    final worldPos = _screenToWorld(screenPos, viewportSize);
    final local = Offset(
      worldPos.x - _stencilPosition.dx,
      worldPos.y - _stencilPosition.dy,
    );
    if (_stencilShape == StencilShape.circle) {
      final nx = local.dx / math.max(_stencilHalfW, 1e-6);
      final ny = local.dy / math.max(_stencilHalfH, 1e-6);
      return nx * nx + ny * ny <= 1;
    }
    return local.dx.abs() <= _stencilHalfW && local.dy.abs() <= _stencilHalfH;
  }

  void _applyStencilRect(Rect r) {
    _stencilPosition = Offset((r.left + r.right) / 2, (r.top + r.bottom) / 2);
    _stencilHalfW = r.width / 2;
    _stencilHalfH = r.height / 2;
  }

  Rect _stencilTargetFromPointer(int handleIndex, Offset world) {
    final start = _stencilResizeStart ?? _stencilWorldRect();
    final raw = _resizeHandleBox(
      start: start,
      handleIndex: handleIndex,
      pointer: world,
      uniformCorners: _stencilShape == StencilShape.circle,
      minSize: _stencilUnit * 0.25,
    );
    return _snapHandleBox(
      raw,
      handleIndex,
      snapGridPoint: _snapPointToGrid,
    );
  }

  static const _kStencilBlueprintSnapScale = 2.6;
  static const _kStencilHoleScoreScale = 0.42;
  static const _kStencilAxisAlign = 0.18;

  Iterable<(Offset a, Offset b, bool isHole)> _blueprintSnapEdges() sync* {
    for (final (ring, isHole) in _snapWorldLoops) {
      for (var j = 0; j < ring.length; j++) {
        yield (ring[j], ring[(j + 1) % ring.length], isHole);
      }
    }
  }

  Iterable<(Offset p, bool isHole)> _blueprintSnapVertices() sync* {
    for (final (ring, isHole) in _snapWorldLoops) {
      for (final p in ring) {
        yield (p, isHole);
      }
    }
  }

  /// Snap an axis-aligned stencil edge to a nearby blueprint edge.
  /// Hole edges beat exterior edges of similar distance.
  ({double value, double score})? _snapStencilAxis({
    required double value,
    required bool isX,
    required double spanMin,
    required double spanMax,
    Iterable<(Offset a, Offset b, bool isHole)>? edges,
  }) {
    if (!_snapBlueprint) return null;
    final edgeList = edges ?? _blueprintSnapEdges();
    final radius = _snapWorldRadius * _kStencilBlueprintSnapScale;
    double bestScore = double.infinity;
    double? best;
    for (final (a, b, isHole) in edgeList) {
      final edx = (b.dx - a.dx).abs();
      final edy = (b.dy - a.dy).abs();
      final isVertical = edx <= math.max(edy * _kStencilAxisAlign, 1e-6);
      final isHorizontal = edy <= math.max(edx * _kStencilAxisAlign, 1e-6);
      if (isX && !isVertical) continue;
      if (!isX && !isHorizontal) continue;
      final edgeMin = isX ? math.min(a.dy, b.dy) : math.min(a.dx, b.dx);
      final edgeMax = isX ? math.max(a.dy, b.dy) : math.max(a.dx, b.dx);
      if (spanMax + radius < edgeMin || edgeMax + radius < spanMin) continue;
      final edgeVal = isX ? (a.dx + b.dx) / 2 : (a.dy + b.dy) / 2;
      final dist = (edgeVal - value).abs();
      if (dist > radius) continue;
      final score = isHole ? dist * _kStencilHoleScoreScale : dist;
      if (score < bestScore) {
        bestScore = score;
        best = edgeVal;
      }
    }
    if (best == null) return null;
    return (value: best, score: bestScore);
  }

  void _snapStencilAfterMove() {
    final r = _stencilWorldRect();
    double? dx;
    double? dy;
    var xScore = double.infinity;
    var yScore = double.infinity;

    void considerX(double from, double to, double score) {
      if (score < xScore) {
        xScore = score;
        dx = to - from;
      }
    }

    void considerY(double from, double to, double score) {
      if (score < yScore) {
        yScore = score;
        dy = to - from;
      }
    }

    for (final x in [r.left, r.right]) {
      final s = _snapStencilAxis(
        value: x,
        isX: true,
        spanMin: r.top,
        spanMax: r.bottom,
      );
      if (s != null) considerX(x, s.value, s.score);
    }
    for (final y in [r.top, r.bottom]) {
      final s = _snapStencilAxis(
        value: y,
        isX: false,
        spanMin: r.left,
        spanMax: r.right,
      );
      if (s != null) considerY(y, s.value, s.score);
    }

    if (_snapBlueprint) {
      final vertRadius = _snapWorldRadius * _kStencilBlueprintSnapScale;
      for (final corner in [
        Offset(r.left, r.bottom),
        Offset(r.right, r.bottom),
        Offset(r.right, r.top),
        Offset(r.left, r.top),
      ]) {
        for (final (p, isHole) in _blueprintSnapVertices()) {
          final dist = (p - corner).distance;
          if (dist > vertRadius) continue;
          final score = isHole ? dist * _kStencilHoleScoreScale : dist;
          considerX(corner.dx, p.dx, score);
          considerY(corner.dy, p.dy, score);
        }
      }
    }

    if (dx == null && dy == null && _snapGrid) {
      final snapped = _snapPointToGrid(_stencilPosition);
      dx = snapped.dx - _stencilPosition.dx;
      dy = snapped.dy - _stencilPosition.dy;
    } else if (_snapGrid) {
      if (dx == null) {
        final snapped = _snapPointToGrid(_stencilPosition);
        dx = snapped.dx - _stencilPosition.dx;
      }
      if (dy == null) {
        final snapped = _snapPointToGrid(_stencilPosition);
        dy = snapped.dy - _stencilPosition.dy;
      }
    }

    if (dx != null || dy != null) {
      _stencilPosition += Offset(dx ?? 0, dy ?? 0);
    }
  }


  void _punchStencil() {
    final holeWorld = _stencilWorldPolygon();
    if (holeWorld.length < 3) return;
    _pushUndo('Punch');
    setState(() {
      final toRemove = <int>[];
      final toAdd = <PlacedPaper>[];
      for (var i = 0; i < _placedPapers.length; i++) {
        final paper = _placedPapers[i];
        if (_isToolProtected(paper) || _isDiscardingPaper(paper.id)) continue;
        final punched = _punchPaperWithHole(paper, holeWorld);
        if (punched == null) continue;
        toRemove.add(i);
        toAdd.addAll(punched);
      }
      for (final idx in toRemove.reversed) {
        _placedPapers.removeAt(idx);
      }
      _placedPapers.addAll(toAdd);
      if (toRemove.isNotEmpty) {
        _selectedPaperIds = {};
      }
    });
    _scheduleCheck();
  }

  List<PlacedPaper>? _punchPaperWithHole(
    PlacedPaper paper,
    List<Offset> holeWorld,
  ) {
    final localHole = holeWorld
        .map((p) => _worldToPaperLocal(Vector3(p.dx, p.dy, 0), paper))
        .toList();
    final exterior = _paperLocalVertices(paper);
    final subject = Polygon2D(
      Ring2D(exterior),
      [for (final h in paper.localHoles) Ring2D(h)],
    );
    final punch = Polygon2D.simple(localHole);
    final boundsA = _aabb(exterior);
    final boundsB = _aabb(localHole);
    if (boundsB.maxX < boundsA.minX ||
        boundsB.minX > boundsA.maxX ||
        boundsB.maxY < boundsA.minY ||
        boundsB.minY > boundsA.maxY) {
      return null;
    }

    final diffs = polygonDifference(subject, punch);
    if (diffs.isEmpty) return const [];
    if (diffs.length == 1 &&
        diffs.first.holes.length == paper.localHoles.length &&
        diffs.first.exterior.points.length == exterior.length) {
      final stillInside = _pointInPolygon(
        _polygonCentroid(localHole),
        exterior,
      );
      if (!stillInside) return null;
    }

    final orders = _allocateSplitOrders(paper.stackOrder, diffs.length);
    return [
      for (var i = 0; i < diffs.length; i++)
        _paperFromLocalCompound(
          paper,
          diffs[i].exterior.points,
          [for (final h in diffs[i].holes) h.points],
          stackOrder: orders[i],
        ),
    ];
  }

  PlacedPaper _paperFromLocalCompound(
    PlacedPaper src,
    List<Offset> exterior,
    List<List<Offset>> holes, {
    double? stackOrder,
  }) {
    final ext = _ensureWinding(exterior, ccw: true);
    final centroid = _polygonCentroid(ext);
    final shifted = ext.map((v) => v - centroid).toList();
    final shiftedHoles = [
      for (final h in holes)
        _ensureWinding(h, ccw: false).map((v) => v - centroid).toList(),
    ];
    final rad = src.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return PlacedPaper(
      id: 'paper_${_nextPaperId++}',
      paperColor: src.paperColor,
      position: Vector3(
        src.position.x + centroid.dx * cosA - centroid.dy * sinA,
        src.position.y + centroid.dx * sinA + centroid.dy * cosA,
        src.position.z,
      ),
      stackOrder: stackOrder ?? _allocateStackMajor(),
      rotationDeg: src.rotationDeg,
      sizeLevel: src.sizeLevel,
      localVertices: shifted,
      localHoles: shiftedHoles,
      groupId: src.groupId,
      materialId: src.materialId,
    );
  }

  List<Offset> _ensureWinding(List<Offset> poly, {required bool ccw}) {
    final area = _signedAreaOf(poly);
    final isCcw = area > 0;
    if (isCcw == ccw) return List<Offset>.from(poly);
    return poly.reversed.toList();
  }

  // ---------------------------------------------------------------------------
  // Align-grid helpers
  // ---------------------------------------------------------------------------

  Offset _worldToGrid(Offset world) =>
      _worldToGridCoords(world, _gridOriginOffset, _gridRotation);

  Offset _gridToWorld(double gx, double gy) =>
      _gridCoordsToWorld(Offset(gx, gy), _gridOriginOffset, _gridRotation);

  Offset _gridCellCenter(int col, int row, [double? spacing]) {
    final s = spacing ?? _activeGridSpacing;
    return _gridToWorld((col + 0.5) * s, (row + 0.5) * s);
  }

  /// Snap a world point to the nearest grid intersection.
  Offset _snapPointToGrid(Offset world, [double? spacing]) {
    final s = spacing ?? _activeGridSpacing;
    final g = _worldToGrid(world);
    return _gridToWorld((g.dx / s).round() * s, (g.dy / s).round() * s);
  }

  void _applyAutoGridAlignment(List<List<Offset>> polygons) {
    final frame = _computeDominantGridFrame(polygons);
    if (frame == null) {
      _gridOriginOffset = Offset.zero;
      _gridRotation = math.pi / 2;
      return;
    }
    _gridOriginOffset = frame.anchor;
    _gridRotation = frame.yAngle;
  }

  void _clearAlignGridTransient() {
    _alignGridPreviewVertex = null;
    _alignGridSecondPreview = null;
    _alignGridHoveredPolyIndex = null;
    _alignGridPointerDown = null;
    _alignGridDidDrag = false;
  }

  ({Offset point, int? hitIdx}) _alignGridPick(Offset wp) {
    int? hitIdx;
    for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
      if (_pointInPolygon(wp, _blueprintWorldPolygons[i])) {
        hitIdx = i;
        break;
      }
    }
    final vertex = hitIdx != null
        ? _closestBlueprintVertex(wp, polyIndex: hitIdx)
        : _closestBlueprintVertex(wp, maxDist: _snapWorldRadius * 3);
    return (point: vertex ?? wp, hitIdx: hitIdx);
  }

  /// Snap the grid origin to [vertex] so paint/erase cells share that corner.
  void _applyAlignGridOrigin(Offset vertex, {int? hitIdx}) {
    _gridOriginOffset = vertex;
    _alignGridPreviewVertex = vertex;
    _alignGridSecondPreview = null;
    _alignGridHoveredPolyIndex = hitIdx;
  }

  /// Nearest blueprint vertex to [target], optionally constrained to one poly.
  Offset? _closestBlueprintVertex(
    Offset target, {
    int? polyIndex,
    double? maxDist,
  }) {
    final polys = polyIndex != null
        ? [_blueprintWorldPolygons[polyIndex]]
        : _blueprintWorldPolygons;
    if (polys.isEmpty) return null;
    double bestDistSq = double.infinity;
    Offset? best;
    for (final poly in polys) {
      if (poly.isEmpty) continue;
      for (final v in poly) {
        final d = (v - target).distanceSquared;
        if (d < bestDistSq) {
          bestDistSq = d;
          best = v;
        }
      }
    }
    if (best == null) return null;
    if (maxDist != null && bestDistSq > maxDist * maxDist) return null;
    return best;
  }

  // ---------------------------------------------------------------------------
  // Magnet-tool helpers
  // ---------------------------------------------------------------------------

  static double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return from + diff * t;
  }

  /// Angle (radians) of the longest edge in [poly].
  static double _longestEdgeAngle(List<Offset> poly) {
    double maxLenSq = 0;
    double angle = 0;
    for (var i = 0; i < poly.length; i++) {
      final j = (i + 1) % poly.length;
      final dx = poly[j].dx - poly[i].dx;
      final dy = poly[j].dy - poly[i].dy;
      final lenSq = dx * dx + dy * dy;
      if (lenSq > maxLenSq) {
        maxLenSq = lenSq;
        angle = math.atan2(dy, dx);
      }
    }
    return angle;
  }

  /// For each unfilled blueprint polygon within [_magnetDistance] of
  /// [worldCursor], compute the rotation that aligns the piece's longest edge
  /// to the slot's longest edge, then try that base angle + {0, 90, 180, 270}.
  ({int bpIndex, Offset targetPos, double targetRotDeg})? _findMagnetMatch(
    PlacedPaper paper,
    Offset worldCursor,
  ) {
    if (_blueprintWorldPolygons.isEmpty) return null;

    final localVerts = _paperLocalVertices(paper);
    if (localVerts.length < 3) return null;

    final localCentroid = _polyCentroid(localVerts);
    final centroidNorm = [
      for (final v in localVerts)
        Offset(v.dx - localCentroid.dx, v.dy - localCentroid.dy),
    ];
    final pieceArea = _polyArea(centroidNorm).abs();
    if (pieceArea < 1e-10) return null;

    final pieceEdgeAngle = _longestEdgeAngle(centroidNorm);
    final tolerance = 0.1 * _minorGridSpacing;
    final distLimit = _magnetDistance;
    final distLimitSq = distLimit * distLimit;

    double bestDist = double.infinity;
    ({int bpIndex, Offset targetPos, double targetRotDeg})? bestMatch;

    for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
      if (_filledBlueprintIndices.contains(i)) continue;
      final bpPoly = _blueprintWorldPolygons[i];
      if (bpPoly.length < 3) continue;

      final bpCentroid = _polyCentroid(bpPoly);

      final dx = bpCentroid.dx - worldCursor.dx;
      final dy = bpCentroid.dy - worldCursor.dy;
      final distSq = dx * dx + dy * dy;
      if (distSq > distLimitSq) continue;

      final bpArea = _polyArea(bpPoly).abs();
      final aAvg = (pieceArea + bpArea) / 2;
      if (aAvg < 1e-10) continue;
      if ((pieceArea - bpArea).abs() / aAvg > 0.15) continue;

      final bpEdgeAngle = _longestEdgeAngle(bpPoly);
      final baseDeg = (bpEdgeAngle - pieceEdgeAngle) * 180 / math.pi;

      for (final offset in [0.0, 90.0, 180.0, 270.0]) {
        final candDeg = baseDeg + offset;
        final rad = candDeg * math.pi / 180;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);

        final rotated = [
          for (final v in centroidNorm)
            Offset(
              bpCentroid.dx + v.dx * cosA - v.dy * sinA,
              bpCentroid.dy + v.dx * sinA + v.dy * cosA,
            ),
        ];

        if (_shapesMatch(rotated, bpPoly, tolerance)) {
          final dist = math.sqrt(distSq);
          if (dist < bestDist) {
            bestDist = dist;
            bestMatch = (
              bpIndex: i,
              targetPos: bpCentroid,
              targetRotDeg: candDeg,
            );
          }
          break;
        }
      }
    }

    return bestMatch;
  }

  void _onMagnetAnimTick() {
    if (_dragPaperId == null) return;
    final paper = _placedPapers.where((p) => p.id == _dragPaperId).firstOrNull;
    if (paper == null) return;
    final freePos = _magnetFreePosition;
    final targetPos = _magnetTargetPosition;
    final freeRot = _magnetFreeRotation;
    final targetRot = _magnetTargetRotation;
    if (freePos == null ||
        targetPos == null ||
        freeRot == null ||
        targetRot == null) {
      return;
    }

    final t = Curves.easeInOut.transform(_magnetAnimController.value);
    setState(() {
      paper.position.x = freePos.dx + (targetPos.dx - freePos.dx) * t;
      paper.position.y = freePos.dy + (targetPos.dy - freePos.dy) * t;
      paper.rotationDeg = _lerpAngle(freeRot, targetRot, t);
    });
  }

  void _clearMagnetState() {
    _magnetTargetBpIndex = null;
    _magnetTargetPosition = null;
    _magnetTargetRotation = null;
    _magnetFreePosition = null;
    _magnetFreeRotation = null;
    _magnetPrevBpIndex = null;
  }

  // ---------------------------------------------------------------------------
  // Paint-tool grid helpers
  // ---------------------------------------------------------------------------

  /// Convert a world-space point to a grid cell index (col, row).
  /// The grid is infinite so all positions are valid.
  (int, int)? _worldToGridCell(Offset worldPt) {
    final s = _activeGridSpacing;
    final g = _worldToGrid(worldPt);
    final col = (g.dx / s).floor();
    final row = (g.dy / s).floor();
    return (col, row);
  }

  /// Bresenham rasterisation between two grid cells so fast pointer moves
  /// don't leave gaps.
  List<(int, int)> _rasterizeLine((int, int) from, (int, int) to) {
    final cells = <(int, int)>[];
    var (x0, y0) = from;
    final (x1, y1) = to;
    final dx = (x1 - x0).abs();
    final dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      cells.add((x0, y0));
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
    return cells;
  }

  /// True only when an existing paper fully encloses the grid cell.  Test
  /// points are inset slightly so they never land exactly on a polygon edge,
  /// avoiding ray-casting ambiguity for grid-aligned boundaries.
  bool _isCellOccupiedByPaper(
    int col,
    int row, {
    bool includeOpsLocked = true,
  }) {
    final s = _activeGridSpacing;
    final inset = s * 0.01;
    final corners = [
      _gridToWorld(col * s + inset, row * s + inset),
      _gridToWorld((col + 1) * s - inset, row * s + inset),
      _gridToWorld((col + 1) * s - inset, (row + 1) * s - inset),
      _gridToWorld(col * s + inset, (row + 1) * s - inset),
    ];
    for (final paper in _placedPapers) {
      if (paper.locked || _isDiscardingPaper(paper.id)) continue;
      if (!includeOpsLocked && paper.opsLocked) continue;
      bool allInside = true;
      for (final c in corners) {
        final local = _worldToPaperLocal(Vector3(c.dx, c.dy, _paperZ), paper);
        if (!_isPointInLocalPaper(local, paper)) {
          allInside = false;
          break;
        }
      }
      if (allInside) return true;
    }
    return false;
  }

  /// True when any cardinal neighbour of (col, row) has its centre inside a
  /// paper polygon.  Uses a lenient centre-point test so even partial overlap
  /// of a neighbour counts as adjacent.  When [onlyPaperIds] is provided,
  /// only those papers are considered.
  bool _isCellAdjacentToPaper(int col, int row, {Set<String>? onlyPaperIds}) {
    final s = _activeGridSpacing;
    const neighbours = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    final papers = onlyPaperIds != null
        ? _placedPapers.where((p) => onlyPaperIds.contains(p.id))
        : _placedPapers;
    for (final (dc, dr) in neighbours) {
      final nc = col + dc;
      final nr = row + dr;
      final center = _gridCellCenter(nc, nr, s);
      final pt = Vector3(center.dx, center.dy, _paperZ);
      for (final paper in papers) {
        if (_isToolProtected(paper)) continue;
        final local = _worldToPaperLocal(pt, paper);
        if (_isPointInLocalPaper(local, paper)) return true;
      }
    }
    return false;
  }

  /// Rasterise a paper's world polygon into the set of minor-grid cells whose
  /// centres fall inside it.
  Set<(int, int)> _rasterizePaperToCells(PlacedPaper paper) {
    final worldCorners = _paperWorldCorners(paper);
    if (worldCorners.isEmpty) return const {};

    final s = _activeGridSpacing;

    double minGx = double.infinity, maxGx = -double.infinity;
    double minGy = double.infinity, maxGy = -double.infinity;
    for (final c in worldCorners) {
      final g = _worldToGrid(Offset(c.x, c.y));
      if (g.dx < minGx) minGx = g.dx;
      if (g.dx > maxGx) maxGx = g.dx;
      if (g.dy < minGy) minGy = g.dy;
      if (g.dy > maxGy) maxGy = g.dy;
    }

    final colMin = (minGx / s).floor();
    final colMax = (maxGx / s).floor();
    final rowMin = (minGy / s).floor();
    final rowMax = (maxGy / s).floor();

    final result = <(int, int)>{};
    for (var c = colMin; c <= colMax; c++) {
      for (var r = rowMin; r <= rowMax; r++) {
        final center = _gridCellCenter(c, r, s);
        final world = Vector3(center.dx, center.dy, _paperZ);
        final local = _worldToPaperLocal(world, paper);
        if (_isPointInLocalPaper(local, paper)) {
          result.add((c, r));
        }
      }
    }
    return result;
  }

  double _paperHalfSizeForLevel(int level) =>
      level * _majorGridSpacing * _kPaperHalfExtentPerLevel;

  List<Offset> _paperLocalVertices(PlacedPaper paper) {
    if (paper.localVertices != null) return paper.localVertices!;
    final hs = _paperHalfSizeForLevel(paper.sizeLevel);
    return [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];
  }

  List<Vector3> _paperWorldCorners(PlacedPaper paper) {
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return [
      for (final o in _paperLocalVertices(paper))
        Vector3(
          paper.position.x + o.dx * cosA - o.dy * sinA,
          paper.position.y + o.dx * sinA + o.dy * cosA,
          paper.position.z,
        ),
    ];
  }

  List<Offset> _paperWorldPolygon2D(PlacedPaper paper) {
    return _paperWorldCorners(paper).map((v) => Offset(v.x, v.y)).toList();
  }

  List<List<Offset>> _paperWorldHoles2D(PlacedPaper paper) {
    if (paper.localHoles.isEmpty) return const [];
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return paper.localHoles.map((hole) {
      return hole
          .map(
            (o) => Offset(
              paper.position.x + o.dx * cosA - o.dy * sinA,
              paper.position.y + o.dx * sinA + o.dy * cosA,
            ),
          )
          .toList();
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Coordinate conversion
  // ---------------------------------------------------------------------------

  Vector3 _screenToWorld(Offset screenPos, Size viewportSize) {
    return craftingScreenToWorldOnPlane(
      screenPos,
      viewportSize,
      _orthoScale,
      _paperZ,
      panOffset: _panOffset,
      viewRotation: _viewRotation,
    );
  }

  Offset _worldToScreen(Vector3 worldPos, Size viewportSize) {
    return craftingWorldToScreen(
      worldPos,
      viewportSize,
      _orthoScale,
      panOffset: _panOffset,
      viewRotation: _viewRotation,
    );
  }

  /// World units per screen pixel for the current ortho camera.
  ///
  /// Ortho half-height is [_orthoScale]; the frustum half-width is
  /// `orthoScale * aspect`, so both axes share `2 * orthoScale / height`.
  /// Using the shorter side (old behavior) overshoots pan/drag on portrait.
  double _worldUnitsPerPixel(Size viewportSize) {
    final h = viewportSize.height;
    if (h < 1) return 0;
    return 2 * _orthoScale / h;
  }

  /// Maps a screen-space drag delta into world delta (y-up), honoring view roll.
  Offset _screenDeltaToWorldDelta(Offset screenDelta, double worldPerPixel) {
    final dx = screenDelta.dx * worldPerPixel;
    final dy = screenDelta.dy * worldPerPixel;
    final c = math.cos(_viewRotation);
    final s = math.sin(_viewRotation);
    // Finger right → +viewX; finger down → -viewY (world y-up).
    return Offset(dx * c + dy * s, dx * s - dy * c);
  }

  /// Camera pan change for a screen drag (content follows the finger).
  Offset _panDeltaFromScreen(Offset screenDelta, double worldPerPixel) {
    final dx = screenDelta.dx * worldPerPixel;
    final dy = screenDelta.dy * worldPerPixel;
    final c = math.cos(_viewRotation);
    final s = math.sin(_viewRotation);
    // Finger right → camera -viewX; finger down → camera +viewY.
    return Offset(-dx * c - dy * s, -dx * s + dy * c);
  }

  // ---------------------------------------------------------------------------
  // Paper stack order (draw / hit front-to-back)
  // ---------------------------------------------------------------------------

  double _allocateStackMajor() => (_nextStackMajor++).toDouble();

  void _syncNextStackMajor() {
    var maxMajor = 0;
    for (final paper in _placedPapers) {
      final major = paper.stackOrder.floor();
      if (major > maxMajor) maxMajor = major;
    }
    _nextStackMajor = maxMajor + 1;
  }

  void _ensureStackOrders() {
    for (var i = 0; i < _placedPapers.length; i++) {
      if (_placedPapers[i].stackOrder <= 0) {
        _placedPapers[i].stackOrder = (i + 1).toDouble();
      }
    }
    _syncNextStackMajor();
  }

  String _formatStackOrder(double z) {
    if ((z - z.roundToDouble()).abs() < 1e-12) return z.round().toString();
    var s = z.toStringAsFixed(12);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  double _childStackOrderAt(double parent, int childIndex) {
    final prefix = _formatStackOrder(parent);
    final key = prefix.contains('.') ? '$prefix$childIndex' : '$prefix.$childIndex';
    return double.parse(key);
  }

  int _nextChildIndex(double parent, {Iterable<double> extra = const []}) {
    final prefix = _formatStackOrder(parent);
    final keys = [
      ..._placedPapers.map((p) => _formatStackOrder(p.stackOrder)),
      ...extra.map(_formatStackOrder),
    ];
    var maxDigit = 0;
    for (final key in keys) {
      if (prefix.contains('.')) {
        if (key.length == prefix.length + 1 && key.startsWith(prefix)) {
          final d = int.tryParse(key[key.length - 1]);
          if (d != null && d > maxDigit) maxDigit = d;
        }
      } else {
        final childPrefix = '$prefix.';
        if (key.length == childPrefix.length + 1 && key.startsWith(childPrefix)) {
          final d = int.tryParse(key[key.length - 1]);
          if (d != null && d > maxDigit) maxDigit = d;
        }
      }
    }
    return maxDigit + 1;
  }

  List<double> _allocateSplitOrders(double parent, int count) {
    if (count <= 0) return const [];
    if (count == 1) return [parent];
    final orders = <double>[parent];
    var idx = _nextChildIndex(parent);
    for (var i = 1; i < count; i++) {
      if (idx > 9) {
        var candidate = parent + 1e-6 * i;
        while (orders.any((z) => (z - candidate).abs() < 1e-12) ||
            _placedPapers.any((p) => (p.stackOrder - candidate).abs() < 1e-12)) {
          candidate += 1e-6;
        }
        orders.add(candidate);
      } else {
        orders.add(_childStackOrderAt(parent, idx++));
      }
    }
    return orders;
  }

  // ---------------------------------------------------------------------------
  // Paper hit testing
  // ---------------------------------------------------------------------------

  String? _hitTestPaper(Offset screenPos, Size viewportSize) {
    final worldPos = _screenToWorld(screenPos, viewportSize);
    final hits = <PlacedPaper>[];
    for (final paper in _placedPapers) {
      if (paper.locked || _isDiscardingPaper(paper.id)) continue;
      final localPt = _worldToPaperLocal(worldPos, paper);
      if (_isPointInLocalPaper(localPt, paper)) hits.add(paper);
    }
    if (hits.isEmpty) return null;
    hits.sort((a, b) => b.stackOrder.compareTo(a.stackOrder));

    final sourceIds = _copyMemorySourceIds;
    final resultIds = _copyMemoryResultIds;
    if (sourceIds != null && resultIds != null && resultIds.isNotEmpty) {
      final onCopy = hits.any((p) => resultIds.contains(p.id));
      final onSource = hits.any((p) => sourceIds.contains(p.id));
      if (onCopy || onSource) {
        if (onCopy) {
          return hits.firstWhere((p) => resultIds.contains(p.id)).id;
        }
        PlacedPaper? topCopy;
        for (final paper in _placedPapers) {
          if (!resultIds.contains(paper.id)) continue;
          if (topCopy == null || paper.stackOrder > topCopy.stackOrder) {
            topCopy = paper;
          }
        }
        if (topCopy != null) return topCopy.id;
      }
    }
    return hits.first.id;
  }

  /// Remove every paper and related selection / lock-fade state.
  void _wipeCanvasPapers() {
    _stopExtraPaperDiscard();
    _placedPapers.clear();
    _nextStackMajor = 1;
    _selectedPaperIds = {};
    _clearCopyMemory();
    _panModeSelectedPaperId = null;
    _stretchPaperId = null;
    _clearStretchBox();
    _stopHandleFollow();
    _isRotationGizmoActive = false;
    _lockFadingPaperIds = {};
    _lockAnimatingPaperIds = {};
    _lockAnimProgress = 0;
    _lockFadeT = 0;
    _lockFadeController.stop();
    _filledBlueprintIndices = {};
    _blueprintLockedArea = 0;
  }

  /// Drop locked papers from the current selection (and pan-mode focus).
  void _deselectLockedPapers() {
    _selectedPaperIds.removeWhere((id) {
      final paper = _placedPapers.where((p) => p.id == id).firstOrNull;
      return paper == null || paper.locked;
    });
    if (_panModeSelectedPaperId != null) {
      final paper = _placedPapers
          .where((p) => p.id == _panModeSelectedPaperId)
          .firstOrNull;
      if (paper == null || paper.locked) {
        _panModeSelectedPaperId = null;
      }
    }
    _syncCopyMemoryWithSelection();
    if (_stretchPaperId != null) {
      final paper =
          _placedPapers.where((p) => p.id == _stretchPaperId).firstOrNull;
      if (paper == null || paper.locked) {
        _stretchPaperId = null;
        _clearStretchBox();
        _stopHandleFollow();
      }
    }
  }

  Offset _worldToPaperLocal(Vector3 worldPos, PlacedPaper paper) {
    final dx = worldPos.x - paper.position.x;
    final dy = worldPos.y - paper.position.y;
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    return Offset(dx * cosA + dy * sinA, -dx * sinA + dy * cosA);
  }

  bool _isPointInLocalPaper(Offset localPt, PlacedPaper paper) {
    bool inExterior;
    if (paper.localVertices != null) {
      inExterior = _pointInPolygon(localPt, paper.localVertices!);
    } else {
      final hs = _paperHalfSizeForLevel(paper.sizeLevel);
      inExterior = localPt.dx.abs() <= hs && localPt.dy.abs() <= hs;
    }
    if (!inExterior) return false;
    for (final hole in paper.localHoles) {
      if (_pointInPolygon(localPt, hole)) return false;
    }
    return true;
  }

  static bool _pointInPolygon(Offset p, List<Offset> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx < (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  // ---------------------------------------------------------------------------
  // Undo / redo helpers
  // ---------------------------------------------------------------------------

  void _pushUndo(String label, {bool? noOp}) {
    final isNoOp = noOp ?? _noOpUndoLabels.contains(label);
    if (!isNoOp && !_toolsBlocked) fmHapticSmallClick();
    _history.pushSnapshot(
      CraftingSnapshot.capture(
        papers: _placedPapers,
        nextPaperId: _nextPaperId,
        inventory: _inventory,
        selectedPaperIds: _selectedPaperIds,
        label: label,
        noOp: isNoOp,
      ),
    );
  }

  /// Adds [cell] to the paint preview if free; fires a small click when new.
  bool _tryPaintCell((int, int) cell) {
    if (_toolsBlocked) return false;
    if (_paintedCells.contains(cell) ||
        _isCellOccupiedByPaper(cell.$1, cell.$2)) {
      return false;
    }
    _paintedCells.add(cell);
    fmHapticSmallClick();
    return true;
  }

  /// Adds [cell] to the erase preview if occupied; fires a small click when new.
  bool _tryEraseCell((int, int) cell) {
    if (_toolsBlocked) return false;
    if (_erasedCells.contains(cell) ||
        !_isCellOccupiedByPaper(cell.$1, cell.$2, includeOpsLocked: false)) {
      return false;
    }
    _erasedCells.add(cell);
    fmHapticSmallClick();
    return true;
  }

  CraftingSnapshot _currentSnapshot(String label) {
    return CraftingSnapshot.capture(
      papers: _placedPapers,
      nextPaperId: _nextPaperId,
      inventory: _inventory,
      selectedPaperIds: _selectedPaperIds,
      label: label,
    );
  }

  void _applySnapshot(CraftingSnapshot snap) {
    setState(() {
      _placedPapers.clear();
      _placedPapers.addAll(snap.papers.map((s) => s.toPaper()));
      _nextPaperId = snap.nextPaperId;
      _ensureStackOrders();
      _inventory.clear();
      _inventory.addAll(snap.inventory);
      _selectedPaperIds = {
        for (final id in snap.selectedPaperIds)
          if (_placedPapers.any((p) => p.id == id && !p.locked)) id,
      };
      _clearCopyMemory();
      _isRotationGizmoActive = false;
    });
    _scheduleCheck();
    _maybeCompleteFill();
  }

  void _undo() {
    if (!_historyRewindAllowed) return;
    final snap = _history.undo(_currentSnapshot('current'));
    if (snap != null) _applySnapshot(snap);
  }

  void _redo() {
    if (!_historyRewindAllowed) return;
    final snap = _history.redo(_currentSnapshot('current'));
    if (snap != null) _applySnapshot(snap);
  }

  // ---------------------------------------------------------------------------
  // Inventory operations
  // ---------------------------------------------------------------------------

  void _placePaperFromInventory(PaperColor color, Offset globalPos) {
    final canvasBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null) return;

    String? materialId;
    if (_useStructureInventory) {
      materialId = _materialIdForPaperColor(color);
      if (materialId == null) return;
      final needed = CraftingMaterial.pixelsPerSheet;
      if (_structureInventory!.get(materialId) < needed) return;
      _structureInventory!.remove(materialId, needed);
    } else {
      final count = _inventory[color] ?? 0;
      if (count <= 0) return;
      _inventory[color] = count - 1;
    }

    const halfSlot = 24.0;
    final pointerCenter = globalPos + const Offset(halfSlot, halfSlot);
    final localPos = canvasBox.globalToLocal(pointerCenter);
    final worldPos = _screenToWorld(localPos, canvasBox.size);

    _pushUndo('Place paper');

    final paper = PlacedPaper(
      id: 'paper_${_nextPaperId++}',
      paperColor: color,
      position: worldPos,
      stackOrder: _allocateStackMajor(),
      materialId: materialId,
    );
    setState(() {
      _placedPapers.add(paper);
      _selectedPaperIds = {paper.id};
      _isRotationGizmoActive = false;
      _craftingMode = CraftingMode.select;
    });
    _scheduleCheck();
  }

  /// Maps a legacy PaperColor to a material ID. When structure inventory is
  /// in use, the slots are populated by actual material IDs; this resolves the
  /// first matching material for the given color.
  String? _materialIdForPaperColor(PaperColor color) {
    if (_structureInventory == null) return null;
    final contents = _structureInventory!.contents;
    if (contents.isEmpty) return null;
    return contents.keys.first;
  }

  /// Place a material-based paper from the structure inventory onto the canvas.
  void _placeMaterialPaper(String materialId, Offset globalPos) {
    final canvasBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null) return;

    final needed = CraftingMaterial.pixelsPerSheet;
    if (_structureInventory!.get(materialId) < needed) return;
    _structureInventory!.remove(materialId, needed);

    const halfSlot = 24.0;
    final pointerCenter = globalPos + const Offset(halfSlot, halfSlot);
    final localPos = canvasBox.globalToLocal(pointerCenter);
    final worldPos = _screenToWorld(localPos, canvasBox.size);

    _pushUndo('Place paper');

    final paper = PlacedPaper(
      id: 'paper_${_nextPaperId++}',
      paperColor: PaperColor.values.first,
      position: worldPos,
      stackOrder: _allocateStackMajor(),
      materialId: materialId,
    );
    setState(() {
      _placedPapers.add(paper);
      _selectedPaperIds = {paper.id};
      _isRotationGizmoActive = false;
      _craftingMode = CraftingMode.select;
    });
    _scheduleCheck();
  }

  /// Returns the display color for a paper, preferring the materialId-derived
  /// color from the registry when available.
  Color displayColorForPaper(PlacedPaper paper) {
    if (paper.materialId != null) {
      return _materialRegistry.colorFor(paper.materialId!);
    }
    return paper.paperColor.color;
  }

  void _returnPaperToInventory(String paperId) {
    final idx = _placedPapers.indexWhere((p) => p.id == paperId);
    if (idx < 0) return;
    _pushUndo('Return paper');
    final paper = _placedPapers[idx];
    setState(() {
      _placedPapers.removeAt(idx);
      if (_useStructureInventory && paper.materialId != null) {
        final recouped = _computeRecoupedUnits(paper);
        if (recouped > 0) {
          _structureInventory!.add(paper.materialId!, recouped);
        }
      } else if (paper.localVertices == null) {
        _inventory[paper.paperColor] = (_inventory[paper.paperColor] ?? 0) + 1;
      }
      _selectedPaperIds.remove(paperId);
      _syncCopyMemoryWithSelection();
      if (_selectedPaperIds.isEmpty) {
        _isRotationGizmoActive = false;
      }
    });
    _scheduleCheck();
  }

  /// Computes how many material units to return when discarding a paper.
  /// Uses floor(area / cellArea) so oblique cuts never generate material.
  int _computeRecoupedUnits(PlacedPaper paper) {
    if (paper.localVertices == null) {
      return CraftingMaterial.pixelsPerSheet;
    }
    final verts = paper.localVertices!;
    if (verts.length < 3) return 0;
    final cellSize = _minorGridSpacing;
    final cellArea = cellSize * cellSize;
    if (cellArea <= 0) return 0;

    double totalArea = polygonSignedArea(verts).abs();
    for (final hole in paper.localHoles) {
      if (hole.length >= 3) {
        totalArea -= polygonSignedArea(hole).abs();
      }
    }
    return (totalArea / cellArea).floor();
  }

  // ---------------------------------------------------------------------------
  // Pointer interaction
  // ---------------------------------------------------------------------------

  void _handlePointerDown(Offset localPos, Size viewportSize) {
    if (_completionPhase != CompletionPhase.none) return;
    if (_craftingMode == CraftingMode.cutting) return;
    if (_toolsBlocked) return;

    if (_isRotationGizmoActive) {
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId == null || !_selectedPaperIds.contains(hitId)) {
        _pushUndo('Select');
        setState(() {
          _isRotationGizmoActive = false;
          _selectedPaperIds = {};
        });
        _scheduleCheck();
        return;
      }
    }

    if (_stretchPaperId != null) {
      final paper = _placedPapers
          .where((p) => p.id == _stretchPaperId)
          .firstOrNull;
      if (paper != null) {
        final handleIdx = _hitTestStretchHandle(
          localPos,
          viewportSize,
          paper,
        );
        if (handleIdx != null) {
          if (_stretchStartLocal != null && _stretchDisplayLocal != null) {
            _bakeStretch();
          }
          final live = _placedPapers
                  .where((p) => p.id == _stretchPaperId)
                  .firstOrNull ??
              paper;
          _pushUndo('Transform');
          final bounds = _paperLocalBounds(live);
          setState(() {
            _stretchHandleIndex = handleIdx;
            _stretchStartLocal = bounds;
            _stretchDisplayLocal = bounds;
          });
          _beginHandleFollow(bounds, (r) => _stretchDisplayLocal = r);
          return;
        }
      }
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId == _stretchPaperId) return;
      setState(() => _endTransform(deselect: true));
      if (hitId == null) return;
    }

    if (_craftingMode == CraftingMode.pan) {
      if (_panModeSelectedPaperId != null) {
        final hitId = _hitTestPaper(localPos, viewportSize);
        if (hitId == _panModeSelectedPaperId) {
          _panModeDragLastScreen = localPos;
          _panModeDragging = false;
          return;
        }
      }
      _panDragLastScreen = localPos;
      return;
    }

    if (_craftingMode == CraftingMode.drawLine) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapCutPoint(Offset(worldPos.x, worldPos.y));
      setState(() {
        _lineDrawStart = snapped.point;
        _lineDrawPreview = snapped.point;
        _cutStartVertexRefs = snapped.refs;
        _cutSnapRay = snapped.ray;
        _cutHighlightEdges = [];
        _cutEdgeGlowController.value = 0;
      });
      return;
    }

    if (_craftingMode == CraftingMode.mirror) {
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId != null) {
        _pushUndo('Select');
        setState(() {
          if (_selectedPaperIds.contains(hitId)) {
            _selectedPaperIds = Set.from(_selectedPaperIds)..remove(hitId);
          } else {
            _selectedPaperIds = Set.from(_selectedPaperIds)..add(hitId);
          }
          _isRotationGizmoActive = false;
        });
        return;
      }
      if (_selectedPaperIds.isEmpty) return;
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() {
        _mirrorLineStart = snapped;
        _mirrorLinePreview = snapped;
      });
      return;
    }

    if (_craftingMode == CraftingMode.rotationCopy) {
      if (_rotCopyGizmoActive) return;
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId != null) {
        _pushUndo('Select');
        setState(() {
          if (_selectedPaperIds.contains(hitId)) {
            _selectedPaperIds = Set.from(_selectedPaperIds)..remove(hitId);
          } else {
            _selectedPaperIds = Set.from(_selectedPaperIds)..add(hitId);
          }
          _isRotationGizmoActive = false;
        });
        return;
      }
      if (_selectedPaperIds.isEmpty) return;
      if (_rotCopyCenterWorld == null) {
        final worldPos = _screenToWorld(localPos, viewportSize);
        final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
        setState(() {
          _rotCopyCenterWorld = snapped;
          _rotCopyGizmoActive = true;
          _rotCopyAngleDeg = 0;
        });
      }
      return;
    }

    if (_craftingMode == CraftingMode.paint) {
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId != null) {
        if (_selectedPaperIds.contains(hitId)) {
          final paper = _placedPapers.firstWhere((p) => p.id == hitId);
          if (!paper.locked) {
            _pushUndo('Move paper');
            _paintDragPaperId = hitId;
            _paintDragLastScreen = localPos;
            return;
          }
        }
        final paper = _placedPapers.firstWhere((p) => p.id == hitId);
        setState(() {
          _selectedPaperIds = {hitId};
          _isRotationGizmoActive = false;
        });
        if (!paper.locked) {
          _pushUndo('Move paper');
          _paintDragPaperId = hitId;
          _paintDragLastScreen = localPos;
        }
        return;
      }

      final worldPos = _screenToWorld(localPos, viewportSize);
      final cell = _worldToGridCell(Offset(worldPos.x, worldPos.y));
      _paintHadSelection = _selectedPaperIds.isNotEmpty;
      _paintSelectionIds = Set.of(_selectedPaperIds);
      _paintDeferredCell = null;
      setState(() {
        _paintedCells = {};
        _paintDragPaperId = null;
        _paintDragLastScreen = null;
        _selectedPaperIds = {};
        _isRotationGizmoActive = false;
        if (cell != null && !_isCellOccupiedByPaper(cell.$1, cell.$2)) {
          if (_paintHadSelection) {
            _paintDeferredCell = cell;
          } else {
            _tryPaintCell(cell);
          }
        }
        _lastPaintCell = cell;
      });
      return;
    }

    if (_craftingMode == CraftingMode.erase) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final cell = _worldToGridCell(Offset(worldPos.x, worldPos.y));
      setState(() {
        _erasedCells = {};
        _selectedPaperIds = {};
        _isRotationGizmoActive = false;
        if (cell != null && _isCellOccupiedByPaper(cell.$1, cell.$2)) {
          _tryEraseCell(cell);
        }
        _lastEraseCell = cell;
      });
      return;
    }

    if (_craftingMode == CraftingMode.alignGrid) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final pick = _alignGridPick(Offset(worldPos.x, worldPos.y));
      setState(() {
        _alignGridPointerDown = localPos;
        _alignGridDidDrag = false;
        _applyAlignGridOrigin(pick.point, hitIdx: pick.hitIdx);
      });
      _scheduleGridLodSync();
      return;
    }

    if (_craftingMode == CraftingMode.stencil) {
      if (_stencilSelected) {
        final handleIdx = _hitTestStencilHandle(localPos, viewportSize);
        if (handleIdx != null) {
          final start = _stencilWorldRect();
          setState(() {
            _stencilHandleIndex = handleIdx;
            _stencilResizeStart = start;
          });
          _beginHandleFollow(start, _applyStencilRect);
          return;
        }
      }
      if (_hitTestStencilBody(localPos, viewportSize)) {
        final worldPos = _screenToWorld(localPos, viewportSize);
        setState(() {
          _stencilSelected = true;
          _stencilDragging = false;
          _stencilDragStartWorld = Offset(worldPos.x, worldPos.y);
          _stencilDragStartPos = _stencilPosition;
        });
        return;
      }
      setState(() => _stencilSelected = false);
      return;
    }

    final paperId = _hitTestPaper(localPos, viewportSize);
    _pointerDownPos = localPos;
    _pointerDownPaperId = paperId;
    _isDragging = false;
    _dragPaperId = null;
    _isMarquee = false;
  }

  void _handlePointerMove(Offset localPos, Size viewportSize) {
    if (_completionPhase != CompletionPhase.none) return;
    if (_craftingMode == CraftingMode.cutting) return;
    // Safety: pan tool's camera drag runs before the shared multitouch early-out
    // further down; never fight the pinch handler.
    if (_toolsBlocked) return;

    if (_craftingMode == CraftingMode.stencil) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final wp = Offset(worldPos.x, worldPos.y);
      if (_stencilHandleIndex != null) {
        _setHandleFollowTarget(
          _stencilTargetFromPointer(_stencilHandleIndex!, wp),
        );
        return;
      }
      if (_stencilDragStartWorld != null && _stencilDragStartPos != null) {
        final delta = wp - _stencilDragStartWorld!;
        if (delta.distance > 1e-4) {
          setState(() {
            _stencilDragging = true;
            _stencilPosition = _stencilDragStartPos! + delta;
            _snapStencilAfterMove();
          });
        }
        return;
      }
    }

    if (_stretchHandleIndex != null && _stretchPaperId != null) {
      final paper = _placedPapers
          .where((p) => p.id == _stretchPaperId)
          .firstOrNull;
      if (paper == null) return;
      final worldPos = _screenToWorld(localPos, viewportSize);
      _setHandleFollowTarget(
        _stretchTargetFromPointer(
          paper,
          _stretchHandleIndex!,
          Offset(worldPos.x, worldPos.y),
        ),
      );
      return;
    }

    if (_craftingMode == CraftingMode.pan) {
      if (_panModeDragLastScreen != null) {
        final distance = (localPos - _panModeDragLastScreen!).distance;
        if (!_panModeDragging && distance < _dragThreshold) return;
        if (!_panModeDragging) _pushUndo('Move paper');
        _panModeDragging = true;
        final paper = _placedPapers
            .where((p) => p.id == _panModeSelectedPaperId)
            .firstOrNull;
        if (paper != null && !paper.locked) {
          final worldPerPixel = _worldUnitsPerPixel(viewportSize);
          final delta = localPos - _panModeDragLastScreen!;
          _panModeDragLastScreen = localPos;
          final worldDelta = _screenDeltaToWorldDelta(delta, worldPerPixel);
          setState(() {
            paper.position.x += worldDelta.dx;
            paper.position.y += worldDelta.dy;
          });
        }
        return;
      }
      if (_panDragLastScreen != null) {
        final delta = localPos - _panDragLastScreen!;
        final worldPerPixel = _worldUnitsPerPixel(viewportSize);
        final panDelta = _panDeltaFromScreen(delta, worldPerPixel);
        setState(() {
          _panOffset = Offset(
            _panOffset.dx + panDelta.dx,
            _panOffset.dy + panDelta.dy,
          );
          _clampPanOffset();
        });
        _panDragLastScreen = localPos;
        return;
      }
      return;
    }

    if (_craftingMode == CraftingMode.drawLine && _lineDrawStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapCutPoint(
        Offset(worldPos.x, worldPos.y),
        fromVertexRefs: _cutStartVertexRefs,
      );
      setState(() {
        _lineDrawPreview = snapped.point;
        _cutSnapRay = snapped.ray;
        _updateCutHighlights(_lineDrawStart!, snapped.point);
      });
      return;
    }

    if (_craftingMode == CraftingMode.mirror && _mirrorLineStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() => _mirrorLinePreview = snapped);
      return;
    }

    if (_craftingMode == CraftingMode.paint) {
      if (_paintDragPaperId != null && _paintDragLastScreen != null) {
        final paper = _placedPapers
            .where((p) => p.id == _paintDragPaperId)
            .firstOrNull;
        if (paper != null && !paper.locked) {
          final worldPerPixel = _worldUnitsPerPixel(viewportSize);
          final delta = localPos - _paintDragLastScreen!;
          _paintDragLastScreen = localPos;
          final worldDelta = _screenDeltaToWorldDelta(delta, worldPerPixel);
          setState(() {
            paper.position.x += worldDelta.dx;
            paper.position.y += worldDelta.dy;
          });
        }
        return;
      }

      final worldPos = _screenToWorld(localPos, viewportSize);
      final cell = _worldToGridCell(Offset(worldPos.x, worldPos.y));
      if (cell != null) {
        if (_paintDeferredCell != null) {
          if (cell == _paintDeferredCell) return;
          _tryPaintCell(_paintDeferredCell!);
          _paintDeferredCell = null;
          _paintHadSelection = false;
        }
        setState(() {
          List<(int, int)> toAdd;
          if (_lastPaintCell != null && _lastPaintCell != cell) {
            toAdd = _rasterizeLine(_lastPaintCell!, cell);
          } else {
            toAdd = [cell];
          }
          for (final c in toAdd) {
            _tryPaintCell(c);
          }
          _lastPaintCell = cell;
        });
      }
      return;
    }

    if (_craftingMode == CraftingMode.erase) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final cell = _worldToGridCell(Offset(worldPos.x, worldPos.y));
      if (cell != null) {
        setState(() {
          List<(int, int)> toAdd;
          if (_lastEraseCell != null && _lastEraseCell != cell) {
            toAdd = _rasterizeLine(_lastEraseCell!, cell);
          } else {
            toAdd = [cell];
          }
          for (final c in toAdd) {
            _tryEraseCell(c);
          }
          _lastEraseCell = cell;
        });
      }
      return;
    }

    if (_craftingMode == CraftingMode.alignGrid &&
        _alignGridPointerDown != null) {
      if (!_alignGridDidDrag &&
          (localPos - _alignGridPointerDown!).distance < _dragThreshold) {
        return;
      }
      final worldPos = _screenToWorld(localPos, viewportSize);
      final pick = _alignGridPick(Offset(worldPos.x, worldPos.y));
      setState(() {
        _alignGridDidDrag = true;
        _alignGridHoveredPolyIndex = pick.hitIdx;
        _alignGridSecondPreview = pick.point;
        final d = pick.point - _gridOriginOffset;
        if (d.distanceSquared > 1e-12) {
          _gridRotation = math.atan2(d.dy, d.dx);
        }
      });
      _scheduleGridLodSync();
      return;
    }

    if (_toolsBlocked || _pointerDownPos == null) return;

    if (!_isDragging && !_isMarquee) {
      final distance = (localPos - _pointerDownPos!).distance;
      if (distance < _dragThreshold) return;

      if (_pointerDownPaperId != null) {
        final downPaper = _placedPapers
            .where((p) => p.id == _pointerDownPaperId)
            .firstOrNull;
        if (downPaper != null && downPaper.locked) {
          return;
        }
        _isDragging = true;
        _dragPaperId = _pointerDownPaperId;
        _pushUndo('Move paper');
        if (!_selectedPaperIds.contains(_dragPaperId)) {
          setState(() {
            _selectedPaperIds = {_dragPaperId!};
            _isRotationGizmoActive = false;
          });
        }
      } else {
        _isMarquee = true;
        _marqueeStartScreen = _pointerDownPos;
        _marqueeCurrentScreen = localPos;
      }
    }

    if (_isMarquee) {
      setState(() {
        _marqueeCurrentScreen = localPos;
      });
      return;
    }

    if (_isDragging && _dragPaperId != null) {
      final paper = _placedPapers
          .where((p) => p.id == _dragPaperId)
          .firstOrNull;
      if (paper == null) return;

      final worldPerPixel = _worldUnitsPerPixel(viewportSize);
      final delta = localPos - _pointerDownPos!;
      _pointerDownPos = localPos;
      final worldDelta = _screenDeltaToWorldDelta(delta, worldPerPixel);
      final dx = worldDelta.dx;
      final dy = worldDelta.dy;

      if (_craftingMode == CraftingMode.magnet &&
          paper.groupId == null &&
          !(_selectedPaperIds.contains(paper.id) &&
              _selectedPaperIds.length > 1)) {
        _magnetFreePosition ??= Offset(paper.position.x, paper.position.y);
        _magnetFreeRotation ??= paper.rotationDeg;
        final newFree = Offset(
          _magnetFreePosition!.dx + dx,
          _magnetFreePosition!.dy + dy,
        );
        _magnetFreePosition = newFree;

        final match = _findMagnetMatch(paper, newFree);

        if (match != null) {
          final sameSlot = _magnetPrevBpIndex == match.bpIndex;
          _magnetTargetBpIndex = match.bpIndex;
          _magnetTargetPosition = match.targetPos;
          _magnetTargetRotation = match.targetRotDeg;
          if (!sameSlot) {
            _magnetPrevBpIndex = match.bpIndex;
            _magnetAnimController.forward(from: 0);
          }
          final t = Curves.easeInOut.transform(_magnetAnimController.value);
          setState(() {
            paper.position.x =
                newFree.dx + (match.targetPos.dx - newFree.dx) * t;
            paper.position.y =
                newFree.dy + (match.targetPos.dy - newFree.dy) * t;
            paper.rotationDeg = _lerpAngle(
              _magnetFreeRotation!,
              match.targetRotDeg,
              t,
            );
          });
        } else {
          if (_magnetPrevBpIndex != null) {
            _magnetPrevBpIndex = null;
            _magnetTargetBpIndex = null;
            _magnetAnimController.reverse();
          } else {
            setState(() {
              paper.position.x = newFree.dx;
              paper.position.y = newFree.dy;
              paper.rotationDeg = _magnetFreeRotation!;
            });
          }
        }
        return;
      }

      setState(() {
        if (paper.groupId != null) {
          for (final p in _placedPapers) {
            if (p.groupId == paper.groupId) {
              p.position.x += dx;
              p.position.y += dy;
            }
          }
        } else if (_selectedPaperIds.contains(paper.id) &&
            _selectedPaperIds.length > 1) {
          for (final p in _placedPapers) {
            if (_selectedPaperIds.contains(p.id)) {
              p.position.x += dx;
              p.position.y += dy;
            }
          }
        } else {
          paper.position.x += dx;
          paper.position.y += dy;
        }
      });
    }
  }

  void _handlePointerUp(Offset localPos, Size viewportSize) {
    if (_completionPhase != CompletionPhase.none) return;
    if (_craftingMode == CraftingMode.cutting) return;
    if (_toolsBlocked) return;

    if (_craftingMode == CraftingMode.stencil) {
      setState(() {
        if (_stencilHandleIndex != null) {
          _stencilHandleIndex = null;
          _stencilResizeStart = null;
          _settleHandleFollow();
        }
        if (_stencilDragging && _stencilDragStartPos != null) {
          _snapStencilAfterMove();
        }
        _stencilDragging = false;
        _stencilDragStartWorld = null;
        _stencilDragStartPos = null;
      });
      return;
    }

    if (_stretchHandleIndex != null && _stretchPaperId != null) {
      _stretchHandleIndex = null;
      final paper = _placedPapers
          .where((p) => p.id == _stretchPaperId)
          .firstOrNull;
      final from = _stretchStartLocal;
      final to = _handleFollowTarget ?? _stretchDisplayLocal;
      if (paper != null &&
          from != null &&
          to != null &&
          _stretchBoundsAreDegenerate(paper, from, to)) {
        _setHandleFollowTarget(from);
        _settleHandleFollow(
          onSettled: () {
            if (!mounted) return;
            setState(() => _stretchDisplayLocal = from);
          },
        );
        return;
      }
      _settleHandleFollow(onSettled: () {
        setState(_bakeStretch);
      });
      return;
    }

    if (_craftingMode == CraftingMode.pan) {
      if (_panModeDragging) {
        final paper = _placedPapers
            .where((p) => p.id == _panModeSelectedPaperId)
            .firstOrNull;
        if (paper != null) {
          final corners = _paperWorldCorners(paper);
          final snap = _computeSnap(corners, excludePaperIds: {paper.id});
          setState(() {
            paper.position.x += snap.dx;
            paper.position.y += snap.dy;
          });
        }
        _panModeDragging = false;
        _panModeDragLastScreen = null;
        _panDragLastScreen = null;
        return;
      }

      final wasDragOnSelected = _panModeDragLastScreen != null;
      _panModeDragLastScreen = null;
      _panDragLastScreen = null;

      final hitId = _hitTestPaper(localPos, viewportSize);
      final now = DateTime.now();
      final isDoubleTap =
          _lastPanTapTime != null &&
          _lastPanTapPos != null &&
          now.difference(_lastPanTapTime!).inMilliseconds < 300 &&
          (localPos - _lastPanTapPos!).distance < 20;

      if (isDoubleTap && hitId != null) {
        setState(() {
          _panModeSelectedPaperId = hitId;
          _selectedPaperIds = {hitId};
          _isRotationGizmoActive = false;
        });
        _lastPanTapTime = null;
        _lastPanTapPos = null;
        return;
      }

      if (!wasDragOnSelected &&
          hitId == null &&
          _panModeSelectedPaperId != null) {
        setState(() {
          _panModeSelectedPaperId = null;
          _selectedPaperIds = {};
          _isRotationGizmoActive = false;
        });
      }

      _lastPanTapTime = now;
      _lastPanTapPos = localPos;
      return;
    }

    if (_craftingMode == CraftingMode.mirror && _mirrorLineStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      final isTap = (_mirrorLineStart! - snapped).distance <= 1e-4;
      if (!isTap) {
        _applyMirrorCopy(_mirrorLineStart!, snapped);
      } else if (_selectedPaperIds.isNotEmpty) {
        _pushUndo('Deselect');
      }
      setState(() {
        _mirrorLineStart = null;
        _mirrorLinePreview = null;
        if (isTap) _selectedPaperIds = {};
      });
      return;
    }

    if (_craftingMode == CraftingMode.drawLine && _lineDrawStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapCutPoint(
        Offset(worldPos.x, worldPos.y),
        fromVertexRefs: _cutStartVertexRefs,
      );
      _cutSnapRay = snapped.ray;
      if ((_lineDrawStart! - snapped.point).distance > 1e-4) {
        _drawnCutLines.add((_lineDrawStart!, snapped.point));
        _updateCutHighlights(_lineDrawStart!, snapped.point);
        _resetCutStroke(fadeHighlights: false);
        if (_kCutFriendAnimationEnabled) {
          _startCutAnimation();
        } else {
          _executeCut();
        }
      } else {
        setState(_resetCutStroke);
      }
      return;
    }

    if (_craftingMode == CraftingMode.paint) {
      if (_paintDragPaperId != null) {
        final paper = _placedPapers
            .where((p) => p.id == _paintDragPaperId)
            .firstOrNull;
        if (paper != null) {
          final corners = _paperWorldCorners(paper);
          final snap = _computeSnap(corners, excludePaperIds: {paper.id});
          setState(() {
            paper.position.x += snap.dx;
            paper.position.y += snap.dy;
          });
        }
        _paintDragPaperId = null;
        _paintDragLastScreen = null;
        _scheduleCheck();
        return;
      }
      if (_paintDeferredCell != null) {
        final dc = _paintDeferredCell!;
        if (_isCellAdjacentToPaper(
          dc.$1,
          dc.$2,
          onlyPaperIds: _paintSelectionIds,
        )) {
          _tryPaintCell(dc);
        }
        _paintDeferredCell = null;
      }
      if (_paintedCells.isNotEmpty) {
        _fusePaintedCells();
      } else {
        _lastPaintCell = null;
      }
      _paintHadSelection = false;
      _paintSelectionIds = {};
      return;
    }

    if (_craftingMode == CraftingMode.erase) {
      if (_erasedCells.isNotEmpty) {
        _applyErase();
      } else {
        _lastEraseCell = null;
      }
      return;
    }

    if (_craftingMode == CraftingMode.alignGrid) {
      final didDrag = _alignGridDidDrag;
      _alignGridPointerDown = null;
      _alignGridDidDrag = false;

      setState(() {
        if (!didDrag) {
          // Quick tap: origin already set on down; keep prior axes.
          _alignGridSecondPreview = null;
          _alignGridHoveredPolyIndex = null;
          _alignGridPreviewVertex = _gridOriginOffset;
        } else {
          final worldPos = _screenToWorld(localPos, viewportSize);
          final pick = _alignGridPick(Offset(worldPos.x, worldPos.y));
          final end = pick.point;
          if ((end - _gridOriginOffset).distanceSquared > 1e-12) {
            _gridRotation = math.atan2(
              end.dy - _gridOriginOffset.dy,
              end.dx - _gridOriginOffset.dx,
            );
            _alignGridSecondPreview = end;
          }
          _alignGridPreviewVertex = _gridOriginOffset;
          _alignGridHoveredPolyIndex = null;
        }
      });
      fmHapticSmallClick();
      _scheduleGridLodSync();
      return;
    }

    if (_toolsBlocked) {
      _pointerDownPos = null;
      _pointerDownPaperId = null;
      _isDragging = false;
      _dragPaperId = null;
      _isMarquee = false;
      _marqueeStartScreen = null;
      _marqueeCurrentScreen = null;
      return;
    }
    if (_isMarquee) {
      final start = _marqueeStartScreen!;
      final end = localPos;
      final leftToRight = end.dx >= start.dx;
      final selection = _computeMarqueeSelection(
        start,
        end,
        viewportSize,
        leftToRight,
      );
      _pushUndo('Select');
      setState(() {
        _selectedPaperIds = selection;
        _isRotationGizmoActive = false;
        _isMarquee = false;
        _marqueeStartScreen = null;
        _marqueeCurrentScreen = null;
      });
    } else if (_isDragging && _dragPaperId != null) {
      final isMagnet = _craftingMode == CraftingMode.magnet;
      if (localPos.dy > viewportSize.height * _inventoryReturnZoneFraction) {
        _returnPaperToInventory(_dragPaperId!);
      } else {
        final paper = _placedPapers
            .where((p) => p.id == _dragPaperId)
            .firstOrNull;
        if (paper != null) {
          if (isMagnet &&
              _magnetTargetBpIndex != null &&
              _magnetAnimController.value > 0.5) {
            setState(() {
              paper.position.x = _magnetTargetPosition!.dx;
              paper.position.y = _magnetTargetPosition!.dy;
              paper.rotationDeg = _magnetTargetRotation!;
            });
          } else if (isMagnet && _magnetFreePosition != null) {
            setState(() {
              paper.position.x = _magnetFreePosition!.dx;
              paper.position.y = _magnetFreePosition!.dy;
              paper.rotationDeg = _magnetFreeRotation ?? paper.rotationDeg;
            });
            final corners = _paperWorldCorners(paper);
            final snap = _computeSnap(corners, excludePaperIds: {paper.id});
            setState(() {
              paper.position.x += snap.dx;
              paper.position.y += snap.dy;
            });
          } else if (paper.groupId != null) {
            final groupMembers = _placedPapers
                .where((p) => p.groupId == paper.groupId)
                .toList();
            final excludeIds = groupMembers.map((p) => p.id).toSet();
            final allCorners = groupMembers
                .expand((p) => _paperWorldCorners(p))
                .toList();
            final snap = _computeSnap(allCorners, excludePaperIds: excludeIds);
            setState(() {
              for (final p in groupMembers) {
                p.position.x += snap.dx;
                p.position.y += snap.dy;
              }
            });
          } else if (_selectedPaperIds.contains(paper.id) &&
              _selectedPaperIds.length > 1) {
            final selected = _placedPapers
                .where((p) => _selectedPaperIds.contains(p.id))
                .toList();
            final allCorners = selected
                .expand((p) => _paperWorldCorners(p))
                .toList();
            final snap = _computeSnap(
              allCorners,
              excludePaperIds: _selectedPaperIds,
            );
            setState(() {
              for (final p in selected) {
                p.position.x += snap.dx;
                p.position.y += snap.dy;
              }
            });
          } else {
            final corners = _paperWorldCorners(paper);
            final snap = _computeSnap(corners, excludePaperIds: {paper.id});
            setState(() {
              paper.position.x += snap.dx;
              paper.position.y += snap.dy;
            });
          }
        }
      }
      if (isMagnet) {
        _magnetAnimController.stop();
        _clearMagnetState();
        _scheduleCheck();
      }
    } else if (_pointerDownPos != null) {
      if (_pointerDownPaperId != null) {
        final tapped = _placedPapers
            .where((p) => p.id == _pointerDownPaperId)
            .firstOrNull;
        if (_selectedPaperIds.length == 1 &&
            _selectedPaperIds.contains(_pointerDownPaperId)) {
          _pushUndo('Select');
          setState(() {
            _selectedPaperIds = {};
            _isRotationGizmoActive = false;
          });
        } else {
          _pushUndo('Select');
          setState(() {
            if (tapped?.groupId != null) {
              _selectedPaperIds = _placedPapers
                  .where((p) => p.groupId == tapped!.groupId && !p.locked)
                  .map((p) => p.id)
                  .toSet();
            } else if (tapped != null && !tapped.locked) {
              _selectedPaperIds = {_pointerDownPaperId!};
            } else {
              _selectedPaperIds = {};
            }
            _isRotationGizmoActive = false;
          });
        }
      } else {
        if (_selectedPaperIds.isNotEmpty) {
          _pushUndo('Select');
          setState(() {
            _selectedPaperIds = {};
            _isRotationGizmoActive = false;
          });
        }
      }
    }

    setState(() {
      _dragPaperId = null;
      _pointerDownPos = null;
      _pointerDownPaperId = null;
      _isDragging = false;
    });
    _scheduleCheck();
  }

  // ---------------------------------------------------------------------------
  // Marquee helpers
  // ---------------------------------------------------------------------------

  Set<String> _computeMarqueeSelection(
    Offset startScreen,
    Offset endScreen,
    Size viewportSize,
    bool fullyInside,
  ) {
    final screenRect = Rect.fromPoints(startScreen, endScreen);
    Offset worldOf(Offset sp) {
      final w = _screenToWorld(sp, viewportSize);
      return Offset(w.x, w.y);
    }

    final worldQuad = [
      worldOf(screenRect.topLeft),
      worldOf(screenRect.topRight),
      worldOf(screenRect.bottomRight),
      worldOf(screenRect.bottomLeft),
    ];
    final mqBox = _aabb(worldQuad);
    final mqEdges = [
      (worldQuad[0], worldQuad[1]),
      (worldQuad[1], worldQuad[2]),
      (worldQuad[2], worldQuad[3]),
      (worldQuad[3], worldQuad[0]),
    ];

    final result = <String>{};
    for (final paper in _placedPapers) {
      if (paper.locked) continue;
      final poly = _paperWorldPolygon2D(paper);
      if (poly.length < 3) continue;
      final pBox = _aabb(poly);
      if (!pBox.overlaps(mqBox)) continue;

      if (fullyInside) {
        if (poly.every((v) => _pointInPolygon(v, worldQuad))) {
          result.add(paper.id);
        }
        continue;
      }

      if (_marqueeIntersectsPaper(paper, poly, worldQuad, mqEdges)) {
        result.add(paper.id);
      }
    }
    return result;
  }

  bool _marqueeIntersectsPaper(
    PlacedPaper paper,
    List<Offset> exterior,
    List<Offset> worldQuad,
    List<(Offset, Offset)> mqEdges,
  ) {
    for (final v in exterior) {
      if (_pointInPolygon(v, worldQuad)) return true;
    }
    for (final c in worldQuad) {
      final local = _worldToPaperLocal(Vector3(c.dx, c.dy, _paperZ), paper);
      if (_isPointInLocalPaper(local, paper)) return true;
    }
    for (final ring in [exterior, ..._paperWorldHoles2D(paper)]) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        for (final (c, d) in mqEdges) {
          if (segmentIntersection(a, b, c, d).hasIntersection) return true;
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Grouping helpers
  // ---------------------------------------------------------------------------

  void _groupSelectedPapers() {
    if (_selectedPaperIds.length < 2) return;
    _pushUndo('Group');
    final gid = 'group_${_nextGroupId++}';
    setState(() {
      for (final p in _placedPapers) {
        if (_selectedPaperIds.contains(p.id)) {
          p.groupId = gid;
        }
      }
    });
  }

  void _ungroupSelectedPapers() {
    _pushUndo('Ungroup');
    setState(() {
      for (final p in _placedPapers) {
        if (_selectedPaperIds.contains(p.id)) {
          p.groupId = null;
        }
      }
    });
  }

  void _discardSelectedPapers() {
    _pushUndo('Discard');
    setState(() {
      final ids = Set<String>.from(_selectedPaperIds);
      _placedPapers.removeWhere((p) => ids.contains(p.id));
      _selectedPaperIds = {};
      _isRotationGizmoActive = false;
    });
    _scheduleCheck();
  }

  /// True for pieces fitted to a blueprint slot (green outline). Invert
  /// skips these so leftover scrap can be discarded without touching them.
  bool _isFittedPaper(PlacedPaper paper) =>
      paper.locked || paper.isBlueprintMatched;

  /// Previous-step commit or current-step ops lock — skip punch / paint / cut.
  bool _isToolProtected(PlacedPaper paper) =>
      paper.locked || paper.opsLocked;

  void _clearCopyMemory() {
    _copyMemorySourceCentroid = null;
    _copyMemorySourceRotationDeg = 0;
    _copyMemorySourceIds = null;
    _copyMemoryResultIds = null;
  }

  void _syncCopyMemoryWithSelection() {
    if (_copyMemoryResultIds == null) return;
    if (_selectedPaperIds.isEmpty ||
        _selectedPaperIds.length != _copyMemoryResultIds!.length ||
        !_selectedPaperIds.containsAll(_copyMemoryResultIds!)) {
      _clearCopyMemory();
    }
  }

  Offset _centroidOfPapers(List<PlacedPaper> papers) {
    if (papers.isEmpty) return Offset.zero;
    var sx = 0.0, sy = 0.0;
    for (final paper in papers) {
      sx += paper.position.x;
      sy += paper.position.y;
    }
    return Offset(sx / papers.length, sy / papers.length);
  }

  Offset _rotateAround(Offset point, Offset center, double deg) {
    if (deg.abs() < 1e-10) return point;
    final rad = deg * math.pi / 180;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Offset(
      center.dx + dx * c - dy * s,
      center.dy + dx * s + dy * c,
    );
  }

  double _signedDeltaDeg(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Half the current dot-grid spacing: +X (right), −Y (down).
  Offset get _defaultCopyTranslation {
    final half = _activeGridSpacing * 0.5;
    return Offset(half, -half);
  }

  /// Select every unfitted paper that is not in the current selection.
  void _invertSelection() {
    _pushUndo('Invert');
    setState(() {
      final inverted = <String>{
        for (final paper in _placedPapers)
          if (!_selectedPaperIds.contains(paper.id) &&
              !_isFittedPaper(paper) &&
              !_isDiscardingPaper(paper.id))
            paper.id,
      };
      _selectedPaperIds = inverted;
      _isRotationGizmoActive = false;
      _panModeSelectedPaperId =
          inverted.length == 1 ? inverted.single : null;
    });
  }

  void _copySelectedPapers() {
    final selected = _placedPapers
        .where(
          (p) =>
              _selectedPaperIds.contains(p.id) &&
              !p.locked &&
              !_isDiscardingPaper(p.id),
        )
        .toList();
    if (selected.isEmpty) return;

    final useMemory = _copyMemoryResultIds != null &&
        _copyMemorySourceCentroid != null &&
        _selectedPaperIds.length == _copyMemoryResultIds!.length &&
        _selectedPaperIds.containsAll(_copyMemoryResultIds!);

    final Offset translation;
    final double rotationDeg;
    if (useMemory) {
      final currentCentroid = _centroidOfPapers(selected);
      translation = currentCentroid - _copyMemorySourceCentroid!;
      rotationDeg = _signedDeltaDeg(
        _copyMemorySourceRotationDeg,
        selected.first.rotationDeg,
      );
    } else {
      translation = _defaultCopyTranslation;
      rotationDeg = 0;
    }

    final sourceCentroid = _centroidOfPapers(selected);
    final sourceRotation = selected.first.rotationDeg;

    final newPapers = <PlacedPaper>[];
    for (final paper in selected) {
      final rotated = _rotateAround(
        Offset(paper.position.x, paper.position.y),
        sourceCentroid,
        rotationDeg,
      );
      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: paper.paperColor,
          position: Vector3(
            rotated.dx + translation.dx,
            rotated.dy + translation.dy,
            paper.position.z,
          ),
          stackOrder: _allocateStackMajor(),
          rotationDeg: (paper.rotationDeg + rotationDeg) % 360,
          sizeLevel: paper.sizeLevel,
          localVertices: paper.localVertices != null
              ? List<Offset>.from(paper.localVertices!)
              : null,
          localHoles: paper.localHoles
              .map((h) => List<Offset>.from(h))
              .toList(),
          materialId: paper.materialId,
        ),
      );
    }

    if (newPapers.isEmpty) return;

    _pushUndo('Copy');
    setState(() {
      _placedPapers.addAll(newPapers);
      _copyMemorySourceCentroid = sourceCentroid;
      _copyMemorySourceRotationDeg = sourceRotation;
      _copyMemorySourceIds = selected.map((p) => p.id).toSet();
      final resultIds = newPapers.map((p) => p.id).toSet();
      _copyMemoryResultIds = resultIds;
      _suppressCopyMemorySync = true;
      _selectedPaperIds = Set<String>.from(resultIds);
      _suppressCopyMemorySync = false;
      _isRotationGizmoActive = false;
      _panModeSelectedPaperId =
          newPapers.length == 1 ? newPapers.single.id : null;
    });
    _scheduleCheck();
  }

  RadialAction _invertSelectionAction() {
    return RadialAction(
      icon: Icons.flip,
      label: 'Invert',
      tint: const Color(0xFF80CBC4),
      side: RadialActionSide.left,
      onTap: _invertSelection,
    );
  }

  RadialAction _copySelectionAction() {
    return RadialAction(
      icon: Icons.copy,
      label: 'Copy',
      tint: const Color(0xFF64B5F6),
      side: RadialActionSide.right,
      onTap: _copySelectedPapers,
    );
  }

  RadialAction _opsLockAction(List<PlacedPaper> selected) {
    final targets = selected.where((p) => !p.locked).toList();
    final allLocked =
        targets.isNotEmpty && targets.every((p) => p.opsLocked);
    return RadialAction(
      icon: allLocked ? Icons.lock_open : Icons.lock_outline,
      label: allLocked ? 'Unlock' : 'Lock',
      tint: const Color(0xFFBCAAA4),
      side: RadialActionSide.topLeft,
      onTap: () => _setSelectedOpsLocked(!allLocked),
    );
  }

  void _setSelectedOpsLocked(bool locked) {
    _pushUndo(locked ? 'Lock' : 'Unlock');
    setState(() {
      for (final paper in _placedPapers) {
        if (!_selectedPaperIds.contains(paper.id) || paper.locked) continue;
        paper.opsLocked = locked;
      }
    });
  }

  void _joinSelectedPapers() {
    if (_selectedPaperIds.length < 2) return;
    _pushUndo('Join');

    final selected = _placedPapers
        .where((p) => _selectedPaperIds.contains(p.id))
        .toList();
    if (selected.length < 2) return;

    // Use the most common color among selected papers.
    final colorCounts = <PaperColor, int>{};
    for (final p in selected) {
      colorCounts[p.paperColor] = (colorCounts[p.paperColor] ?? 0) + 1;
    }
    final dominantColor = colorCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    // Collect world-space exteriors and holes from all selected papers.
    final allExteriors = <List<Offset>>[];
    final allOriginalHoles = <List<Offset>>[];
    for (final paper in selected) {
      allExteriors.add(_paperWorldPolygon2D(paper));
      allOriginalHoles.addAll(_paperWorldHoles2D(paper));
    }

    final unionLoops = unionPolygons(allExteriors);
    if (unionLoops.isEmpty) return;

    final classified = _classifyCompoundFaces(unionLoops);

    // Keep original holes whose centroid is still inside a union exterior but
    // not filled by any input exterior.
    final survivingHoles = <List<Offset>>[];
    for (final hole in allOriginalHoles) {
      final hc = _polygonCentroid(hole);
      bool insideExterior = false;
      for (final (ext, _) in classified) {
        if (_pointInPolygon(hc, ext)) {
          insideExterior = true;
          break;
        }
      }
      if (!insideExterior) continue;
      bool filled = false;
      for (final ext in allExteriors) {
        if (_pointInPolygon(hc, ext)) {
          filled = true;
          break;
        }
      }
      if (!filled) survivingHoles.add(hole);
    }

    final newPapers = <PlacedPaper>[];
    for (final (exterior, unionHoles) in classified) {
      if (exterior.length < 3) continue;
      final mergedHoles = <List<Offset>>[...unionHoles];
      for (final sh in survivingHoles) {
        if (_pointInPolygon(_polygonCentroid(sh), exterior)) {
          mergedHoles.add(sh);
        }
      }
      final centroid = _polygonCentroid(exterior);
      final shifted = exterior.map((v) => v - centroid).toList();
      final shiftedHoles = mergedHoles
          .map((h) => h.map((v) => v - centroid).toList())
          .toList();
      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: dominantColor,
          position: Vector3(centroid.dx, centroid.dy, _paperZ),
          stackOrder: _allocateStackMajor(),
          rotationDeg: 0,
          sizeLevel: 1,
          localVertices: shifted,
          localHoles: shiftedHoles,
        ),
      );
    }

    if (newPapers.isEmpty) return;

    setState(() {
      _placedPapers.removeWhere((p) => _selectedPaperIds.contains(p.id));
      _placedPapers.addAll(newPapers);
      _selectedPaperIds = {newPapers.last.id};
      _isRotationGizmoActive = false;
    });
    _scheduleCheck();
  }

  /// Centroid of the currently selected papers in world space.
  Vector3 _collectiveCentroid() {
    final selected = _placedPapers
        .where((p) => _selectedPaperIds.contains(p.id))
        .toList();
    if (selected.isEmpty) return Vector3.zero();
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final p in selected) {
      sx += p.position.x;
      sy += p.position.y;
      sz += p.position.z;
    }
    final n = selected.length.toDouble();
    return Vector3(sx / n, sy / n, sz / n);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final hadViewport = _viewportSize.width > 1 && _viewportSize.height > 1;
        _viewportSize = viewportSize;
        _scheduleGridLodSync();
        if (_pendingCameraFit &&
            !hadViewport &&
            viewportSize.width > 1 &&
            viewportSize.height > 1 &&
            _blueprintWorldPolygons.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pendingCameraFit) return;
            if (_blueprintWorldPolygons.isEmpty) return;
            _pendingCameraFit = false;
            final cam = _cameraForPolygons(_blueprintWorldPolygons);
            setState(() {
              _orthoScale = cam.ortho;
              _panOffset = cam.pan;
              _viewRotation = cam.rotation;
            });
          });
        }
        return GestureClassifier(
          onGestureUpdate: (state) => _onCraftGesture(state, viewportSize),
          child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCanvas(viewportSize),
            ..._buildPaperOverlays(viewportSize),
            if (_rotCopyGizmoActive && _rotCopyCenterWorld != null)
              _buildRotCopyGizmo(viewportSize),
            // Close / cut / check — bottom-left, above the centered column.
            if (widget.onDismiss != null ||
                (_craftingMode == CraftingMode.drawLine &&
                    _drawnCutLines.isNotEmpty) ||
                _selectedBlueprint != null)
              FmSafePositioned(
                bottom: _kBottomControlColumnClearance,
                left: 12,
                minimum: kFmScreenInset,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onDismiss != null) ...[
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                    if (_craftingMode == CraftingMode.drawLine &&
                        _drawnCutLines.isNotEmpty) ...[
                      if (widget.onDismiss != null) const SizedBox(width: 8),
                      _buildCutButton(),
                    ],
                    if (_selectedBlueprint != null) ...[
                      if (widget.onDismiss != null ||
                          (_craftingMode == CraftingMode.drawLine &&
                              _drawnCutLines.isNotEmpty))
                        const SizedBox(width: 8),
                      _buildCheckModeToggle(),
                    ],
                  ],
                ),
              ),
            // Tool modes — vertically centered on the left, above the column.
            FmSafePositioned(
              left: 12,
              top: 0,
              bottom: _kBottomControlColumnClearance,
              minimum: kFmScreenInset,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildToolModeBar(),
              ),
            ),
            if (_selectedBlueprint != null)
              FmSafePositioned(
                right: 12,
                top: 88,
                minimum: kFmScreenInset,
                child: _buildProgressBar(),
              ),
            FmSafePositioned(
              right: 12,
              top: 0,
              bottom: _kBottomControlColumnClearance,
              minimum: kFmScreenInset,
              child: Align(
                alignment: Alignment.centerRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildSnapToolbar(),
                    const SizedBox(height: 12),
                    _buildConfigButton(),
                  ],
                ),
              ),
            ),
            if (_craftingMode == CraftingMode.cutting)
              FmSafePositioned(
                left: 16,
                bottom: _kBottomControlColumnClearance,
                minimum: kFmScreenInset,
                child: _buildCutProgressBar(),
              ),
            FmSafePositioned(
              left: 0,
              right: 0,
              bottom: 0,
              minimum: kFmScreenInset,
              child: Center(child: _buildBottomControlColumn()),
            ),
          ],
        ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Progress bar
  // ---------------------------------------------------------------------------

  Widget _buildProgressBar() {
    final double progress;
    if (_blueprintTotalArea <= 0) {
      progress = 0;
    } else if (_progressAnimController.isAnimating) {
      progress =
          _progressAnimFrom +
          (_progressAnimTo - _progressAnimFrom) * _progressAnimController.value;
    } else {
      progress = (_blueprintLockedArea / _blueprintTotalArea).clamp(0, 1);
    }
    final pct = (progress * 100).round();
    final isCrafted = pct >= 100;

    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isCrafted ? 'Crafted!' : 'Progress',
                    style: TextStyle(
                      color: isCrafted ? Colors.amber : Colors.white70,
                      fontSize: 11,
                      fontWeight: isCrafted
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: isCrafted ? Colors.amber : Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCrafted ? Colors.amber : Colors.greenAccent,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Line tool / cut controls
  // ---------------------------------------------------------------------------

  Widget _buildToolModeBar() {
    final isCutting = _craftingMode == CraftingMode.cutting;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolModeButton(
            icon: Icons.pan_tool,
            tooltip: 'Pan',
            isActive: _craftingMode == CraftingMode.pan,
            onTap: isCutting
                ? null
                : () => setState(() {
                    _endTransform();
                    _craftingMode = CraftingMode.pan;
                    _drawnCutLines.clear();
                    _resetCutStroke();
                    _panModeSelectedPaperId = null;
                    _paintedCells = {};
                    _lastPaintCell = null;
                    _erasedCells = {};
                    _lastEraseCell = null;
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.near_me,
            tooltip: 'Select',
            isActive: _craftingMode == CraftingMode.select,
            onTap: isCutting
                ? null
                : () => setState(() {
                    _endTransform();
                    _craftingMode = CraftingMode.select;
                    _drawnCutLines.clear();
                    _resetCutStroke();
                    _panModeSelectedPaperId = null;
                    _paintedCells = {};
                    _lastPaintCell = null;
                    _erasedCells = {};
                    _lastEraseCell = null;
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.content_cut,
            tooltip: 'Draw cut lines',
            isActive: _craftingMode == CraftingMode.drawLine,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.drawLine) {
                      _craftingMode = CraftingMode.pan;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                    } else {
                      _craftingMode = CraftingMode.drawLine;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.brush,
            tooltip: 'Paint',
            isActive: _craftingMode == CraftingMode.paint,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.paint) {
                      _craftingMode = CraftingMode.pan;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    } else {
                      _craftingMode = CraftingMode.paint;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.auto_fix_off,
            tooltip: 'Erase',
            isActive: _craftingMode == CraftingMode.erase,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.erase) {
                      _craftingMode = CraftingMode.pan;
                      _erasedCells = {};
                      _lastEraseCell = null;
                    } else {
                      _craftingMode = CraftingMode.erase;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.grid_on,
            tooltip: 'Align grid (drag +Y, tap to move origin)',
            isActive: _craftingMode == CraftingMode.alignGrid,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.alignGrid) {
                      _craftingMode = CraftingMode.pan;
                      _clearAlignGridTransient();
                    } else {
                      _craftingMode = CraftingMode.alignGrid;
                      _clearAlignGridTransient();
                      _alignGridPreviewVertex = _gridOriginOffset;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                      _paintedCells = {};
                      _lastPaintCell = null;
                      _erasedCells = {};
                      _lastEraseCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.attractions,
            tooltip: 'Magnet',
            isActive: _craftingMode == CraftingMode.magnet,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.magnet) {
                      _craftingMode = CraftingMode.pan;
                    } else {
                      _craftingMode = CraftingMode.magnet;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                      _paintedCells = {};
                      _lastPaintCell = null;
                      _clearMagnetState();
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.crop_din,
            tooltip: 'Stencil punch',
            isActive: _craftingMode == CraftingMode.stencil,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.stencil) {
                      _craftingMode = CraftingMode.pan;
                      _stencilSelected = false;
                      _stencilHandleIndex = null;
                      _stencilResizeStart = null;
                      _stopHandleFollow();
                    } else {
                      _enterStencilMode();
                    }
                  }),
          ),
          if (_craftingMode == CraftingMode.stencil) ...[
            const SizedBox(height: 4),
            _ToolModeButton(
              icon: Icons.rectangle_outlined,
              tooltip: '2×4 rectangle',
              isActive: _stencilShape == StencilShape.rectangle,
              onTap: () => setState(() {
                _stencilShape = StencilShape.rectangle;
                _applyStencilDefaultSize();
              }),
            ),
            const SizedBox(height: 2),
            _ToolModeButton(
              icon: Icons.circle_outlined,
              tooltip: '2×2 circle',
              isActive: _stencilShape == StencilShape.circle,
              onTap: () => setState(() {
                _stencilShape = StencilShape.circle;
                _applyStencilDefaultSize();
              }),
            ),
          ],
          const SizedBox(height: 6),
          Container(height: 1, width: 24, color: Colors.white24),
          const SizedBox(height: 6),
          _ToolModeButton(
            icon: Icons.flip,
            tooltip: 'Mirror copy',
            isActive: _craftingMode == CraftingMode.mirror,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.mirror) {
                      _craftingMode = CraftingMode.select;
                      _mirrorLineStart = null;
                      _mirrorLinePreview = null;
                    } else {
                      _craftingMode = CraftingMode.mirror;
                      _mirrorLineStart = null;
                      _mirrorLinePreview = null;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                      _panModeSelectedPaperId = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.rotate_left,
            tooltip: 'Rotation copy',
            isActive: _craftingMode == CraftingMode.rotationCopy,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.rotationCopy) {
                      _craftingMode = CraftingMode.select;
                      _rotCopyCenterWorld = null;
                      _rotCopyGizmoActive = false;
                    } else {
                      _craftingMode = CraftingMode.rotationCopy;
                      _rotCopyCenterWorld = null;
                      _rotCopyGizmoActive = false;
                      _rotCopyAngleDeg = 0;
                      _drawnCutLines.clear();
                      _resetCutStroke();
                      _panModeSelectedPaperId = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          if (_craftingMode == CraftingMode.paint) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _useStructureInventory
                    ? [
                        for (final entry
                            in _structureInventory!.contents.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _paintMaterialId = entry.key;
                              }),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: _materialRegistry.colorFor(entry.key),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _paintMaterialId == entry.key
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]
                    : [
                        for (final pc in PaperColor.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: GestureDetector(
                              onTap: () => setState(() => _paintColor = pc),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: pc.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _paintColor == pc
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
              ),
            ),
            const SizedBox(height: 4),
            Tooltip(
              message: 'Fuse with adjacent pieces',
              child: GestureDetector(
                onTap: () =>
                    setState(() => _paintFusionEnabled = !_paintFusionEnabled),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _paintFusionEnabled
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _paintFusionEnabled
                          ? Colors.white
                          : Colors.white38,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.merge_type,
                    size: 14,
                    color: _paintFusionEnabled ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSnapToolbar() {
    Widget snapToggle(
      IconData icon,
      String tooltip,
      bool active,
      ValueChanged<bool> onChanged,
    ) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: active
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged(!active),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                icon,
                color: active ? Colors.white : Colors.white38,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Icon(Icons.adjust, color: Colors.white54, size: 14),
          ),
          snapToggle(
            Icons.grid_3x3,
            'Snap to grid',
            _snapGrid,
            (v) => setState(() => _snapGrid = v),
          ),
          const SizedBox(height: 2),
          snapToggle(
            Icons.architecture,
            'Snap to blueprint',
            _snapBlueprint,
            (v) => setState(() => _snapBlueprint = v),
          ),
          const SizedBox(height: 2),
          snapToggle(
            Icons.note_outlined,
            'Snap to paper',
            _snapPaper,
            (v) => setState(() => _snapPaper = v),
          ),
        ],
      ),
    );
  }

  Widget _buildCutButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text('Cut (${_drawnCutLines.length})'),
      onPressed: () {
        if (_kCutFriendAnimationEnabled) {
          _startCutAnimation();
        } else {
          _executeCut();
        }
      },
    );
  }

  Widget _buildCutProgressBar() {
    final progress = _cutAnimController.value;
    final pct = (progress * 100).round();
    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
          width: 160,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Cutting...',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.redAccent,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Config popover
  // ---------------------------------------------------------------------------

  Widget _buildConfigButton() {
    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
        onPressed: _showConfigPopover,
        tooltip: 'Canvas & snap settings',
      ),
    );
  }

  void _showConfigPopover() {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ConfigPopover(
        canvasDisplayMode: _canvasDisplayMode,
        showMinorLines: _showMinorLines,
        gridRegionAssist: _gridRegionAssist,
        cutSpeed: _cutSpeed,
        onChanged: (mode, minor, regionAssist, speed) {
          setState(() {
            _canvasDisplayMode = mode;
            _showMinorLines = minor;
            _gridRegionAssist = regionAssist;
            _cutSpeed = speed;
          });
          entry.markNeedsBuild();
        },
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // ---------------------------------------------------------------------------
  // Blueprint dropdown
  // ---------------------------------------------------------------------------

  Widget _buildBlueprintDropdown() {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        offset: Offset(0, -(_blueprintSets.length + 1) * 40.0),
        color: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onSelected: (value) {
          if (value.isEmpty) {
            _selectBlueprintSet(null);
          } else {
            final set = _blueprintSets
                .where((s) => s.name == value)
                .firstOrNull;
            _selectBlueprintSet(set);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: '',
            child: Text(
              'None',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          for (final set in _blueprintSets)
            PopupMenuItem(
              value: set.name,
              child: Text(
                set.name,
                style: TextStyle(
                  color: set.name == _selectedSet?.name
                      ? Colors.white
                      : Colors.white70,
                  fontSize: 13,
                  fontWeight: set.name == _selectedSet?.name
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedSet?.name ?? 'Blueprint Set',
                style: TextStyle(
                  color: _selectedSet != null ? Colors.white : Colors.white54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_up, color: Colors.white54, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnionToggle() {
    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleChip('Disjoint', !_blueprintUnionMode, () {
            setState(() => _blueprintUnionMode = false);
          }),
          _toggleChip('Union', _blueprintUnionMode, () {
            setState(() => _blueprintUnionMode = true);
          }),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckModeToggle() {
    return Material(
      color: Colors.black.withOpacity(0.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _checkMode = !_checkMode;
            if (_checkMode) {
              _scheduleCheck();
            } else {
              _filledBlueprintIndices = {};
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _checkMode ? Icons.check_box : Icons.check_box_outline_blank,
                color: _checkMode ? Colors.greenAccent : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Check',
                style: TextStyle(
                  color: _checkMode ? Colors.white : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFillAllButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _completionPhase == CompletionPhase.none ? _fillAll : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_fix_high,
                color: _completionPhase == CompletionPhase.none
                    ? Colors.amberAccent
                    : Colors.white24,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Fill All',
                style: TextStyle(
                  color: _completionPhase == CompletionPhase.none
                      ? Colors.white
                      : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _fillAll() {
    if (_selectedBlueprint == null ||
        _blueprintWorldPolygons.isEmpty ||
        _completionPhase != CompletionPhase.none ||
        _fillCompleteLatched) {
      return;
    }

    final colors = PaperColor.values;
    setState(() {
      for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
        final alreadyFilled = _filledBlueprintIndices.contains(i) ||
            _placedPapers.any((p) => p.lockedBlueprintIndex == i);
        if (alreadyFilled) {
          _filledBlueprintIndices.add(i);
          continue;
        }

        final poly = _blueprintWorldPolygons[i];
        if (poly.length < 3) continue;

        final centroid = _polyCentroid(poly);
        final localVerts = poly
            .map((v) => Offset(v.dx - centroid.dx, v.dy - centroid.dy))
            .toList();

        final paper = PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: colors[i % colors.length],
          position: Vector3(centroid.dx, centroid.dy, _paperZ),
          stackOrder: _allocateStackMajor(),
          localVertices: localVerts,
        );
        paper.lockedBlueprintIndex = i;
        paper.opsLocked = true;
        _placedPapers.add(paper);
        _filledBlueprintIndices.add(i);
      }
      _blueprintLockedArea = _blueprintTotalArea;
    });

    _maybeCompleteFill();
  }

  // ---------------------------------------------------------------------------
  // Canvas
  // ---------------------------------------------------------------------------

  Widget _buildCanvas(Size viewportSize) {
    return DragTarget<Object>(
      onAcceptWithDetails: (details) {
        if (details.data is PaperColor) {
          _placePaperFromInventory(details.data as PaperColor, details.offset);
        } else if (details.data is String) {
          _placeMaterialPaper(details.data as String, details.offset);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isReceivingDrag = candidateData.isNotEmpty;
        return Listener(
            key: _canvasKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _canvasPointerCount++;
              if (_canvasPointerCount >= 2 ||
                  _toolsSuppressedUntilPointersUp ||
                  _panZoomActive ||
                  _pinchEpisode) {
                _enterPinchExclusiveMode();
                return;
              }
              // Defer the tool until slop or a clean tap — a trackpad pinch
              // often delivers PointerDown before PointerPanZoomStart.
              _queueToolPointerDown(e.localPosition, viewportSize);
            },
            onPointerMove: (e) {
              if (_toolsBlocked) {
                _cancelPendingToolDown();
                return;
              }
              if (_pendingToolDown != null) {
                if ((e.localPosition - _pendingToolDown!).distance <
                    _dragThreshold) {
                  return;
                }
                _flushPendingToolDown();
              }
              _handlePointerMove(e.localPosition, viewportSize);
            },
            onPointerUp: (e) {
              _canvasPointerCount = math.max(0, _canvasPointerCount - 1);
              final suppress = _toolsBlocked || _pinchEpisode;
              if (!suppress && _pendingToolDown != null) {
                _flushPendingToolDown();
              } else {
                _cancelPendingToolDown();
              }
              _maybeUnlockToolsAfterPointersUp();
              if (suppress) return;
              _handlePointerUp(e.localPosition, viewportSize);
            },
            onPointerPanZoomStart: (_) {
              _panZoomActive = true;
              _enterPinchExclusiveMode();
            },
            onPointerPanZoomEnd: (_) {
              _panZoomActive = false;
              _maybeUnlockToolsAfterPointersUp();
            },
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                setState(() {
                  _orthoScale = (_orthoScale + event.scrollDelta.dy * 0.5)
                      .clamp(_minOrthoScale, _maxOrthoScale);
                });
                _scheduleGridLodSync();
              }
            },
            onPointerCancel: (_) {
              _canvasPointerCount = 0;
              _cancelPendingToolDown();
              _enterPinchExclusiveMode();
              if (!_panZoomActive) {
                _maybeUnlockToolsAfterPointersUp();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: CraftingTestPainter(
                    geometry: _geometry,
                    objectRotation: _objectRotation,
                    objectPosition: _objectPosition,
                    objectColor: _objectColor,
                    friendVisible: _friendVisible,
                    drawingPlaneSize: _drawingPlaneSize,
                    orthoScale: _orthoScale,
                    panOffset: _panOffset,
                    viewRotation: _viewRotation,
                    canvasDisplayMode: _canvasDisplayMode,
                    showMinorLines: _showMinorLines,
                    papers: _placedPapers,
                    selectedPaperIds: _selectedPaperIds,
                    friendExpression: FriendExpressionConfig.cube,
                    eyeGeometry3d: FriendEyeGeometry3d.sphere,
                    blueprintPolygons: _blueprintUnionMode
                        ? _blueprintUnionPolygons
                        : _blueprintWorldPolygons,
                    filledBlueprintIndices: _checkMode && !_blueprintUnionMode
                        ? _filledBlueprintIndices
                        : const {},
                    groupOverlayPolygons: _groupOverlayPolygons,
                    groupOverlayColors: _groupOverlayColors,
                    activeHighlightT: _activeHighlightT,
                    activeGlow: _activeGlow,
                    loadAnimT: _loadAnimT,
                    hideUnfilledBlueprint: _hideUnfilledBlueprint,
                    lockFadingPaperIds: _lockFadingPaperIds,
                    lockFadeT: _lockFadeT,
                    discardOpacityById: _discardOpacities(),
                    marqueeRect:
                        _isMarquee &&
                            _marqueeStartScreen != null &&
                            _marqueeCurrentScreen != null
                        ? Rect.fromPoints(
                            _marqueeStartScreen!,
                            _marqueeCurrentScreen!,
                          )
                        : null,
                    marqueeIsIntersect:
                        _isMarquee &&
                        _marqueeStartScreen != null &&
                        _marqueeCurrentScreen != null &&
                        _marqueeCurrentScreen!.dx < _marqueeStartScreen!.dx,
                    marqueeDashOffset: _marqueeDashController.value * 16.0,
                    lockAnimatingPaperIds: _lockAnimatingPaperIds,
                    lockAnimProgress: _lockAnimProgress,
                    completionPhase: _completionPhase,
                    foldNodeStates: _foldNodeStates,
                    foldDisplacementMatrix: _foldDisplacementMatrix,
                    foldColorProgress: _foldColorProgress,
                    foldOpacity: _foldOpacity,
                    dotDissolveProgress:
                        _completionPhase == CompletionPhase.dissolveReveal
                        ? _dotDissolveProgress
                        : (_completionPhase == CompletionPhase.none
                              ? null
                              : 1.0),
                    foldViewProjection: _computeFoldVP(viewportSize),
                    dotWipeOpacityAt:
                        _dotWipeAnimation != null &&
                            _dotWipeAnimation!.isAnimating
                        ? _dotWipeAnimation!.opacityAt
                        : null,
                    structureFootprint: widget.structureFootprint,
                    drawnCutLines: _drawnCutLines,
                    lineDrawStart: _lineDrawStart,
                    lineDrawPreview: _lineDrawPreview,
                    cutHighlightEdges: _cutHighlightEdges,
                    cutHighlightGlow: _cutEdgeGlowController.value,
                    cutSnapRay: _cutSnapRay,
                    craftingMode: _craftingMode,
                    activeToolpath: _activeToolpath,
                    cutAnimProgress: _craftingMode == CraftingMode.cutting
                        ? _cutAnimController.value
                        : 0,
                    hideDrawingPlane: widget.hideDrawingPlane,
                    paintedCells: _paintedCells,
                    paintColor: _paintColor,
                    erasedCells: _erasedCells,
                    mirrorLineStart: _mirrorLineStart,
                    mirrorLinePreview: _mirrorLinePreview,
                    ghostPapers: _computeGhostPapers(),
                    rotCopyCenterWorld: _rotCopyCenterWorld,
                    gridDivisions: _gridDivisions,
                    gridLodFrom: _gridLodFrom,
                    gridLodTo: _gridLodTo,
                    gridLodFadeT: _gridLodAnimController.value,
                    activeGridSpacing: _activeGridSpacing,
                    paperColorResolver: displayColorForPaper,
                    gridOriginOffset: _gridOriginOffset,
                    gridRotation: _gridRotation,
                    alignGridIndicator: _alignGridPreviewVertex,
                    alignGridAxisEnd: _alignGridSecondPreview,
                    alignGridHighlightPolyIndex: _alignGridHoveredPolyIndex,
                    stretchPaperId: _stretchPaperId,
                    stretchHandleIndex: _stretchHandleIndex,
                    stretchStartBounds: _stretchStartLocal,
                    stretchDisplayBounds: _stretchDisplayLocal,
                    gridRegionAssist: _gridRegionAssist,
                    blueprintHoles: _blueprintUnionMode
                        ? const []
                        : _blueprintWorldHoles,
                    stencilVisible: _craftingMode == CraftingMode.stencil,
                    stencilShape: _stencilShape,
                    stencilPosition: _stencilPosition,
                    stencilHalfW: _stencilHalfW,
                    stencilHalfH: _stencilHalfH,
                    stencilSelected: _stencilSelected,
                    stencilHandleIndex: _stencilHandleIndex,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
                if (isReceivingDrag)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Paper overlay (radial menu / rotation gizmo)
  // ---------------------------------------------------------------------------

  static const _copyToolModes = {
    CraftingMode.mirror,
    CraftingMode.rotationCopy,
  };

  List<Widget> _buildPaperOverlays(Size viewportSize) {
    if (_craftingMode == CraftingMode.stencil) {
      if (!_stencilSelected ||
          _stencilDragging ||
          _stencilHandleIndex != null) {
        return const [];
      }
      final screenCenter = _worldToScreen(
        Vector3(_stencilPosition.dx, _stencilPosition.dy, _paperZ),
        viewportSize,
      );
      return [
        ObjectRadialMenu(
          center: screenCenter,
          title: _stencilShape == StencilShape.circle
              ? 'Circle stencil'
              : 'Rectangle stencil',
          actions: [
            RadialAction(
              icon: Icons.adjust,
              label: 'Punch',
              tint: const Color(0xFFEF5350),
              side: RadialActionSide.top,
              onTap: _punchStencil,
            ),
          ],
        ),
      ];
    }

    if (_stretchPaperId != null) return const [];

    if (_selectedPaperIds.isEmpty || _isDragging || _isMarquee) {
      return const [];
    }

    final selectedPapers = _placedPapers
        .where((p) => _selectedPaperIds.contains(p.id) && !p.locked)
        .toList();
    if (selectedPapers.isEmpty) return const [];

    // In copy-tool modes, rely on the cyan edge highlight from the painter;
    // for multi-selection also show a bounding marquee with count.
    if (_copyToolModes.contains(_craftingMode)) {
      if (selectedPapers.length > 1) {
        return [_buildSelectionMarquee(selectedPapers, viewportSize)];
      }
      return const [];
    }

    // --- Single selection ---
    if (selectedPapers.length == 1) {
      return [_buildSinglePaperOverlay(selectedPapers.first, viewportSize)];
    }

    // --- Multi selection: bounding marquee + radial menu ---
    return [
      _buildSelectionMarquee(selectedPapers, viewportSize),
      _buildMultiPaperOverlay(selectedPapers, viewportSize),
    ];
  }

  /// Compute ghost papers for live preview of copy tools.
  List<PlacedPaper> _computeGhostPapers() {
    // Mirror preview
    if (_craftingMode == CraftingMode.mirror &&
        _mirrorLineStart != null &&
        _mirrorLinePreview != null &&
        (_mirrorLineStart! - _mirrorLinePreview!).distance > 1e-4 &&
        _selectedPaperIds.isNotEmpty) {
      final lineA = _mirrorLineStart!;
      final lineB = _mirrorLinePreview!;
      final lineAngle =
          math.atan2(lineB.dy - lineA.dy, lineB.dx - lineA.dx) * 180 / math.pi;

      return _placedPapers
          .where((p) => _selectedPaperIds.contains(p.id) && !p.locked)
          .map((paper) {
            final origPos = Offset(paper.position.x, paper.position.y);
            final reflected = _reflectPoint(origPos, lineA, lineB);
            final newRot = (2 * lineAngle - paper.rotationDeg) % 360;

            List<Offset>? newVerts;
            if (paper.localVertices != null) {
              final rad = paper.rotationDeg * math.pi / 180;
              final cosA = math.cos(rad);
              final sinA = math.sin(rad);
              final worldVerts = paper.localVertices!.map((o) {
                return Offset(
                  origPos.dx + o.dx * cosA - o.dy * sinA,
                  origPos.dy + o.dx * sinA + o.dy * cosA,
                );
              }).toList();
              final reflectedWorld = worldVerts
                  .map((v) => _reflectPoint(v, lineA, lineB))
                  .toList();
              final newRad = newRot * math.pi / 180;
              final cosB = math.cos(newRad);
              final sinB = math.sin(newRad);
              newVerts = reflectedWorld.reversed.map((w) {
                final dx0 = w.dx - reflected.dx;
                final dy0 = w.dy - reflected.dy;
                return Offset(
                  dx0 * cosB + dy0 * sinB,
                  -dx0 * sinB + dy0 * cosB,
                );
              }).toList();
            }

            return PlacedPaper(
              id: 'ghost_${paper.id}',
              paperColor: paper.paperColor,
              position: Vector3(reflected.dx, reflected.dy, paper.position.z),
              stackOrder: paper.stackOrder,
              rotationDeg: newRot,
              sizeLevel: paper.sizeLevel,
              localVertices: newVerts,
              localHoles: const [],
            );
          })
          .toList();
    }

    // Rotation copy preview
    if (_craftingMode == CraftingMode.rotationCopy &&
        _rotCopyGizmoActive &&
        _rotCopyCenterWorld != null &&
        _rotCopyAngleDeg.abs() > 1e-4 &&
        _selectedPaperIds.isNotEmpty) {
      final cx = _rotCopyCenterWorld!.dx;
      final cy = _rotCopyCenterWorld!.dy;
      final rad = _rotCopyAngleDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);

      return _placedPapers
          .where((p) => _selectedPaperIds.contains(p.id) && !p.locked)
          .map((paper) {
            final dx = paper.position.x - cx;
            final dy = paper.position.y - cy;
            return PlacedPaper(
              id: 'ghost_${paper.id}',
              paperColor: paper.paperColor,
              position: Vector3(
                cx + dx * cosA - dy * sinA,
                cy + dx * sinA + dy * cosA,
                paper.position.z,
              ),
              stackOrder: paper.stackOrder,
              rotationDeg: (paper.rotationDeg + _rotCopyAngleDeg) % 360,
              sizeLevel: paper.sizeLevel,
              localVertices: paper.localVertices != null
                  ? List<Offset>.from(paper.localVertices!)
                  : null,
              localHoles: paper.localHoles
                  .map((h) => List<Offset>.from(h))
                  .toList(),
            );
          })
          .toList();
    }

    return const [];
  }

  Widget _buildSelectionMarquee(
    List<PlacedPaper> selectedPapers,
    Size viewportSize,
  ) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final paper in selectedPapers) {
      for (final c in _paperWorldCorners(paper)) {
        final s = _worldToScreen(c, viewportSize);
        if (s.dx < minX) minX = s.dx;
        if (s.dy < minY) minY = s.dy;
        if (s.dx > maxX) maxX = s.dx;
        if (s.dy > maxY) maxY = s.dy;
      }
    }

    const pad = 10.0;
    const labelH = 22.0;
    const gap = 4.0;
    final boxW = (maxX - minX) + pad * 2;
    final boxH = (maxY - minY) + pad * 2;

    return Positioned(
      left: minX - pad,
      top: minY - pad,
      width: boxW,
      height: boxH + gap + labelH,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: boxW,
              height: boxH,
              child: CustomPaint(
                painter: _DashedRectPainter(
                  color: Colors.cyanAccent.withValues(alpha: 0.5),
                  strokeWidth: 1.0,
                  dashLen: 3.0,
                  gapLen: 3.0,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: boxH + gap,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${selectedPapers.length} selected',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotCopyGizmo(Size viewportSize) {
    final center = _rotCopyCenterWorld!;
    final screenCenter = _worldToScreen(
      Vector3(center.dx, center.dy, _paperZ),
      viewportSize,
    );
    return RotationGizmo(
      center: screenCenter,
      rotationDeg: _rotCopyAngleDeg,
      objectName: 'Copy angle',
      screenRefAngle: 0,
      rotationSign: -1.0,
      onRotationChanged: (deg) {
        setState(() => _rotCopyAngleDeg = deg);
      },
      onDismiss: () {
        if (_rotCopyAngleDeg.abs() > 1e-4) {
          _applyRotationCopy(_rotCopyAngleDeg);
        } else {
          setState(() {
            _rotCopyCenterWorld = null;
            _rotCopyGizmoActive = false;
            _rotCopyAngleDeg = 0;
          });
        }
      },
    );
  }

  Widget _buildSinglePaperOverlay(PlacedPaper paper, Size viewportSize) {
    final screenCenter = _worldToScreen(paper.position, viewportSize);

    if (paper.locked) {
      return ObjectRadialMenu(
        center: screenCenter,
        title: 'Matched — ${paper.paperColor.label} Piece',
        actions: [
          RadialAction(
            icon: Icons.refresh,
            label: 'Rotate',
            tint: const Color(0xFFFFD54F),
            onTap: () {
              _pushUndo('Rotate');
              setState(() => _isRotationGizmoActive = true);
            },
          ),
          _invertSelectionAction(),
        ],
      );
    }

    if (_isRotationGizmoActive) {
      return RotationGizmo(
        center: screenCenter,
        rotationDeg: paper.rotationDeg,
        objectName: paper.paperColor.label,
        screenRefAngle: 0,
        rotationSign: -1.0,
        onRotationChanged: (deg) {
          setState(() => paper.rotationDeg = deg);
        },
        onDismiss: () {
          setState(() => _isRotationGizmoActive = false);
          _scheduleCheck();
        },
      );
    }

    final isCutPiece = paper.localVertices != null;
    const sizeLabels = {1: '6×6', 2: '12×12', 3: '18×18'};
    final title = isCutPiece
        ? '${paper.paperColor.label} Piece  ${paper.rotationDeg.round()}°'
        : '${paper.paperColor.label} Paper ${sizeLabels[paper.sizeLevel]}  ${paper.rotationDeg.round()}°';

    final actions = <RadialAction>[
      RadialAction(
        icon: Icons.refresh,
        label: 'Rotate',
        tint: const Color(0xFFFFD54F),
        onTap: () {
          _pushUndo('Rotate');
          setState(() => _isRotationGizmoActive = true);
        },
      ),
      RadialAction(
        icon: Icons.open_in_full,
        label: 'xform',
        tint: const Color(0xFF4FC3F7),
        side: RadialActionSide.bottom,
        onTap: () => _startTransform(paper),
      ),
      RadialAction(
        icon: Icons.delete_outline,
        label: 'Discard',
        tint: const Color(0xFF90A4AE),
        side: RadialActionSide.bottomLeft,
        onTap: () => _returnPaperToInventory(paper.id),
      ),
    ];

    if (_kPaperSizeControlsEnabled && !isCutPiece && paper.sizeLevel < 3) {
      actions.add(
        RadialAction(
          icon: Icons.add,
          label: 'Size +',
          tint: const Color(0xFF81C784),
          onTap: () {
            _pushUndo('Resize');
            setState(() => paper.sizeLevel++);
          },
        ),
      );
    }
    if (_kPaperSizeControlsEnabled && !isCutPiece && paper.sizeLevel > 1) {
      actions.add(
        RadialAction(
          icon: Icons.remove,
          label: 'Size -',
          tint: const Color(0xFF81C784),
          onTap: () {
            _pushUndo('Resize');
            setState(() => paper.sizeLevel--);
          },
        ),
      );
    }

    actions.add(_invertSelectionAction());
    actions.add(_copySelectionAction());
    actions.add(_opsLockAction([paper]));

    return ObjectRadialMenu(
      center: screenCenter,
      title: title,
      actions: actions,
    );
  }

  Widget _buildMultiPaperOverlay(
    List<PlacedPaper> selectedPapers,
    Size viewportSize,
  ) {
    final centroid = _collectiveCentroid();
    final screenCenter = _worldToScreen(centroid, viewportSize);

    if (_isRotationGizmoActive) {
      return RotationGizmo(
        center: screenCenter,
        rotationDeg: _multiRotationBaseDeg,
        objectName: '${selectedPapers.length} items',
        screenRefAngle: 0,
        rotationSign: -1.0,
        onRotationChanged: (newDeg) {
          final deltaDeg = newDeg - _multiRotationBaseDeg;
          final deltaRad = deltaDeg * math.pi / 180;
          final cx = centroid.x;
          final cy = centroid.y;
          setState(() {
            for (final paper in selectedPapers) {
              final basePosVec = _basePositions[paper.id];
              final baseRot = _baseRotations[paper.id];
              if (basePosVec == null || baseRot == null) continue;
              final dx = basePosVec.x - cx;
              final dy = basePosVec.y - cy;
              paper.position.x =
                  cx + dx * math.cos(deltaRad) - dy * math.sin(deltaRad);
              paper.position.y =
                  cy + dx * math.sin(deltaRad) + dy * math.cos(deltaRad);
              paper.rotationDeg = (baseRot + deltaDeg) % 360;
            }
          });
        },
        onDismiss: () {
          setState(() => _isRotationGizmoActive = false);
          _scheduleCheck();
        },
      );
    }

    // Determine if all selected share the same groupId
    final groupIds = selectedPapers
        .map((p) => p.groupId)
        .where((g) => g != null)
        .toSet();
    final allSameGroup =
        groupIds.length == 1 && selectedPapers.every((p) => p.groupId != null);

    final actions = <RadialAction>[
      RadialAction(
        icon: Icons.refresh,
        label: 'Rotate',
        tint: const Color(0xFFFFD54F),
        onTap: () {
          _pushUndo('Rotate');
          setState(() {
            _multiRotationBaseDeg = 0;
            _baseRotations = {
              for (final p in selectedPapers) p.id: p.rotationDeg,
            };
            _basePositions = {
              for (final p in selectedPapers) p.id: p.position.clone(),
            };
            _isRotationGizmoActive = true;
          });
        },
      ),
    ];

    if (allSameGroup) {
      actions.add(
        RadialAction(
          icon: Icons.link_off,
          label: 'Ungroup',
          tint: const Color(0xFF42A5F5),
          onTap: _ungroupSelectedPapers,
        ),
      );
    } else {
      actions.add(
        RadialAction(
          icon: Icons.link,
          label: 'Group',
          tint: const Color(0xFF42A5F5),
          onTap: _groupSelectedPapers,
        ),
      );
    }

    actions.add(
      RadialAction(
        icon: Icons.merge,
        label: 'Join',
        tint: const Color(0xFF66BB6A),
        onTap: _joinSelectedPapers,
      ),
    );

    actions.add(
      RadialAction(
        icon: Icons.delete_outline,
        label: 'Discard',
        tint: const Color(0xFF90A4AE),
        side: RadialActionSide.bottomLeft,
        onTap: _discardSelectedPapers,
      ),
    );
    actions.add(_invertSelectionAction());
    actions.add(_copySelectionAction());
    actions.add(_opsLockAction(selectedPapers));

    return ObjectRadialMenu(
      center: screenCenter,
      title: '${selectedPapers.length} items selected',
      actions: actions,
    );
  }

  /// Groups simple face polygons into compound shapes: each exterior paired
  /// with any holes it contains. Faces whose signed area has opposite winding
  /// to the largest face are treated as candidate holes.
  static List<(List<Offset>, List<List<Offset>>)> _classifyCompoundFaces(
    List<List<Offset>> faces,
  ) {
    if (faces.isEmpty) return [];

    final areas = faces.map(_signedAreaOf).toList();

    // Determine dominant winding: the largest-area face is an exterior.
    double maxAbsArea = 0;
    double dominantSign = 1;
    for (final a in areas) {
      if (a.abs() > maxAbsArea) {
        maxAbsArea = a.abs();
        dominantSign = a >= 0 ? 1 : -1;
      }
    }

    final exteriors = <int>[];
    final holes = <int>[];
    for (var i = 0; i < faces.length; i++) {
      if (areas[i] * dominantSign > 0) {
        exteriors.add(i);
      } else {
        holes.add(i);
      }
    }

    // Sort exteriors smallest-area-first for containment matching.
    exteriors.sort((a, b) => areas[a].abs().compareTo(areas[b].abs()));

    final holeAssignment = <int, List<List<Offset>>>{
      for (final e in exteriors) e: [],
    };

    for (final hi in holes) {
      final holePoly = faces[hi];
      final sample = holePoly.first;
      for (final ei in exteriors) {
        if (_pointInPolygon(sample, faces[ei])) {
          holeAssignment[ei]!.add(holePoly);
          break;
        }
      }
      // Holes that don't land inside any exterior are discarded (duplicates
      // from the reverse walk).
    }

    return [for (final ei in exteriors) (faces[ei], holeAssignment[ei]!)];
  }

  static double _signedAreaOf(List<Offset> polygon) {
    var area = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      area += polygon[i].dx * polygon[j].dy;
      area -= polygon[j].dx * polygon[i].dy;
    }
    return area / 2;
  }

  static Offset _polygonCentroid(List<Offset> polygon) {
    double cx = 0, cy = 0, area = 0;
    for (int i = 0; i < polygon.length; i++) {
      final j = (i + 1) % polygon.length;
      final cross =
          polygon[i].dx * polygon[j].dy - polygon[j].dx * polygon[i].dy;
      area += cross;
      cx += (polygon[i].dx + polygon[j].dx) * cross;
      cy += (polygon[i].dy + polygon[j].dy) * cross;
    }
    area /= 2;
    if (area.abs() < 1e-10) {
      return polygon.reduce((a, b) => a + b) / polygon.length.toDouble();
    }
    return Offset(cx / (6 * area), cy / (6 * area));
  }

  // ---------------------------------------------------------------------------
  // Paint tool: fuse painted cells into PlacedPaper(s)
  // ---------------------------------------------------------------------------

  /// Find 4-connected components in a set of grid cells.
  static List<Set<(int, int)>> _connectedComponents(Set<(int, int)> cells) {
    final remaining = Set<(int, int)>.from(cells);
    final components = <Set<(int, int)>>[];
    while (remaining.isNotEmpty) {
      final seed = remaining.first;
      final component = <(int, int)>{};
      final queue = [seed];
      remaining.remove(seed);
      while (queue.isNotEmpty) {
        final c = queue.removeLast();
        component.add(c);
        for (final n in [
          (c.$1 + 1, c.$2),
          (c.$1 - 1, c.$2),
          (c.$1, c.$2 + 1),
          (c.$1, c.$2 - 1),
        ]) {
          if (remaining.remove(n)) queue.add(n);
        }
      }
      components.add(component);
    }
    return components;
  }

  /// Build boundary polygon(s) from a connected set of grid cells using
  /// directed-edge chaining. Returns (exterior, holes) with exterior wound CCW
  /// and holes wound CW in world space.
  (List<Offset>, List<List<Offset>>) _boundaryPolygons(Set<(int, int)> cells) {
    final s = _activeGridSpacing;

    Offset gridToWorld(int gx, int gy) => _gridToWorld(gx * s, gy * s);

    // Collect directed boundary edges. For a cell (c,r), its boundary edges
    // (with exterior to the left of the direction) are:
    //   bottom  (no neighbour below):  (c, r)   -> (c+1, r)
    //   right   (no neighbour right):  (c+1, r) -> (c+1, r+1)
    //   top     (no neighbour above):  (c+1, r+1) -> (c, r+1)
    //   left    (no neighbour left):   (c, r+1) -> (c, r)
    final edges = <((int, int), (int, int))>[];
    for (final (c, r) in cells) {
      if (!cells.contains((c, r - 1))) edges.add(((c, r), (c + 1, r)));
      if (!cells.contains((c + 1, r))) edges.add(((c + 1, r), (c + 1, r + 1)));
      if (!cells.contains((c, r + 1))) edges.add(((c + 1, r + 1), (c, r + 1)));
      if (!cells.contains((c - 1, r))) edges.add(((c, r + 1), (c, r)));
    }

    // Build adjacency: from-vertex -> list of to-vertices.
    final adj = <(int, int), List<(int, int)>>{};
    for (final (from, to) in edges) {
      (adj[from] ??= []).add(to);
    }

    // Chain into closed loops.
    final used = <((int, int), (int, int))>{};
    final loops = <List<Offset>>[];
    for (final (from, to) in edges) {
      if (used.contains((from, to))) continue;
      final loop = <Offset>[];
      var cur = from;
      var nxt = to;
      while (true) {
        used.add((cur, nxt));
        loop.add(gridToWorld(cur.$1, cur.$2));
        final candidates = adj[nxt];
        if (candidates == null) break;
        (int, int)? next;
        for (final c in candidates) {
          if (!used.contains((nxt, c))) {
            next = c;
            break;
          }
        }
        if (next == null) break;
        cur = nxt;
        nxt = next;
        if (cur == from && nxt == to) break;
      }
      if (loop.length >= 3) loops.add(loop);
    }

    if (loops.isEmpty) return (const [], const []);

    // Classify: largest absolute area is the exterior.
    int extIdx = 0;
    double maxArea = 0;
    for (var i = 0; i < loops.length; i++) {
      final a = _signedAreaOf(loops[i]).abs();
      if (a > maxArea) {
        maxArea = a;
        extIdx = i;
      }
    }

    var exterior = loops[extIdx];
    // Ensure exterior is CCW (positive signed area).
    if (_signedAreaOf(exterior) < 0) exterior = exterior.reversed.toList();

    final holes = <List<Offset>>[];
    for (var i = 0; i < loops.length; i++) {
      if (i == extIdx) continue;
      var hole = loops[i];
      // Ensure holes are CW (negative signed area).
      if (_signedAreaOf(hole) > 0) hole = hole.reversed.toList();
      holes.add(hole);
    }

    return (exterior, holes);
  }

  void _applyErase() {
    final cells = Set<(int, int)>.from(_erasedCells);
    setState(() {
      _erasedCells = {};
      _lastEraseCell = null;
    });
    if (cells.isEmpty) return;

    _pushUndo('Erase');

    // Determine which papers overlap the erased cells.
    final papersToRemove = <int>[];
    final papersToAdd = <PlacedPaper>[];

    for (var i = 0; i < _placedPapers.length; i++) {
      final paper = _placedPapers[i];
      if (_isToolProtected(paper)) continue;

      final paperCells = _rasterizePaperToCells(paper);
      if (paperCells.isEmpty) continue;

      final overlap = paperCells.intersection(cells);
      if (overlap.isEmpty) continue;

      final remaining = paperCells.difference(cells);
      papersToRemove.add(i);

      if (remaining.isEmpty) continue;

      // Rebuild paper(s) from remaining cells.
      final rebuilt = <({List<Offset> ext, List<List<Offset>> holes})>[];
      for (final comp in _connectedComponents(remaining)) {
        final (ext, holes) = _boundaryPolygons(comp);
        if (ext.length < 3) continue;
        rebuilt.add((ext: ext, holes: holes));
      }
      final orders = _allocateSplitOrders(paper.stackOrder, rebuilt.length);
      for (var ri = 0; ri < rebuilt.length; ri++) {
        final ext = rebuilt[ri].ext;
        final holes = rebuilt[ri].holes;
        final centroid = _polygonCentroid(ext);
        final shifted = ext.map((v) => v - centroid).toList();
        final shiftedHoles = holes
            .where((h) => h.length >= 3)
            .map((h) => h.map((v) => v - centroid).toList())
            .toList();

        papersToAdd.add(
          PlacedPaper(
            id: 'paper_${_nextPaperId++}',
            paperColor: paper.paperColor,
            position: Vector3(centroid.dx, centroid.dy, paper.position.z),
            stackOrder: orders[ri],
            rotationDeg: 0,
            sizeLevel: paper.sizeLevel,
            localVertices: shifted,
            localHoles: shiftedHoles,
          ),
        );
      }
    }

    if (papersToRemove.isNotEmpty || papersToAdd.isNotEmpty) {
      setState(() {
        for (final idx in papersToRemove.reversed) {
          _selectedPaperIds.remove(_placedPapers[idx].id);
          _placedPapers.removeAt(idx);
        }
        _syncCopyMemoryWithSelection();
        _placedPapers.addAll(papersToAdd);
        _isRotationGizmoActive = false;
      });
      _scheduleCheck();
    }
  }

  void _fusePaintedCells() {
    final cells = Set<(int, int)>.from(_paintedCells);
    setState(() {
      _paintedCells = {};
      _lastPaintCell = null;
    });

    if (cells.isEmpty) return;
    _pushUndo('Paint');

    // Consume material from structure inventory (1 unit per cell painted)
    String? materialId;
    if (_useStructureInventory) {
      materialId =
          _paintMaterialId ?? _structureInventory!.contents.keys.firstOrNull;
      if (materialId == null) return;
      final available = _structureInventory!.get(materialId);
      final toConsume = cells.length.clamp(0, available);
      if (toConsume == 0) return;
      _structureInventory!.remove(materialId, toConsume);
      // Only paint cells we can afford
      if (toConsume < cells.length) {
        final cellList = cells.toList();
        cells.clear();
        cells.addAll(cellList.take(toConsume));
      }
    }

    final papersToRemove = <int>[];
    final absorbedPapers = <PlacedPaper>[];

    if (_paintFusionEnabled) {
      final paintedWithNeighbours = <(int, int)>{};
      for (final (c, r) in cells) {
        paintedWithNeighbours
          ..add((c, r))
          ..add((c + 1, r))
          ..add((c - 1, r))
          ..add((c, r + 1))
          ..add((c, r - 1));
      }

      for (var i = 0; i < _placedPapers.length; i++) {
        final paper = _placedPapers[i];
        if (_isToolProtected(paper)) continue;
        if (paper.isBlueprintMatched) continue;

        final paperCells = _rasterizePaperToCells(paper);
        if (paperCells.isEmpty) continue;

        if (paperCells.any((pc) => paintedWithNeighbours.contains(pc))) {
          papersToRemove.add(i);
          absorbedPapers.add(paper);
        }
      }
    }

    // Build painted boundary polygon(s) from the grid cells.
    final paintedComponents = _connectedComponents(cells);
    final paintedPolygons = <List<Offset>>[];
    final paintedHoles = <List<Offset>>[];
    for (final comp in paintedComponents) {
      final (ext, holes) = _boundaryPolygons(comp);
      if (ext.isNotEmpty) paintedPolygons.add(ext);
      paintedHoles.addAll(holes);
    }

    if (absorbedPapers.isEmpty) {
      // No papers to fuse with -- create papers directly from painted cells.
      final newPapers = <PlacedPaper>[];
      for (var i = 0; i < paintedPolygons.length; i++) {
        final ext = paintedPolygons[i];
        final centroid = _polygonCentroid(ext);
        final shifted = ext.map((v) => v - centroid).toList();
        final holeShifted = paintedHoles
            .where((h) => _pointInPolygon(_polygonCentroid(h), ext))
            .map((h) => h.map((v) => v - centroid).toList())
            .toList();
        newPapers.add(
          PlacedPaper(
            id: 'paper_${_nextPaperId++}',
            paperColor: _paintColor,
            position: Vector3(centroid.dx, centroid.dy, _paperZ),
            stackOrder: _allocateStackMajor(),
            rotationDeg: 0,
            sizeLevel: 1,
            localVertices: shifted,
            localHoles: holeShifted,
            materialId: materialId,
          ),
        );
      }
      if (newPapers.isNotEmpty) {
        setState(() {
          _placedPapers.addAll(newPapers);
          _selectedPaperIds = {};
          _isRotationGizmoActive = false;
        });
        _scheduleCheck();
      }
      return;
    }

    // Collect all exterior polygons for the union (exact world-space geometry).
    final allExteriors = <List<Offset>>[...paintedPolygons];
    final allOriginalHoles = <List<Offset>>[...paintedHoles];
    for (final paper in absorbedPapers) {
      allExteriors.add(_paperWorldPolygon2D(paper));
      allOriginalHoles.addAll(_paperWorldHoles2D(paper));
    }

    // Compute the exact polygon union of painted boundaries + paper polygons.
    final unionLoops = unionPolygons(allExteriors);
    if (unionLoops.isEmpty) return;

    // Classify union loops into (exterior, holes) groups.
    final classified = _classifyCompoundFaces(unionLoops);

    // Re-check which original holes survive: centroid still inside the union
    // exterior and not filled by any other exterior polygon.
    final survivingHoles = <List<Offset>>[];
    for (final hole in allOriginalHoles) {
      final holeCentroid = _polygonCentroid(hole);
      bool insideAnyExterior = false;
      for (final (ext, _) in classified) {
        if (_pointInPolygon(holeCentroid, ext)) {
          insideAnyExterior = true;
          break;
        }
      }
      if (!insideAnyExterior) continue;
      // Only keep the hole if it's not filled by any input exterior.
      bool filledByExterior = false;
      for (final ext in allExteriors) {
        if (_pointInPolygon(holeCentroid, ext)) {
          filledByExterior = true;
          break;
        }
      }
      if (!filledByExterior) survivingHoles.add(hole);
    }

    final newPapers = <PlacedPaper>[];
    for (final (exterior, unionHoles) in classified) {
      if (exterior.length < 3) continue;
      // Merge holes from the union classification with surviving original holes
      // that belong to this exterior.
      final mergedHoles = <List<Offset>>[...unionHoles];
      for (final sh in survivingHoles) {
        if (_pointInPolygon(_polygonCentroid(sh), exterior)) {
          mergedHoles.add(sh);
        }
      }

      final centroid = _polygonCentroid(exterior);
      final shifted = exterior.map((v) => v - centroid).toList();
      final shiftedHoles = mergedHoles
          .map((h) => h.map((v) => v - centroid).toList())
          .toList();

      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: _paintColor,
          position: Vector3(centroid.dx, centroid.dy, _paperZ),
          stackOrder: _allocateStackMajor(),
          rotationDeg: 0,
          sizeLevel: 1,
          localVertices: shifted,
          localHoles: shiftedHoles,
          materialId: materialId,
        ),
      );
    }

    if (newPapers.isNotEmpty || papersToRemove.isNotEmpty) {
      setState(() {
        for (final idx in papersToRemove.reversed) {
          _selectedPaperIds.remove(_placedPapers[idx].id);
          _placedPapers.removeAt(idx);
        }
        _placedPapers.addAll(newPapers);
        _selectedPaperIds = {};
        _isRotationGizmoActive = false;
      });
      _scheduleCheck();
    }
  }

  // ---------------------------------------------------------------------------
  // Cut application (line-based)
  // ---------------------------------------------------------------------------

  void _applyCuts() {
    if (_drawnCutLines.isEmpty) return;
    _pushUndo('Cut');

    setState(() {
      final papersToRemove = <int>[];
      final papersToAdd = <PlacedPaper>[];

      for (var pi = 0; pi < _placedPapers.length; pi++) {
        final paper = _placedPapers[pi];
        if (_isToolProtected(paper)) continue;

        final rad = paper.rotationDeg * math.pi / 180;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        final cx = paper.position.x;
        final cy = paper.position.y;

        Offset toLocal(double wx, double wy) {
          final dx0 = wx - cx;
          final dy0 = wy - cy;
          return Offset(dx0 * cosA + dy0 * sinA, -dx0 * sinA + dy0 * cosA);
        }

        final polygon = _paperLocalVertices(paper);

        final newSegments = <(Offset, Offset)>[];
        for (final line in _drawnCutLines) {
          final la = toLocal(line.$1.dx, line.$1.dy);
          final lb = toLocal(line.$2.dx, line.$2.dy);
          newSegments.add((la, lb));
        }

        // Accumulate: append new segments to existing ones.
        final allSegments = <(Offset, Offset)>[
          ...paper.cutSegments,
          ...newSegments,
        ];

        final pieces = splitPaperByCuts(
          polygon,
          allSegments,
          holes: paper.localHoles,
        );
        final split = pieces.length > 1 ||
            (pieces.length == 1 &&
                pieces.first.$2.length != paper.localHoles.length);

        if (split) {
          papersToRemove.add(pi);
          final orders = _allocateSplitOrders(paper.stackOrder, pieces.length);
          for (var ci = 0; ci < pieces.length; ci++) {
            final (exterior, holes) = pieces[ci];
            final centroid = _polygonCentroid(exterior);
            final shifted = exterior.map((v) => v - centroid).toList();
            final shiftedHoles = holes
                .map((h) => h.map((v) => v - centroid).toList())
                .toList();
            final wcx = cx + centroid.dx * cosA - centroid.dy * sinA;
            final wcy = cy + centroid.dx * sinA + centroid.dy * cosA;
            papersToAdd.add(
              PlacedPaper(
                id: 'paper_${_nextPaperId++}',
                paperColor: paper.paperColor,
                position: Vector3(wcx, wcy, paper.position.z),
                stackOrder: orders[ci],
                rotationDeg: paper.rotationDeg,
                sizeLevel: paper.sizeLevel,
                localVertices: shifted,
                localHoles: shiftedHoles,
                groupId: paper.groupId,
              ),
            );
          }
        } else {
          paper.cutSegments
            ..clear()
            ..addAll(allSegments);
        }
      }

      for (final idx in papersToRemove.reversed) {
        _placedPapers.removeAt(idx);
      }
      _placedPapers.addAll(papersToAdd);
      if (papersToRemove.isNotEmpty) {
        _selectedPaperIds = {};
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Copy tools: mirror, rotation, translation
  // ---------------------------------------------------------------------------

  /// Reflect a 2D point across the line from [a] to [b].
  static Offset _reflectPoint(Offset p, Offset a, Offset b) {
    final d = b - a;
    final lenSq = d.dx * d.dx + d.dy * d.dy;
    if (lenSq < 1e-12) return p;
    final v = p - a;
    final t = (v.dx * d.dx + v.dy * d.dy) / lenSq;
    final proj = Offset(a.dx + t * d.dx, a.dy + t * d.dy);
    return Offset(2 * proj.dx - p.dx, 2 * proj.dy - p.dy);
  }

  void _applyMirrorCopy(Offset lineA, Offset lineB) {
    if (_selectedPaperIds.isEmpty) return;

    final lineAngle =
        math.atan2(lineB.dy - lineA.dy, lineB.dx - lineA.dx) * 180 / math.pi;
    final newPapers = <PlacedPaper>[];

    for (final paper in _placedPapers) {
      if (!_selectedPaperIds.contains(paper.id)) continue;
      if (paper.locked) continue;

      final origPos = Offset(paper.position.x, paper.position.y);
      final reflected = _reflectPoint(origPos, lineA, lineB);

      // Reflection negates rotation relative to the mirror line.
      final newRot = (2 * lineAngle - paper.rotationDeg) % 360;

      // Reflect and reverse-wind local vertices so winding stays consistent.
      List<Offset>? newVerts;
      if (paper.localVertices != null) {
        final rad = paper.rotationDeg * math.pi / 180;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);

        final worldVerts = paper.localVertices!.map((o) {
          return Offset(
            origPos.dx + o.dx * cosA - o.dy * sinA,
            origPos.dy + o.dx * sinA + o.dy * cosA,
          );
        }).toList();

        final reflectedWorld = worldVerts
            .map((v) => _reflectPoint(v, lineA, lineB))
            .toList();

        final newRad = newRot * math.pi / 180;
        final cosB = math.cos(newRad);
        final sinB = math.sin(newRad);

        newVerts = reflectedWorld.reversed.map((w) {
          final dx0 = w.dx - reflected.dx;
          final dy0 = w.dy - reflected.dy;
          return Offset(dx0 * cosB + dy0 * sinB, -dx0 * sinB + dy0 * cosB);
        }).toList();
      }

      List<List<Offset>> newHoles = const [];
      if (paper.localHoles.isNotEmpty) {
        final rad = paper.rotationDeg * math.pi / 180;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        final newRad = newRot * math.pi / 180;
        final cosB = math.cos(newRad);
        final sinB = math.sin(newRad);

        newHoles = paper.localHoles.map((hole) {
          final worldHole = hole.map((o) {
            return Offset(
              origPos.dx + o.dx * cosA - o.dy * sinA,
              origPos.dy + o.dx * sinA + o.dy * cosA,
            );
          }).toList();
          final reflectedHole = worldHole
              .map((v) => _reflectPoint(v, lineA, lineB))
              .toList();
          return reflectedHole.reversed.map((w) {
            final dx0 = w.dx - reflected.dx;
            final dy0 = w.dy - reflected.dy;
            return Offset(dx0 * cosB + dy0 * sinB, -dx0 * sinB + dy0 * cosB);
          }).toList();
        }).toList();
      }

      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: paper.paperColor,
          position: Vector3(reflected.dx, reflected.dy, paper.position.z),
          stackOrder: _allocateStackMajor(),
          rotationDeg: newRot,
          sizeLevel: paper.sizeLevel,
          localVertices: newVerts,
          localHoles: newHoles,
        ),
      );
    }

    if (newPapers.isNotEmpty) {
      _pushUndo('Mirror copy');
      setState(() {
        _placedPapers.addAll(newPapers);
        _selectedPaperIds = newPapers.map((p) => p.id).toSet();
        _isRotationGizmoActive = false;
        _craftingMode = CraftingMode.select;
      });
      _scheduleCheck();
    }
  }

  void _applyRotationCopy(double angleDeg) {
    if (_selectedPaperIds.isEmpty || _rotCopyCenterWorld == null) return;
    if (angleDeg.abs() < 1e-4) return;

    final cx = _rotCopyCenterWorld!.dx;
    final cy = _rotCopyCenterWorld!.dy;
    final rad = angleDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);

    final newPapers = <PlacedPaper>[];
    for (final paper in _placedPapers) {
      if (!_selectedPaperIds.contains(paper.id)) continue;
      if (paper.locked) continue;

      final dx = paper.position.x - cx;
      final dy = paper.position.y - cy;
      final newX = cx + dx * cosA - dy * sinA;
      final newY = cy + dx * sinA + dy * cosA;
      final newRot = (paper.rotationDeg + angleDeg) % 360;

      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: paper.paperColor,
          position: Vector3(newX, newY, paper.position.z),
          stackOrder: _allocateStackMajor(),
          rotationDeg: newRot,
          sizeLevel: paper.sizeLevel,
          localVertices: paper.localVertices != null
              ? List<Offset>.from(paper.localVertices!)
              : null,
          localHoles: paper.localHoles
              .map((h) => List<Offset>.from(h))
              .toList(),
        ),
      );
    }

    if (newPapers.isNotEmpty) {
      _pushUndo('Rotation copy');
      setState(() {
        _placedPapers.addAll(newPapers);
        _selectedPaperIds = newPapers.map((p) => p.id).toSet();
        _isRotationGizmoActive = false;
        _rotCopyCenterWorld = null;
        _rotCopyGizmoActive = false;
        _rotCopyAngleDeg = 0;
        _craftingMode = CraftingMode.select;
      });
      _scheduleCheck();
    }
  }

  // ---------------------------------------------------------------------------
  // Inventory bar
  // ---------------------------------------------------------------------------

  Widget _buildBottomControlColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedBlueprint != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUnionToggle(),
              const SizedBox(width: 8),
              _buildFillAllButton(),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _buildUndoRedoBar(),
        const SizedBox(height: 8),
        _buildInventoryBar(),
      ],
    );
  }

  Widget _buildUndoRedoBar() {
    return ListenableBuilder(
      listenable: _history,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.undo, size: 22),
                color: _history.canUndo ? Colors.white : Colors.white24,
                tooltip: 'Undo',
                onPressed: _history.canUndo ? _undo : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${_history.operativeActionCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.redo, size: 22),
                color: _history.canRedo ? Colors.white : Colors.white24,
                tooltip: 'Redo',
                onPressed: _history.canRedo ? _redo : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Inventory bar
  // ---------------------------------------------------------------------------

  Widget _buildInventoryBar() {
    if (_useStructureInventory) {
      return _buildMaterialInventoryBar();
    }
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < PaperColor.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildInventorySlot(
              PaperColor.values[i],
              _inventory[PaperColor.values[i]] ?? 0,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialInventoryBar() {
    final contents = _structureInventory!.contents;
    if (contents.isEmpty) {
      return Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'No materials',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      );
    }
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < contents.entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildMaterialSlot(
              contents.entries.elementAt(i).key,
              contents.entries.elementAt(i).value,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialSlot(String materialId, int count) {
    final color = _materialRegistry.colorFor(materialId);
    final isEmpty = count < CraftingMaterial.pixelsPerSheet;
    const slotSize = 48.0;

    final child = Container(
      width: slotSize,
      height: slotSize,
      decoration: BoxDecoration(
        color: isEmpty ? color.withOpacity(0.15) : color.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEmpty ? Colors.white.withOpacity(0.1) : color,
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            left: 2,
            bottom: 2,
            right: 2,
            child: Text(
              _materialRegistry.labelFor(materialId),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 7,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (isEmpty) return child;

    return Draggable<String>(
      data: materialId,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: slotSize * 1.2,
            height: slotSize * 1.2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 12),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        width: slotSize,
        height: slotSize,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
        ),
      ),
      child: child,
    );
  }

  Widget _buildInventorySlot(PaperColor paperColor, int count) {
    final isEmpty = count <= 0;
    const slotSize = 48.0;

    final child = Container(
      width: slotSize,
      height: slotSize,
      decoration: BoxDecoration(
        color: isEmpty
            ? paperColor.color.withOpacity(0.15)
            : paperColor.color.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEmpty ? Colors.white.withOpacity(0.1) : paperColor.color,
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          if (count > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (isEmpty) return child;

    return Draggable<PaperColor>(
      data: paperColor,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: Container(
            width: slotSize * 1.2,
            height: slotSize * 1.2,
            decoration: BoxDecoration(
              color: paperColor.color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: paperColor.color.withOpacity(0.4),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        width: slotSize,
        height: slotSize,
        decoration: BoxDecoration(
          color: paperColor.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Selection marquee dashed-rect painter
// ---------------------------------------------------------------------------

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLen = 3.0,
    this.gapLen = 3.0,
  });

  final Color color;
  final double strokeWidth;
  final double dashLen;
  final double gapLen;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final path = Path()..addRect(Offset.zero & size);
    final total = dashLen + gapLen;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += total;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      color != old.color ||
      strokeWidth != old.strokeWidth ||
      dashLen != old.dashLen ||
      gapLen != old.gapLen;
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class CraftingTestPainter extends CustomPainter {
  CraftingTestPainter({
    required this.geometry,
    required this.objectRotation,
    required this.objectPosition,
    required this.objectColor,
    this.friendVisible = false,
    required this.drawingPlaneSize,
    required this.orthoScale,
    this.panOffset = Offset.zero,
    this.viewRotation = 0,
    this.canvasDisplayMode = CanvasDisplayMode.grid,
    this.showMinorLines = true,
    this.papers = const [],
    this.selectedPaperIds = const {},
    this.friendExpression,
    this.eyeGeometry3d = FriendEyeGeometry3d.sphere,
    this.blueprintPolygons = const [],
    this.filledBlueprintIndices = const {},
    this.groupOverlayPolygons = const [],
    this.groupOverlayColors = const [],
    this.activeHighlightT = 1.0,
    this.activeGlow = 0.0,
    this.loadAnimT = 1.0,
    this.hideUnfilledBlueprint = false,
    this.lockFadingPaperIds = const {},
    this.lockFadeT = 1.0,
    this.discardOpacityById = const {},
    this.marqueeRect,
    this.marqueeIsIntersect = false,
    this.marqueeDashOffset = 0,
    this.lockAnimatingPaperIds = const {},
    this.lockAnimProgress = 0,
    this.completionPhase = CompletionPhase.none,
    this.foldNodeStates = const {},
    this.foldDisplacementMatrix,
    this.foldColorProgress = 0,
    this.foldOpacity = 1.0,
    this.dotDissolveProgress,
    this.foldViewProjection,
    this.dotWipeOpacityAt,
    this.structureFootprint,
    this.drawnCutLines = const [],
    this.lineDrawStart,
    this.lineDrawPreview,
    this.cutHighlightEdges = const [],
    this.cutHighlightGlow = 0,
    this.cutSnapRay,
    this.craftingMode = CraftingMode.select,
    this.activeToolpath = const [],
    this.cutAnimProgress = 0,
    this.hideDrawingPlane = true,
    this.paintedCells = const {},
    this.paintColor,
    this.mirrorLineStart,
    this.mirrorLinePreview,
    this.ghostPapers = const [],
    this.rotCopyCenterWorld,
    this.erasedCells = const {},
    this.gridDivisions = 32,
    this.gridLodFrom = 0,
    this.gridLodTo = 0,
    this.gridLodFadeT = 1.0,
    this.activeGridSpacing,
    this.paperColorResolver,
    this.gridOriginOffset = Offset.zero,
    this.gridRotation = math.pi / 2,
    this.alignGridIndicator,
    this.alignGridAxisEnd,
    this.alignGridHighlightPolyIndex,
    this.stretchPaperId,
    this.stretchHandleIndex,
    this.stretchStartBounds,
    this.stretchDisplayBounds,
    this.gridRegionAssist = true,
    this.blueprintHoles = const [],
    this.stencilVisible = false,
    this.stencilShape = StencilShape.rectangle,
    this.stencilPosition = Offset.zero,
    this.stencilHalfW = 1,
    this.stencilHalfH = 1,
    this.stencilSelected = false,
    this.stencilHandleIndex,
  });

  final Geometry geometry;
  final Quaternion objectRotation;
  final Vector3 objectPosition;
  final Color objectColor;
  final bool friendVisible;
  final double drawingPlaneSize;
  final double orthoScale;
  final Offset panOffset;
  final double viewRotation;
  final CanvasDisplayMode canvasDisplayMode;
  final bool showMinorLines;
  final List<PlacedPaper> papers;
  final Set<String> selectedPaperIds;
  final FriendExpressionConfig? friendExpression;
  final FriendEyeGeometry3d eyeGeometry3d;
  final List<List<Offset>> blueprintPolygons;
  final Set<int> filledBlueprintIndices;
  final List<List<Offset>> groupOverlayPolygons;
  final List<Color> groupOverlayColors;
  final double activeHighlightT;
  final double activeGlow;
  final double loadAnimT;
  final bool hideUnfilledBlueprint;
  final Set<String> lockFadingPaperIds;
  final double lockFadeT;
  final Map<String, double> discardOpacityById;
  final Rect? marqueeRect;
  final bool marqueeIsIntersect;
  final double marqueeDashOffset;
  final Set<String> lockAnimatingPaperIds;
  final double lockAnimProgress;
  final CompletionPhase completionPhase;
  final Map<int, _FoldNodeState> foldNodeStates;
  final Matrix4? foldDisplacementMatrix;
  final double foldColorProgress;

  /// Opacity of the folding geometry (used while it fades in during reveal).
  final double foldOpacity;

  /// Random dot-dissolve progress (0..1); null disables the dissolve effect.
  final double? dotDissolveProgress;
  final Matrix4? foldViewProjection;
  final double Function(double normalizedPosition)? dotWipeOpacityAt;
  final Rect? structureFootprint;
  final List<(Offset, Offset)> drawnCutLines;
  final Offset? lineDrawStart;
  final Offset? lineDrawPreview;
  final List<(Offset, Offset)> cutHighlightEdges;
  final double cutHighlightGlow;
  final (Offset, Offset)? cutSnapRay;
  final CraftingMode craftingMode;
  final List<ToolpathSegment> activeToolpath;
  final double cutAnimProgress;
  final bool hideDrawingPlane;
  final Set<(int, int)> paintedCells;
  final PaperColor? paintColor;

  // Copy-tool overlays
  final Offset? mirrorLineStart;
  final Offset? mirrorLinePreview;
  final List<PlacedPaper> ghostPapers;
  final Offset? rotCopyCenterWorld;
  final Set<(int, int)> erasedCells;
  final int gridDivisions;
  final int gridLodFrom;
  final int gridLodTo;
  final double gridLodFadeT;
  final double? activeGridSpacing;
  final Color Function(PlacedPaper paper)? paperColorResolver;
  final Offset gridOriginOffset;

  /// World angle (radians) of the grid +Y axis.
  final double gridRotation;
  final Offset? alignGridIndicator;
  final Offset? alignGridAxisEnd;
  final int? alignGridHighlightPolyIndex;

  // Stretch gizmo
  final String? stretchPaperId;
  final int? stretchHandleIndex;
  final Rect? stretchStartBounds;
  final Rect? stretchDisplayBounds;
  final bool gridRegionAssist;
  final List<List<List<Offset>>> blueprintHoles;
  final bool stencilVisible;
  final StencilShape stencilShape;
  final Offset stencilPosition;
  final double stencilHalfW;
  final double stencilHalfH;
  final bool stencilSelected;
  final int? stencilHandleIndex;

  double get _effectiveGridSpacing =>
      activeGridSpacing ?? drawingPlaneSize / gridDivisions;

  double _gridSpacingForLod(int lod) {
    final base = drawingPlaneSize / gridDivisions;
    return base * math.pow(2, lod).toDouble();
  }

  double _paperHalfSizeForLevel(int level) =>
      level * drawingPlaneSize / 4 * _kPaperHalfExtentPerLevel;

  /// Stable pseudo-random value in [0, 1) for a grid dot at (i, j), used to
  /// stagger the dissolve so dots fade out in a scattered pattern.
  static double _dotDissolveThreshold(int i, int j) {
    var h = (i * 73856093) ^ (j * 19349663);
    h &= 0x7fffffff;
    return (h % 1000) / 1000.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final viewProjection = craftingTestViewProjection(
      size,
      orthoScale,
      panOffset: panOffset,
      viewRotation: viewRotation,
    );
    final camera = scene_camera.Camera(
      name: 'shadow-cam',
      position: Vector3(panOffset.dx, panOffset.dy, 500),
      target: Vector3(panOffset.dx, panOffset.dy, 0),
      up: Vector3(-math.sin(viewRotation), math.cos(viewRotation), 0),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: orthoScale,
      near: 0.1,
      far: 1500,
    );
    final view = camera.viewMatrix;

    final rotMatrix3 = objectRotation.asRotationMatrix();
    final world = Matrix4.identity()
      ..translate(objectPosition.x, objectPosition.y, objectPosition.z)
      ..setRotation(rotMatrix3);

    final isFolding =
        completionPhase == CompletionPhase.fold ||
        completionPhase == CompletionPhase.done;
    final isRevealing = completionPhase == CompletionPhase.dissolveReveal;
    final foldVP = foldViewProjection ?? viewProjection;

    if (isFolding) {
      _drawFoldFaces(canvas, size, foldVP);
    } else {
      if (!hideDrawingPlane) _drawDrawingPlane(canvas, size, viewProjection);
      _drawGrid(canvas, size, viewProjection);
      _drawStructureFootprint(canvas, size, viewProjection);
      _drawGroupOverlayPolygons(canvas, size, viewProjection);
      _drawBlueprintPolygons(canvas, size, viewProjection);
      _drawPapers(canvas, size, viewProjection);
      _drawLockedPaperOverlays(canvas, size, viewProjection);
      if (paintedCells.isNotEmpty && paintColor != null) {
        _drawPaintPreview(canvas, size, viewProjection);
      }
      if (erasedCells.isNotEmpty) {
        _drawErasePreview(canvas, size, viewProjection);
      }
      // During the reveal, the folding geometry fades in over the (dissolving)
      // 2D regions before the fold proper begins.
      if (isRevealing) {
        _drawFoldFaces(canvas, size, foldVP, opacity: foldOpacity);
      }
    }

    if (isFolding) return;

    // Ghost papers (copy-tool previews)
    if (ghostPapers.isNotEmpty) {
      _drawGhostPapers(canvas, size, viewProjection);
    }

    // Mirror line preview
    if (mirrorLineStart != null && mirrorLinePreview != null) {
      _drawMirrorLine(canvas, size, viewProjection);
    }

    // Rotation copy center
    if (rotCopyCenterWorld != null) {
      _drawRotCopyCenter(canvas, size, viewProjection);
    }

    _drawCutHighlightEdges(canvas, size, viewProjection);
    _drawCutSnapRay(canvas, size, viewProjection);

    // Draw cut lines / preview / toolpath
    _drawCutLines(canvas, size, viewProjection);
    if (lineDrawStart != null && lineDrawPreview != null) {
      _drawLinePreview(canvas, size, viewProjection);
    }
    if (craftingMode == CraftingMode.cutting && activeToolpath.isNotEmpty) {
      _drawToolpath(canvas, size, viewProjection);
    }

    // Stretch gizmo
    if (stretchPaperId != null) {
      _drawStretchGizmo(canvas, size, viewProjection);
    }

    if (stencilVisible) {
      _drawStencil(canvas, size, viewProjection);
    }

    // Friend mesh (only during cut animation)
    if (friendVisible) {
      final visibleEdges = <(Offset, Offset)>[];
      final facesToDraw = <_Face>[];

      _projectMesh(
        size,
        camera,
        view,
        viewProjection,
        world,
        visibleEdges,
        facesToDraw,
      );

      facesToDraw.sort((a, b) => a.depth.compareTo(b.depth));

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white24;

      for (final face in facesToDraw) {
        final path = Path()..addPolygon(face.points, true);
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = face.color;
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }

      if (friendExpression != null) {
        _drawFriendEyes(
          canvas,
          size,
          viewProjection,
          world,
          friendExpression!,
          eyeGeometry3d,
        );
      }
    }

    _drawCentroidCrosses(canvas, size, viewProjection);
    _drawGroupCropFeet(canvas, size, viewProjection);

    if (alignGridIndicator != null) {
      _drawAlignGridIndicator(canvas, size, viewProjection);
    }

    if (marqueeRect != null) {
      _drawMarqueeRect(canvas, marqueeRect!, marqueeDashOffset);
    }
  }

  void _drawDrawingPlane(Canvas canvas, Size size, Matrix4 viewProjection) {
    final half = drawingPlaneSize / 2;
    final corners = [
      Vector3(-half, -half, 0),
      Vector3(half, -half, 0),
      Vector3(half, half, 0),
      Vector3(-half, half, 0),
    ];
    final screenCorners = <Offset>[];
    for (final c in corners) {
      final p = _projectToScreen(c, viewProjection, size);
      if (p != null) screenCorners.add(p);
    }
    if (screenCorners.length < 4) return;

    final planePath = Path()..addPolygon(screenCorners, true);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.grey.shade400;
    canvas.drawPath(planePath, borderPaint);
  }

  void _drawGrid(Canvas canvas, Size size, Matrix4 viewProjection) {
    if (canvasDisplayMode == CanvasDisplayMode.none) return;

    final t = gridLodFadeT.clamp(0.0, 1.0);
    if (gridLodFrom != gridLodTo && t < 1.0) {
      _drawGridAtLod(
        canvas,
        size,
        viewProjection,
        gridLodFrom,
        layerOpacity: 1.0 - t,
      );
      _drawGridAtLod(canvas, size, viewProjection, gridLodTo, layerOpacity: t);
    } else {
      _drawGridAtLod(
        canvas,
        size,
        viewProjection,
        gridLodTo,
        layerOpacity: 1.0,
      );
    }
  }

  void _drawGridAtLod(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
    int lod, {
    required double layerOpacity,
  }) {
    if (layerOpacity <= 0) return;

    final spacing = _gridSpacingForLod(lod);
    const majorInterval = 4;
    final ox = gridOriginOffset.dx;
    final oy = gridOriginOffset.dy;
    final xDir = _gridXDir(gridRotation);
    final yDir = _gridYDir(gridRotation);

    // Visible world AABB of the (possibly rolled) view frustum.
    final aspect = size.width / size.height;
    final halfH = orthoScale;
    final halfW = orthoScale * aspect;
    final c = math.cos(viewRotation);
    final s = math.sin(viewRotation);
    Offset corner(double vx, double vy) =>
        Offset(panOffset.dx + vx * c - vy * s, panOffset.dy + vx * s + vy * c);
    final corners = [
      corner(-halfW, -halfH),
      corner(halfW, -halfH),
      corner(halfW, halfH),
      corner(-halfW, halfH),
    ];
    var worldMinX = corners.first.dx, worldMaxX = corners.first.dx;
    var worldMinY = corners.first.dy, worldMaxY = corners.first.dy;
    for (final p in corners) {
      worldMinX = math.min(worldMinX, p.dx);
      worldMaxX = math.max(worldMaxX, p.dx);
      worldMinY = math.min(worldMinY, p.dy);
      worldMaxY = math.max(worldMaxY, p.dy);
    }

    // Grid-space AABB of the world AABB corners (covers the frustum).
    var gMinX = double.infinity, gMaxX = double.negativeInfinity;
    var gMinY = double.infinity, gMaxY = double.negativeInfinity;
    for (final p in [
      Offset(worldMinX, worldMinY),
      Offset(worldMaxX, worldMinY),
      Offset(worldMaxX, worldMaxY),
      Offset(worldMinX, worldMaxY),
    ]) {
      final g = _worldToGridCoords(p, gridOriginOffset, gridRotation);
      gMinX = math.min(gMinX, g.dx);
      gMaxX = math.max(gMaxX, g.dx);
      gMinY = math.min(gMinY, g.dy);
      gMaxY = math.max(gMaxY, g.dy);
    }

    final iMin = (gMinX / spacing).floor() - 1;
    final iMax = (gMaxX / spacing).ceil() + 1;
    final jMin = (gMinY / spacing).floor() - 1;
    final jMax = (gMaxY / spacing).ceil() + 1;

    Offset gridPt(double gi, double gj) => Offset(
      ox + gi * xDir.dx + gj * yDir.dx,
      oy + gi * xDir.dy + gj * yDir.dy,
    );

    if (canvasDisplayMode == CanvasDisplayMode.grid) {
      final minorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = Colors.grey.shade400.withValues(alpha: 0.375 * layerOpacity);
      final majorPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.grey.shade500.withValues(alpha: 0.75 * layerOpacity);

      // Lines of constant i (parallel to +Y).
      for (var i = iMin; i <= iMax; i++) {
        final isMajor = i % majorInterval == 0;
        if (!showMinorLines && !isMajor) continue;
        final paint = isMajor ? majorPaint : minorPaint;
        final a = gridPt(i * spacing, (jMin - 1) * spacing);
        final b = gridPt(i * spacing, (jMax + 1) * spacing);
        final sa = _projectToScreen(
          Vector3(a.dx, a.dy, 0.1),
          viewProjection,
          size,
        );
        final sb = _projectToScreen(
          Vector3(b.dx, b.dy, 0.1),
          viewProjection,
          size,
        );
        if (sa != null && sb != null) canvas.drawLine(sa, sb, paint);
      }

      // Lines of constant j (parallel to +X).
      for (var j = jMin; j <= jMax; j++) {
        final isMajor = j % majorInterval == 0;
        if (!showMinorLines && !isMajor) continue;
        final paint = isMajor ? majorPaint : minorPaint;
        final a = gridPt((iMin - 1) * spacing, j * spacing);
        final b = gridPt((iMax + 1) * spacing, j * spacing);
        final sa = _projectToScreen(
          Vector3(a.dx, a.dy, 0.1),
          viewProjection,
          size,
        );
        final sb = _projectToScreen(
          Vector3(b.dx, b.dy, 0.1),
          viewProjection,
          size,
        );
        if (sa != null && sb != null) canvas.drawLine(sa, sb, paint);
      }
    } else {
      // Dot mode — uniform size; interior dots tint by grid-fit quality.
      final fitColors = _blueprintGridFitColors(spacing);
      const dotRadius = 1.35;
      const originRadius = 3.6;
      const baseAlpha = 0.55;
      final hasWipe = dotWipeOpacityAt != null;
      final dissolve = dotDissolveProgress;
      final visibleW = worldMaxX - worldMinX;
      Offset? originScreen;

      for (var i = iMin; i <= iMax; i++) {
        if (!showMinorLines && i % majorInterval != 0) continue;

        for (var j = jMin; j <= jMax; j++) {
          if (!showMinorLines && j % majorInterval != 0) continue;

          final world = gridPt(i * spacing, j * spacing);
          final wipeAlpha = hasWipe
              ? dotWipeOpacityAt!(
                  ((world.dx - worldMinX) / visibleW).clamp(0.0, 1.0),
                )
              : 1.0;
          if (wipeAlpha <= 0) continue;

          double dissolveAlpha = 1.0;
          if (dissolve != null) {
            const fadeWindow = 0.25;
            final threshold = _dotDissolveThreshold(i, j) * (1 - fadeWindow);
            if (dissolve >= threshold + fadeWindow) {
              continue;
            } else if (dissolve > threshold) {
              dissolveAlpha = 1.0 - (dissolve - threshold) / fadeWindow;
            }
          }

          final pt = _projectToScreen(
            Vector3(world.dx, world.dy, 0.1),
            viewProjection,
            size,
          );
          if (pt == null) continue;

          final stencilAlpha = wipeAlpha * dissolveAlpha * layerOpacity;
          if (_worldInStencil(world)) {
            _drawStencilGridX(canvas, pt, 0.95 * stencilAlpha);
            continue;
          }

          if (_worldInOpsLockedPaper(world)) {
            canvas.drawCircle(
              pt,
              dotRadius,
              Paint()
                ..style = PaintingStyle.fill
                ..color = Colors.grey.shade600.withValues(
                  alpha: 0.55 * stencilAlpha,
                ),
            );
            continue;
          }

          final isOrigin = i == 0 && j == 0;
          if (isOrigin) {
            originScreen = pt;
            continue;
          }

          final interior = _interiorGridFitColor(world, fitColors);
          final color = (interior ?? Colors.grey.shade400).withValues(
            alpha: (interior != null ? 0.85 : baseAlpha) *
                wipeAlpha *
                dissolveAlpha *
                layerOpacity,
          );
          canvas.drawCircle(
            pt,
            dotRadius,
            Paint()
              ..style = PaintingStyle.fill
              ..color = color,
          );
        }
      }

      if (originScreen != null) {
        canvas.drawCircle(
          originScreen,
          originRadius + 1.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = _kGridOriginDot.withValues(alpha: 0.95 * layerOpacity),
        );
        canvas.drawCircle(
          originScreen,
          originRadius,
          Paint()
            ..style = PaintingStyle.fill
            ..color = _kGridOriginDot.withValues(alpha: 0.92 * layerOpacity),
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Blueprint grid-fit (interior dot tint)
  // -------------------------------------------------------------------------

  static bool _pointInPolygonPainter(Offset p, List<Offset> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx, yi = polygon[i].dy;
      final xj = polygon[j].dx, yj = polygon[j].dy;
      if (((yi > p.dy) != (yj > p.dy)) &&
          (p.dx < (xj - xi) * (p.dy - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Color of interior dots for each blueprint polygon at [spacing].
  List<(List<Offset> poly, List<List<Offset>> holes, Color color)>
      _blueprintGridFitColors(double spacing) {
    final out = <(List<Offset>, List<List<Offset>>, Color)>[];
    for (var i = 0; i < blueprintPolygons.length; i++) {
      final poly = blueprintPolygons[i];
      if (poly.length < 3) continue;
      final holes = i < blueprintHoles.length
          ? blueprintHoles[i]
          : const <List<Offset>>[];
      out.add((poly, holes, _gridFitColorForPolygon(poly, spacing)));
    }
    return out;
  }

  Color? _interiorGridFitColor(
    Offset world,
    List<(List<Offset>, List<List<Offset>>, Color)> fitColors,
  ) {
    for (final (poly, holes, color) in fitColors) {
      if (!_pointInPolygonPainter(world, poly)) continue;
      var inHole = false;
      for (final hole in holes) {
        if (hole.length >= 3 && _pointInPolygonPainter(world, hole)) {
          inHole = true;
          break;
        }
      }
      if (!inHole) return color;
    }
    return null;
  }

  /// Red: <2 edges on the current grid. Yellow: ≥2 but not a majority.
  /// Green: most edges lie on a grid line at this zoom.
  Color _gridFitColorForPolygon(List<Offset> poly, double spacing) {
    var edges = 0;
    var aligned = 0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      if ((b - a).distance < 1e-6) continue;
      edges++;
      if (_edgeOnCurrentGrid(a, b, spacing)) aligned++;
    }
    if (edges == 0 || aligned < 2) return _kGridFitMisaligned;
    if (aligned * 2 > edges) return _kGridFitAligned;
    return _kGridFitPartial;
  }

  bool _edgeOnCurrentGrid(Offset a, Offset b, double spacing) {
    if (spacing <= 1e-9) return false;
    final ga = _worldToGridCoords(a, gridOriginOffset, gridRotation);
    final gb = _worldToGridCoords(b, gridOriginOffset, gridRotation);
    final dx = (ga.dx - gb.dx).abs();
    final dy = (ga.dy - gb.dy).abs();
    final len = (gb - ga).distance;
    if (len < 1e-9) return false;
    const parallelFrac = 0.08;
    final tol = spacing * 0.08;
    bool onLine(double v) {
      final nearest = (v / spacing).round() * spacing;
      return (v - nearest).abs() <= tol;
    }
    final alongGridY = dx / len <= parallelFrac && onLine(ga.dx);
    final alongGridX = dy / len <= parallelFrac && onLine(ga.dy);
    return alongGridY || alongGridX;
  }

  void _drawStructureFootprint(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    if (structureFootprint == null) return;
    final r = structureFootprint!;
    final corners = [
      Vector3(r.left, r.top, 0.05),
      Vector3(r.right, r.top, 0.05),
      Vector3(r.right, r.bottom, 0.05),
      Vector3(r.left, r.bottom, 0.05),
    ];
    final screenPts = <Offset>[];
    for (final c in corners) {
      final sp = _projectToScreen(c, viewProjection, size);
      if (sp != null) screenPts.add(sp);
    }
    if (screenPts.length < 4) return;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.04);
    final path = Path()..addPolygon(screenPts, true);
    canvas.drawPath(path, fillPaint);

    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.35);
    const dashLen = 8.0;
    const gapLen = 5.0;
    for (var i = 0; i < screenPts.length; i++) {
      final a = screenPts[i];
      final b = screenPts[(i + 1) % screenPts.length];
      _drawDashedLine(canvas, a, b, dashLen, gapLen, dashPaint);
    }
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    double dashLen,
    double gapLen,
    Paint paint,
  ) {
    final delta = b - a;
    final totalLen = delta.distance;
    if (totalLen < 1) return;
    final dir = delta / totalLen;
    var drawn = 0.0;
    while (drawn < totalLen) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dashLen).clamp(0, totalLen);
      canvas.drawLine(start, end, paint);
      drawn += dashLen + gapLen;
    }
  }

  void _drawGroupOverlayPolygons(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    final count = math.min(
      groupOverlayPolygons.length,
      groupOverlayColors.length,
    );
    for (var i = 0; i < count; i++) {
      final poly = groupOverlayPolygons[i];
      final screenPts = <Offset>[];
      for (final v in poly) {
        final sp = _projectToScreen(
          Vector3(v.dx, v.dy, 0.04),
          viewProjection,
          size,
        );
        if (sp != null) screenPts.add(sp);
      }
      if (screenPts.length < 3) continue;
      final path = Path()..addPolygon(screenPts, true);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = groupOverlayColors[i];
      canvas.drawPath(path, paint);
    }
  }

  /// Two white flashes, then settle to the blueprint yellow.
  ({Color color, double width, double glow}) _blueprintLoadStroke(
    Color settled,
  ) {
    final t = loadAnimT.clamp(0.0, 1.0);
    if (t >= 1 || hideUnfilledBlueprint) {
      return (color: settled, width: 1.5, glow: 0.0);
    }
    const flashEnd = 0.58;
    if (t < flashEnd) {
      final local = t / flashEnd;
      final pulse = math.sin(local * math.pi * 2).abs();
      return (
        color: Colors.white.withValues(alpha: 0.2 + 0.8 * pulse),
        width: 1.5 + 2.2 * pulse,
        glow: pulse,
      );
    }
    final settle = Curves.easeOut.transform(
      ((t - flashEnd) / (1 - flashEnd)).clamp(0.0, 1.0),
    );
    return (
      color: Color.lerp(Colors.white, settled, settle)!,
      width: 3.7 + (1.5 - 3.7) * settle,
      glow: (1.0 - settle) * 0.35,
    );
  }

  void _drawBlueprintPolygons(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    if (blueprintPolygons.isEmpty) return;

    final grey = Colors.white.withValues(alpha: 0.22);
    final yellow = Colors.yellow.withValues(alpha: 0.7);
    final settledStroke = Color.lerp(
      grey,
      yellow,
      activeHighlightT.clamp(0, 1),
    )!;
    final load = _blueprintLoadStroke(settledStroke);

    final defaultPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = load.width
      ..color = load.color;

    final filledPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.25
      ..color = Colors.greenAccent.withValues(alpha: 0.7);

    // Soft glow during load flashes and camera intro.
    final glow = math.max(activeGlow, load.glow);
    if (glow > 0.01) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + 6.0 * glow
        ..color = Colors.white.withValues(alpha: 0.45 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (var i = 0; i < blueprintPolygons.length; i++) {
        if (filledBlueprintIndices.contains(i)) continue;
        final poly = blueprintPolygons[i];
        final screenPts = <Offset>[];
        for (final v in poly) {
          final sp = _projectToScreen(
            Vector3(v.dx, v.dy, 0.045),
            viewProjection,
            size,
          );
          if (sp != null) screenPts.add(sp);
        }
        if (screenPts.length < 3) continue;
        final glowPath = Path()..addPolygon(screenPts, true);
        if (i < blueprintHoles.length) {
          for (final hole in blueprintHoles[i]) {
            final holePts = <Offset>[];
            for (final v in hole) {
              final sp = _projectToScreen(
                Vector3(v.dx, v.dy, 0.045),
                viewProjection,
                size,
              );
              if (sp != null) holePts.add(sp);
            }
            if (holePts.length >= 3) glowPath.addPolygon(holePts, true);
          }
        }
        canvas.drawPath(glowPath, glowPaint);
      }
    }

    if (hideUnfilledBlueprint && loadAnimT < 1) {
      // Lock-fade beat: new outlines stay hidden until the load flash.
    } else {
      for (var i = 0; i < blueprintPolygons.length; i++) {
        final poly = blueprintPolygons[i];
        final screenPts = <Offset>[];
        for (final v in poly) {
          final sp = _projectToScreen(
            Vector3(v.dx, v.dy, 0.05),
            viewProjection,
            size,
          );
          if (sp != null) screenPts.add(sp);
        }
        if (screenPts.length < 3) continue;
        final path = Path()..addPolygon(screenPts, true);
        if (i < blueprintHoles.length) {
          for (final hole in blueprintHoles[i]) {
            final holePts = <Offset>[];
            for (final v in hole) {
              final sp = _projectToScreen(
                Vector3(v.dx, v.dy, 0.05),
                viewProjection,
                size,
              );
              if (sp != null) holePts.add(sp);
            }
            if (holePts.length >= 3) path.addPolygon(holePts, true);
          }
        }
        path.fillType = PathFillType.evenOdd;
        final paint = filledBlueprintIndices.contains(i)
            ? filledPaint
            : defaultPaint;
        canvas.drawPath(path, paint);
      }
    }

    // Draw highlight stroke over the active align-grid region.
    if (alignGridHighlightPolyIndex != null &&
        alignGridHighlightPolyIndex! < blueprintPolygons.length) {
      final highlightPoly = blueprintPolygons[alignGridHighlightPolyIndex!];
      final pts = <Offset>[];
      for (final v in highlightPoly) {
        final sp = _projectToScreen(
          Vector3(v.dx, v.dy, 0.07),
          viewProjection,
          size,
        );
        if (sp != null) pts.add(sp);
      }
      if (pts.length >= 3) {
        final highlightPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFFB8D4);
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(path, highlightPaint);
      }
    }
  }

  void _drawPaintPreview(Canvas canvas, Size size, Matrix4 viewProjection) {
    final s = _effectiveGridSpacing;
    final xDir = _gridXDir(gridRotation);
    final yDir = _gridYDir(gridRotation);
    final ox = gridOriginOffset.dx;
    final oy = gridOriginOffset.dy;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paintColor!.color.withValues(alpha: 0.55);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = paintColor!.color.withValues(alpha: 0.85);

    Offset corner(double gi, double gj) => Offset(
      ox + gi * xDir.dx + gj * yDir.dx,
      oy + gi * xDir.dy + gj * yDir.dy,
    );

    for (final (col, row) in paintedCells) {
      final corners = [
        corner(col * s, row * s),
        corner((col + 1) * s, row * s),
        corner((col + 1) * s, (row + 1) * s),
        corner(col * s, (row + 1) * s),
      ];
      final projected = <Offset>[];
      for (final c in corners) {
        final p = _projectToScreen(Vector3(c.dx, c.dy, 1), viewProjection, size);
        if (p != null) projected.add(p);
      }
      if (projected.length < 3) continue;

      final path = Path()..addPolygon(projected, true);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }
  }

  void _drawErasePreview(Canvas canvas, Size size, Matrix4 viewProjection) {
    final s = _effectiveGridSpacing;
    final xDir = _gridXDir(gridRotation);
    final yDir = _gridYDir(gridRotation);
    final ox = gridOriginOffset.dx;
    final oy = gridOriginOffset.dy;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x55FF4444);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xAAFF4444);

    Offset corner(double gi, double gj) => Offset(
      ox + gi * xDir.dx + gj * yDir.dx,
      oy + gi * xDir.dy + gj * yDir.dy,
    );

    for (final (col, row) in erasedCells) {
      final corners = [
        corner(col * s, row * s),
        corner((col + 1) * s, row * s),
        corner((col + 1) * s, (row + 1) * s),
        corner(col * s, (row + 1) * s),
      ];
      final projected = <Offset>[];
      for (final c in corners) {
        final p = _projectToScreen(Vector3(c.dx, c.dy, 1), viewProjection, size);
        if (p != null) projected.add(p);
      }
      if (projected.length < 3) continue;

      final path = Path()..addPolygon(projected, true);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }
  }

  void _drawPapers(Canvas canvas, Size size, Matrix4 viewProjection) {
    // Locked first, then live, so committed geometry never covers new work.
    // Within a layer, lower stackOrder is behind.
    for (final lockedLayer in const [true, false]) {
    final layerPapers = papers.where((p) => p.locked == lockedLayer).toList()
      ..sort((a, b) => a.stackOrder.compareTo(b.stackOrder));
    final paperPaths = <(Path, PlacedPaper)>[];
    for (final paper in layerPapers) {
      final hs = _paperHalfSizeForLevel(paper.sizeLevel);
      final localVerts =
          paper.localVertices ??
          [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];

      final rad = paper.rotationDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);
      final cx = paper.position.x;
      final cy = paper.position.y;
      final cz = paper.position.z;

      final screenCorners = <Offset>[];
      for (final raw in localVerts) {
        final o = _stretchMappedLocal(paper, raw);
        final rx = o.dx * cosA - o.dy * sinA;
        final ry = o.dx * sinA + o.dy * cosA;
        final p = _projectToScreen(
          Vector3(cx + rx, cy + ry, cz),
          viewProjection,
          size,
        );
        if (p != null) screenCorners.add(p);
      }
      if (screenCorners.length < 3) continue;

      var paperPath = Path()..addPolygon(screenCorners, true);

      // Add hole sub-paths for compound papers.
      for (final hole in paper.localHoles) {
        final screenHole = <Offset>[];
        for (final raw in hole) {
          final o = _stretchMappedLocal(paper, raw);
          final rx = o.dx * cosA - o.dy * sinA;
          final ry = o.dx * sinA + o.dy * cosA;
          final p = _projectToScreen(
            Vector3(cx + rx, cy + ry, cz),
            viewProjection,
            size,
          );
          if (p != null) screenHole.add(p);
        }
        if (screenHole.length >= 3) {
          paperPath.addPolygon(screenHole, true);
        }
      }
      paperPath.fillType = PathFillType.evenOdd;

      final shadowPath = Path()
        ..addPolygon(
          screenCorners.map((p) => p + const Offset(2, 2)).toList(),
          true,
        );
      final discardT = discardOpacityById[paper.id];
      canvas.drawPath(
        shadowPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.black.withOpacity(0.08 * (discardT ?? 1.0)),
      );

      final baseColor =
          paperColorResolver?.call(paper) ?? paper.paperColor.color;
      final fading = lockFadingPaperIds.contains(paper.id);
      final fillAlpha = discardT != null
          ? 0.85 * discardT
          : fading
          ? 0.85 + (0.15 - 0.85) * lockFadeT.clamp(0.0, 1.0)
          : (paper.locked
              ? 0.15
              : paper.isOpsLocked
              ? 0.75
              : 0.85);
      final Color fillColor = baseColor.withValues(alpha: fillAlpha);

      canvas.drawPath(
        paperPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor,
      );

      // Draw per-paper cut segments clipped to the paper polygon
      if (paper.cutSegments.isNotEmpty) {
        final cutPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withOpacity(paper.locked ? 0.12 : 0.5);
        for (final seg in paper.cutSegments) {
          final clipped = _clipSegmentToPolygon(seg.$1, seg.$2, localVerts);
          for (final (ca, cb) in clipped) {
            final wxa = cx + ca.dx * cosA - ca.dy * sinA;
            final wya = cy + ca.dx * sinA + ca.dy * cosA;
            final wxb = cx + cb.dx * cosA - cb.dy * sinA;
            final wyb = cy + cb.dx * sinA + cb.dy * cosA;
            final sa = _projectToScreen(
              Vector3(wxa, wya, cz + 0.1),
              viewProjection,
              size,
            );
            final sb = _projectToScreen(
              Vector3(wxb, wyb, cz + 0.1),
              viewProjection,
              size,
            );
            if (sa != null && sb != null) {
              canvas.drawLine(sa, sb, cutPaint);
            }
          }
        }
      }

      paperPaths.add((paperPath, paper));
    }
    _strokePaperBorders(canvas, paperPaths);
    }
  }

  void _strokePaperBorders(
    Canvas canvas,
    List<(Path, PlacedPaper)> paperPaths,
  ) {
    for (final (paperPath, paper) in paperPaths) {
      final isSelected = selectedPaperIds.contains(paper.id);
      final isMatched = paper.isBlueprintMatched;
      final isAnimating = lockAnimatingPaperIds.contains(paper.id);

      Color borderColor;
      double borderWidth;
      final discardT = discardOpacityById[paper.id];
      if (discardT != null) {
        borderColor = Colors.white.withValues(alpha: 0.75 * discardT);
        borderWidth = 0.75;
      } else if (isAnimating) {
        borderColor = Color.lerp(Colors.white, Colors.green, lockAnimProgress)!;
        borderWidth = 1.0 + lockAnimProgress * 1.0;
      } else if (lockFadingPaperIds.contains(paper.id)) {
        final t = lockFadeT.clamp(0.0, 1.0);
        final from = isMatched ? Colors.green : Colors.white;
        borderColor = Color.lerp(
          from,
          Colors.white.withValues(alpha: 0.15),
          t,
        )!;
        borderWidth = 2.0 + (0.75 - 2.0) * t;
      } else if (paper.locked) {
        borderColor = Colors.green;
        borderWidth = 2.0;
      } else if (isSelected) {
        borderColor = Colors.cyanAccent;
        borderWidth = 2.0;
      } else {
        borderColor = Colors.white;
        borderWidth = 0.75;
      }

      canvas.drawPath(
        paperPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = borderColor,
      );
    }
  }

  void _drawLockedPaperOverlays(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    final matchedPapers = papers
        .where(
          (p) =>
              p.isBlueprintMatched &&
              !p.locked &&
              !lockAnimatingPaperIds.contains(p.id),
        )
        .toList();
    if (matchedPapers.isEmpty) return;

    final overlayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.green;

    for (final paper in matchedPapers) {
      final hs = _paperHalfSizeForLevel(paper.sizeLevel);
      final localVerts =
          paper.localVertices ??
          [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];

      final rad = paper.rotationDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);
      final cx = paper.position.x;
      final cy = paper.position.y;
      final cz = paper.position.z;

      final screenCorners = <Offset>[];
      for (final o in localVerts) {
        final rx = o.dx * cosA - o.dy * sinA;
        final ry = o.dx * sinA + o.dy * cosA;
        final p = _projectToScreen(
          Vector3(cx + rx, cy + ry, cz),
          viewProjection,
          size,
        );
        if (p != null) screenCorners.add(p);
      }
      if (screenCorners.length < 3) continue;

      var path = Path()..addPolygon(screenCorners, true);
      for (final hole in paper.localHoles) {
        final screenHole = <Offset>[];
        for (final o in hole) {
          final rx = o.dx * cosA - o.dy * sinA;
          final ry = o.dx * sinA + o.dy * cosA;
          final p = _projectToScreen(
            Vector3(cx + rx, cy + ry, cz),
            viewProjection,
            size,
          );
          if (p != null) screenHole.add(p);
        }
        if (screenHole.length >= 3) {
          path.addPolygon(screenHole, true);
        }
      }
      path.fillType = PathFillType.evenOdd;
      canvas.drawPath(path, overlayPaint);
    }
  }

  void _drawFoldFaces(
    Canvas canvas,
    Size size,
    Matrix4 vp, {
    double opacity = 1.0,
  }) {
    final o = opacity.clamp(0.0, 1.0);
    if (o <= 0) return;
    final faceColor = Color.lerp(
      Colors.white,
      const Color(0xFFFFD54F),
      foldColorProgress,
    )!.withOpacity(0.9 * o);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.7 * o);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = faceColor;

    final disp = foldDisplacementMatrix ?? Matrix4.identity();
    final allFaces = <(Path, double)>[];

    for (final state in foldNodeStates.values) {
      if (state.unfoldedVertices3D.length < 3) continue;

      final worldXform = disp * state.cumulativeMatrix;
      final screenPts = <Offset>[];
      double depthSum = 0;

      for (final v in state.unfoldedVertices3D) {
        final wp = v.clone();
        worldXform.transform3(wp);
        final sp = _projectToScreen(wp, vp, size);
        if (sp != null) screenPts.add(sp);
        depthSum += wp.z;
      }
      if (screenPts.length < 3) continue;
      final path = Path()..addPolygon(screenPts, true);
      allFaces.add((path, depthSum / screenPts.length));
    }

    allFaces.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (path, _) in allFaces) {
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, borderPaint);
    }
  }

  void _drawCutSnapRay(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    final ray = cutSnapRay;
    if (ray == null) return;
    final (extA, extB) = extendLineSegment(
      ray.$1,
      ray.$2,
      drawingPlaneSize,
    );
    final a = _projectToScreen(
      Vector3(extA.dx, extA.dy, 0.06),
      viewProjection,
      size,
    );
    final b = _projectToScreen(
      Vector3(extB.dx, extB.dy, 0.06),
      viewProjection,
      size,
    );
    if (a == null || b == null) return;
    canvas.drawLine(
      a,
      b,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = Colors.cyanAccent.withValues(alpha: 0.25),
    );
  }

  void _drawCutHighlightEdges(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    if (cutHighlightEdges.isEmpty || cutHighlightGlow <= 0.01) return;
    final t = cutHighlightGlow.clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.cyanAccent.withValues(alpha: 0.55 * t)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.cyanAccent.withValues(alpha: 0.95 * t);

    for (final edge in cutHighlightEdges) {
      final a = _projectToScreen(
        Vector3(edge.$1.dx, edge.$1.dy, 0.08),
        viewProjection,
        size,
      );
      final b = _projectToScreen(
        Vector3(edge.$2.dx, edge.$2.dy, 0.08),
        viewProjection,
        size,
      );
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, glowPaint);
      canvas.drawLine(a, b, corePaint);
    }
  }

  void _drawCutLines(Canvas canvas, Size size, Matrix4 viewProjection) {
    if (drawnCutLines.isEmpty) return;

    final extension = drawingPlaneSize;

    // Extended rays (thin, 50% opacity, both directions)
    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.redAccent.withOpacity(0.5);
    for (final line in drawnCutLines) {
      final (extA, extB) = extendLineSegment(line.$1, line.$2, extension);
      final a = _projectToScreen(
        Vector3(extA.dx, extA.dy, 2),
        viewProjection,
        size,
      );
      final b = _projectToScreen(
        Vector3(extB.dx, extB.dy, 2),
        viewProjection,
        size,
      );
      if (a != null && b != null) {
        canvas.drawLine(a, b, rayPaint);
      }
    }

    // Actual cut segments (dashed, full opacity)
    const dashLen = 6.0;
    const gapLen = 4.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.redAccent;
    for (final line in drawnCutLines) {
      final a = _projectToScreen(
        Vector3(line.$1.dx, line.$1.dy, 2),
        viewProjection,
        size,
      );
      final b = _projectToScreen(
        Vector3(line.$2.dx, line.$2.dy, 2),
        viewProjection,
        size,
      );
      if (a != null && b != null) {
        _drawDashedLine(canvas, a, b, dashLen, gapLen, paint);
      }
    }

    // Vertices at endpoints
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.redAccent;
    for (final line in drawnCutLines) {
      for (final pt in [line.$1, line.$2]) {
        final sp = _projectToScreen(
          Vector3(pt.dx, pt.dy, 2),
          viewProjection,
          size,
        );
        if (sp != null) canvas.drawCircle(sp, 3.5, dotPaint);
      }
    }
  }

  void _drawLinePreview(Canvas canvas, Size size, Matrix4 viewProjection) {
    final start = lineDrawStart!;
    final end = lineDrawPreview!;

    // Extended ray preview (thin, 50% opacity)
    final extension = drawingPlaneSize;
    final (extA, extB) = extendLineSegment(start, end, extension);
    final extScreenA = _projectToScreen(
      Vector3(extA.dx, extA.dy, 2),
      viewProjection,
      size,
    );
    final extScreenB = _projectToScreen(
      Vector3(extB.dx, extB.dy, 2),
      viewProjection,
      size,
    );
    if (extScreenA != null && extScreenB != null) {
      final rayPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.redAccent.withOpacity(0.5);
      canvas.drawLine(extScreenA, extScreenB, rayPaint);
    }

    final a = _projectToScreen(
      Vector3(start.dx, start.dy, 2),
      viewProjection,
      size,
    );
    final b = _projectToScreen(
      Vector3(end.dx, end.dy, 2),
      viewProjection,
      size,
    );
    if (a == null || b == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.redAccent.withOpacity(0.5);
    canvas.drawLine(a, b, paint);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.redAccent.withOpacity(0.7);
    canvas.drawCircle(a, 4, dotPaint);
    canvas.drawCircle(b, 4, dotPaint);
  }

  void _drawToolpath(Canvas canvas, Size size, Matrix4 viewProjection) {
    final cutPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.redAccent.withOpacity(0.4);
    final travelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withOpacity(0.2);
    const dashLen = 4.0;
    const gapLen = 3.0;

    for (final seg in activeToolpath) {
      final a = _projectToScreen(
        Vector3(seg.start.dx, seg.start.dy, 2),
        viewProjection,
        size,
      );
      final b = _projectToScreen(
        Vector3(seg.end.dx, seg.end.dy, 2),
        viewProjection,
        size,
      );
      if (a == null || b == null) continue;
      if (seg.isCutting) {
        _drawDashedLine(canvas, a, b, dashLen, gapLen, cutPaint);
      } else {
        _drawDashedLine(canvas, a, b, dashLen, gapLen, travelPaint);
      }
    }
  }

  void _drawCentroidCrosses(Canvas canvas, Size size, Matrix4 viewProjection) {
    if (selectedPaperIds.isEmpty) return;
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.grey.withOpacity(0.5);
    const crossSize = 5.0;

    for (final paper in papers) {
      if (!selectedPaperIds.contains(paper.id)) continue;
      final sp = _projectToScreen(paper.position, viewProjection, size);
      if (sp == null) continue;
      canvas.drawLine(
        Offset(sp.dx - crossSize, sp.dy),
        Offset(sp.dx + crossSize, sp.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(sp.dx, sp.dy - crossSize),
        Offset(sp.dx, sp.dy + crossSize),
        crossPaint,
      );
    }
  }

  void _drawGroupCropFeet(Canvas canvas, Size size, Matrix4 viewProjection) {
    final groupMap = <String, List<PlacedPaper>>{};
    for (final paper in papers) {
      if (paper.groupId == null) continue;
      groupMap.putIfAbsent(paper.groupId!, () => []).add(paper);
    }
    if (groupMap.isEmpty) return;

    final cropPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.grey.withOpacity(0.35);
    const footLen = 10.0;

    for (final members in groupMap.values) {
      // Only show crop feet if the group is selected
      final anySelected = members.any((p) => selectedPaperIds.contains(p.id));
      if (!anySelected) continue;

      double minSx = double.infinity, minSy = double.infinity;
      double maxSx = -double.infinity, maxSy = -double.infinity;
      for (final paper in members) {
        final hs = _paperHalfSizeForLevel(paper.sizeLevel);
        final localVerts =
            paper.localVertices ??
            [
              Offset(-hs, -hs),
              Offset(hs, -hs),
              Offset(hs, hs),
              Offset(-hs, hs),
            ];
        final rad = paper.rotationDeg * math.pi / 180;
        final cosA = math.cos(rad);
        final sinA = math.sin(rad);
        for (final o in localVerts) {
          final rx = o.dx * cosA - o.dy * sinA;
          final ry = o.dx * sinA + o.dy * cosA;
          final sp = _projectToScreen(
            Vector3(
              paper.position.x + rx,
              paper.position.y + ry,
              paper.position.z,
            ),
            viewProjection,
            size,
          );
          if (sp != null) {
            minSx = math.min(minSx, sp.dx);
            minSy = math.min(minSy, sp.dy);
            maxSx = math.max(maxSx, sp.dx);
            maxSy = math.max(maxSy, sp.dy);
          }
        }
      }
      if (minSx == double.infinity) continue;

      const pad = 4.0;
      final l = minSx - pad, t = minSy - pad;
      final r = maxSx + pad, b = maxSy + pad;

      // Top-left corner
      canvas.drawLine(Offset(l, t), Offset(l + footLen, t), cropPaint);
      canvas.drawLine(Offset(l, t), Offset(l, t + footLen), cropPaint);
      // Top-right corner
      canvas.drawLine(Offset(r, t), Offset(r - footLen, t), cropPaint);
      canvas.drawLine(Offset(r, t), Offset(r, t + footLen), cropPaint);
      // Bottom-left corner
      canvas.drawLine(Offset(l, b), Offset(l + footLen, b), cropPaint);
      canvas.drawLine(Offset(l, b), Offset(l, b - footLen), cropPaint);
      // Bottom-right corner
      canvas.drawLine(Offset(r, b), Offset(r - footLen, b), cropPaint);
      canvas.drawLine(Offset(r, b), Offset(r, b - footLen), cropPaint);
    }
  }

  void _drawAlignGridIndicator(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    final pt = alignGridIndicator!;
    final sp = _projectToScreen(
      Vector3(pt.dx, pt.dy, 0.2),
      viewProjection,
      size,
    );
    if (sp == null) return;

    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.cyanAccent;
    final innerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.cyanAccent.withValues(alpha: 0.4);
    canvas.drawCircle(sp, 8.0, innerPaint);
    canvas.drawCircle(sp, 8.0, outerPaint);

    // Small crosshair
    const arm = 12.0;
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.cyanAccent.withValues(alpha: 0.8);
    canvas.drawLine(
      Offset(sp.dx - arm, sp.dy),
      Offset(sp.dx + arm, sp.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(sp.dx, sp.dy - arm),
      Offset(sp.dx, sp.dy + arm),
      crossPaint,
    );

    final end = alignGridAxisEnd;
    if (end != null) {
      final ep = _projectToScreen(
        Vector3(end.dx, end.dy, 0.2),
        viewProjection,
        size,
      );
      if (ep != null) {
        final axisPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = Colors.cyanAccent.withValues(alpha: 0.9);
        canvas.drawLine(sp, ep, axisPaint);
        canvas.drawCircle(ep, 6.0, innerPaint);
        canvas.drawCircle(ep, 6.0, outerPaint);

        // Arrowhead toward +Y
        final d = ep - sp;
        final len = d.distance;
        if (len > 1) {
          final ux = d.dx / len;
          final uy = d.dy / len;
          const head = 10.0;
          final left = Offset(
            ep.dx - ux * head - uy * head * 0.55,
            ep.dy - uy * head + ux * head * 0.55,
          );
          final right = Offset(
            ep.dx - ux * head + uy * head * 0.55,
            ep.dy - uy * head - ux * head * 0.55,
          );
          canvas.drawLine(ep, left, axisPaint);
          canvas.drawLine(ep, right, axisPaint);
        }
      }
    }
  }

  void _drawMarqueeRect(Canvas canvas, Rect rect, double dashOffset) {
    final path = Path()..addRect(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withOpacity(0.7);

    const dashLen = 4.0;
    const gapLen = 4.0;
    final totalLen = dashLen + gapLen;

    for (final metric in path.computeMetrics()) {
      var distance = dashOffset % totalLen;
      while (distance < metric.length) {
        final end = math.min(distance + dashLen, metric.length);
        final extracted = metric.extractPath(distance, end);
        canvas.drawPath(extracted, paint);
        distance += totalLen;
      }
    }
  }

  void _projectMesh(
    Size size,
    scene_camera.Camera camera,
    Matrix4 view,
    Matrix4 viewProjection,
    Matrix4 world,
    List<(Offset, Offset)> visibleEdges,
    List<_Face> facesToDraw,
  ) {
    final lights = [
      DirectionalLight(
        color: Colors.white,
        intensity: 0.9,
        direction: Vector3(-0.6, -1, -0.4),
      ),
      DirectionalLight(
        color: Colors.white70,
        intensity: 0.3,
        direction: Vector3(0.5, -0.8, -0.3),
      ),
    ];
    const globalIllumination = 0.3;

    for (var fi = 0; fi < geometry.faces.length; fi++) {
      final face = geometry.faces[fi];
      if (face.length < 3) continue;

      final worldVertices = <Vector3>[];
      final points = <Offset>[];
      final depths = <double>[];
      var shouldDiscard = false;

      for (final index in face) {
        final localVertex = geometry.vertices[index];
        final worldPos = Vector3.copy(localVertex);
        world.transform3(worldPos);
        worldVertices.add(worldPos);

        final cameraSpace = Vector3.copy(worldPos);
        view.transform3(cameraSpace);
        if (cameraSpace.z > 0) {
          shouldDiscard = true;
          break;
        }
        depths.add(cameraSpace.z);

        final projected = _projectToScreen(worldPos, viewProjection, size);
        if (projected == null) {
          shouldDiscard = true;
          break;
        }
        points.add(projected);
      }

      if (shouldDiscard || points.length < 3) continue;

      final normal = _faceNormal(worldVertices);
      final faceCenter = Vector3.zero();
      for (final v in worldVertices) {
        faceCenter.add(v);
      }
      faceCenter.scale(1 / worldVertices.length);

      final toCamera = (camera.position - faceCenter)..normalize();
      final facingCamera = normal.dot(toCamera) > 0;

      for (var i = 0; i < points.length; i++) {
        final j = (i + 1) % points.length;
        visibleEdges.add((points[i], points[j]));
      }

      final shadingNormal = facingCamera ? normal : -normal;
      final shade = _shadeForFace(shadingNormal, lights, globalIllumination);
      final depth = depths.reduce((a, b) => a + b) / depths.length;

      final baseColor =
          geometry.faceColors != null && fi < geometry.faceColors!.length
          ? geometry.faceColors![fi]
          : objectColor;
      final litColor = _applyLighting(baseColor, shade);

      facesToDraw.add(_Face(points: points, color: litColor, depth: depth));
    }
  }

  void _drawFriendEyes(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
    Matrix4 world,
    FriendExpressionConfig expr,
    FriendEyeGeometry3d style,
  ) {
    final halfSpacing = expr.eyeSpacing / 2;
    final leftLocal = Vector3(
      -halfSpacing,
      expr.eyeHeight,
      expr.eyeForwardOffset,
    );
    final rightLocal = Vector3(
      halfSpacing,
      expr.eyeHeight,
      expr.eyeForwardOffset,
    );
    _drawSingleCraftingEye(
      canvas,
      size,
      viewProjection,
      world,
      expr,
      style,
      leftLocal,
    );
    _drawSingleCraftingEye(
      canvas,
      size,
      viewProjection,
      world,
      expr,
      style,
      rightLocal,
    );
  }

  Vector3 _craftingLocalToWorld(Matrix4 world, Vector3 local) {
    final v = Vector3.copy(local);
    world.transform3(v);
    return v;
  }

  void _drawSingleCraftingEye(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
    Matrix4 world,
    FriendExpressionConfig expr,
    FriendEyeGeometry3d style,
    Vector3 centerLocal,
  ) {
    final rx = expr.eyeRadiusX;
    final ry = expr.eyeRadiusY;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = expr.eyeColor;

    if (style == FriendEyeGeometry3d.sphere) {
      final c = _craftingLocalToWorld(world, centerLocal);
      final up = _craftingLocalToWorld(world, centerLocal + Vector3(0, ry, 0));
      final rightPt = _craftingLocalToWorld(
        world,
        centerLocal + Vector3(rx, 0, 0),
      );
      final ps = _projectToScreen(c, viewProjection, size);
      final pu = _projectToScreen(up, viewProjection, size);
      final pr = _projectToScreen(rightPt, viewProjection, size);
      if (ps == null || pu == null || pr == null) return;
      final projRY = (ps - pu).distance;
      final projRX = (ps - pr).distance;
      canvas.save();
      canvas.translate(ps.dx, ps.dy);
      canvas.scale(projRX, projRY);
      canvas.drawOval(const Rect.fromLTWH(-1, -1, 2, 2), paint);
      canvas.restore();
      return;
    }

    const segments = 28;
    final rim = <Offset>[];
    for (var k = 0; k < 2; k++) {
      final zOff = k == 0 ? -ry : ry;
      for (var i = 0; i < segments; i++) {
        final t = 2.0 * math.pi * i / segments;
        final lp =
            centerLocal + Vector3(rx * math.cos(t), rx * math.sin(t), zOff);
        final wp = _craftingLocalToWorld(world, lp);
        final p = _projectToScreen(wp, viewProjection, size);
        if (p != null) rim.add(p);
      }
    }
    if (rim.length < 3) return;
    final hull = convexHull(rim);
    if (hull.length < 3) return;
    canvas.drawPath(Path()..addPolygon(hull, true), paint);
  }

  static bool _pointInPoly(Offset p, List<Offset> polygon) {
    var inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx < (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Clips a segment (a,b) to the interior of a polygon, returning
  /// the sub-segments that lie inside.
  static List<(Offset, Offset)> _clipSegmentToPolygon(
    Offset a,
    Offset b,
    List<Offset> polygon,
  ) {
    const eps = 1e-6;
    final hits = <double>[0.0, 1.0];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;

    for (var i = 0; i < polygon.length; i++) {
      final p = polygon[i];
      final q = polygon[(i + 1) % polygon.length];
      final ip = _segIntersect(a, b, p, q);
      if (ip != null) {
        final t = len2 < eps * eps
            ? 0.0
            : ((ip.dx - a.dx) * dx + (ip.dy - a.dy) * dy) / len2;
        if (t > -eps && t < 1 + eps) {
          hits.add(t.clamp(0.0, 1.0));
        }
      }
    }
    hits.sort();

    final result = <(Offset, Offset)>[];
    for (var i = 0; i < hits.length - 1; i++) {
      final t0 = hits[i];
      final t1 = hits[i + 1];
      if ((t1 - t0) < eps) continue;
      final mid = (t0 + t1) / 2;
      final midPt = Offset(a.dx + dx * mid, a.dy + dy * mid);
      if (_pointInPoly(midPt, polygon)) {
        result.add((
          Offset(a.dx + dx * t0, a.dy + dy * t0),
          Offset(a.dx + dx * t1, a.dy + dy * t1),
        ));
      }
    }
    return result;
  }

  static Offset? _segIntersect(Offset a, Offset b, Offset c, Offset d) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final cdx = d.dx - c.dx;
    final cdy = d.dy - c.dy;
    final denom = abx * cdy - aby * cdx;
    if (denom.abs() < 1e-10) return null;
    final acx = c.dx - a.dx;
    final acy = c.dy - a.dy;
    final t = (acx * cdy - acy * cdx) / denom;
    final u = (acx * aby - acy * abx) / denom;
    if (t < -1e-9 || t > 1 + 1e-9 || u < -1e-9 || u > 1 + 1e-9) return null;
    return Offset(a.dx + abx * t, a.dy + aby * t);
  }

  // ---------------------------------------------------------------------------
  // Copy-tool overlay drawing
  // ---------------------------------------------------------------------------

  void _drawGhostPapers(Canvas canvas, Size size, Matrix4 viewProjection) {
    for (final paper in ghostPapers) {
      final hs = _paperHalfSizeForLevel(paper.sizeLevel);
      final localVerts =
          paper.localVertices ??
          [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];

      final rad = paper.rotationDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);
      final cx = paper.position.x;
      final cy = paper.position.y;
      final cz = paper.position.z;

      final screenCorners = <Offset>[];
      for (final o in localVerts) {
        final rx = o.dx * cosA - o.dy * sinA;
        final ry = o.dx * sinA + o.dy * cosA;
        final p = _projectToScreen(
          Vector3(cx + rx, cy + ry, cz),
          viewProjection,
          size,
        );
        if (p != null) screenCorners.add(p);
      }
      if (screenCorners.length < 3) continue;

      var paperPath = Path()..addPolygon(screenCorners, true);
      for (final hole in paper.localHoles) {
        final screenHole = <Offset>[];
        for (final o in hole) {
          final rx = o.dx * cosA - o.dy * sinA;
          final ry = o.dx * sinA + o.dy * cosA;
          final p = _projectToScreen(
            Vector3(cx + rx, cy + ry, cz),
            viewProjection,
            size,
          );
          if (p != null) screenHole.add(p);
        }
        if (screenHole.length >= 3) paperPath.addPolygon(screenHole, true);
      }
      paperPath.fillType = PathFillType.evenOdd;

      final ghostColor =
          paperColorResolver?.call(paper) ?? paper.paperColor.color;
      canvas.drawPath(
        paperPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = ghostColor.withValues(alpha: 0.35),
      );
      canvas.drawPath(
        paperPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ghostColor.withValues(alpha: 0.7),
      );
    }
  }

  void _drawMirrorLine(Canvas canvas, Size size, Matrix4 viewProjection) {
    final a = _projectToScreen(
      Vector3(mirrorLineStart!.dx, mirrorLineStart!.dy, 0.1),
      viewProjection,
      size,
    );
    final b = _projectToScreen(
      Vector3(mirrorLinePreview!.dx, mirrorLinePreview!.dy, 0.1),
      viewProjection,
      size,
    );
    if (a == null || b == null) return;

    final extended = extendLineSegment(a, b, 2000);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFAA66FF);

    const dashLen = 8.0;
    const gapLen = 6.0;
    final dir = extended.$2 - extended.$1;
    final total = dir.distance;
    if (total < 1e-4) return;
    final unit = dir / total;
    var dist = 0.0;
    final path = Path();
    while (dist < total) {
      final segEnd = (dist + dashLen).clamp(0.0, total);
      path.moveTo(
        extended.$1.dx + unit.dx * dist,
        extended.$1.dy + unit.dy * dist,
      );
      path.lineTo(
        extended.$1.dx + unit.dx * segEnd,
        extended.$1.dy + unit.dy * segEnd,
      );
      dist = segEnd + gapLen;
    }
    canvas.drawPath(path, paint);
  }

  void _drawRotCopyCenter(Canvas canvas, Size size, Matrix4 viewProjection) {
    final p = _projectToScreen(
      Vector3(rotCopyCenterWorld!.dx, rotCopyCenterWorld!.dy, 0.1),
      viewProjection,
      size,
    );
    if (p == null) return;

    const crossSize = 10.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFF8800);

    canvas.drawLine(
      p - const Offset(crossSize, 0),
      p + const Offset(crossSize, 0),
      paint,
    );
    canvas.drawLine(
      p - const Offset(0, crossSize),
      p + const Offset(0, crossSize),
      paint,
    );
    canvas.drawCircle(p, 4, paint);
  }

  Offset _stretchMappedLocal(PlacedPaper paper, Offset v) {
    if (paper.id != stretchPaperId) return v;
    final from = stretchStartBounds;
    final to = stretchDisplayBounds;
    if (from == null || to == null) return v;
    final w = from.width.abs() < 1e-9 ? 1.0 : from.width;
    final h = from.height.abs() < 1e-9 ? 1.0 : from.height;
    return Offset(
      to.left + (v.dx - from.left) / w * to.width,
      to.top + (v.dy - from.top) / h * to.height,
    );
  }

  Offset _stencilLocalToScreen(
    Offset local,
    Matrix4 viewProjection,
    Size size,
  ) {
    return _projectToScreen(
          Vector3(
            stencilPosition.dx + local.dx,
            stencilPosition.dy + local.dy,
            1.05,
          ),
          viewProjection,
          size,
        ) ??
        Offset.zero;
  }

  bool _worldInOpsLockedPaper(Offset world) {
    for (final paper in papers) {
      if (!paper.isOpsLocked) continue;
      final hs = _paperHalfSizeForLevel(paper.sizeLevel);
      final verts = paper.localVertices ??
          [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];
      final rad = paper.rotationDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);
      final dx = world.dx - paper.position.x;
      final dy = world.dy - paper.position.y;
      final local = Offset(dx * cosA + dy * sinA, -dx * sinA + dy * cosA);
      if (!_pointInPolygonPainter(local, verts)) continue;
      var inHole = false;
      for (final hole in paper.localHoles) {
        if (hole.length >= 3 && _pointInPolygonPainter(local, hole)) {
          inHole = true;
          break;
        }
      }
      if (!inHole) return true;
    }
    return false;
  }

  bool _worldInStencil(Offset world) {
    if (!stencilVisible) return false;
    final local = world - stencilPosition;
    if (stencilShape == StencilShape.circle) {
      final nx = local.dx / math.max(stencilHalfW, 1e-6);
      final ny = local.dy / math.max(stencilHalfH, 1e-6);
      return nx * nx + ny * ny <= 1;
    }
    return local.dx.abs() <= stencilHalfW && local.dy.abs() <= stencilHalfH;
  }

  void _drawStencilGridX(Canvas canvas, Offset pt, double opacity) {
    const s = 3.2;
    final paint = Paint()
      ..color = const Color(0xFFE53935).withValues(alpha: opacity)
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pt + const Offset(-s, -s), pt + const Offset(s, s), paint);
    canvas.drawLine(pt + const Offset(-s, s), pt + const Offset(s, -s), paint);
  }

  void _drawStencil(Canvas canvas, Size size, Matrix4 viewProjection) {
    final hw = stencilHalfW;
    final hh = stencilHalfH;
    final outline = <Offset>[];
    if (stencilShape == StencilShape.circle) {
      const n = 48;
      for (var i = 0; i < n; i++) {
        outline.add(
          _stencilLocalToScreen(
            Offset(
              hw * math.cos(2 * math.pi * i / n),
              hh * math.sin(2 * math.pi * i / n),
            ),
            viewProjection,
            size,
          ),
        );
      }
    } else {
      for (final p in [
        Offset(-hw, -hh),
        Offset(hw, -hh),
        Offset(hw, hh),
        Offset(-hw, hh),
      ]) {
        outline.add(_stencilLocalToScreen(p, viewProjection, size));
      }
    }
    if (outline.length < 2) return;

    final path = Path()..addPolygon(outline, true);
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFE53935);
    _drawDashedPath(canvas, path, 7, 5, dashPaint);

    if (!stencilSelected) return;

    final handles = [
      _stencilLocalToScreen(Offset(0, hh), viewProjection, size),
      _stencilLocalToScreen(Offset(hw, 0), viewProjection, size),
      _stencilLocalToScreen(Offset(0, -hh), viewProjection, size),
      _stencilLocalToScreen(Offset(-hw, 0), viewProjection, size),
      _stencilLocalToScreen(Offset(-hw, hh), viewProjection, size),
      _stencilLocalToScreen(Offset(hw, hh), viewProjection, size),
      _stencilLocalToScreen(Offset(hw, -hh), viewProjection, size),
      _stencilLocalToScreen(Offset(-hw, -hh), viewProjection, size),
    ];
    const handleSize = 6.0;
    final handleFill = Paint()..color = const Color(0xFFE53935);
    final handleStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final activeFill = Paint()..color = Colors.yellowAccent;
    for (var i = 0; i < handles.length; i++) {
      final h = handles[i];
      final isCorner = i >= 4;
      final fill = stencilHandleIndex == i ? activeFill : handleFill;
      final hs = isCorner ? handleSize : handleSize * 0.85;
      final rect = Rect.fromCenter(center: h, width: hs * 2, height: hs * 2);
      if (isCorner) {
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, handleStroke);
      } else {
        canvas.drawOval(rect, fill);
        canvas.drawOval(rect, handleStroke);
      }
    }
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    double dashLen,
    double gapLen,
    Paint paint,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLen;
      }
    }
  }

  void _drawStretchGizmo(Canvas canvas, Size size, Matrix4 viewProjection) {
    final paper = papers.where((p) => p.id == stretchPaperId).firstOrNull;
    if (paper == null) return;

    final bounds =
        stretchDisplayBounds ??
        stretchStartBounds ??
        _paperLocalBoundsForPainter(paper);
    final cx = paper.position.x;
    final cy = paper.position.y;
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final start = stretchStartBounds ?? bounds;
    final sx = start.width.abs() < 1e-9 ? 1.0 : bounds.width / start.width;
    final sy = start.height.abs() < 1e-9 ? 1.0 : bounds.height / start.height;

    Offset toScreen(double lx, double ly) {
      final wx = cx + lx * cosA - ly * sinA;
      final wy = cy + lx * sinA + ly * cosA;
      return _projectToScreen(Vector3(wx, wy, 1.01), viewProjection, size) ??
          Offset.zero;
    }

    final l = bounds.left, r = bounds.right;
    final t = bounds.top, b = bounds.bottom;

    // Bounding box corners in screen space
    final tl = toScreen(l, b);
    final tr = toScreen(r, b);
    final br = toScreen(r, t);
    final bl = toScreen(l, t);

    // Draw bounding box
    final boxPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final boxPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(boxPath, boxPaint);

    // Handle positions: 0=top, 1=right, 2=bottom, 3=left, 4-7=corners
    final mx = (l + r) / 2, my = (t + b) / 2;
    final handles = [
      toScreen(mx, b), // 0: top
      toScreen(r, my), // 1: right
      toScreen(mx, t), // 2: bottom
      toScreen(l, my), // 3: left
      tl, // 4: TL
      tr, // 5: TR
      br, // 6: BR
      bl, // 7: BL
    ];

    const handleSize = 6.0;
    final handleFill = Paint()..color = Colors.cyanAccent;
    final handleStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final activeHandleFill = Paint()..color = Colors.yellowAccent;

    for (var i = 0; i < handles.length; i++) {
      final h = handles[i];
      final isCorner = i >= 4;
      final isActive = stretchHandleIndex == i;
      final fill = isActive ? activeHandleFill : handleFill;
      final hs = isCorner ? handleSize : handleSize * 0.85;
      final rect = Rect.fromCenter(center: h, width: hs * 2, height: hs * 2);
      if (isCorner) {
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, handleStroke);
      } else {
        canvas.drawOval(rect, fill);
        canvas.drawOval(rect, handleStroke);
      }
    }

    // Percentage readout during active drag
    if (stretchHandleIndex != null &&
        ((sx - 1.0).abs() > 1e-4 || (sy - 1.0).abs() > 1e-4)) {
      final activeIdx = stretchHandleIndex ?? 0;
      final hPos = handles[activeIdx.clamp(0, 7)];
      final stretchesX = activeIdx == 1 || activeIdx == 3 || activeIdx >= 4;
      final stretchesY = activeIdx == 0 || activeIdx == 2 || activeIdx >= 4;
      final parts = <String>[];
      String fmtPct(double s) {
        final pct = ((s - 1) * 100).round();
        return pct >= 0 ? '+$pct%' : '$pct%';
      }

      if (stretchesX) parts.add('W:${fmtPct(sx)}');
      if (stretchesY) parts.add('H:${fmtPct(sy)}');
      final label = parts.join(' ');

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          hPos.dx - tp.width / 2 - 6,
          hPos.dy - tp.height - 14,
          tp.width + 12,
          tp.height + 6,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        bgRect,
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );
      tp.paint(
        canvas,
        Offset(hPos.dx - tp.width / 2, hPos.dy - tp.height - 11),
      );
    }
  }

  Rect _paperLocalBoundsForPainter(PlacedPaper paper) {
    final verts = paper.localVertices ?? _defaultSquareVerts(paper);
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final v in verts) {
      if (v.dx < minX) minX = v.dx;
      if (v.dx > maxX) maxX = v.dx;
      if (v.dy < minY) minY = v.dy;
      if (v.dy > maxY) maxY = v.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<Offset> _defaultSquareVerts(PlacedPaper paper) {
    final hs = _paperHalfSizeForLevel(paper.sizeLevel);
    return [Offset(-hs, -hs), Offset(hs, -hs), Offset(hs, hs), Offset(-hs, hs)];
  }

  @override
  bool shouldRepaint(covariant CraftingTestPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Config popover overlay
// ---------------------------------------------------------------------------

class _ConfigPopover extends StatelessWidget {
  const _ConfigPopover({
    required this.canvasDisplayMode,
    required this.showMinorLines,
    required this.gridRegionAssist,
    required this.cutSpeed,
    required this.onChanged,
    required this.onDismiss,
  });

  final CanvasDisplayMode canvasDisplayMode;
  final bool showMinorLines;
  final bool gridRegionAssist;
  final double cutSpeed;
  final void Function(
    CanvasDisplayMode mode,
    bool minor,
    bool regionAssist,
    double speed,
  )
  onChanged;
  final VoidCallback onDismiss;

  void _fire({
    CanvasDisplayMode? mode,
    bool? minor,
    bool? regionAssist,
    double? speed,
  }) {
    onChanged(
      mode ?? canvasDisplayMode,
      minor ?? showMinorLines,
      regionAssist ?? gridRegionAssist,
      speed ?? cutSpeed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onDismiss,
          child: const SizedBox.expand(),
        ),
        FmSafePositioned(
          top: 48,
          right: 64,
          child: Material(
            color: const Color(0xEE1A1A2E),
            borderRadius: BorderRadius.circular(12),
            elevation: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Canvas',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in CanvasDisplayMode.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(
                              mode == CanvasDisplayMode.none
                                  ? 'None'
                                  : mode == CanvasDisplayMode.dot
                                  ? 'Dot'
                                  : 'Grid',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: canvasDisplayMode == mode,
                            selectedColor: Colors.white.withValues(alpha: 0.2),
                            backgroundColor: Colors.transparent,
                            side: BorderSide(
                              color: canvasDisplayMode == mode
                                  ? Colors.white38
                                  : Colors.white12,
                            ),
                            labelStyle: TextStyle(
                              color: canvasDisplayMode == mode
                                  ? Colors.white
                                  : Colors.white54,
                            ),
                            onSelected: (_) => _fire(mode: mode),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _checkRow(
                    'Minor lines',
                    showMinorLines,
                    (v) => _fire(minor: v),
                  ),
                  _checkRow(
                    'Grid region assist',
                    gridRegionAssist,
                    (v) => _fire(regionAssist: v),
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  const Text(
                    'Debug',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Cut speed: ${cutSpeed.toStringAsFixed(0)} cells/s',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 200,
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: Colors.redAccent,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: Colors.redAccent,
                        overlayColor: Colors.redAccent.withOpacity(0.2),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: cutSpeed,
                        min: 1,
                        max: 50,
                        onChanged: (v) => _fire(speed: v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _checkRow(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: Colors.tealAccent.shade200,
                side: const BorderSide(color: Colors.white38),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: value ? Colors.white : Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Projection helpers (shared by hit tests, overlays, and CraftingTestPainter)
// ---------------------------------------------------------------------------

Matrix4 craftingTestViewProjection(
  Size size,
  double orthoScale, {
  Offset panOffset = Offset.zero,
  double viewRotation = 0,
}) {
  final camera = scene_camera.Camera(
    name: 'shadow-cam',
    position: Vector3(panOffset.dx, panOffset.dy, 500),
    target: Vector3(panOffset.dx, panOffset.dy, 0),
    up: Vector3(-math.sin(viewRotation), math.cos(viewRotation), 0),
    projection: scene_camera.ProjectionType.orthographic,
    orthographicScale: orthoScale,
    near: 0.1,
    far: 1500,
  );
  final aspect = size.width / size.height;
  return camera.projectionMatrix(aspect) * camera.viewMatrix;
}

/// Inverse of [_projectToScreen] for a world z = [planeZ] (same plane as papers).
Vector3 craftingScreenToWorldOnPlane(
  Offset screen,
  Size size,
  double orthoScale,
  double planeZ, {
  Offset panOffset = Offset.zero,
  double viewRotation = 0,
}) {
  if (size.width <= 0 || size.height <= 0) {
    return Vector3(0, 0, planeZ);
  }
  final mvp = craftingTestViewProjection(
    size,
    orthoScale,
    panOffset: panOffset,
    viewRotation: viewRotation,
  );
  final inv = Matrix4.copy(mvp);
  final determinant = inv.invert();
  if (determinant == 0 || determinant.isNaN) {
    final aspect = size.width / size.height;
    final ndcX = 2.0 * screen.dx / size.width - 1.0;
    final ndcY = 1.0 - 2.0 * screen.dy / size.height;
    final vx = ndcX * orthoScale * aspect;
    final vy = ndcY * orthoScale;
    final c = math.cos(viewRotation);
    final s = math.sin(viewRotation);
    return Vector3(
      panOffset.dx + vx * c - vy * s,
      panOffset.dy + vx * s + vy * c,
      planeZ,
    );
  }
  final ndcX = 2.0 * screen.dx / size.width - 1.0;
  final ndcY = 1.0 - 2.0 * screen.dy / size.height;

  Vector3? homog(Vector4 v) {
    final w = v.w;
    if (w.abs() < 1e-10) return null;
    return Vector3(v.x / w, v.y / w, v.z / w);
  }

  final a = homog(inv.transform(Vector4(ndcX, ndcY, -1.0, 1.0)));
  final b = homog(inv.transform(Vector4(ndcX, ndcY, 1.0, 1.0)));
  if (a == null || b == null) {
    return Vector3(panOffset.dx, panOffset.dy, planeZ);
  }
  final dir = b - a;
  if (dir.z.abs() < 1e-8) {
    return Vector3(a.x, a.y, planeZ);
  }
  final t = (planeZ - a.z) / dir.z;
  return a + dir * t;
}

Offset craftingWorldToScreen(
  Vector3 worldPos,
  Size size,
  double orthoScale, {
  Offset panOffset = Offset.zero,
  double viewRotation = 0,
}) {
  final mvp = craftingTestViewProjection(
    size,
    orthoScale,
    panOffset: panOffset,
    viewRotation: viewRotation,
  );
  return _projectToScreen(worldPos, mvp, size) ?? Offset.zero;
}

/// Unit +X of a grid whose +Y points at world angle [yAngle].
Offset _gridXDir(double yAngle) =>
    Offset(math.sin(yAngle), -math.cos(yAngle));

/// Unit +Y of a grid whose +Y points at world angle [yAngle].
Offset _gridYDir(double yAngle) =>
    Offset(math.cos(yAngle), math.sin(yAngle));

Offset _worldToGridCoords(Offset world, Offset origin, double yAngle) {
  final xDir = _gridXDir(yAngle);
  final yDir = _gridYDir(yAngle);
  final rel = world - origin;
  return Offset(
    rel.dx * xDir.dx + rel.dy * xDir.dy,
    rel.dx * yDir.dx + rel.dy * yDir.dy,
  );
}

Offset _gridCoordsToWorld(Offset grid, Offset origin, double yAngle) {
  final xDir = _gridXDir(yAngle);
  final yDir = _gridYDir(yAngle);
  return Offset(
    origin.dx + grid.dx * xDir.dx + grid.dy * yDir.dx,
    origin.dy + grid.dx * xDir.dy + grid.dy * yDir.dy,
  );
}

double _undirectedEdgeAngle(double atan) {
  var a = atan;
  while (a <= -math.pi / 2) {
    a += math.pi;
  }
  while (a > math.pi / 2) {
    a -= math.pi;
  }
  return a;
}

/// Dominant undirected edge axis → grid +Y, with a vertex as the origin.
///
/// Orientation: most common undirected edge direction (180° collapses to the
/// same axis). Anchor: blueprint vertex furthest left, then highest.
({Offset anchor, double yAngle})? _computeDominantGridFrame(
  List<List<Offset>> polygons,
) {
  // Quantize undirected angles to 0.5° buckets; score by edge count, then length.
  const step = math.pi / 360;
  final countByBucket = <int, int>{};
  final lengthByBucket = <int, double>{};

  for (final poly in polygons) {
    if (poly.length < 2) continue;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final d = b - a;
      final len = d.distance;
      if (len < 1e-9) continue;
      final undirected = _undirectedEdgeAngle(math.atan2(d.dy, d.dx));
      final q = (undirected / step).round();
      countByBucket[q] = (countByBucket[q] ?? 0) + 1;
      lengthByBucket[q] = (lengthByBucket[q] ?? 0) + len;
    }
  }
  if (countByBucket.isEmpty) return null;

  var bestQ = countByBucket.keys.first;
  var bestCount = countByBucket[bestQ]!;
  var bestLen = lengthByBucket[bestQ] ?? 0.0;
  for (final e in countByBucket.entries) {
    final len = lengthByBucket[e.key] ?? 0.0;
    if (e.value > bestCount || (e.value == bestCount && len > bestLen)) {
      bestCount = e.value;
      bestLen = len;
      bestQ = e.key;
    }
  }

  var undirected = bestQ * step;
  undirected = _undirectedEdgeAngle(undirected);

  // Pick a directed +Y among the two orientations on this axis.
  // Prefer the direction closer to world +Y, then +X.
  double score(double ang) => math.sin(ang) * 2 + math.cos(ang);
  var yAngle = undirected;
  final alt = undirected + math.pi;
  if (score(alt) > score(yAngle)) yAngle = alt;

  // Anchor = furthest left, then highest (world +Y up) among all verts.
  Offset? anchor;
  for (final poly in polygons) {
    for (final v in poly) {
      if (anchor == null ||
          v.dx < anchor.dx - 1e-9 ||
          ((v.dx - anchor.dx).abs() < 1e-9 && v.dy > anchor.dy)) {
        anchor = v;
      }
    }
  }
  if (anchor == null) return null;

  return (anchor: anchor, yAngle: yAngle);
}

/// Undirected edge angles in (-π/2, π/2], so 0° and 180° collapse to one axis.
List<double> _viewOrientationCandidates(List<List<Offset>> polygons) {
  final angles = <double>{0.0};
  void addEdgeAngle(double atan) {
    // Map to (-π/2, π/2]: α and α+π are the same undirected line.
    var a = atan;
    while (a <= -math.pi / 2) {
      a += math.pi;
    }
    while (a > math.pi / 2) {
      a -= math.pi;
    }
    // Quantize to 0.5° to merge near-duplicates.
    const step = math.pi / 360;
    final q = (a / step).round() * step;
    var nq = q;
    while (nq <= -math.pi / 2) {
      nq += math.pi;
    }
    while (nq > math.pi / 2) {
      nq -= math.pi;
    }
    if (nq.abs() < 1e-9) nq = 0;
    angles.add(nq);
  }

  for (final poly in polygons) {
    if (poly.length < 2) continue;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final d = b - a;
      if (d.distanceSquared < 1e-12) continue;
      addEdgeAngle(math.atan2(d.dy, d.dx));
    }
  }
  return angles.toList();
}

/// Axis-aligned bounds of [points] in a frame whose +X is world angle [phi].
({Offset center, double width, double height}) _orientedBounds(
  List<Offset> points,
  double phi,
) {
  final c = math.cos(phi);
  final s = math.sin(phi);
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final p in points) {
    final lx = p.dx * c + p.dy * s;
    final ly = -p.dx * s + p.dy * c;
    if (lx < minX) minX = lx;
    if (lx > maxX) maxX = lx;
    if (ly < minY) minY = ly;
    if (ly > maxY) maxY = ly;
  }
  final midX = (minX + maxX) / 2;
  final midY = (minY + maxY) / 2;
  // Local (midX, midY) → world via basis X=(c,s), Y=(-s,c).
  final center = Offset(midX * c - midY * s, midX * s + midY * c);
  return (center: center, width: maxX - minX, height: maxY - minY);
}

class _Face {
  _Face({required this.points, required this.color, required this.depth});
  final List<Offset> points;
  final Color color;
  final double depth;
}

Vector4 _transformPosition(Matrix4 matrix, Vector3 position) {
  final storage = matrix.storage;
  final x = position.x;
  final y = position.y;
  final z = position.z;
  return Vector4(
    storage[0] * x + storage[4] * y + storage[8] * z + storage[12],
    storage[1] * x + storage[5] * y + storage[9] * z + storage[13],
    storage[2] * x + storage[6] * y + storage[10] * z + storage[14],
    storage[3] * x + storage[7] * y + storage[11] * z + storage[15],
  );
}

Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
  final clip = _transformPosition(mvp, worldPos);
  if (!_vector4IsFinite(clip) || clip.w < 1e-3) return null;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (!ndcX.isFinite || !ndcY.isFinite) return null;
  final screenX = (ndcX * 0.5 + 0.5) * size.width;
  final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
  if (!screenX.isFinite || !screenY.isFinite) return null;
  return Offset(screenX, screenY);
}

bool _vector4IsFinite(Vector4 value) {
  return value.x.isFinite &&
      value.y.isFinite &&
      value.z.isFinite &&
      value.w.isFinite;
}

Vector3 _faceNormal(List<Vector3> vertices) {
  final a = vertices[0];
  final b = vertices[1];
  final c = vertices[2];
  final edge1 = b - a;
  final edge2 = c - a;
  final normal = edge1.cross(edge2);
  if (normal.length2 == 0) return Vector3.zero();
  return normal.normalized();
}

double _shadeForFace(
  Vector3 normal,
  List<DirectionalLight> lights,
  double globalIllumination,
) {
  if (normal.length2 == 0) return globalIllumination.clamp(0.0, 1.0);
  final normalizedNormal = normal.normalized();
  var lightContribution = 0.0;
  for (final light in lights) {
    final dir = (-light.direction).normalized();
    final intensity = math.max(0, normalizedNormal.dot(dir)) * light.intensity;
    lightContribution += intensity;
  }
  return (globalIllumination + lightContribution).clamp(0.0, 1.0);
}

Color _applyLighting(Color base, double factor) {
  final r = (base.red * factor).clamp(0, 255).toInt();
  final g = (base.green * factor).clamp(0, 255).toInt();
  final b = (base.blue * factor).clamp(0, 255).toInt();
  return Color.fromARGB(base.alpha, r, g, b);
}

class _ToolModeButton extends StatelessWidget {
  const _ToolModeButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
