import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../crafting/paper_splitting.dart';
import 'geometry.dart';
import 'collision.dart';
import 'models.dart';
import 'harvest.dart';
import 'plane_navigation.dart';
import 'recipes.dart';
import 'bedroom_items.dart';
import 'bedrooms.dart';

class ProtoplaneController extends ChangeNotifier {
  ProtoplaneController({this.preset = WorldPreset.ink}) {
    landscape = PaperLandscape(preset: preset);
    paper = preset.materials.first;
    balances.addEntries(
      preset.materials.map((m) => MapEntry(m, m.starterUnits)),
    );
    _ground();
  }
  final Map<String, CraftPlane> planes = {};
  WorldPreset preset;
  List<PaperMaterial> get materials => preset.materials;
  late PaperLandscape landscape;
  Map<PaperColor, int>? lastHarvest;
  bool harvestPending = false;
  String? _harvestPreviewKey;
  HarvestResult? _harvestPreview;
  HarvestResult? get harvestPreview {
    final plane = activePlane;
    if (plane == null ||
        !plane.id.startsWith('ground-') ||
        editId != null ||
        !closed) {
      return null;
    }
    final key =
        '${identityHashCode(landscape)}/${plane.id}/${landscape.revision(plane.id)}/${draft.path.join(',')}';
    if (_harvestPreviewKey == key) return _harvestPreview;
    _harvestPreviewKey = key;
    final outline = Region(trace.sublist(0, trace.length - 1));
    _harvestPreview = outline.valid && plane.region.containsRegion(outline)
        ? landscape.preview(plane, outline)
        : null;
    return _harvestPreview;
  }

  bool _harvest(HarvestResult result) {
    if (objects.values.any(
      (o) => o.planeId == result.planeId && o.region.overlaps(result.outline),
    )) {
      report('Cutout overlaps placed paper');
      return false;
    }
    final before = _gestureBefore ?? _snapshot();
    final credits = landscape.collect(result);
    for (final entry in credits.entries) {
      balances[entry.key] = balances[entry.key]! + entry.value;
    }
    drafts.remove(draftKey);
    lastHarvest = credits;
    if (_gestureBefore != null) {
      harvestPending = true;
    } else {
      _record(before, committed: true);
    }
    notifyListeners();
    return true;
  }

  final Map<String, CraftObject> objects = {};
  PlaneNavigationGraph? _navigationGraph;
  Map<String, CraftPlane> _navigationPlanes = {};
  Map<String, CraftObject> _navigationObjects = {};
  PlaneNavigationGraph get navigationGraph {
    if (_navigationGraph == null ||
        !mapEquals(_navigationPlanes, planes) ||
        !mapEquals(_navigationObjects, objects)) {
      _navigationPlanes = Map.of(planes);
      _navigationObjects = Map.of(objects);
      _navigationGraph = PlaneNavigationGraph(planes, objects);
    }
    return _navigationGraph!;
  }

  final Map<String, CraftDraft> drafts = {};
  List<Bedroom> bedrooms = [];
  Bedroom? get activeBedroom {
    final floorId = supportingFloor(
      editId ?? activePlane?.owner,
      objects,
      planes,
    );
    return bedrooms.where((b) => b.floorId == floorId).firstOrNull;
  }

  final Map<PaperMaterial, int> balances = {};
  final List<String> _undo = [], _redo = [];
  int nextId = 1;
  String? activePlaneId, editId, error;
  int gridIndex = 0;
  late PaperMaterial paper;
  CraftTool tool = CraftTool.scissors;
  String? _gestureBefore;
  void Function(Map<String, dynamic>)? onCommitted;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  CraftPlane? get activePlane => planes[activePlaneId];
  CraftGrid? get grid => activePlane == null
      ? null
      : activePlane!.grids[gridIndex.clamp(0, activePlane!.grids.length - 1)];
  String get draftKey =>
      '${activePlaneId ?? ''}/${grid?.id ?? ''}/${editId ?? ''}';
  CraftDraft get draft =>
      drafts[draftKey] ?? CraftDraft(depth: objects[editId]?.depth ?? 0);
  List<Offset> get trace => grid?.trace(draft.path) ?? [];
  bool get closed =>
      draft.path.length >= 4 && draft.path.first == draft.path.last;
  bool isPlane(String id) => objects.values.any((o) => o.planeId == id);

  int? protoplaneCells;

  void setProtoplaneCells(int cells) {
    if (cells < 1 || cells > 5) throw RangeError.range(cells, 1, 5);
    if (protoplaneCells == cells) return;
    if (_gestureBefore != null) cancelGesture();
    protoplaneCells = cells;
    _resizeProtoplaneGrids();
    // Draft node IDs refer to the old lattice, so discard them on resolution changes.
    drafts.clear();
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  void _resizeProtoplaneGrids() {
    final cells = protoplaneCells;
    if (cells == null) return;
    for (final p in planes.values.toList()) {
      if (p.id.startsWith('ground-') ||
          p.wallCandidate ||
          p.id.startsWith('upper-')) {
        planes[p.id] = p.withGrids(
          p.grids
              .map(
                (g) => lattice(
                  g.id,
                  p.region,
                  count: cells + 1,
                  recipes: g.recipes,
                  name: g.name,
                ),
              )
              .toList(),
        );
      }
    }
  }

  void _ground() {
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final id = 'ground-$x-$y';
        final region = rectangle(1, 1);
        planes[id] = CraftPlane(
          id: id,
          origin: Vector3(x - 4, 0, 4 - y.toDouble()),
          u: Vector3(1, 0, 0),
          v: Vector3(0, 0, -1),
          region: region,
          grids: [
            protoplaneCells == null
                ? harvestGrid(lattice(id, region), region)
                : lattice(id, region, count: protoplaneCells! + 1),
          ],
        );
      }
    }
  }

  void clearWorld() {
    final before = _snapshot();
    _gestureBefore = null;
    objects.clear();
    landscape = PaperLandscape(preset: preset);
    harvestPending = false;
    lastHarvest = null;
    planes.clear();
    drafts.clear();
    bedrooms = [];
    for (final color in materials) {
      balances[color] = color.starterUnits;
    }
    nextId = 1;
    activePlaneId = editId = error = null;
    gridIndex = 0;
    _ground();
    _record(before, committed: true);
    notifyListeners();
  }

  void enter(String planeId, {String? editObject}) {
    if (!planes.containsKey(planeId)) return;
    lastHarvest = null;
    activePlaneId = planeId;
    editId = editObject;
    gridIndex = 0;
    error = null;
    notifyListeners();
  }

  void leave() {
    activePlaneId = null;
    editId = null;
    error = null;
    notifyListeners();
  }

  void selectGrid(int index) {
    gridIndex = index.clamp(0, activePlane!.grids.length - 1);
    error = null;
    notifyListeners();
  }

  void selectPaper(PaperMaterial color) {
    if (!materials.contains(color)) return;
    paper = color;
    notifyListeners();
  }

  void selectTool(CraftTool value) {
    tool = value;
    notifyListeners();
  }

  void report(String message) {
    error = message;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void beginGesture() {
    lastHarvest = null;
    _gestureBefore = _snapshot();
    error = null;
  }

  void finishGesture({bool resetDrawing = false}) {
    if (resetDrawing) {
      drafts.remove(draftKey);
      error = null;
    }
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before != null && before != _snapshot()) {
      _record(before, committed: harvestPending);
    }
    harvestPending = false;
    notifyListeners();
  }

  void cancelGesture() {
    harvestPending = false;
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before != null) _restore(before);
    notifyListeners();
  }

  bool appendNode(int node) {
    final g = grid;
    if (g == null || node < 0 || node >= g.nodes.length || closed) return false;
    final path = List<int>.of(draft.path);
    if (path.isNotEmpty && path.last == node) return false;
    if (path.isNotEmpty && g.connection(path.last, node) == null) {
      final route = g.collinearRoute(path.last, node);
      if (route == null) return false;
      // Validate the whole expansion before exposing any partial mutation.
      final expanded = [...path, ...route];
      for (var i = path.length; i < expanded.length; i++) {
        if (expanded.take(i).contains(expanded[i]) &&
            !(i == expanded.length - 1 &&
                expanded[i] == expanded.first &&
                i >= 3)) {
          return false;
        }
      }
      final trace = g.trace(expanded);
      final loop = expanded.first == expanded.last;
      if (!simplePath(
        loop ? trace.sublist(0, trace.length - 1) : trace,
        closed: loop,
      )) {
        return false;
      }
      drafts[draftKey] = CraftDraft(path: expanded, depth: draft.depth);
      error = null;
      notifyListeners();
      return true;
    }
    if (path.contains(node) && !(node == path.first && path.length >= 3)) {
      error = 'Lines cannot cross themselves';
      notifyListeners();
      return false;
    }
    path.add(node);
    if (path.length > 1) {
      final p = g.trace(path);
      final loop = path.first == path.last;
      if (!simplePath(loop ? p.sublist(0, p.length - 1) : p, closed: loop)) {
        error = 'Lines cannot cross themselves';
        notifyListeners();
        return false;
      }
    }
    drafts[draftKey] = CraftDraft(path: path, depth: draft.depth);
    error = null;
    notifyListeners();
    return true;
  }

  void removeDraftEdge(int index) {
    if (index < 0 || index >= draft.path.length - 1) return;
    _change(() {
      drafts[draftKey] = CraftDraft(path: draft.path.take(index + 1).toList());
    });
  }

  /// Step back without creating a nested transaction during an active drag.
  bool removeLastDraftNode({bool continuous = false}) {
    if (activePlane == null || draft.path.isEmpty) return false;
    void remove() {
      drafts[draftKey] = CraftDraft(
        path: draft.path.take(draft.path.length - 1).toList(),
        depth: draft.depth,
      );
      error = null;
    }

    if (continuous) {
      remove();
      notifyListeners();
    } else {
      _change(remove);
    }
    return true;
  }

  bool rewindDraftTo(int node, {bool continuous = false}) {
    final path = draft.path;
    final index = path.indexOf(node);
    // The starting node is always reserved for loop closure.
    if (activePlane == null || index <= 0 || index >= path.length - 1) {
      return false;
    }
    void rewind() {
      drafts[draftKey] = CraftDraft(
        path: path.take(index + 1).toList(),
        depth: draft.depth,
      );
      error = null;
    }

    if (continuous) {
      rewind();
      notifyListeners();
    } else {
      _change(rewind);
    }
    return true;
  }

  void clearDraft() => _change(() {
    drafts.remove(draftKey);
  });
  List<CraftKind> get matches =>
      activePlane == null || grid == null || editId != null
      ? []
      : recognize(activePlane!, grid!, draft.path);
  CraftKind? get chosen {
    final found = matches;
    return found.contains(draft.choice) ? draft.choice : found.firstOrNull;
  }

  void choose(CraftKind kind) {
    if (!matches.contains(kind)) return;
    _change(() {
      drafts[draftKey] = draft.copyWith(
        choice: kind,
        depth: recipes[kind]!.defaultDepth,
      );
    });
  }

  double get previewDepth {
    if (editId != null) {
      return drafts.containsKey(draftKey)
          ? draft.depth
          : objects[editId]?.depth ?? 0;
    }
    final kind = chosen;
    if (kind == null) return draft.depth;
    return draft.choice == null && draft.depth == 0
        ? recipes[kind]!.defaultDepth
        : draft.depth;
  }

  void setDepth(double depth, {bool continuous = false}) {
    void change() {
      drafts[draftKey] = draft.copyWith(
        depth: depth.clamp(0, 1),
        choice: chosen,
      );
    }

    if (continuous) {
      change();
      notifyListeners();
    } else {
      _change(change);
    }
  }

  CraftObject? get previewObject {
    if (harvestPreview != null) return null;
    if (editId != null) return objects[editId]?.copyWith(depth: previewDepth);
    final kind = chosen;
    if (kind == null || trace.length < 2) return null;
    Region region;
    final path = trace;
    if (kind == CraftKind.screen) {
      // Narrow occupancy strip; sheet area is length × height, not this strip.
      final quads = <Region>[];
      for (var i = 1; i < path.length; i++) {
        final d = path[i] - path[i - 1];
        final n = Offset(-d.dy, d.dx) / d.distance * .004;
        quads.add(
          Region([path[i - 1] + n, path[i] + n, path[i] - n, path[i - 1] - n]),
        );
      }
      // A screen may bend; occupancy validation checks every strip separately.
      region = quads.first;
    } else {
      region = Region(trace.sublist(0, trace.length - 1));
      if (kind == CraftKind.planter || kind == CraftKind.window) {
        region = hollowRegion(region);
      }
    }
    return CraftObject(
      id: 'preview',
      planeId: activePlaneId!,
      kind: kind,
      region: region,
      color: paper,
      depth: previewDepth,
      path: kind == CraftKind.screen ? path : [],
    );
  }

  int get quote {
    final p = previewObject;
    if (p == null) return 0;
    final old = objects[editId];
    if (old != null) {
      final screenPieces = screenCutPreview;
      if (screenPieces != null) {
        return (math.max(0, previewDepth - old.depth) *
                    screenPieces.fold(
                      0.0,
                      (sum, o) => sum + pathLength(o.path),
                    ) *
                    128 -
                1e-8)
            .ceil();
      }
      final cuts = cutPreview;
      if (cuts != null) {
        return (math.max(0, previewDepth - old.depth) *
                    cuts.fold(0.0, (sum, r) => sum + r.perimeter) *
                    128 -
                1e-8)
            .ceil();
      }
      return (math.max(0, p.materialArea - old.materialArea) * 128 - 1e-8)
          .ceil();
    }
    return (p.materialArea * 128 - 1e-8).ceil();
  }

  String? validateObject(CraftObject object, {String? replacing}) {
    final plane = planes[object.planeId];
    if (plane == null) return 'Missing support plane';
    final item = bedroomItems[object.kind];
    if (item != null && !item.supports.contains(objects[plane.owner]?.kind)) {
      return '${object.kind.label} needs its supporting furniture';
    }
    if (!object.region.valid) return 'Invalid outline';
    if (object.kind != CraftKind.screen &&
        !plane.region.containsRegion(object.region)) {
      return 'Outside the plane';
    }
    if (object.kind == CraftKind.window || object.kind == CraftKind.door) {
      final wall = objects[plane.owner];
      if (replacing == null &&
          (wall == null ||
              !wall.region.containsRegion(Region(object.region.outer)))) {
        return 'Opening must lie in remaining wall paper';
      }
    }
    if (replacing == null &&
        !recipes[object.kind]!.depthAllowed(object.depth)) {
      return 'Depth does not match ${object.kind.label}';
    }
    for (final part in occupancy(object)) {
      if (!plane.region.containsRegion(part)) return 'Outside the plane';
      for (final other in objects.values) {
        if (other.id == replacing || other.planeId != object.planeId) continue;
        if (occupancy(other).any(part.overlaps)) {
          return 'Overlaps an existing piece';
        }
      }
    }
    if (replacing != null && _hasDependents(replacing)) {
      final old = objects[replacing]!;
      if ((old.depth - object.depth).abs() > geometryEpsilon ||
          !object.region.containsRegion(old.region)) {
        return 'Attached objects need this support';
      }
    }
    // Check volume across differently oriented support planes as well.
    for (final other in objects.values) {
      if (other.id == replacing ||
          other.planeId == object.planeId ||
          other.id == plane.owner ||
          _ancestor(other.id, plane.owner)) {
        continue;
      }
      final op = planes[other.planeId]!;
      // Wall thicknesses may meet at a shared construction corner. Their
      // planar endpoints must coincide; crossings through wall interiors
      // still use the normal collision test.
      if (object.kind == CraftKind.wall && other.kind == CraftKind.wall) {
        final ends = [
          plane.point(Offset(object.region.bounds.left, 0)),
          plane.point(Offset(object.region.bounds.right, 0)),
        ];
        final otherEnds = [
          op.point(Offset(other.region.bounds.left, 0)),
          op.point(Offset(other.region.bounds.right, 0)),
        ];
        if (ends.any(
          (a) => otherEnds.any((b) => a.distanceTo(b) < geometryEpsilon),
        )) {
          continue;
        }
      }
      if (solidsOverlap(object, plane, other, op)) {
        return 'Intersects another object';
      }
      if (plane.normal.dot(op.normal).abs() < .999) continue;
      final base = (op.origin - plane.origin).dot(plane.normal);
      if (math.min(object.depth, base + other.depth) - math.max(0, base) <=
          geometryEpsilon) {
        continue;
      }
      final projected = Region(
        other.region.outer.map((p) => plane.local(op.point(p))).toList(),
        other.region.holes
            .map((h) => h.map((p) => plane.local(op.point(p))).toList())
            .toList(),
      );
      if (object.region.overlaps(projected)) return 'Intersects another object';
    }
    return null;
  }

  Iterable<Region> occupancy(CraftObject object) sync* {
    if (object.kind != CraftKind.screen) {
      yield object.region;
      return;
    }
    for (var i = 1; i < object.path.length; i++) {
      final a = object.path[i - 1], b = object.path[i];
      final d = b - a, n = Offset(-d.dy, d.dx) / d.distance * .004;
      yield Region([a + n, b + n, b - n, a - n]);
    }
  }

  bool _ancestor(String objectId, String? descendant) {
    var cursor = descendant;
    final seen = <String>{};
    while (cursor != null && seen.add(cursor)) {
      if (cursor == objectId) return true;
      cursor = planes[objects[cursor]?.planeId]?.owner;
    }
    return false;
  }

  bool _hasDependents(String id) => planes.values.any(
    (p) =>
        (p.owner == id || p.supports.contains(id)) &&
        objects.values.any((o) => o.planeId == p.id),
  );

  /// Closed drawings complete at the closing node; open recipes complete on lift.
  bool completeCraft({bool allowOpen = false}) {
    final harvest = harvestPreview;
    if (harvest != null) return _harvest(harvest);
    if (editId != null || (!closed && !allowOpen) || matches.isEmpty) {
      return false;
    }
    return create();
  }

  bool create() {
    lastHarvest = null;
    final harvest = harvestPreview;
    if (harvest != null) return _harvest(harvest);
    final candidate = previewObject;
    if (candidate == null || editId != null) return false;
    final message = validateObject(candidate);
    if (message != null) {
      report(message);
      return false;
    }
    final cost = quote;
    if (balances[paper]! < cost) {
      report('Not enough ${paper.name} paper');
      return false;
    }
    final before = _gestureBefore ?? _snapshot();
    final object = candidate.copyWith(id: 'object-${nextId++}');
    final plane = activePlane!;
    if (object.kind == CraftKind.window || object.kind == CraftKind.door) {
      final owner = objects[plane.owner];
      if (owner == null || owner.kind != CraftKind.wall) return false;
      final remaining = owner.region.subtract(Region(object.region.outer));
      if (remaining.length != 1 || !remaining.single.valid) {
        nextId--;
        report('Opening must leave one connected wall');
        return false;
      }
      objects[owner.id] = owner.copyWith(
        region: remaining.single,
        attachmentIds: [...owner.attachmentIds, object.id],
      );
    }
    objects[object.id] = object;
    balances[paper] = balances[paper]! - cost;
    drafts.remove(draftKey);
    _derivePlanes();
    _gestureBefore = null;
    _record(before, committed: true);
    notifyListeners();
    return true;
  }

  List<Region>? get cutPreview {
    final object = objects[editId];
    if (object == null || trace.length < 2) return null;
    if (object.kind == CraftKind.screen) return null;
    if (closed) {
      return object.region.subtract(Region(trace.sublist(0, trace.length - 1)));
    }
    final p = trace;
    bool onBoundary(Offset point) => object.region.rings.any(
      (ring) => edges(ring).any((e) => onSegment(point, e.$1, e.$2)),
    );
    if (!onBoundary(p.first) || !onBoundary(p.last)) return null;
    final pieces = splitPaperByCuts(object.region.outer, [
      for (var i = 1; i < p.length; i++) (p[i - 1], p[i]),
    ], holes: object.region.holes).map((p) => Region(p.$1, p.$2)).toList();
    return pieces.length > 1 ? pieces : null;
  }

  List<CraftObject>? get screenCutPreview {
    final object = objects[editId];
    if (object?.kind != CraftKind.screen || trace.length < 2) return null;
    final paths = cutPolyline(object!.path, trace, closed);
    if (paths == null) return null;
    return paths.map((path) {
      final d = path[1] - path[0], n = Offset(-d.dy, d.dx) / d.distance * .004;
      final region = Region([
        path[0] + n,
        path[1] + n,
        path[1] - n,
        path[0] - n,
      ]);
      return object.copyWith(path: path, region: region, depth: previewDepth);
    }).toList();
  }

  List<CraftObject>? get cutObjects {
    final object = objects[editId];
    if (object == null) return null;
    return screenCutPreview ??
        cutPreview
            ?.map((r) => object.copyWith(region: r, depth: previewDepth))
            .toList();
  }

  List<CraftKind> transformations(String id) {
    final object = objects[id], plane = planes[objects[id]?.planeId];
    if (object == null ||
        plane == null ||
        _hasDependents(id) ||
        [
          CraftKind.floor,
          CraftKind.wall,
          CraftKind.window,
          CraftKind.door,
          CraftKind.screen,
        ].contains(object.kind)) {
      return [];
    }
    final found = <CraftKind>{};
    for (final grid in plane.grids) {
      final curved = grid.edges
          .where((e) => e.control != null)
          .any(
            (e) => e
                .points(grid.nodes)
                .skip(1)
                .any((p) => object.region.outer.any((v) => near(p, v))),
          );
      found.addAll(recognizeRegion(plane, grid, object.region, curved: curved));
    }
    return found
        .where(
          (kind) =>
              kind != object.kind &&
              ![
                CraftKind.floor,
                CraftKind.wall,
                CraftKind.window,
                CraftKind.door,
                CraftKind.screen,
              ].contains(kind),
        )
        .toList()
      ..sort((a, b) => recipes[a]!.priority.compareTo(recipes[b]!.priority));
  }

  CraftObject _transformed(CraftObject object, CraftKind kind) =>
      object.copyWith(
        kind: kind,
        depth: recipes[kind]!.depthAllowed(object.depth)
            ? object.depth
            : recipes[kind]!.defaultDepth,
      );
  int transformationQuote(String id, CraftKind kind) {
    final object = objects[id]!;
    return (math.max(
                  0,
                  _transformed(object, kind).materialArea - object.materialArea,
                ) *
                128 -
            1e-8)
        .ceil();
  }

  bool transformObject(String id, CraftKind kind) {
    if (!transformations(id).contains(kind)) {
      report('This object cannot transform to that type');
      return false;
    }
    final object = objects[id]!, next = _transformed(objects[id]!, kind);
    final message = validateObject(next, replacing: id);
    if (message != null) {
      report(message);
      return false;
    }
    final cost = transformationQuote(id, kind);
    if (balances[object.color]! < cost) {
      report('Not enough paper');
      return false;
    }
    final before = _snapshot();
    objects[id] = next;
    planes.remove('surface-$id');
    balances[object.color] = balances[object.color]! - cost;
    drafts.clear();
    _derivePlanes();
    _record(before, committed: true);
    notifyListeners();
    return true;
  }

  bool applyEdit() {
    final original = objects[editId];
    if (original == null) return false;
    final cuts = cutObjects;
    if (draft.path.isNotEmpty && cuts == null) {
      report('Complete a cut between boundaries');
      return false;
    }
    if (_hasDependents(original.id) &&
        (cuts != null || previewDepth != original.depth)) {
      report('Attached objects need this support');
      return false;
    }
    final edited = cuts ?? [original.copyWith(depth: previewDepth)];
    if (edited.isEmpty || edited.any((o) => !o.region.valid)) {
      report('Cut must leave valid paper');
      return false;
    }
    for (final o in edited) {
      final message = validateObject(o, replacing: original.id);
      if (message != null) {
        report(message);
        return false;
      }
    }
    final cost = quote;
    if (balances[original.color]! < cost) {
      report('Not enough ${original.color.name} paper');
      return false;
    }
    final before = _snapshot();
    objects[original.id] = edited.first;
    for (final piece in edited.skip(1)) {
      final id = 'object-${nextId++}';
      objects[id] = piece.copyWith(id: id);
    }
    balances[original.color] = balances[original.color]! - cost;
    drafts.remove(draftKey);
    _derivePlanes();
    _record(before, committed: true);
    notifyListeners();
    return true;
  }

  void _derivePlanes() {
    final old = Map<String, CraftPlane>.of(planes);
    planes.removeWhere((id, p) => !id.startsWith('ground-'));
    // Objects are inserted parent-first and IDs remain stable through saves.
    for (final object in objects.values) {
      final source = planes[object.planeId] ?? old[object.planeId];
      if (source == null) continue;
      final ownId = 'surface-${object.id}';
      final isWall = object.kind == CraftKind.wall;
      final available = surfaceRecipes(object.kind);
      final prior = old[ownId];
      final sameOutline =
          prior != null &&
          jsonEncode(prior.region.toJson()) ==
              jsonEncode(object.region.toJson());
      // Wall crafting boundary retains its original extent: holes are occupancy
      // constraints, not a shrinking coordinate system for its attachment grid.
      final workRegion = isWall && prior != null ? prior.region : object.region;
      planes[ownId] = CraftPlane(
        id: ownId,
        origin: source.origin + source.normal * (object.depth + .002),
        u: source.u,
        v: source.v,
        region: workRegion,
        owner: object.id,
        grids: sameOutline || (isWall && prior != null)
            ? prior.grids
            : object.kind == CraftKind.floor
            ? [
                ...floorGrids(ownId, object.region, _seed(object.id)),
                bedroomGrid(ownId, object.region),
              ]
            : [
                lattice(
                  ownId,
                  workRegion,
                  count: 5,
                  recipes: available,
                  name: isWall ? 'Openings' : 'Surface',
                ),
              ],
      );
      if (object.kind == CraftKind.floor) {
        final ring = simplifyRing(object.region.outer);
        for (var i = 0; i < ring.length; i++) {
          final a = ring[i], b = ring[(i + 1) % ring.length];
          final edge = source.point(b) - source.point(a);
          final id = 'wall-${object.id}-$i';
          final region = rectangle(edge.length, 1);
          planes[id] = CraftPlane(
            id: id,
            origin: source.point(a, object.depth + .003),
            u: edge.normalized(),
            v: Vector3(0, 1, 0),
            region: region,
            owner: object.id,
            wallCandidate: true,
            grids: [
              lattice(id, region, recipes: [CraftKind.wall], name: 'Wall'),
            ],
          );
        }
      }
      if (object.kind == CraftKind.wall) {
        final floor = objects[source.owner];
        final floorSource = floor == null ? null : planes[floor.planeId];
        if (floor == null || floorSource == null) continue;
        final id = 'upper-${floor.id}';
        final existing = planes[id];
        planes[id] = CraftPlane(
          id: id,
          origin: floorSource.origin + Vector3(0, floor.depth + 1.003, 0),
          u: floorSource.u,
          v: floorSource.v,
          region: floor.region,
          owner: floor.id,
          supports: [...?existing?.supports, object.id],
          grids:
              old[id]?.grids ??
              [lattice(id, floor.region, name: 'Upper floor')],
        );
      }
    }
    drafts.removeWhere(
      (key, value) => !planes.keys.any((id) => key.startsWith('$id/')),
    );
    if (!planes.containsKey(activePlaneId)) {
      activePlaneId = null;
      editId = null;
    }
    _upgradeBedroomGrids();
    bedrooms = evaluateBedrooms(objects, planes);
  }

  void _upgradeBedroomGrids() {
    _resizeProtoplaneGrids();
    for (final p in List<CraftPlane>.of(planes.values)) {
      if (p.id.startsWith('ground-') ||
          p.wallCandidate ||
          objects[p.owner]?.kind == CraftKind.wall) {
        planes[p.id] = p.withGrids(
          p.grids
              .map(
                (g) => CraftGrid(
                  id: g.id,
                  name: g.name,
                  nodes: g.nodes,
                  edges: g.edges.where((e) {
                    final d = g.nodes[e.a] - g.nodes[e.b];
                    return e.control == null &&
                        (d.dx.abs() < geometryEpsilon ||
                            d.dy.abs() < geometryEpsilon);
                  }).toList(),
                  recipes: g.recipes,
                  examples: g.examples,
                  tiled: g.tiled,
                ),
              )
              .toList(),
        );
      }
    }

    for (final p in List<CraftPlane>.of(planes.values)) {
      if (p.id.startsWith('surface-') &&
          objects[p.owner]?.kind == CraftKind.tabletop &&
          !p.grids.any((g) => g.recipes.contains(CraftKind.lamp))) {
        planes[p.id] = p.withGrids(
          p.grids
              .map(
                (g) => CraftGrid(
                  id: g.id,
                  name: g.name,
                  nodes: g.nodes,
                  edges: g.edges,
                  recipes: [...g.recipes, CraftKind.lamp],
                  examples: g.examples,
                ),
              )
              .toList(),
        );
      }
      if (p.id.startsWith('surface-') &&
          objects[p.owner]?.kind == CraftKind.floor &&
          !p.grids.any((g) => g.id == '${p.id}-bedroom')) {
        planes[p.id] = p.withGrids([...p.grids, bedroomGrid(p.id, p.region)]);
      }
    }
    for (final p in List<CraftPlane>.of(planes.values)) {
      if (p.id.startsWith('surface-') &&
          objects[p.owner]?.kind == CraftKind.floor) {
        planes[p.id] = p.withGrids(
          p.grids.map((g) => tileFloorGrid(g, p.region)).toList(),
        );
      }
    }
  }

  int _seed(String s) =>
      s.codeUnits.fold(17, (a, b) => (a * 31 + b) & 0x7fffffff);

  void _change(VoidCallback action) {
    final before = _snapshot();
    action();
    if (before != _snapshot()) _record(before);
    error = null;
    notifyListeners();
  }

  void _record(String before, {bool committed = false}) {
    _undo.add(before);
    _redo.clear();
    error = null;
    if (committed) onCommitted?.call(toJson());
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    onCommitted?.call(toJson());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    onCommitted?.call(toJson());
    notifyListeners();
  }

  String _snapshot() => jsonEncode({
    'world': toJson(),
    'drafts': {for (final e in drafts.entries) e.key: e.value.toJson()},
    'active': activePlaneId,
    'edit': editId,
    'grid': gridIndex,
  });
  void _restore(String snapshot) {
    final j = jsonDecode(snapshot) as Map<String, dynamic>;
    _load(j['world']);
    drafts
      ..clear()
      ..addAll({
        for (final e in (j['drafts'] as Map).entries)
          e.key: CraftDraft.fromJson(e.value),
      });
    activePlaneId = j['active'];
    editId = j['edit'];
    gridIndex = j['grid'];
    error = null;
  }

  Map<String, dynamic> toJson() => {
    'version': 3,
    'preset': preset.name,
    'paper': paper.id,
    'landscape': landscape.toJson(),
    'nextId': nextId,
    'planes': planes.values.map((p) => p.toJson()).toList(),
    'objects': objects.values.map((o) => o.toJson()).toList(),
    'balances': {for (final e in balances.entries) e.key.id: e.value},
  };
  void load(Map<String, dynamic> json) {
    final validated = ProtoplaneController();
    try {
      validated._load(json);
      validated._validateLoaded();
      _load(validated.toJson());
    } finally {
      validated.dispose();
    }
    _undo.clear();
    _redo.clear();
    drafts.clear();
    activePlaneId = null;
    editId = null;
    notifyListeners();
  }

  void _load(Map<String, dynamic> j) {
    if (j['version'] != 1 && j['version'] != 2 && j['version'] != 3) {
      throw const FormatException('Unsupported world version');
    }
    preset = j['version'] == 3
        ? WorldPreset.values.byName(j['preset'])
        : WorldPreset.pastel;
    paper = j['version'] == 3 && j['paper'] != null
        ? PaperMaterial.decode(j['paper'])
        : materials.first;
    if (!materials.contains(paper)) {
      throw const FormatException('Invalid selected material');
    }
    balances.clear();
    planes
      ..clear()
      ..addEntries(
        (j['planes'] as List).map((p) {
          final plane = CraftPlane.fromJson(p);
          return MapEntry(plane.id, plane);
        }),
      );
    objects
      ..clear()
      ..addEntries(
        (j['objects'] as List).map((o) {
          final object = CraftObject.fromJson(o);
          return MapEntry(object.id, object);
        }),
      );
    nextId = j['nextId'];
    for (final color in materials) {
      final value =
          j['balances'][j['version'] == 3 ? color.id : color.name] ??
          (j['version'] == 1 &&
                  (color == PaperColor.blue || color == PaperColor.sand)
              ? 256
              : null);
      if (value is! int || value < 0) {
        throw const FormatException('Invalid paper balance');
      }
      balances[color] = value;
    }
    for (final plane in planes.values.toList()) {
      if (plane.id.startsWith('ground-') &&
          plane.grids.first.nodes.length < 25) {
        planes[plane.id] = plane.withGrids([
          harvestGrid(plane.grids.first, plane.region),
          ...plane.grids.skip(1),
        ]);
      }
    }
    _resizeProtoplaneGrids();
    landscape = j['version'] != 1
        ? PaperLandscape.fromJson(j['landscape'], planes, preset: preset)
        : PaperLandscape(preset: preset);
    if (j['version'] == 1) {
      for (final object in objects.values) {
        if (object.planeId.startsWith('ground-')) {
          landscape.deplete(object.planeId, object.region);
        }
      }
    }
    lastHarvest = null;
    harvestPending = false;
    _harvestPreviewKey = null;
    _upgradeBedroomGrids();
    bedrooms = evaluateBedrooms(objects, planes);
  }

  void _validateLoaded() {
    if (nextId < 1 || balances.values.any((b) => b < 0) || planes.length < 64) {
      throw const FormatException('Invalid world data');
    }
    for (final p in planes.values) {
      if (!p.region.valid ||
          p.grids.isEmpty ||
          [
            p.origin.x,
            p.origin.y,
            p.origin.z,
            ...p.u.storage,
            ...p.v.storage,
          ].any((v) => !v.isFinite) ||
          (p.u.length - 1).abs() > 1e-5 ||
          (p.v.length - 1).abs() > 1e-5 ||
          p.u.dot(p.v).abs() > 1e-5 ||
          (p.owner != null && !objects.containsKey(p.owner)) ||
          p.supports.any((s) => !objects.containsKey(s))) {
        throw const FormatException('Invalid plane');
      }
      for (final g in p.grids) {
        if (g.nodes.any((n) => !n.dx.isFinite || !n.dy.isFinite) ||
            g.edges.any(
              (e) =>
                  e.a < 0 ||
                  e.b < 0 ||
                  e.a >= g.nodes.length ||
                  e.b >= g.nodes.length,
            )) {
          throw const FormatException('Invalid crafting grid');
        }
      }
    }
    for (final o in objects.values) {
      if (!materials.contains(o.material) ||
          !planes.containsKey(o.planeId) ||
          !o.region.valid ||
          !o.depth.isFinite ||
          o.depth < 0 ||
          o.depth > 1 ||
          o.attachmentIds.any((id) => !objects.containsKey(id))) {
        throw const FormatException('Invalid object');
      }
    }
  }
}
