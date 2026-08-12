import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/crafting_blueprint.dart';
import '../crafting/crafting_history.dart';
import '../crafting/crafting_material.dart';
import '../crafting/blueprint_set.dart';
import '../crafting/placed_paper.dart';
import '../data/crafting_state.dart';
import '../crafting/paper_splitting.dart';
import '../gameplay/inventory.dart';
import '../geometry/polygon_union.dart';
import '../geometry/geometry.dart';
import '../geometry/geometry_algorithms.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/friend_expression.dart';
import '../rendering/lights.dart';
import '../rendering/scene/camera.dart' as scene_camera;
import '../tiles/tiles.dart';
import '../gestures/gesture_system.dart';
import 'fm_haptics.dart';
import 'fm_safe_area.dart';
import 'fm_step_cards.dart';
import 'object_radial_menu.dart';
import 'rotation_gizmo.dart';
import 'wipe_animation.dart';

/// Paper resize controls in the radial menu (disabled for now).
const _kPaperSizeControlsEnabled = false;

/// Friend walk animation during cut (disabled for now; logic preserved).
const _kCutFriendAnimationEnabled = false;

const _noOpUndoLabels = {'Select', 'Deselect'};

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
  });

  final List<List<Offset>> blueprintPolygons;
  final List<List<Offset>> paperPolygons;
  final double tolerance;
}

class _AABB {
  const _AABB(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;
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

  for (final paper in params.paperPolygons) {
    if (paper.length < 3) continue;
    final cleaned = _removeCollinears(_dedup(paper, dedupTol), angularTolRad);
    final pBox = _aabb(cleaned);
    final candidates = hash.query(
      _AABB(pBox.minX - tol, pBox.minY - tol, pBox.maxX + tol, pBox.maxY + tol),
    );
    if (candidates.isEmpty) continue;

    for (final bpIdx in candidates) {
      if (filled.contains(bpIdx)) continue;
      if (_shapesMatch(cleaned, bpClean[bpIdx], tol)) {
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
  translationCopy,
  erase,
  alignGrid,
  stretch,
}

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

// ---------------------------------------------------------------------------
// Completion animation
// ---------------------------------------------------------------------------

enum CompletionPhase { none, dissolveReveal, fold, done }

class _FoldNodeState {
  _FoldNodeState({
    required this.nodeId,
    required this.node,
    required this.unfoldedVertices3D,
  });

  final int nodeId;
  final TransformTreeNode node;
  final List<Vector3> unfoldedVertices3D;
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

  PlacedPaper toPaper() {
    final p = PlacedPaper(
      id: id,
      paperColor: paperColor,
      position: position.clone(),
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
    this.defaultBlueprintName,
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

  /// When true, the drawing-plane outline is hidden (e.g. inside room editor).
  final bool hideDrawingPlane;

  /// When true, plays a horizontal dot-wipe reveal on entry.
  final bool showDotWipe;

  /// When set, the blueprint with this name is auto-selected after loading.
  final String? defaultBlueprintName;

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
  State<CraftingTestView> createState() => _CraftingTestViewState();
}

class _CraftingTestViewState extends State<CraftingTestView>
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

  // Mirror tool
  Offset? _mirrorLineStart;
  Offset? _mirrorLinePreview;

  // Rotation copy tool
  Offset? _rotCopyCenterWorld;
  bool _rotCopyGizmoActive = false;
  double _rotCopyAngleDeg = 0;

  // Translation copy tool
  Offset? _transCopyStartWorld;
  Offset? _transCopyCurrentWorld;

  // Selection & interaction
  Set<String> _selectedPaperIds = {};
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
  bool _blueprintUnionMode = false;
  List<List<Offset>> _blueprintUnionPolygons = [];

  // Blueprint sets
  List<BlueprintSet> _blueprintSets = [];
  BlueprintSet? _selectedSet;
  int _currentStepIndex = 0;
  int? _promotingIndex;
  final Set<int> _completedStepIndices = {};

  /// Guards against double-advance while a step completion is in flight.
  bool _stepAdvanceInProgress = false;

  /// Non-active group step polygons drawn grey/green behind the editable step.
  List<List<Offset>> _groupOverlayPolygons = [];
  List<Color> _groupOverlayColors = [];

  /// Active-step outline highlight (0 = grey → 1 = yellow) and early glow.
  double _activeHighlightT = 1.0;
  double _activeGlow = 0.0;

  // Camera ease-in-out transitions (group overview → step, step → step).
  late final AnimationController _cameraAnimController;
  Offset _camPanFrom = Offset.zero;
  Offset _camPanTo = Offset.zero;
  double _camOrthoFrom = 300;
  double _camOrthoTo = 300;
  double _camRotFrom = 0;
  double _camRotTo = 0;
  bool _cameraIntroHighlight = false;

  /// Group intro requested before the first layout pass had a real viewport.
  bool _pendingGroupIntro = false;

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

  // Stretch tool
  String? _stretchPaperId;
  Offset? _stretchHandleStartWorld;
  int? _stretchHandleIndex; // 0-3 edges (T,R,B,L), 4-7 corners (TL,TR,BR,BL)
  double _stretchScaleX = 1.0;
  double _stretchScaleY = 1.0;
  Rect? _stretchOriginalBounds; // local-space AABB before drag began
  Offset _stretchAnchorLocal =
      Offset.zero; // opposite edge/corner in local space

  // Blueprint progress tracking
  double _blueprintTotalArea = 0;
  double _blueprintLockedArea = 0;

  // Craft execute button (shown at 100% coverage)
  bool _craftExecuteButtonVisible = false;
  late final AnimationController _craftButtonAnimController;

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
  /// The two-click Align Grid tool sets this from the vector between picks.
  double _gridRotation = math.pi / 2;

  // Align-grid tool: phase 0 = pick origin, phase 1 = pick +Y direction point.
  int _alignGridPhase = 0;
  int? _alignGridHoveredPolyIndex;
  Offset? _alignGridPreviewVertex;
  Offset? _alignGridSecondPreview;
  Offset? _alignGridPointerDown;

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

  /// Once multitouch is seen, tools stay dead until *every* finger lifts.
  /// Prevents the last finger-up from committing paint/erase/cut/etc.
  bool _toolsSuppressedUntilPointersUp = false;
  int _canvasPointerCount = 0;
  Offset? _pinchStartPan;
  double? _pinchStartOrtho;
  Offset? _pinchAnchorWorld;

  /// Undo-stack depth at the start of the current one-finger tool gesture.
  /// Multitouch aborts revert any history pushed beyond this.
  int _toolGestureUndoDepthAtDown = 0;

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
      _canvasPointerCount >= 2;

  void _clearPinchBaseline() {
    _pinchStartPan = null;
    _pinchStartOrtho = null;
    _pinchAnchorWorld = null;
  }

  void _beginToolGestureBaseline() {
    _toolGestureUndoDepthAtDown = _history.undoDepth;
    _preGestureGridOrigin = _gridOriginOffset;
    _preGestureGridRotation = _gridRotation;
  }

  void _lockToolsForMultiTouch() {
    _toolsSuppressedUntilPointersUp = true;
  }

  void _maybeUnlockToolsAfterPointersUp() {
    if (_canvasPointerCount <= 0) {
      _canvasPointerCount = 0;
      _toolsSuppressedUntilPointersUp = false;
      _isMultiTouch = false;
      _clearPinchBaseline();
    }
  }

  /// Cancel any in-progress one-finger tool work when a second finger lands.
  /// Reverts history pushed during the gesture, clears previews, and restores
  /// align-grid pose. Camera pan/zoom state is kept so pinch can continue.
  void _abortToolGestureForMultiTouch() {
    // Revert mutations (move/stretch/etc.) recorded after finger-down.
    var reverted = false;
    while (_history.undoDepth > _toolGestureUndoDepthAtDown &&
        _history.canUndo) {
      final snap = _history.undo(_currentSnapshot('cancel-multitouch'));
      if (snap != null) {
        _placedPapers
          ..clear()
          ..addAll(snap.papers.map((s) => s.toPaper()));
        _nextPaperId = snap.nextPaperId;
        _inventory
          ..clear()
          ..addAll(snap.inventory);
        _selectedPaperIds = Set<String>.from(snap.selectedPaperIds);
        reverted = true;
      }
    }
    _history.clearRedo();
    _toolGestureUndoDepthAtDown = _history.undoDepth;

    // Align-grid live-edits the grid without undo — snap back.
    final gridChanged =
        _gridOriginOffset != _preGestureGridOrigin ||
        _gridRotation != _preGestureGridRotation;

    setState(() {
      if (gridChanged) {
        _gridOriginOffset = _preGestureGridOrigin;
        _gridRotation = _preGestureGridRotation;
      }
      if (reverted) {
        _isRotationGizmoActive = false;
      }

      _pointerDownPos = null;
      _pointerDownPaperId = null;
      _isDragging = false;
      _dragPaperId = null;
      _isMarquee = false;
      _marqueeStartScreen = null;
      _marqueeCurrentScreen = null;
      _lineDrawStart = null;
      _lineDrawPreview = null;
      // Pan tool one-finger camera drag — must clear or a later move applies a
      // huge stale delta against the pre-pinch finger position (pinch jitter).
      _panDragLastScreen = null;
      _panModeDragging = false;
      _panModeDragLastScreen = null;
      _paintedCells = {};
      _lastPaintCell = null;
      _paintDragPaperId = null;
      _paintDragLastScreen = null;
      _paintHadSelection = false;
      _paintDeferredCell = null;
      _paintSelectionIds = {};
      _mirrorLineStart = null;
      _mirrorLinePreview = null;
      _transCopyStartWorld = null;
      _transCopyCurrentWorld = null;
      _erasedCells = {};
      _lastEraseCell = null;
      _alignGridPhase = 0;
      _alignGridPointerDown = null;
      _alignGridHoveredPolyIndex = null;
      _alignGridPreviewVertex = null;
      _alignGridSecondPreview = null;
      // Drop in-progress stretch without committing.
      _stretchHandleIndex = null;
      _stretchHandleStartWorld = null;
      _stretchOriginalBounds = null;
      _stretchScaleX = 1.0;
      _stretchScaleY = 1.0;
      _stretchAnchorLocal = Offset.zero;
    });

    if (reverted) {
      _scheduleCheck();
      _updateCraftExecuteButtonVisibility();
    }
    if (gridChanged) _scheduleGridLodSync();
  }

  /// Stable two-finger pan/zoom from [GestureClassifier] (span from gesture start).
  void _onCraftGesture(GestureState state, Size viewportSize) {
    if (_completionPhase != CompletionPhase.none) return;

    // Real two-finger touch, or trackpad pan-zoom (synthetic twoFingerDrag).
    final isTwoFinger = state.pointerCount >= 2 ||
        (state.type == GestureType.twoFingerDrag && state.pointers.isEmpty);

    if (isTwoFinger) {
      // Child Listener may have already flagged multitouch to suppress tools;
      // still (re)capture baselines if missing so pinch can run.
      final needsBaseline = _pinchStartOrtho == null ||
          _pinchStartPan == null ||
          _pinchAnchorWorld == null;
      if (!_isMultiTouch) {
        _isMultiTouch = true;
        _lockToolsForMultiTouch();
        _abortToolGestureForMultiTouch();
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
      // Leave pinch mode when fingers drop below 2, but keep tools locked
      // until the pointer count hits zero (last finger-up must not commit).
      _isMultiTouch = false;
      _clearPinchBaseline();
      _panDragLastScreen = null;
      _panModeDragging = false;
      _panModeDragLastScreen = null;
      _pointerDownPos = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _drawingPlaneSize = _computeDrawingPlaneSize();
    if (widget.canvasSize != null) {
      _orthoScale = widget.initialOrthoScale ?? _drawingPlaneSize * 1.1;
    }
    _geometry = _buildGeometry();

    _cutAnimController = AnimationController(vsync: this)
      ..addListener(_onCutAnimTick)
      ..addStatusListener(_onCutAnimStatus);

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

    _craftButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));

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
    _marqueeDashController.dispose();
    _lockAnimController.dispose();
    _progressAnimController.dispose();
    _dissolveController.dispose();
    _foldController.dispose();
    _magnetAnimController.dispose();
    _craftButtonAnimController.dispose();
    _gridLodAnimController.dispose();
    _cameraAnimController.dispose();
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
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where(
          (p) =>
              p.startsWith('assets/crafting_blueprints/') &&
              p.endsWith('.json') &&
              !p.endsWith('/group.json'),
        )
        .toList();

    final loaded = <CraftingBlueprint>[];
    for (final path in paths) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        loaded.add(CraftingBlueprint.fromJson(json));
      } catch (_) {
        // Skip malformed files.
      }
    }
    final groupDefs = await BlueprintGroupDef.loadAll();
    if (mounted) {
      setState(() {
        _blueprints = loaded;
        _blueprintSets = _buildBlueprintSets(loaded, groupDefs);
      });
      // Prefer Group 05 as the default craft; fall back to widget override.
      final group05 = _blueprintSets
          .where(
            (s) =>
                s.isGroup &&
                s.steps.any((st) => st.craft.toLowerCase() == 'group05'),
          )
          .firstOrNull;
      if (group05 != null && _selectedSet == null) {
        _selectBlueprintSet(group05);
      } else if (widget.defaultBlueprintName != null &&
          _selectedBlueprint == null) {
        final match = loaded
            .where((b) => b.craft == widget.defaultBlueprintName)
            .firstOrNull;
        if (match != null) {
          _selectBlueprint(match);
        }
      }
    }
  }

  List<BlueprintSet> _buildBlueprintSets(
    List<CraftingBlueprint> blueprints,
    List<BlueprintGroupDef> groupDefs,
  ) {
    final sets = <BlueprintSet>[];
    final groupedCrafts = <String>{};

    for (final def in groupDefs) {
      final set = def.toBlueprintSet(
        blueprints,
        minorGridSpacing: _minorGridSpacing,
      );
      if (set == null) continue;
      sets.add(set);
      groupedCrafts.add(def.craftFolder.toLowerCase());
    }

    // Islands not covered by a group.json remain selectable as single-step sets.
    for (final bp in blueprints) {
      if (groupedCrafts.contains(bp.craft.toLowerCase())) continue;
      sets.add(BlueprintSet.single(bp));
    }

    return sets;
  }

  CraftingBlueprint? _findBlueprintForStep(BlueprintStep step) {
    return _blueprints
        .where((b) => b.craft == step.craft && b.island == step.island)
        .firstOrNull;
  }

  void _selectBlueprintSet(BlueprintSet? set) {
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
      _promotingIndex = null;
      _stepAdvanceInProgress = false;
      // Fresh group/set session — drop prior locked papers from the canvas.
      _placedPapers.removeWhere((p) => p.locked);
    });

    final bp = _findBlueprintForStep(set.steps[0]);
    if (set.isGroup) {
      _selectBlueprint(bp, playGroupIntro: true);
    } else {
      _selectBlueprint(bp);
    }
  }

  void _advanceToNextStep() {
    if (_selectedSet == null) return;
    if (_stepAdvanceInProgress) {
      debugPrint(
        '[craft-group] advance ignored (already in progress) '
        'step=$_currentStepIndex completed=$_completedStepIndices',
      );
      return;
    }
    final nextIndex = _currentStepIndex + 1;
    if (nextIndex >= _selectedSet!.steps.length) return;
    final isGroup = _selectedSet!.isGroup;
    final fromStep = _currentStepIndex;

    debugPrint(
      '[craft-group] advance $fromStep → $nextIndex '
      '(group=$isGroup, filled=${_filledBlueprintIndices.length}, '
      'lockedArea=$_blueprintLockedArea/$_blueprintTotalArea)',
    );

    _stepAdvanceInProgress = true;
    setState(() {
      _completedStepIndices.add(fromStep);
      // Commit matched papers so later steps can't rematch or clear them.
      for (final paper in _placedPapers) {
        if (paper.lockedBlueprintIndex != null) {
          paper.locked = true;
        }
      }
      // Invalidate completion immediately so visibility/check can't re-fire
      // advance while we wait for the card transition.
      _filledBlueprintIndices = {};
      _blueprintLockedArea = 0;
      _blueprintTotalArea = 0;
      if (!isGroup) {
        _placedPapers.clear();
        _blueprintWorldPolygons = [];
        _blueprintUnionPolygons = [];
      }
      _completionPhase = CompletionPhase.none;
      _craftExecuteButtonVisible = false;
      _foldNodeStates = {};
      _foldSchedule = [];
      _dotDissolveProgress = 0;
      _foldOpacity = 0;
      _foldColorProgress = 0;
    });

    Future.delayed(FmStepCards.baseDuration, () {
      if (!mounted) {
        _stepAdvanceInProgress = false;
        return;
      }
      if (_selectedSet == null) {
        _stepAdvanceInProgress = false;
        return;
      }
      debugPrint(
        '[craft-group] loading step $nextIndex '
        '(papers=${_placedPapers.length}, '
        'locked=${_placedPapers.where((p) => p.locked).length})',
      );
      setState(() {
        _promotingIndex = nextIndex;
        _currentStepIndex = nextIndex;
      });
      Future.delayed(FmStepCards.promoteDuration, () {
        if (!mounted) return;
        if (_promotingIndex == nextIndex) {
          setState(() => _promotingIndex = null);
        }
      });
      final bp = _findBlueprintForStep(_selectedSet!.steps[nextIndex]);
      _selectBlueprint(bp, animateCameraToStep: isGroup);
      _stepAdvanceInProgress = false;
      debugPrint(
        '[craft-group] now on step $_currentStepIndex '
        'completed=$_completedStepIndices '
        'activePolys=${_blueprintWorldPolygons.length} '
        'totalArea=$_blueprintTotalArea',
      );
    });
  }

  void _selectBlueprint(
    CraftingBlueprint? blueprint, {
    bool playGroupIntro = false,
    bool animateCameraToStep = false,
  }) {
    final stayingInGroup =
        (_selectedSet?.isGroup ?? false) &&
        (playGroupIntro || animateCameraToStep);

    setState(() {
      // Save locked papers for the outgoing blueprint (non-group switches).
      if (_selectedBlueprint != null && !stayingInGroup) {
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
                ),
              )
              .toList();
        } else {
          _blueprintProgress.remove(outKey);
        }
        _placedPapers.removeWhere((p) => p.locked);
      }
      _lockAnimatingPaperIds = {};
      _lockAnimProgress = 0;

      _selectedBlueprint = blueprint;
      _blueprintWorldPolygons = [];
      _blueprintUnionPolygons = [];
      _blueprintTotalArea = 0;
      _blueprintLockedArea = 0;
      _alignGridPreviewVertex = null;
      _alignGridSecondPreview = null;
      _alignGridHoveredPolyIndex = null;
      _alignGridPhase = 0;
      if (blueprint == null) {
        _gridOriginOffset = Offset.zero;
        _gridRotation = math.pi / 2;
        _groupOverlayPolygons = [];
        _groupOverlayColors = [];
        return;
      }

      final useGroupLayout = _selectedSet?.isGroup == true;
      final activeStep =
          useGroupLayout &&
              _currentStepIndex < (_selectedSet?.steps.length ?? 0)
          ? _selectedSet!.steps[_currentStepIndex]
          : null;
      final layoutOffset = activeStep?.layoutOffset ?? Offset.zero;
      final layoutRotationDeg = activeStep?.layoutRotationDeg ?? 0.0;

      late final double nudgeX, nudgeY, cx, cy;
      final List<List<Offset>> allScaled;
      if (useGroupLayout) {
        // Group layout offsets already place islands; no extra centering.
        nudgeX = layoutOffset.dx;
        nudgeY = layoutOffset.dy;
        cx = 0;
        cy = 0;
        allScaled = _scaleBlueprintPolygons(
          blueprint,
          nudgeX,
          nudgeY,
          cx,
          cy,
          rotationDeg: layoutRotationDeg,
        );
      } else {
        final offset = _computeBlueprintOffset(blueprint);
        if (offset == null) return;
        (nudgeX, nudgeY, cx, cy) = offset;
        allScaled = _scaleBlueprintPolygons(blueprint, nudgeX, nudgeY, cx, cy);
      }

      // Reset completion state (animations disabled).
      _completionPhase = CompletionPhase.none;
      _craftExecuteButtonVisible = false;
      _craftButtonAnimController.reset();
      _dissolveController.reset();
      _foldController.reset();
      _dotDissolveProgress = 0;
      _foldOpacity = 0;
      _foldColorProgress = 0;
      _foldNodeStates = {};
      _foldSchedule = [];

      _polyIndexToRegion = {};
      var polyI = 0;
      for (final node in blueprint.transformTree.nodes) {
        if (node.unfoldedPolygon2D.length >= 3) {
          _polyIndexToRegion[polyI] = node.layer;
          polyI++;
        }
      }
      _blueprintWorldPolygons = allScaled;
      _applyAutoGridAlignment(allScaled);

      _blueprintTotalArea = 0;
      for (final poly in allScaled) {
        _blueprintTotalArea += _polyArea(poly).abs();
      }

      _blueprintUnionPolygons = useGroupLayout
          ? allScaled
          : _computeUnionPolygons(blueprint, cx, cy, nudgeX, nudgeY);
      _filledBlueprintIndices = {};

      // Restore locked papers only when not staying in a live group session.
      if (!stayingInGroup) {
        final saved = _blueprintProgress[_progressKey(blueprint)];
        if (saved != null) {
          for (final snap in saved) {
            _placedPapers.add(snap.toPaper());
            _filledBlueprintIndices.add(snap.lockedBlueprintIndex);
            if (snap.lockedBlueprintIndex < allScaled.length) {
              _blueprintLockedArea += _polyArea(
                allScaled[snap.lockedBlueprintIndex],
              ).abs();
            }
          }
        }
      } else if (animateCameraToStep) {
        // Re-derive filled indices from papers already locked to this step's polys.
        // Papers keep global positions; fill state starts fresh for the new active step.
        _filledBlueprintIndices = {};
        _blueprintLockedArea = 0;
      }

      if (useGroupLayout) {
        _rebuildGroupOverlays();
      } else {
        _groupOverlayPolygons = [];
        _groupOverlayColors = [];
        _activeHighlightT = 1.0;
        _activeGlow = 0.0;
      }

      if (!playGroupIntro && !animateCameraToStep && allScaled.isNotEmpty) {
        final cam = _cameraForPolygons(allScaled);
        _orthoScale = cam.ortho;
        _panOffset = cam.pan;
        _viewRotation = cam.rotation;
      }
    });

    if (playGroupIntro && _selectedSet?.isGroup == true) {
      _startGroupIntroCamera();
    } else if (animateCameraToStep && _selectedSet?.isGroup == true) {
      if (_blueprintWorldPolygons.isNotEmpty) {
        final cam = _cameraForPolygons(_blueprintWorldPolygons);
        _animateCameraTo(cam.pan, cam.ortho, rotation: cam.rotation);
      }
    }

    _scheduleCheck();
    _scheduleGridLodSync();
  }

  String _progressKey(CraftingBlueprint bp) => '${bp.craft}#${bp.island}';

  List<List<Offset>> _scaleBlueprintPolygons(
    CraftingBlueprint blueprint,
    double nudgeX,
    double nudgeY,
    double cx,
    double cy, {
    double rotationDeg = 0,
  }) {
    final scaled = <List<Offset>>[];
    for (final node in blueprint.transformTree.nodes) {
      final verts = node.unfoldedPolygon2D;
      if (verts.length < 3) continue;
      scaled.add(
        verts
            .map(
              (v) => Offset(
                v.dx * _minorGridSpacing - cx,
                v.dy * _minorGridSpacing - cy,
              ),
            )
            .toList(),
      );
    }
    if (scaled.isEmpty) return scaled;

    List<List<Offset>> oriented = scaled;
    if (rotationDeg != 0) {
      var sx = 0.0, sy = 0.0, n = 0;
      for (final poly in scaled) {
        for (final p in poly) {
          sx += p.dx;
          sy += p.dy;
          n++;
        }
      }
      final ox = sx / n;
      final oy = sy / n;
      final rad = rotationDeg * math.pi / 180;
      final c = math.cos(rad);
      final s = math.sin(rad);
      oriented = [
        for (final poly in scaled)
          [
            for (final p in poly)
              Offset(
                ox + (p.dx - ox) * c - (p.dy - oy) * s,
                oy + (p.dx - ox) * s + (p.dy - oy) * c,
              ),
          ],
      ];
    }

    return [
      for (final poly in oriented)
        [for (final p in poly) Offset(p.dx + nudgeX, p.dy + nudgeY)],
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

  void _rebuildGroupOverlays() {
    final set = _selectedSet;
    _groupOverlayPolygons = [];
    _groupOverlayColors = [];
    if (set == null || !set.isGroup) return;

    for (var step = 0; step < set.steps.length; step++) {
      if (step == _currentStepIndex) continue;
      final bp = _findBlueprintForStep(set.steps[step]);
      if (bp == null) continue;
      final offset = set.steps[step].layoutOffset;
      final polys = _scaleBlueprintPolygons(
        bp,
        offset.dx,
        offset.dy,
        0,
        0,
        rotationDeg: set.steps[step].layoutRotationDeg,
      );
      final color = _completedStepIndices.contains(step)
          ? Colors.greenAccent.withValues(alpha: 0.7)
          : Colors.white.withValues(alpha: 0.22);
      for (final poly in polys) {
        _groupOverlayPolygons.add(poly);
        _groupOverlayColors.add(color);
      }
    }
  }

  void _startGroupIntroCamera() {
    final set = _selectedSet;
    if (set == null || !set.isGroup) return;

    // Need a real viewport to fit portrait/landscape correctly.
    if (_viewportSize.width < 1 || _viewportSize.height < 1) {
      _pendingGroupIntro = true;
      return;
    }
    _pendingGroupIntro = false;

    // Overview bounds across every component.
    final allPolys = <List<Offset>>[];
    for (var step = 0; step < set.steps.length; step++) {
      final bp = _findBlueprintForStep(set.steps[step]);
      if (bp == null) continue;
      final offset = set.steps[step].layoutOffset;
      allPolys.addAll(
        _scaleBlueprintPolygons(
          bp,
          offset.dx,
          offset.dy,
          0,
          0,
          rotationDeg: set.steps[step].layoutRotationDeg,
        ),
      );
    }
    final overview = _boundsOfPolygons(allPolys);
    final first = _boundsOfPolygons(_blueprintWorldPolygons);
    if (overview == null || first == null) return;

    final overviewCam = _cameraForPolygons(allPolys, padding: 0.85);
    final firstCam = _cameraForPolygons(_blueprintWorldPolygons, padding: 0.7);

    // Hold the full-group overview briefly before zooming in.
    setState(() {
      _panOffset = overviewCam.pan;
      _orthoScale = overviewCam.ortho;
      _viewRotation = overviewCam.rotation;
      _activeHighlightT = 0;
      _activeGlow = 0;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_selectedSet != set) return;
      _animateCameraTo(
        firstCam.pan,
        firstCam.ortho,
        rotation: firstCam.rotation,
        introHighlight: true,
        duration: const Duration(milliseconds: 1400),
      );
    });
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

  /// Computes the centering/snap offset from the unfolded polygon bounding box.
  /// Returns (nudgeX, nudgeY, cx, cy) or null if there's no geometry.
  (double, double, double, double)? _computeBlueprintOffset(
    CraftingBlueprint blueprint,
  ) {
    final allScaled = <List<Offset>>[];
    for (final node in blueprint.transformTree.nodes) {
      final verts = node.unfoldedPolygon2D;
      if (verts.length >= 3) {
        allScaled.add(
          verts
              .map(
                (v) =>
                    Offset(v.dx * _minorGridSpacing, v.dy * _minorGridSpacing),
              )
              .toList(),
        );
      }
    }
    if (allScaled.isEmpty) return null;

    // Use the root node's polygon for centering when available, otherwise all.
    final root = blueprint.transformTree.root;
    final rootVerts = root.unfoldedPolygon2D;
    final anchorPolygons = rootVerts.length >= 3
        ? [
            rootVerts
                .map(
                  (v) => Offset(
                    v.dx * _minorGridSpacing,
                    v.dy * _minorGridSpacing,
                  ),
                )
                .toList(),
          ]
        : allScaled;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final poly in anchorPolygons) {
      for (final v in poly) {
        minX = math.min(minX, v.dx);
        minY = math.min(minY, v.dy);
        maxX = math.max(maxX, v.dx);
        maxY = math.max(maxY, v.dy);
      }
    }

    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final newMinX = minX - cx;
    final newMinY = minY - cy;
    final snappedX = (newMinX / _minorGridSpacing).round() * _minorGridSpacing;
    final snappedY = (newMinY / _minorGridSpacing).round() * _minorGridSpacing;

    return (snappedX - newMinX, snappedY - newMinY, cx, cy);
  }

  /// Computes the union of polygons per layer, then concatenates all results.
  List<List<Offset>> _computeUnionPolygons(
    CraftingBlueprint blueprint,
    double cx,
    double cy,
    double nudgeX,
    double nudgeY,
  ) {
    final perLayer = _computePerLayerUnions(blueprint, cx, cy, nudgeX, nudgeY);
    return perLayer.values.expand((polys) => polys).toList();
  }

  /// Builds per-layer union polygons keyed by layer name.
  Map<String, List<List<Offset>>> _computePerLayerUnions(
    CraftingBlueprint blueprint,
    double cx,
    double cy,
    double nudgeX,
    double nudgeY,
  ) {
    final byLayer = <String, List<List<Offset>>>{};
    for (final node in blueprint.transformTree.nodes) {
      final verts = node.unfoldedPolygon2D;
      if (verts.length < 3) continue;
      (byLayer[node.layer] ??= []).add(
        verts
            .map(
              (v) => Offset(
                v.dx * _minorGridSpacing - cx + nudgeX,
                v.dy * _minorGridSpacing - cy + nudgeY,
              ),
            )
            .toList(),
      );
    }
    final result = <String, List<List<Offset>>>{};
    for (final entry in byLayer.entries) {
      result[entry.key] = unionPolygons(entry.value);
    }
    return result;
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
    final paperIds = <String>[];
    for (final paper in _placedPapers) {
      // Papers committed to a finished step stay out of the active match.
      if (paper.locked) continue;
      final corners = _paperWorldCorners(paper);
      paperPolys.add(corners.map((v) => Offset(v.x, v.y)).toList());
      paperIds.add(paper.id);
    }

    final tolerance = 0.1 * _minorGridSpacing;

    final params = _CheckCoverageParams(
      blueprintPolygons: bpPolygons,
      paperPolygons: paperPolys,
      tolerance: tolerance,
    );

    try {
      final result = await compute(_checkCoverage, params);
      if (!mounted || generation != _checkGeneration) return;
      if (_stepAdvanceInProgress) {
        debugPrint('[craft-group] check result ignored (advance in progress)');
        return;
      }

      final previouslyFilled = _filledBlueprintIndices;
      final newlyFilled = result.difference(previouslyFilled);

      debugPrint(
        '[craft-group] check step=$_currentStepIndex '
        'filled=${result.length}/${bpPolygons.length} '
        'new=${newlyFilled.length} papers=${paperIds.length}',
      );

      if (newlyFilled.isNotEmpty && _lockAnimatingPaperIds.isEmpty) {
        _startLockAnimation(newlyFilled, bpPolygons, paperPolys, paperIds);
      }

      // Only clear match indices on unlocked papers for the active step.
      for (final paper in _placedPapers) {
        if (paper.locked) continue;
        if (paper.lockedBlueprintIndex != null &&
            !result.contains(paper.lockedBlueprintIndex!)) {
          paper.lockedBlueprintIndex = null;
        }
      }

      setState(() => _filledBlueprintIndices = result);
      _recomputeLockedArea();
      _updateCraftExecuteButtonVisibility();
    } catch (e, st) {
      debugPrint('Check coverage failed: $e\n$st');
    }
  }

  void _startLockAnimation(
    Set<int> newlyFilled,
    List<List<Offset>> bpPolygons,
    List<List<Offset>> paperPolys,
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

      for (var pi = 0; pi < paperPolys.length; pi++) {
        final pid = paperIds[pi];
        if (animating.contains(pid)) continue;
        final cleaned = _removeCollinears(
          _dedup(paperPolys[pi], dedupTol),
          angularTolRad,
        );
        if (_shapesMatch(cleaned, bpClean, tolerance)) {
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
        }
      }
    });
    _lockAnimController.forward(from: 0);
  }

  void _finalizeLock() {
    setState(() {
      _lockAnimatingPaperIds = {};
      _lockAnimProgress = 0;
    });
    // _recomputeLockedArea already calls _updateCraftExecuteButtonVisibility.
    _recomputeLockedArea();
    _scheduleCheck();
  }

  bool _isCraftComplete() {
    if (_stepAdvanceInProgress) return false;
    return _blueprintTotalArea > 0 &&
        _blueprintLockedArea >= _blueprintTotalArea * 0.999 &&
        _completionPhase == CompletionPhase.none;
  }

  void _updateCraftExecuteButtonVisibility() {
    final shouldShow = _isCraftComplete();
    if (shouldShow == _craftExecuteButtonVisible) return;

    // When in a multi-step set, auto-trigger the completion sequence.
    if (shouldShow && _selectedSet != null && _selectedSet!.steps.length > 1) {
      if (_stepAdvanceInProgress) return;
      debugPrint(
        '[craft-group] step $_currentStepIndex complete → auto-advance '
        '(locked=$_blueprintLockedArea / total=$_blueprintTotalArea, '
        'filled=${_filledBlueprintIndices.length})',
      );
      setState(() => _craftExecuteButtonVisible = false);
      _notifyCraftCompleted();
      _startCompletionSequence();
      return;
    }

    setState(() => _craftExecuteButtonVisible = shouldShow);
    if (shouldShow) {
      _craftButtonAnimController.forward(from: 0);
    } else {
      _craftButtonAnimController.reverse();
    }
  }

  void _onCraftExecutePressed() {
    if (!_isCraftComplete()) return;
    setState(() => _craftExecuteButtonVisible = false);
    _craftButtonAnimController.reverse();
    _notifyCraftCompleted();
    _startCompletionSequence();
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
    _updateCraftExecuteButtonVisibility();
  }

  void _notifyCraftCompleted() {
    if (_selectedBlueprint == null) return;
    final matchedPapers = _placedPapers
        .where((p) => p.lockedBlueprintIndex != null)
        .map((p) => CraftingPaperState.fromPaper(p))
        .toList();
    if (matchedPapers.isEmpty) return;
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
    if (_stepAdvanceInProgress) {
      debugPrint('[craft-group] completion ignored (advance in progress)');
      return;
    }

    debugPrint(
      '[craft-group] completion sequence at step $_currentStepIndex '
      '(set=${_selectedSet?.name}, steps=${_selectedSet?.steps.length})',
    );

    fmHapticBigClick();

    // Skip dissolve/fold for now — finish immediately.
    if (_completedPapers.isNotEmpty) {
      widget.onCraftFoldComplete?.call(
        _completedPapers,
        _selectedBlueprint!.craft,
        _selectedBlueprint!,
      );
    }

    if (_selectedSet != null &&
        _currentStepIndex < _selectedSet!.steps.length - 1) {
      _advanceToNextStep();
      return;
    }

    // Entire set (or single blueprint) finished.
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

    if (_selectedSet != null &&
        _currentStepIndex < _selectedSet!.steps.length - 1) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _completionPhase = CompletionPhase.none);
        _advanceToNextStep();
      });
      return;
    }

    widget.onDismiss?.call();
  }

  void _buildFoldGeometry() {
    if (_selectedBlueprint == null) return;
    final bp = _selectedBlueprint!;
    final tree = bp.transformTree;

    // Create a _FoldNodeState for every node using raw 3D vertices.
    _foldNodeStates = {};
    for (final node in tree.nodes) {
      _foldNodeStates[node.id] = _FoldNodeState(
        nodeId: node.id,
        node: node,
        unfoldedVertices3D: node.unfoldedVertices
            .map((v) => v.clone())
            .toList(),
      );
    }

    // Build the leaf-to-root staggered schedule with overlapping windows.
    final leafToRoot = tree.leafToRootOrder();
    _foldSchedule = [];
    final count = leafToRoot.length;
    if (count > 0) {
      const overlap = 0.7;
      final slotDuration = count > 1
          ? 1.0 / (1.0 + (count - 1) * (1.0 - overlap))
          : 1.0;
      for (var i = 0; i < count; i++) {
        final startT = i * slotDuration * (1.0 - overlap);
        final endT = (startT + slotDuration).clamp(0.0, 1.0);
        _foldSchedule.add((leafToRoot[i].id, startT, endT));
      }
    }

    // Store blueprint offsets for displacement interpolation.
    _foldOriginOffset = Vector3(
      bp.originOffset.dx,
      bp.originOffset.dy + bp.unfoldedYDisplacement,
      0,
    );
    _foldFoldedOffset = bp.foldedOffset.clone();
    _foldDisplacementMatrix = Matrix4.identity();

    // Compute raw-space centroid and ortho scale for the orbit camera.
    double rMinX = double.infinity, rMinY = double.infinity;
    double rMaxX = double.negativeInfinity, rMaxY = double.negativeInfinity;
    for (final node in tree.nodes) {
      for (final v in node.unfoldedVertices) {
        final wx = v.x + _foldOriginOffset.x;
        final wy = v.y + _foldOriginOffset.y;
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
    final bp = _selectedBlueprint;
    if (bp == null) return;
    final tree = bp.transformTree;

    // Reset all cumulative matrices to identity.
    for (final state in _foldNodeStates.values) {
      state.cumulativeMatrix = Matrix4.identity();
    }

    // Walk the schedule (leaf-to-root). For each node, compute the step
    // matrix and multiply it into the node AND all its descendants.
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

      // Apply stepMatrix to this node and all descendants.
      final affected = <int>{nodeId, ...tree.descendants(nodeId)};
      for (final id in affected) {
        final s = _foldNodeStates[id];
        if (s != null) {
          s.cumulativeMatrix = stepMatrix * s.cumulativeMatrix;
        }
      }
    }

    // Compute island displacement: lerp from unfolded origin to folded offset.
    final dispPos =
        _foldOriginOffset + (_foldFoldedOffset - _foldOriginOffset) * globalT;
    _foldDisplacementMatrix = Matrix4.identity()..setTranslation(dispPos);
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
        if (paper.locked) continue;
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
      setState(() => _drawnCutLines.clear());
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
      _lineDrawStart = null;
      _lineDrawPreview = null;
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
    if (_snapBlueprint && _blueprintWorldPolygons.isNotEmpty) {
      bpVerts = _blueprintWorldPolygons.expand((poly) => poly).toList();
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

  /// Transform a local coordinate by the current stretch (anchor-relative).
  double _stretchLocal(double v, double anchor, double scale) {
    return v * scale + anchor * (1 - scale);
  }

  /// 8 handle positions for the stretch gizmo in world space.
  /// 0=top, 1=right, 2=bottom, 3=left (edge midpoints)
  /// 4=topLeft, 5=topRight, 6=bottomRight, 7=bottomLeft (corners)
  List<Offset> _stretchHandleWorldPositions(PlacedPaper paper, Rect bounds) {
    final cx = paper.position.x;
    final cy = paper.position.y;
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final ax = _stretchAnchorLocal.dx;
    final ay = _stretchAnchorLocal.dy;
    final sx = _stretchScaleX;
    final sy = _stretchScaleY;

    Offset toWorld(double lx, double ly) {
      final slx = _stretchLocal(lx, ax, sx);
      final sly = _stretchLocal(ly, ay, sy);
      return Offset(cx + slx * cosA - sly * sinA, cy + slx * sinA + sly * cosA);
    }

    final l = bounds.left, r = bounds.right;
    final t = bounds.top, b = bounds.bottom;
    final mx = (l + r) / 2, my = (t + b) / 2;

    return [
      toWorld(mx, b), // 0: top (max Y in world)
      toWorld(r, my), // 1: right
      toWorld(mx, t), // 2: bottom
      toWorld(l, my), // 3: left
      toWorld(l, b), // 4: topLeft
      toWorld(r, b), // 5: topRight
      toWorld(r, t), // 6: bottomRight
      toWorld(l, t), // 7: bottomLeft
    ];
  }

  /// Hit-test stretch handles — returns handle index 0-7 or null.
  int? _hitTestStretchHandle(
    Offset screenPos,
    Size viewportSize,
    PlacedPaper paper,
  ) {
    final bounds = _stretchOriginalBounds ?? _paperLocalBounds(paper);
    final handles = _stretchHandleWorldPositions(paper, bounds);
    final worldPerPixel = _worldUnitsPerPixel(viewportSize);
    final hitRadius = 15.0 * worldPerPixel;

    final worldPos = _screenToWorld(screenPos, viewportSize);
    final wp = Offset(worldPos.x, worldPos.y);

    for (var i = 0; i < handles.length; i++) {
      if ((handles[i] - wp).distance <= hitRadius) return i;
    }
    return null;
  }

  /// Snap a stretched edge coordinate to blueprint polygon edges.
  /// [axisValue] is the world-space coordinate of the edge being stretched.
  /// [isHorizontal] true for left/right edges (snapping X), false for
  /// top/bottom edges (snapping Y).
  /// Returns the snapped value, or null if no snap found.
  double? _snapStretchToBlueprintEdge(
    double axisValue,
    bool isHorizontal,
    PlacedPaper paper,
  ) {
    if (!_snapBlueprint || _blueprintWorldPolygons.isEmpty) return null;
    final radius = _snapWorldRadius;
    double bestDist = double.infinity;
    double? bestSnap;

    for (final poly in _blueprintWorldPolygons) {
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        if (isHorizontal) {
          // Snap to vertical blueprint edges (constant X)
          if ((a.dx - b.dx).abs() < 1e-4) {
            final dist = (a.dx - axisValue).abs();
            if (dist < bestDist && dist <= radius) {
              bestDist = dist;
              bestSnap = a.dx;
            }
          }
        } else {
          // Snap to horizontal blueprint edges (constant Y)
          if ((a.dy - b.dy).abs() < 1e-4) {
            final dist = (a.dy - axisValue).abs();
            if (dist < bestDist && dist <= radius) {
              bestDist = dist;
              bestSnap = a.dy;
            }
          }
        }
      }
    }
    return bestSnap;
  }

  /// Round a scale factor to the nearest 5% increment.
  double _roundToStretchIncrement(double scale) {
    return (scale * 20).round() / 20.0;
  }

  /// Anchor point in local space for the given handle index.
  /// For edge handles the non-stretched axis anchors at 0 (center).
  Offset _stretchAnchorForHandle(int handleIndex, Rect bounds) {
    switch (handleIndex) {
      case 0:
        return Offset(0, bounds.top); // top edge → anchor bottom
      case 1:
        return Offset(bounds.left, 0); // right edge → anchor left
      case 2:
        return Offset(0, bounds.bottom); // bottom edge → anchor top
      case 3:
        return Offset(bounds.right, 0); // left edge → anchor right
      case 4:
        return Offset(bounds.right, bounds.top); // TL → anchor BR
      case 5:
        return Offset(bounds.left, bounds.top); // TR → anchor BL
      case 6:
        return Offset(bounds.left, bounds.bottom); // BR → anchor TL
      case 7:
        return Offset(bounds.right, bounds.bottom); // BL → anchor TR
      default:
        return Offset.zero;
    }
  }

  void _applyStretch() {
    if (_stretchPaperId == null) return;
    final paper = _placedPapers
        .where((p) => p.id == _stretchPaperId)
        .firstOrNull;
    if (paper == null) return;
    if ((_stretchScaleX - 1.0).abs() < 1e-4 &&
        (_stretchScaleY - 1.0).abs() < 1e-4)
      return;

    final sx = _stretchScaleX;
    final sy = _stretchScaleY;
    final ax = _stretchAnchorLocal.dx;
    final ay = _stretchAnchorLocal.dy;

    // Scale each vertex relative to the anchor point
    Offset xformOff(Offset v) =>
        Offset(v.dx * sx + ax * (1 - sx), v.dy * sy + ay * (1 - sy));

    final verts = _paperLocalVertices(paper);
    final scaled = verts.map(xformOff).toList();
    final scaledHoles = paper.localHoles
        .map((h) => h.map(xformOff).toList())
        .toList();
    final scaledCuts = paper.cutSegments
        .map((s) => (xformOff(s.$1), xformOff(s.$2)))
        .toList();

    // Shift paper position so the anchor stays in world space
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final dlx = ax * (1 - sx);
    final dly = ay * (1 - sy);
    final worldDx = dlx * cosA - dly * sinA;
    final worldDy = dlx * sinA + dly * cosA;

    // Re-center vertices around their new centroid so position stays canonical
    var cxLocal = 0.0, cyLocal = 0.0;
    for (final v in scaled) {
      cxLocal += v.dx;
      cyLocal += v.dy;
    }
    cxLocal /= scaled.length;
    cyLocal /= scaled.length;
    final recentered = scaled
        .map((v) => Offset(v.dx - cxLocal, v.dy - cyLocal))
        .toList();
    final recenteredHoles = scaledHoles
        .map(
          (h) => h.map((v) => Offset(v.dx - cxLocal, v.dy - cyLocal)).toList(),
        )
        .toList();
    final recenteredCuts = scaledCuts
        .map(
          (s) => (
            Offset(s.$1.dx - cxLocal, s.$1.dy - cyLocal),
            Offset(s.$2.dx - cxLocal, s.$2.dy - cyLocal),
          ),
        )
        .toList();

    // World position of the new centroid
    final newPosX =
        paper.position.x + worldDx + cxLocal * cosA - cyLocal * sinA;
    final newPosY =
        paper.position.y + worldDy + cxLocal * sinA + cyLocal * cosA;

    final idx = _placedPapers.indexOf(paper);
    setState(() {
      final replacement = PlacedPaper(
        id: paper.id,
        paperColor: paper.paperColor,
        position: Vector3(newPosX, newPosY, paper.position.z),
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
      _placedPapers[idx] = replacement;
      _stretchPaperId = replacement.id;
    });
    _stretchScaleX = 1.0;
    _stretchScaleY = 1.0;
    _stretchOriginalBounds = null;
    _stretchAnchorLocal = Offset.zero;
    _scheduleCheck();
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
    _alignGridPhase = 0;
    _alignGridPreviewVertex = null;
    _alignGridSecondPreview = null;
    _alignGridHoveredPolyIndex = null;
    _alignGridPointerDown = null;
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
  bool _isCellOccupiedByPaper(int col, int row) {
    final s = _activeGridSpacing;
    final inset = s * 0.01;
    final corners = [
      _gridToWorld(col * s + inset, row * s + inset),
      _gridToWorld((col + 1) * s - inset, row * s + inset),
      _gridToWorld((col + 1) * s - inset, (row + 1) * s - inset),
      _gridToWorld(col * s + inset, (row + 1) * s - inset),
    ];
    for (final paper in _placedPapers) {
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

  double _paperHalfSizeForLevel(int level) => level * _majorGridSpacing;

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
  // Paper hit testing
  // ---------------------------------------------------------------------------

  String? _hitTestPaper(Offset screenPos, Size viewportSize) {
    final worldPos = _screenToWorld(screenPos, viewportSize);
    for (int i = _placedPapers.length - 1; i >= 0; i--) {
      final paper = _placedPapers[i];
      final localPt = _worldToPaperLocal(worldPos, paper);
      if (_isPointInLocalPaper(localPt, paper)) return paper.id;
    }
    return null;
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
        !_isCellOccupiedByPaper(cell.$1, cell.$2)) {
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
      _inventory.clear();
      _inventory.addAll(snap.inventory);
      _selectedPaperIds = Set<String>.from(snap.selectedPaperIds);
      _isRotationGizmoActive = false;
    });
    _scheduleCheck();
    _updateCraftExecuteButtonVisibility();
  }

  void _undo() {
    final snap = _history.undo(_currentSnapshot('current'));
    if (snap != null) _applySnapshot(snap);
  }

  void _redo() {
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
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() {
        _lineDrawStart = snapped;
        _lineDrawPreview = snapped;
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

    if (_craftingMode == CraftingMode.translationCopy) {
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
          _transCopyStartWorld = null;
          _transCopyCurrentWorld = null;
        });
        return;
      }
      if (_selectedPaperIds.isEmpty) return;
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() {
        _transCopyStartWorld = snapped;
        _transCopyCurrentWorld = snapped;
      });
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
      final wp = Offset(worldPos.x, worldPos.y);
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
      setState(() {
        _alignGridPointerDown = localPos;
        _alignGridHoveredPolyIndex = hitIdx;
        if (_alignGridPhase == 0) {
          _alignGridPreviewVertex = vertex;
          _alignGridSecondPreview = null;
        } else {
          _alignGridSecondPreview = vertex ?? wp;
          final anchor = _gridOriginOffset;
          final end = _alignGridSecondPreview!;
          final d = end - anchor;
          if (d.distanceSquared > 1e-12) {
            _gridRotation = math.atan2(d.dy, d.dx);
          }
        }
      });
      _scheduleGridLodSync();
      return;
    }

    if (_craftingMode == CraftingMode.stretch) {
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
            _pushUndo('Stretch');
            final bounds = _paperLocalBounds(paper);
            final worldPos = _screenToWorld(localPos, viewportSize);
            setState(() {
              _stretchHandleIndex = handleIdx;
              _stretchHandleStartWorld = Offset(worldPos.x, worldPos.y);
              _stretchOriginalBounds = bounds;
              _stretchAnchorLocal = _stretchAnchorForHandle(handleIdx, bounds);
              _stretchScaleX = 1.0;
              _stretchScaleY = 1.0;
            });
            return;
          }
        }
      }
      final hitId = _hitTestPaper(localPos, viewportSize);
      if (hitId != null) {
        setState(() {
          if (_stretchPaperId != null && _stretchPaperId != hitId) {
            _applyStretch();
          }
          _stretchPaperId = hitId;
          _stretchHandleIndex = null;
          _stretchScaleX = 1.0;
          _stretchScaleY = 1.0;
          _stretchOriginalBounds = null;
        });
      } else {
        if (_stretchPaperId != null) {
          _applyStretch();
          setState(() {
            _stretchPaperId = null;
            _stretchHandleIndex = null;
          });
        }
      }
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

    if (_craftingMode == CraftingMode.stretch &&
        _stretchHandleIndex != null &&
        _stretchHandleStartWorld != null &&
        _stretchPaperId != null) {
      final paper = _placedPapers
          .where((p) => p.id == _stretchPaperId)
          .firstOrNull;
      if (paper == null) return;
      final bounds = _stretchOriginalBounds ?? _paperLocalBounds(paper);
      final worldPos = _screenToWorld(localPos, viewportSize);
      final wp = Offset(worldPos.x, worldPos.y);

      final rad = paper.rotationDeg * math.pi / 180;
      final cosA = math.cos(rad);
      final sinA = math.sin(rad);
      final dx0 = wp.dx - paper.position.x;
      final dy0 = wp.dy - paper.position.y;
      final localX = dx0 * cosA + dy0 * sinA;
      final localY = -dx0 * sinA + dy0 * cosA;

      final hi = _stretchHandleIndex!;
      final ax = _stretchAnchorLocal.dx;
      final ay = _stretchAnchorLocal.dy;
      double sx = _stretchScaleX;
      double sy = _stretchScaleY;
      const minScale = 0.2;
      const maxScale = 1.5;

      final stretchesX = hi == 1 || hi == 3 || hi >= 4;
      final stretchesY = hi == 0 || hi == 2 || hi >= 4;

      if (stretchesX && bounds.width.abs() > 1e-6) {
        // The dragged edge in original local space
        final handleX = (hi == 1 || hi == 5 || hi == 6)
            ? bounds.right
            : bounds.left;
        final span = handleX - ax;
        if (span.abs() > 1e-6) {
          sx = ((localX - ax) / span).clamp(minScale, maxScale);
          sx = _roundToStretchIncrement(sx);

          // Blueprint edge snap
          final stretchedEdge = _stretchLocal(handleX, ax, sx);
          final worldEdgeX = paper.position.x + stretchedEdge * cosA;
          final snapped = _snapStretchToBlueprintEdge(worldEdgeX, true, paper);
          if (snapped != null) {
            final localSnapped = (snapped - paper.position.x) / cosA;
            final snapSx = ((localSnapped - ax) / span).clamp(
              minScale,
              maxScale,
            );
            sx = snapSx;
          }
        }
      }

      if (stretchesY && bounds.height.abs() > 1e-6) {
        final handleY = (hi == 0 || hi == 4 || hi == 5)
            ? bounds.bottom
            : bounds.top;
        final span = handleY - ay;
        if (span.abs() > 1e-6) {
          sy = ((localY - ay) / span).clamp(minScale, maxScale);
          sy = _roundToStretchIncrement(sy);

          // Blueprint edge snap
          final stretchedEdge = _stretchLocal(handleY, ay, sy);
          final worldEdgeY = paper.position.y + stretchedEdge * cosA;
          final snapped = _snapStretchToBlueprintEdge(worldEdgeY, false, paper);
          if (snapped != null) {
            final localSnapped = (snapped - paper.position.y) / cosA;
            final snapSy = ((localSnapped - ay) / span).clamp(
              minScale,
              maxScale,
            );
            sy = snapSy;
          }
        }
      }

      setState(() {
        _stretchScaleX = sx;
        _stretchScaleY = sy;
      });
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
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() => _lineDrawPreview = snapped);
      return;
    }

    if (_craftingMode == CraftingMode.mirror && _mirrorLineStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() => _mirrorLinePreview = snapped);
      return;
    }

    if (_craftingMode == CraftingMode.translationCopy &&
        _transCopyStartWorld != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      setState(() => _transCopyCurrentWorld = snapped);
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
      final worldPos = _screenToWorld(localPos, viewportSize);
      final wp = Offset(worldPos.x, worldPos.y);
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
      setState(() {
        _alignGridHoveredPolyIndex = hitIdx;
        if (_alignGridPhase == 0) {
          _alignGridPreviewVertex = vertex;
        } else {
          final end = vertex ?? wp;
          _alignGridSecondPreview = end;
          final d = end - _gridOriginOffset;
          if (d.distanceSquared > 1e-12) {
            _gridRotation = math.atan2(d.dy, d.dx);
          }
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

    if (_craftingMode == CraftingMode.stretch) {
      if (_stretchHandleIndex != null && _stretchPaperId != null) {
        _applyStretch();
        setState(() {
          _stretchHandleIndex = null;
          _stretchHandleStartWorld = null;
          _stretchOriginalBounds = null;
        });
      }
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

    if (_craftingMode == CraftingMode.translationCopy &&
        _transCopyStartWorld != null &&
        _transCopyCurrentWorld != null) {
      final delta = _transCopyCurrentWorld! - _transCopyStartWorld!;
      final isTap = delta.distance <= 1e-4;
      if (!isTap) {
        _applyTranslationCopy(delta);
      } else if (_selectedPaperIds.isNotEmpty) {
        _pushUndo('Deselect');
      }
      setState(() {
        _transCopyStartWorld = null;
        _transCopyCurrentWorld = null;
        if (isTap) _selectedPaperIds = {};
      });
      return;
    }

    if (_craftingMode == CraftingMode.drawLine && _lineDrawStart != null) {
      final worldPos = _screenToWorld(localPos, viewportSize);
      final snapped = _snapWorldPoint(Offset(worldPos.x, worldPos.y));
      if ((_lineDrawStart! - snapped).distance > 1e-4) {
        _drawnCutLines.add((_lineDrawStart!, snapped));
        _lineDrawStart = null;
        _lineDrawPreview = null;
        if (_kCutFriendAnimationEnabled) {
          _startCutAnimation();
        } else {
          _executeCut();
        }
      } else {
        setState(() {
          _lineDrawStart = null;
          _lineDrawPreview = null;
        });
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
      final down = _alignGridPointerDown;
      _alignGridPointerDown = null;
      if (down != null && (localPos - down).distance > _dragThreshold) {
        // Treated as a pan/drag — don't commit a click.
        setState(() {
          _alignGridHoveredPolyIndex = null;
          if (_alignGridPhase == 0) {
            _alignGridPreviewVertex = null;
          }
        });
        return;
      }

      final worldPos = _screenToWorld(localPos, viewportSize);
      final wp = Offset(worldPos.x, worldPos.y);
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

      setState(() {
        if (_alignGridPhase == 0) {
          if (vertex == null) {
            // Empty click: restore auto-alignment for the active blueprint.
            _applyAutoGridAlignment(_blueprintWorldPolygons);
            _clearAlignGridTransient();
            fmHapticSmallClick();
          } else {
            _gridOriginOffset = vertex;
            _alignGridPreviewVertex = vertex;
            _alignGridSecondPreview = null;
            _alignGridPhase = 1;
            _alignGridHoveredPolyIndex = hitIdx;
            fmHapticSmallClick();
          }
        } else {
          final end = vertex ?? wp;
          if ((end - _gridOriginOffset).distanceSquared < 1e-12) {
            // Cancel direction pick; keep origin.
            _alignGridPhase = 0;
            _alignGridSecondPreview = null;
            _alignGridHoveredPolyIndex = null;
          } else {
            _gridRotation = math.atan2(
              end.dy - _gridOriginOffset.dy,
              end.dx - _gridOriginOffset.dx,
            );
            _alignGridPreviewVertex = _gridOriginOffset;
            _alignGridSecondPreview = end;
            _alignGridPhase = 0;
            _alignGridHoveredPolyIndex = null;
            fmHapticSmallClick();
          }
        }
      });
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
                  .where((p) => p.groupId == tapped!.groupId)
                  .map((p) => p.id)
                  .toSet();
            } else {
              _selectedPaperIds = {_pointerDownPaperId!};
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
    final worldTL = _screenToWorld(
      Offset(
        math.min(startScreen.dx, endScreen.dx),
        math.min(startScreen.dy, endScreen.dy),
      ),
      viewportSize,
    );
    final worldBR = _screenToWorld(
      Offset(
        math.max(startScreen.dx, endScreen.dx),
        math.max(startScreen.dy, endScreen.dy),
      ),
      viewportSize,
    );

    final minX = math.min(worldTL.x, worldBR.x);
    final maxX = math.max(worldTL.x, worldBR.x);
    final minY = math.min(worldTL.y, worldBR.y);
    final maxY = math.max(worldTL.y, worldBR.y);

    final result = <String>{};
    for (final paper in _placedPapers) {
      final corners = _paperWorldCorners(paper);
      if (fullyInside) {
        final allInside = corners.every(
          (v) => v.x >= minX && v.x <= maxX && v.y >= minY && v.y <= maxY,
        );
        if (allInside) result.add(paper.id);
      } else {
        final anyInside = corners.any(
          (v) => v.x >= minX && v.x <= maxX && v.y >= minY && v.y <= maxY,
        );
        if (anyInside) {
          result.add(paper.id);
          continue;
        }
        // Check if any marquee corner is inside the paper polygon
        final marqueeCorners = [
          Offset(minX, minY),
          Offset(maxX, minY),
          Offset(maxX, maxY),
          Offset(minX, maxY),
        ];
        final xyCorners = corners.map((v) => Offset(v.x, v.y)).toList();
        for (final mc in marqueeCorners) {
          if (_pointInPolygon(mc, xyCorners)) {
            result.add(paper.id);
            break;
          }
        }
      }
    }
    return result;
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
        if (_pendingGroupIntro &&
            !hadViewport &&
            viewportSize.width > 1 &&
            viewportSize.height > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pendingGroupIntro) _startGroupIntroCamera();
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildCanvas(viewportSize),
            ..._buildPaperOverlays(viewportSize),
            if (_rotCopyGizmoActive && _rotCopyCenterWorld != null)
              _buildRotCopyGizmo(viewportSize),
            // Step cards — full-width three-zone rail (matches cards-debug).
            if (_selectedSet != null && _selectedSet!.steps.length > 1)
              FmSafePositioned(
                top: 48,
                left: 0,
                right: 0,
                child: FmStepCards(
                  steps: _selectedSet!.steps,
                  currentIndex: _currentStepIndex,
                  promotingIndex: _promotingIndex,
                ),
              ),
            // Main toolbar — bottom-left, above inventory + undo/redo.
            FmSafePositioned(
              bottom: 86,
              left: 12,
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
                  // Blueprint dropdown hidden — Group 05 loads by default.
                  if (_selectedBlueprint != null) ...[
                    if (widget.onDismiss != null ||
                        (_craftingMode == CraftingMode.drawLine &&
                            _drawnCutLines.isNotEmpty))
                      const SizedBox(width: 8),
                    _buildUnionToggle(),
                    const SizedBox(width: 8),
                    _buildCheckModeToggle(),
                    const SizedBox(width: 8),
                    _buildFillAllButton(),
                    const SizedBox(width: 8),
                    _buildCraftNowButton(),
                  ],
                ],
              ),
            ),
            // Tool modes — left side, below ← Dev / step-card row.
            FmSafePositioned(left: 12, top: 48, child: _buildToolModeBar()),
            if (_selectedBlueprint != null)
              FmSafePositioned(
                right: 12,
                top: 48,
                child: _buildProgressBar(),
              ),
            FmSafePositioned(
              right: 12,
              top: 48,
              bottom: 100,
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
                bottom: 90,
                child: _buildCutProgressBar(),
              ),
            FmSafePositioned(
              left: 0,
              right: 0,
              bottom: 86,
              child: _buildUndoRedoBar(),
            ),
            FmSafePositioned(
              right: 16,
              bottom: 100,
              child: _buildCraftExecuteButton(),
            ),
            FmSafePositioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: _buildInventoryBar(),
            ),
          ],
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
                    _craftingMode = CraftingMode.pan;
                    _drawnCutLines.clear();
                    _lineDrawStart = null;
                    _lineDrawPreview = null;
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
                    _craftingMode = CraftingMode.select;
                    _drawnCutLines.clear();
                    _lineDrawStart = null;
                    _lineDrawPreview = null;
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.grid_on,
            tooltip: 'Align grid (origin, then +Y)',
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                      _clearMagnetState();
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.open_in_full,
            tooltip: 'Stretch',
            isActive: _craftingMode == CraftingMode.stretch,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.stretch) {
                      _craftingMode = CraftingMode.pan;
                      _stretchPaperId = null;
                      _stretchHandleIndex = null;
                      _stretchScaleX = 1.0;
                      _stretchScaleY = 1.0;
                    } else {
                      _craftingMode = CraftingMode.stretch;
                      _selectedPaperIds = {};
                      _isRotationGizmoActive = false;
                      _panModeSelectedPaperId = null;
                      _drawnCutLines.clear();
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                      _stretchPaperId = null;
                      _stretchHandleIndex = null;
                      _stretchScaleX = 1.0;
                      _stretchScaleY = 1.0;
                    }
                  }),
          ),
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
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
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
                      _panModeSelectedPaperId = null;
                      _paintedCells = {};
                      _lastPaintCell = null;
                    }
                  }),
          ),
          const SizedBox(height: 2),
          _ToolModeButton(
            icon: Icons.control_point_duplicate,
            tooltip: 'Translation copy',
            isActive: _craftingMode == CraftingMode.translationCopy,
            onTap: isCutting
                ? null
                : () => setState(() {
                    if (_craftingMode == CraftingMode.translationCopy) {
                      _craftingMode = CraftingMode.select;
                      _transCopyStartWorld = null;
                      _transCopyCurrentWorld = null;
                    } else {
                      _craftingMode = CraftingMode.translationCopy;
                      _transCopyStartWorld = null;
                      _transCopyCurrentWorld = null;
                      _drawnCutLines.clear();
                      _lineDrawStart = null;
                      _lineDrawPreview = null;
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
        _completionPhase != CompletionPhase.none) {
      return;
    }

    // Find which blueprint polygon indices are NOT yet filled (locked).
    final unfilledIndices = <int>[];
    for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
      final alreadyLocked = _placedPapers.any(
        (p) => p.locked && p.lockedBlueprintIndex == i,
      );
      if (!alreadyLocked) {
        unfilledIndices.add(i);
      }
    }
    if (unfilledIndices.isEmpty) return;

    // Leave one piece out -- pick the last unfilled index.
    final leaveOutIdx = unfilledIndices.removeLast();
    final colors = PaperColor.values;

    setState(() {
      // Place papers that exactly match each unfilled blueprint polygon.
      for (final bpIdx in unfilledIndices) {
        final poly = _blueprintWorldPolygons[bpIdx];
        if (poly.length < 3) continue;

        final centroid = _polyCentroid(poly);
        final localVerts = poly
            .map((v) => Offset(v.dx - centroid.dx, v.dy - centroid.dy))
            .toList();

        final paper = PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: colors[bpIdx % colors.length],
          position: Vector3(centroid.dx, centroid.dy, _paperZ),
          localVertices: localVerts,
        );
        _placedPapers.add(paper);
      }

      // Place the leave-out piece offset from its target position.
      final leavePoly = _blueprintWorldPolygons[leaveOutIdx];
      if (leavePoly.length >= 3) {
        final centroid = _polyCentroid(leavePoly);
        final localVerts = leavePoly
            .map((v) => Offset(v.dx - centroid.dx, v.dy - centroid.dy))
            .toList();

        final paper = PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: colors[leaveOutIdx % colors.length],
          position: Vector3(
            centroid.dx + _majorGridSpacing * 3,
            centroid.dy + _majorGridSpacing * 2,
            _paperZ,
          ),
          localVertices: localVerts,
        );
        _placedPapers.add(paper);
      }
    });

    _scheduleCheck();
  }

  Widget _buildCraftNowButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _completionPhase == CompletionPhase.none ? _craftNow : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt,
                color: _completionPhase == CompletionPhase.none
                    ? Colors.orangeAccent
                    : Colors.white24,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Craft Now',
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

  void _craftNow() {
    if (_selectedBlueprint == null ||
        _blueprintWorldPolygons.isEmpty ||
        _completionPhase != CompletionPhase.none) {
      return;
    }

    final colors = PaperColor.values;

    setState(() {
      for (var i = 0; i < _blueprintWorldPolygons.length; i++) {
        final alreadyLocked = _placedPapers.any(
          (p) => p.locked && p.lockedBlueprintIndex == i,
        );
        if (alreadyLocked) continue;

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
          localVertices: localVerts,
        );
        paper.locked = true;
        paper.lockedBlueprintIndex = i;
        _placedPapers.add(paper);
        _filledBlueprintIndices.add(i);
      }

      _blueprintLockedArea = _blueprintTotalArea;
      _craftExecuteButtonVisible = false;
    });

    _notifyCraftCompleted();
    _startCompletionSequence();
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
        return GestureClassifier(
          onGestureUpdate: (state) => _onCraftGesture(state, viewportSize),
          child: Listener(
            key: _canvasKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _canvasPointerCount++;
              // Suppress tools on 2nd+ finger / after any multitouch episode.
              if (_canvasPointerCount >= 2 || _toolsSuppressedUntilPointersUp) {
                _lockToolsForMultiTouch();
                _abortToolGestureForMultiTouch();
                return;
              }
              _beginToolGestureBaseline();
              _handlePointerDown(e.localPosition, viewportSize);
            },
            onPointerMove: (e) {
              if (_toolsBlocked) return;
              _handlePointerMove(e.localPosition, viewportSize);
            },
            onPointerUp: (e) {
              _canvasPointerCount = math.max(0, _canvasPointerCount - 1);
              final suppress = _toolsSuppressedUntilPointersUp;
              _maybeUnlockToolsAfterPointersUp();
              // Never commit a tool action during/after multitouch — including
              // the last finger lifting one-at-a-time after a pinch.
              if (suppress) return;
              _handlePointerUp(e.localPosition, viewportSize);
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
              _abortToolGestureForMultiTouch();
              _toolsSuppressedUntilPointersUp = false;
              _isMultiTouch = false;
              _clearPinchBaseline();
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
                    transCopyArrow:
                        _transCopyStartWorld != null &&
                            _transCopyCurrentWorld != null
                        ? (_transCopyStartWorld!, _transCopyCurrentWorld!)
                        : null,
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
                    stretchScaleX: _stretchScaleX,
                    stretchScaleY: _stretchScaleY,
                    stretchHandleIndex: _stretchHandleIndex,
                    stretchOriginalBounds: _stretchOriginalBounds,
                    stretchAnchorLocal: _stretchAnchorLocal,
                    gridRegionAssist: _gridRegionAssist,
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
    CraftingMode.translationCopy,
  };

  List<Widget> _buildPaperOverlays(Size viewportSize) {
    if (_selectedPaperIds.isEmpty || _isDragging || _isMarquee) {
      return const [];
    }

    final selectedPapers = _placedPapers
        .where((p) => _selectedPaperIds.contains(p.id))
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

    // Translation copy preview
    if (_craftingMode == CraftingMode.translationCopy &&
        _transCopyStartWorld != null &&
        _transCopyCurrentWorld != null &&
        _selectedPaperIds.isNotEmpty) {
      final delta = _transCopyCurrentWorld! - _transCopyStartWorld!;
      if (delta.distance < 1e-4) return const [];

      return _placedPapers
          .where((p) => _selectedPaperIds.contains(p.id) && !p.locked)
          .map((paper) {
            return PlacedPaper(
              id: 'ghost_${paper.id}',
              paperColor: paper.paperColor,
              position: Vector3(
                paper.position.x + delta.dx,
                paper.position.y + delta.dy,
                paper.position.z,
              ),
              rotationDeg: paper.rotationDeg,
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
          RadialAction(
            icon: paper.localVertices != null
                ? Icons.delete_outline
                : Icons.inventory_2,
            label: paper.localVertices != null ? 'Discard' : 'Return',
            tint: const Color(0xFF90A4AE),
            onTap: () => _returnPaperToInventory(paper.id),
          ),
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

    actions.add(
      RadialAction(
        icon: isCutPiece ? Icons.delete_outline : Icons.inventory_2,
        label: isCutPiece ? 'Discard' : 'Return',
        tint: const Color(0xFF90A4AE),
        onTap: () => _returnPaperToInventory(paper.id),
      ),
    );

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
        onTap: _discardSelectedPapers,
      ),
    );

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
      if (paper.locked) continue;

      final paperCells = _rasterizePaperToCells(paper);
      if (paperCells.isEmpty) continue;

      final overlap = paperCells.intersection(cells);
      if (overlap.isEmpty) continue;

      final remaining = paperCells.difference(cells);
      papersToRemove.add(i);

      if (remaining.isEmpty) continue;

      // Rebuild paper(s) from remaining cells.
      final components = _connectedComponents(remaining);
      for (final comp in components) {
        final (ext, holes) = _boundaryPolygons(comp);
        if (ext.length < 3) continue;
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
        _placedPapers.addAll(papersToAdd);
        _isRotationGizmoActive = false;
      });
      _scheduleCheck();
    }
  }

  void _fusePaintedCells() {
    _pushUndo('Paint');
    final cells = Set<(int, int)>.from(_paintedCells);
    setState(() {
      _paintedCells = {};
      _lastPaintCell = null;
    });

    if (cells.isEmpty) return;

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
        if (paper.locked) continue;
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
        if (paper.locked) continue;

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

        // Include hole boundaries in the planar graph.
        final graphSegments = <(Offset, Offset)>[...allSegments];
        for (final hole in paper.localHoles) {
          for (var hi = 0; hi < hole.length; hi++) {
            graphSegments.add((hole[hi], hole[(hi + 1) % hole.length]));
          }
        }

        final faces = splitPolygonByCuts(polygon, graphSegments);

        if (faces.length > 1) {
          papersToRemove.add(pi);
          final compound = _classifyCompoundFaces(faces);
          for (final (exterior, holes) in compound) {
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

  void _applyTranslationCopy(Offset delta) {
    if (_selectedPaperIds.isEmpty) return;

    final newPapers = <PlacedPaper>[];
    for (final paper in _placedPapers) {
      if (!_selectedPaperIds.contains(paper.id)) continue;
      if (paper.locked) continue;

      newPapers.add(
        PlacedPaper(
          id: 'paper_${_nextPaperId++}',
          paperColor: paper.paperColor,
          position: Vector3(
            paper.position.x + delta.dx,
            paper.position.y + delta.dy,
            paper.position.z,
          ),
          rotationDeg: paper.rotationDeg,
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
      _pushUndo('Translation copy');
      setState(() {
        _placedPapers.addAll(newPapers);
        _selectedPaperIds = newPapers.map((p) => p.id).toSet();
        _isRotationGizmoActive = false;
        _craftingMode = CraftingMode.select;
      });
      _scheduleCheck();
    }
  }

  // ---------------------------------------------------------------------------
  // Inventory bar
  // ---------------------------------------------------------------------------

  Widget _buildUndoRedoBar() {
    return Center(
      child: ListenableBuilder(
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
      ),
    );
  }

  Widget _buildCraftExecuteButton() {
    if (!_craftExecuteButtonVisible && _craftButtonAnimController.isDismissed) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _craftButtonAnimController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: FadeTransition(
        opacity: _craftButtonAnimController,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            elevation: 8,
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: _isCraftComplete() ? _onCraftExecutePressed : null,
          child: const Text('Craft!'),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inventory bar
  // ---------------------------------------------------------------------------

  Widget _buildInventoryBar() {
    if (_useStructureInventory) {
      return _buildMaterialInventoryBar();
    }
    return Center(
      child: Container(
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
      ),
    );
  }

  Widget _buildMaterialInventoryBar() {
    final contents = _structureInventory!.contents;
    if (contents.isEmpty) {
      return Center(
        child: Container(
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
        ),
      );
    }
    return Center(
      child: Container(
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
    this.transCopyArrow,
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
    this.stretchScaleX = 1.0,
    this.stretchScaleY = 1.0,
    this.stretchHandleIndex,
    this.stretchOriginalBounds,
    this.stretchAnchorLocal = Offset.zero,
    this.gridRegionAssist = true,
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
  final (Offset, Offset)? transCopyArrow;
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
  final double stretchScaleX;
  final double stretchScaleY;
  final int? stretchHandleIndex;
  final Rect? stretchOriginalBounds;
  final Offset stretchAnchorLocal;
  final bool gridRegionAssist;

  double get _effectiveGridSpacing =>
      activeGridSpacing ?? drawingPlaneSize / gridDivisions;

  double _gridSpacingForLod(int lod) {
    final base = drawingPlaneSize / gridDivisions;
    return base * math.pow(2, lod).toDouble();
  }

  double _paperHalfSizeForLevel(int level) => level * drawingPlaneSize / 4;

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
      _drawGridRegionAssist(canvas, size, viewProjection);
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

    // Translation copy arrow
    if (transCopyArrow != null) {
      _drawTransCopyArrow(canvas, size, viewProjection);
    }

    // Draw cut lines / preview / toolpath
    _drawCutLines(canvas, size, viewProjection);
    if (lineDrawStart != null && lineDrawPreview != null) {
      _drawLinePreview(canvas, size, viewProjection);
    }
    if (craftingMode == CraftingMode.cutting && activeToolpath.isNotEmpty) {
      _drawToolpath(canvas, size, viewProjection);
    }

    // Stretch gizmo
    if (craftingMode == CraftingMode.stretch && stretchPaperId != null) {
      _drawStretchGizmo(canvas, size, viewProjection);
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
      // Dot mode
      const minorBaseAlpha = 0.45;
      const majorBaseAlpha = 0.85;
      final hasWipe = dotWipeOpacityAt != null;
      final dissolve = dotDissolveProgress;
      final visibleW = worldMaxX - worldMinX;

      for (var i = iMin; i <= iMax; i++) {
        final iMajor = i % majorInterval == 0;
        if (!showMinorLines && !iMajor) continue;

        for (var j = jMin; j <= jMax; j++) {
          final jMajor = j % majorInterval == 0;
          if (!showMinorLines && !jMajor) continue;

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
          final isMajorDot = iMajor && jMajor;
          final baseAlpha = isMajorDot ? majorBaseAlpha : minorBaseAlpha;
          final paint = Paint()
            ..style = PaintingStyle.fill
            ..color = (isMajorDot ? Colors.grey.shade500 : Colors.grey.shade400)
                .withValues(
                  alpha: baseAlpha * wipeAlpha * dissolveAlpha * layerOpacity,
                );
          canvas.drawCircle(pt, isMajorDot ? 2.5 : 1.0, paint);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Grid Region Assist
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

  bool _isPolygonGridAligned(List<Offset> poly, double spacing, Offset origin) {
    const eps = 1e-2;
    bool onGrid(double v) {
      final m = v % spacing;
      final r = m.abs();
      return r < eps || (spacing - r) < eps;
    }

    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final ga = _worldToGridCoords(a, origin, gridRotation);
      final gb = _worldToGridCoords(b, origin, gridRotation);
      final alongY = (ga.dx - gb.dx).abs() < eps && onGrid(ga.dx);
      final alongX = (ga.dy - gb.dy).abs() < eps && onGrid(ga.dy);
      if (!alongY && !alongX) return false;
    }
    return true;
  }

  void _drawGridRegionAssist(Canvas canvas, Size size, Matrix4 viewProjection) {
    if (!gridRegionAssist) return;
    if (canvasDisplayMode != CanvasDisplayMode.dot) return;

    final spacing = _gridSpacingForLod(gridLodTo);
    final ox = gridOriginOffset.dx;
    final oy = gridOriginOffset.dy;

    // Collect grid-aligned polygons (skip filled ones).
    final alignedPolys = <List<Offset>>[];
    for (var i = 0; i < blueprintPolygons.length; i++) {
      if (filledBlueprintIndices.contains(i)) continue;
      final poly = blueprintPolygons[i];
      if (poly.length < 3) continue;
      if (_isPolygonGridAligned(poly, spacing, gridOriginOffset)) {
        alignedPolys.add(poly);
      }
    }
    if (alignedPolys.isEmpty) return;

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

    final t = gridLodFadeT.clamp(0.0, 1.0);
    final layerOpacity = (gridLodFrom != gridLodTo && t < 1.0) ? t : 1.0;
    const majorInterval = 4;
    final xDir = _gridXDir(gridRotation);
    final yDir = _gridYDir(gridRotation);
    Offset gridPt(double gi, double gj) => Offset(
      ox + gi * xDir.dx + gj * yDir.dx,
      oy + gi * xDir.dy + gj * yDir.dy,
    );

    final goldPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.yellow.withValues(alpha: 0.7 * layerOpacity);

    for (var i = iMin; i <= iMax; i++) {
      final iMajor = i % majorInterval == 0;
      if (!showMinorLines && !iMajor) continue;

      for (var j = jMin; j <= jMax; j++) {
        final jMajor = j % majorInterval == 0;
        if (!showMinorLines && !jMajor) continue;
        final worldPt = gridPt(i * spacing, j * spacing);
        bool inside = false;
        for (final poly in alignedPolys) {
          if (_pointInPolygonPainter(worldPt, poly)) {
            inside = true;
            break;
          }
        }
        if (!inside) continue;

        final pt = _projectToScreen(
          Vector3(worldPt.dx, worldPt.dy, 0.1),
          viewProjection,
          size,
        );
        if (pt == null) continue;
        final isMajorDot = iMajor && jMajor;
        canvas.drawCircle(pt, isMajorDot ? 2.5 : 1.0, goldPaint);
      }
    }

    // If crossfading LODs, also draw for the outgoing LOD.
    if (gridLodFrom != gridLodTo && t < 1.0) {
      final spacingFrom = _gridSpacingForLod(gridLodFrom);
      final fromAlignedPolys = <List<Offset>>[];
      for (var i = 0; i < blueprintPolygons.length; i++) {
        if (filledBlueprintIndices.contains(i)) continue;
        final poly = blueprintPolygons[i];
        if (poly.length < 3) continue;
        if (_isPolygonGridAligned(poly, spacingFrom, gridOriginOffset)) {
          fromAlignedPolys.add(poly);
        }
      }
      if (fromAlignedPolys.isNotEmpty) {
        final fromIMin = (gMinX / spacingFrom).floor() - 1;
        final fromIMax = (gMaxX / spacingFrom).ceil() + 1;
        final fromJMin = (gMinY / spacingFrom).floor() - 1;
        final fromJMax = (gMaxY / spacingFrom).ceil() + 1;
        final fromOpacity = 1.0 - t;
        final fromGoldPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.yellow.withValues(alpha: 0.7 * fromOpacity);

        for (var i = fromIMin; i <= fromIMax; i++) {
          final iMajor = i % majorInterval == 0;
          if (!showMinorLines && !iMajor) continue;
          for (var j = fromJMin; j <= fromJMax; j++) {
            final jMajor = j % majorInterval == 0;
            if (!showMinorLines && !jMajor) continue;
            final worldPt = gridPt(i * spacingFrom, j * spacingFrom);
            bool inside = false;
            for (final poly in fromAlignedPolys) {
              if (_pointInPolygonPainter(worldPt, poly)) {
                inside = true;
                break;
              }
            }
            if (!inside) continue;
            final pt = _projectToScreen(
              Vector3(worldPt.dx, worldPt.dy, 0.1),
              viewProjection,
              size,
            );
            if (pt == null) continue;
            final isMajorDot = iMajor && jMajor;
            canvas.drawCircle(pt, isMajorDot ? 2.5 : 1.0, fromGoldPaint);
          }
        }
      }
    }
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

  void _drawBlueprintPolygons(
    Canvas canvas,
    Size size,
    Matrix4 viewProjection,
  ) {
    if (blueprintPolygons.isEmpty) return;

    final grey = Colors.white.withValues(alpha: 0.22);
    final yellow = Colors.yellow.withValues(alpha: 0.7);
    final activeStroke = Color.lerp(
      grey,
      yellow,
      activeHighlightT.clamp(0, 1),
    )!;

    final defaultPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = activeStroke;

    final filledPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.25
      ..color = Colors.greenAccent.withValues(alpha: 0.7);

    // Soft yellow glow while intro-highlighting the active blueprint.
    if (activeGlow > 0.01) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 + 6.0 * activeGlow
        ..color = Colors.yellow.withValues(alpha: 0.35 * activeGlow)
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
        canvas.drawPath(Path()..addPolygon(screenPts, true), glowPaint);
      }
    }

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
      final paint = filledBlueprintIndices.contains(i)
          ? filledPaint
          : defaultPaint;
      canvas.drawPath(path, paint);
      final isFilled = filledBlueprintIndices.contains(i);
      final t = gridLodFadeT.clamp(0.0, 1.0);
      if (gridLodFrom != gridLodTo && t < 1.0) {
        _drawBlueprintPolygonGrid(
          canvas,
          poly,
          size,
          viewProjection,
          isFilled: isFilled,
          lod: gridLodFrom,
          layerOpacity: 1.0 - t,
        );
        _drawBlueprintPolygonGrid(
          canvas,
          poly,
          size,
          viewProjection,
          isFilled: isFilled,
          lod: gridLodTo,
          layerOpacity: t,
        );
      } else {
        _drawBlueprintPolygonGrid(
          canvas,
          poly,
          size,
          viewProjection,
          isFilled: isFilled,
          lod: gridLodTo,
          layerOpacity: 1.0,
        );
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

  void _drawBlueprintPolygonGrid(
    Canvas canvas,
    List<Offset> poly,
    Size size,
    Matrix4 viewProjection, {
    required bool isFilled,
    required int lod,
    required double layerOpacity,
  }) {
    if (poly.length < 3 || layerOpacity <= 0) return;

    final spacing = _gridSpacingForLod(lod);
    final majorInterval = 4;

    // Longest edge defines U axis; origin at its start vertex.
    var bestEdge = 0;
    var bestLenSq = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final lenSq =
          (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
      if (lenSq > bestLenSq) {
        bestLenSq = lenSq;
        bestEdge = i;
      }
    }

    final origin = poly[bestEdge];
    final edgeEnd = poly[(bestEdge + 1) % poly.length];
    var uDir = edgeEnd - origin;
    final uLen = uDir.distance;
    if (uLen < 1e-9) return;
    uDir = Offset(uDir.dx / uLen, uDir.dy / uLen);
    var vDir = Offset(-uDir.dy, uDir.dx);

    final centroid = _blueprintPolygonCentroid(poly);
    final toCentroid = centroid - origin;
    if (toCentroid.dx * vDir.dx + toCentroid.dy * vDir.dy < 0) {
      vDir = Offset(-vDir.dx, -vDir.dy);
    }

    var uMin = double.infinity, uMax = -double.infinity;
    var vMin = double.infinity, vMax = -double.infinity;
    for (final p in poly) {
      final d = p - origin;
      final u = d.dx * uDir.dx + d.dy * uDir.dy;
      final v = d.dx * vDir.dx + d.dy * vDir.dy;
      uMin = math.min(uMin, u);
      uMax = math.max(uMax, u);
      vMin = math.min(vMin, v);
      vMax = math.max(vMax, v);
    }

    final pad = spacing * 0.5;
    uMin -= pad;
    uMax += pad;
    vMin -= pad;
    vMax += pad;

    const outlineAlpha = 0.7;
    const gridAlpha = outlineAlpha / 3;
    final baseColor = isFilled ? Colors.greenAccent : Colors.yellow;
    final gridColor = baseColor.withValues(alpha: gridAlpha * layerOpacity);

    for (var pass = 0; pass < 2; pass++) {
      final alongU = pass == 0;
      final minCoord = alongU ? vMin : uMin;
      final maxCoord = alongU ? vMax : uMax;
      final start = (minCoord / spacing).floor() * spacing;
      for (var c = start; c <= maxCoord + 1e-9; c += spacing) {
        final index = (c / spacing).round().abs();
        final isMajor = index % majorInterval == 0;
        final linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMajor ? 0.75 : 0.5
          ..color = gridColor;

        final a = alongU
            ? origin + uDir * uMin + vDir * c
            : origin + uDir * c + vDir * vMin;
        final b = alongU
            ? origin + uDir * uMax + vDir * c
            : origin + uDir * c + vDir * vMax;

        for (final (wa, wb) in _clipSegmentToPolygon(a, b, poly)) {
          final sa = _projectToScreen(
            Vector3(wa.dx, wa.dy, 0.06),
            viewProjection,
            size,
          );
          final sb = _projectToScreen(
            Vector3(wb.dx, wb.dy, 0.06),
            viewProjection,
            size,
          );
          if (sa != null && sb != null) {
            canvas.drawLine(sa, sb, linePaint);
          }
        }
      }
    }
  }

  static Offset _blueprintPolygonCentroid(List<Offset> polygon) {
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
    if (area.abs() < 1e-12) return polygon.first;
    return Offset(cx / (6 * area), cy / (6 * area));
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
    final paperPaths = <(Path, PlacedPaper)>[];

    for (final paper in papers) {
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

      // Add hole sub-paths for compound papers.
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
          paperPath.addPolygon(screenHole, true);
        }
      }
      paperPath.fillType = PathFillType.evenOdd;

      final shadowPath = Path()
        ..addPolygon(
          screenCorners.map((p) => p + const Offset(2, 2)).toList(),
          true,
        );
      canvas.drawPath(
        shadowPath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.black.withOpacity(0.08),
      );

      final baseColor =
          paperColorResolver?.call(paper) ?? paper.paperColor.color;
      final Color fillColor = baseColor.withValues(alpha: 0.85);

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
          ..color = Colors.white.withOpacity(0.5);
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

    // Pass 2: borders on top of all fills
    for (final (paperPath, paper) in paperPaths) {
      final isSelected = selectedPaperIds.contains(paper.id);
      final isMatched = paper.isBlueprintMatched;
      final isAnimating = lockAnimatingPaperIds.contains(paper.id);

      Color borderColor;
      double borderWidth;
      if (isAnimating) {
        borderColor = Color.lerp(Colors.white, Colors.green, lockAnimProgress)!;
        borderWidth = 1.0 + lockAnimProgress * 1.0;
      } else if (isMatched) {
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
          (p) => p.isBlueprintMatched && !lockAnimatingPaperIds.contains(p.id),
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

  void _drawTransCopyArrow(Canvas canvas, Size size, Matrix4 viewProjection) {
    final a = _projectToScreen(
      Vector3(transCopyArrow!.$1.dx, transCopyArrow!.$1.dy, 0.1),
      viewProjection,
      size,
    );
    final b = _projectToScreen(
      Vector3(transCopyArrow!.$2.dx, transCopyArrow!.$2.dy, 0.1),
      viewProjection,
      size,
    );
    if (a == null || b == null) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF44BBFF);

    canvas.drawLine(a, b, paint);

    final dir = b - a;
    final len = dir.distance;
    if (len < 8) return;
    final unit = dir / len;
    final perp = Offset(-unit.dy, unit.dx);
    const arrowSize = 8.0;
    final tip1 = b - unit * arrowSize + perp * arrowSize * 0.5;
    final tip2 = b - unit * arrowSize - perp * arrowSize * 0.5;
    final arrowPath = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(tip1.dx, tip1.dy)
      ..moveTo(b.dx, b.dy)
      ..lineTo(tip2.dx, tip2.dy);
    canvas.drawPath(arrowPath, paint);
  }

  double _stretchLocalPaint(double v, double anchor, double scale) {
    return v * scale + anchor * (1 - scale);
  }

  void _drawStretchGizmo(Canvas canvas, Size size, Matrix4 viewProjection) {
    final paper = papers.where((p) => p.id == stretchPaperId).firstOrNull;
    if (paper == null) return;

    final bounds = stretchOriginalBounds ?? _paperLocalBoundsForPainter(paper);
    final cx = paper.position.x;
    final cy = paper.position.y;
    final rad = paper.rotationDeg * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final ax = stretchAnchorLocal.dx;
    final ay = stretchAnchorLocal.dy;
    final sx = stretchScaleX;
    final sy = stretchScaleY;

    Offset toScreen(double lx, double ly) {
      final slx = _stretchLocalPaint(lx, ax, sx);
      final sly = _stretchLocalPaint(ly, ay, sy);
      final wx = cx + slx * cosA - sly * sinA;
      final wy = cy + slx * sinA + sly * cosA;
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
({Offset anchor, double yAngle})? _computeDominantGridFrame(
  List<List<Offset>> polygons,
) {
  // Quantize undirected angles to 0.5° buckets; score by edge count, then length.
  const step = math.pi / 360;
  final countByBucket = <int, int>{};
  final lengthByBucket = <int, double>{};
  final vertsByBucket = <int, List<Offset>>{};

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
      (vertsByBucket[q] ??= []).addAll([a, b]);
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

  final candidates = vertsByBucket[bestQ] ?? const <Offset>[];
  if (candidates.isEmpty) return null;

  // Anchor = "bottom-left" vertex in the oriented grid frame.
  Offset anchor = candidates.first;
  var bestG = _worldToGridCoords(anchor, Offset.zero, yAngle);
  for (final v in candidates) {
    final g = _worldToGridCoords(v, Offset.zero, yAngle);
    if (g.dx < bestG.dx - 1e-9 ||
        ((g.dx - bestG.dx).abs() < 1e-9 && g.dy < bestG.dy)) {
      anchor = v;
      bestG = g;
    }
  }

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
