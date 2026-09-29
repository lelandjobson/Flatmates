import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../geometry/polygon_union.dart';
import '../gridcraft/blueprint.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/painter.dart';
import '../gridcraft/rules.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/craft_palette.dart';
import '../ui/game/game_tool_carousel.dart';

enum _EditorTool {
  shapes,
  level,
  exits,
  length,
  forbid,
  colors,
  numbers,
  arrows,
  docks,
  links,
  seams,
}

enum _ShapeTool { draw, select, delete }

enum _MarkMode { place, erase, flip }

const Color _hud = Color(0xFF1A1A1A);

Color _editorToolFill(_EditorTool tool) => switch (tool) {
  _EditorTool.shapes => CraftPalette.kentuckyBlue.fill,
  _EditorTool.level => CraftPalette.midnightBlue.fill,
  _EditorTool.exits => CraftPalette.cyan.fill,
  _EditorTool.length => CraftPalette.turquoise.fill,
  _EditorTool.forbid => CraftPalette.scarlet.fill,
  _EditorTool.colors => CraftPalette.fuschia.fill,
  _EditorTool.numbers => CraftPalette.butter.fill,
  _EditorTool.arrows => CraftPalette.ginger.fill,
  _EditorTool.docks => CraftPalette.seaFoam.fill,
  _EditorTool.links => CraftPalette.babyBoy.fill,
  _EditorTool.seams => CraftPalette.coral.fill,
};

Color _shapeToolFill(_ShapeTool tool) => switch (tool) {
  _ShapeTool.draw => CraftPalette.cerulean.fill,
  _ShapeTool.select => CraftPalette.granite.fill,
  _ShapeTool.delete => CraftPalette.red.fill,
};

Color _markFill(_MarkMode mode) => switch (mode) {
  _MarkMode.place => CraftPalette.grass.fill,
  _MarkMode.erase => CraftPalette.stone.fill,
  _MarkMode.flip => CraftPalette.mango.fill,
};

/// Authors a blueprint's levels, then sends one into play.
class PuzzleEditorView extends StatefulWidget {
  const PuzzleEditorView({super.key, this.store});

  final LevelStore? store;

  @override
  State<PuzzleEditorView> createState() => _PuzzleEditorViewState();
}

class _PuzzleEditorViewState extends State<PuzzleEditorView> {
  final LevelStore _store = LevelStore();
  late PapercutCamera _camera;
  List<GridBlueprint> _levels = const [];
  GridBlueprint _blueprint = blankPuzzle();
  late GridBlueprint _snapshot;
  int _stepIndex = 0;
  Set<int> _selected = {};
  Set<RulePick> _picked = {};
  List<Offset> _draft = const [];
  _EditorTool _tool = _EditorTool.shapes;
  _ShapeTool _shape = _ShapeTool.draw;
  _MarkMode _mark = _MarkMode.place;
  int _color = 0;
  Offset? _hover;
  Offset? _edgeAnchor;
  Offset? _linkAnchor;
  int? _linkPair;
  bool _needsFrame = true;
  Size _viewport = Size.zero;
  Offset? _lastFocal;
  Offset? _downWorld;
  double _moved = 0;
  double _gestureScale = 1;
  bool _zoomed = false;
  bool _dragShape = false;
  List<List<Offset>>? _dragBase;
  GridRules? _dragRules;
  Offset _dragDelta = Offset.zero;
  Offset? _downScreen;
  int? _pressPolygon;
  RulePick? _pressMark;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  LevelStore get _levelsStore => widget.store ?? _store;

  GridStep get _step => _blueprint.steps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _snapshot = cloneGridBlueprint(_blueprint);
    _camera = PapercutCamera()..addListener(_onCamera);
    _refreshLevels();
  }

  @override
  void dispose() {
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshLevels() async {
    final saved = await _levelsStore.loadAll();
    if (!mounted) return;
    setState(() {
      _levels = saved;
      if (!_levels.any((level) => level.id == _blueprint.id)) return;
      _levels = [
        for (final level in _levels)
          if (level.id == _blueprint.id) _blueprint else level,
      ];
    });
  }

  void _adopt(GridBlueprint blueprint, {bool snapshot = true}) {
    _blueprint = blueprint.copyWith(
      steps: [
        for (final step in blueprint.steps) step.copyWith(paperMargin: 2),
      ],
    );
    _stepIndex = 0;
    _selected = {};
    _picked = {};
    _draft = const [];
    _marqueeStart = null;
    _marqueeEnd = null;
    _edgeAnchor = null;
    _linkAnchor = null;
    _linkPair = null;
    _hover = null;
    if (snapshot) _snapshot = cloneGridBlueprint(blueprint);
    _needsFrame = true;
    _frame();
  }

  void _frame() {
    final paper = _step.paper;
    final span = math.max(paper.width, paper.height);
    _camera.frameSheet(
      _viewport,
      sheetMm: span < 1 ? _step.paperMargin * _step.gridSpacing * 2 : span,
      center: paper.center,
    );
  }

  Offset _snapPoint(Offset world) {
    final spacing = _step.gridSpacing;
    if (spacing <= 1e-9) return world;
    return Offset(
      (world.dx / spacing).roundToDouble() * spacing,
      (world.dy / spacing).roundToDouble() * spacing,
    );
  }

  Offset? _worldAt(Offset local) => _camera.planePoint(local, _viewport);

  void _replaceStep(GridStep step) {
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = step;
    _blueprint = _blueprint.copyWith(steps: steps);
  }

  void _setRules(GridRules rules) {
    _replaceStep(_step.copyWith(rules: rules));
  }

  int? _hit(Offset world) {
    for (var i = _step.polygons.length - 1; i >= 0; i--) {
      final ring = _step.polygons[i];
      if (!_step.isRingClosed(i) || ring.length < 3) continue;
      if (isInsidePolygon(world, ring)) return i;
    }
    var best = -1;
    var bestDistance = _step.gridSpacing * 0.45;
    for (var i = _step.polygons.length - 1; i >= 0; i--) {
      final ring = _step.polygons[i];
      final count = _step.edgeCountOf(i);
      for (var edge = 0; edge < count; edge++) {
        final distance = _segmentDistance(
          world,
          ring[edge],
          ring[(edge + 1) % ring.length],
        );
        if (distance < bestDistance) {
          bestDistance = distance;
          best = i;
        }
      }
    }
    return best < 0 ? null : best;
  }

  List<Offset> get _shownDraft {
    final hover = _hover;
    if (_edgeAnchor != null && hover != null && _tool != _EditorTool.shapes) {
      return [_edgeAnchor!, hover];
    }
    if (_linkAnchor != null && hover != null && _tool == _EditorTool.links) {
      return [_linkAnchor!, hover];
    }
    if (_tool != _EditorTool.shapes ||
        _shape != _ShapeTool.draw ||
        hover == null) {
      return _draft;
    }
    if (_draft.isNotEmpty && sameGridPoint(hover, _draft.last)) return _draft;
    return [..._draft, hover];
  }

  void _onTap(Offset world) {
    final point = _snapPoint(world);
    switch (_tool) {
      case _EditorTool.shapes:
        _onShapeTap(world, point);
      case _EditorTool.level:
        _editLevel(point);
      case _EditorTool.exits:
      case _EditorTool.length:
        break;
      case _EditorTool.forbid:
        _editPoints(
          point,
          _step.rules.forbidden,
          (points) => _step.rules.copyWith(forbidden: points),
        );
      case _EditorTool.docks:
        _editPoints(
          point,
          _step.rules.docks,
          (points) => _step.rules.copyWith(docks: points),
        );
      case _EditorTool.colors:
        _editColors(point);
      case _EditorTool.numbers:
        _editNumbers(point);
      case _EditorTool.arrows:
        _editEdge(point, seam: false);
      case _EditorTool.seams:
        _editEdge(point, seam: true);
      case _EditorTool.links:
        _editLinks(point);
    }
  }

  void _onShapeTap(Offset world, Offset point) {
    switch (_shape) {
      case _ShapeTool.draw:
        final click = applyDraftClick(_draft, point);
        setState(() {
          _draft = click.draft;
          final closed = click.closed;
          final open = click.open;
          if (closed != null) {
            _commitOutline(closed, closedRing: true);
          } else if (open != null) {
            _commitOutline(open, closedRing: false);
          }
        });
      case _ShapeTool.select:
        final edged = _selected.length == 1
            ? _edgeIndex(_selected.single, point)
            : null;
        if (edged != null) {
          _toggleEdge(_selected.single, edged);
          return;
        }
        final index = _hit(world);
        final mark = index == null ? _hitMark(world) : null;
        setState(() {
          if (index == null && mark == null) {
            _selected = {};
            _picked = {};
            return;
          }
          if (index != null) {
            if (!_selected.add(index)) _selected.remove(index);
            return;
          }
          if (!_picked.add(mark!)) _picked.remove(mark);
        });
      case _ShapeTool.delete:
        final index = _hit(world);
        if (index == null) return;
        _removePolygons({index});
    }
  }

  void _removePolygons(Set<int> indexes) {
    if (indexes.isEmpty) return;
    setState(() {
      _replaceStep(_step.filterPieces((index) => !indexes.contains(index)));
      _selected = {};
    });
  }

  void _editPoints(
    Offset point,
    List<Offset> points,
    GridRules Function(List<Offset> points) write,
  ) {
    if (_mark == _MarkMode.erase) {
      final index = _nearestPoint(points, point);
      if (index < 0) return;
      final next = [...points]..removeAt(index);
      setState(() => _setRules(write(next)));
      return;
    }
    if (points.any((existing) => sameGridPoint(existing, point))) return;
    setState(() => _setRules(write([...points, point])));
  }

  void _editColors(Offset point) {
    final rules = _step.rules;
    final index = _nearestMark(
      rules.colors.length,
      (i) => rules.colors[i].point,
      point,
    );
    if (_mark == _MarkMode.erase) {
      if (index < 0) return;
      final next = [...rules.colors]..removeAt(index);
      setState(() => _setRules(rules.copyWith(colors: next)));
      return;
    }
    if (index >= 0) {
      final next = [...rules.colors];
      next[index] = ColorMark(point, _color);
      setState(() => _setRules(rules.copyWith(colors: next)));
      return;
    }
    setState(() {
      _setRules(
        rules.copyWith(colors: [...rules.colors, ColorMark(point, _color)]),
      );
    });
  }

  void _editNumbers(Offset point) {
    final rules = _step.rules;
    final index = _nearestMark(
      rules.numbers.length,
      (i) => rules.numbers[i].point,
      point,
    );
    if (_mark == _MarkMode.erase) {
      if (index < 0) return;
      final next = [...rules.numbers]..removeAt(index);
      setState(() => _setRules(rules.copyWith(numbers: next)));
      return;
    }
    if (index >= 0) return;
    final used = {for (final mark in rules.numbers) mark.number};
    var number = 1;
    while (used.contains(number)) {
      number++;
    }
    setState(() {
      _setRules(
        rules.copyWith(numbers: [...rules.numbers, OrderMark(point, number)]),
      );
    });
  }

  void _editEdge(Offset point, {required bool seam}) {
    final rules = _step.rules;
    final edges = seam ? rules.seams : rules.arrows;
    if (_mark == _MarkMode.erase) {
      final index = _nearestEdge(edges, point);
      if (index < 0) return;
      final next = [...edges]..removeAt(index);
      setState(() {
        _setRules(
          seam ? rules.copyWith(seams: next) : rules.copyWith(arrows: next),
        );
      });
      return;
    }
    if (_mark == _MarkMode.flip && !seam) {
      final index = _nearestEdge(edges, point);
      if (index < 0) return;
      final edge = edges[index];
      final next = [...edges];
      next[index] = GridEdge(edge.b, edge.a);
      setState(() => _setRules(rules.copyWith(arrows: next)));
      return;
    }
    final anchor = _edgeAnchor;
    if (anchor == null || sameGridPoint(anchor, point)) {
      setState(() => _edgeAnchor = point);
      return;
    }
    final edge = GridEdge(anchor, point);
    setState(() {
      _edgeAnchor = null;
      _setRules(
        seam
            ? rules.copyWith(seams: [...rules.seams, edge])
            : rules.copyWith(arrows: [...rules.arrows, edge]),
      );
    });
  }

  void _editLinks(Offset point) {
    final rules = _step.rules;
    if (_mark == _MarkMode.erase) {
      final index = _nearestMark(
        rules.links.length,
        (i) => rules.links[i].point,
        point,
      );
      if (index < 0) return;
      final next = [...rules.links]..removeAt(index);
      setState(() => _setRules(rules.copyWith(links: next)));
      return;
    }
    final anchor = _linkAnchor;
    if (anchor == null) {
      var pair = 1;
      for (final mark in rules.links) {
        if (mark.pair >= pair) pair = mark.pair + 1;
      }
      setState(() {
        _linkAnchor = point;
        _linkPair = pair;
        _setRules(
          rules.copyWith(links: [...rules.links, LinkMark(point, pair)]),
        );
      });
      return;
    }
    if (sameGridPoint(anchor, point)) return;
    final pair = _linkPair ?? 1;
    setState(() {
      _linkAnchor = null;
      _linkPair = null;
      _setRules(
        rules.copyWith(links: [..._step.rules.links, LinkMark(point, pair)]),
      );
    });
  }

  int _nearestPoint(List<Offset> points, Offset target) {
    return _nearestMark(points.length, (index) => points[index], target);
  }

  int _nearestMark(int count, Offset Function(int index) at, Offset target) {
    final limit = _step.gridSpacing * 0.75;
    var best = -1;
    var bestDistance = limit;
    for (var i = 0; i < count; i++) {
      final distance = (at(i) - target).distance;
      if (distance > bestDistance) continue;
      best = i;
      bestDistance = distance;
    }
    return best;
  }

  int _nearestEdge(List<GridEdge> edges, Offset target) {
    final limit = _step.gridSpacing * 0.75;
    var best = -1;
    var bestDistance = limit;
    for (var i = 0; i < edges.length; i++) {
      final distance = _segmentDistance(target, edges[i].a, edges[i].b);
      if (distance > bestDistance) continue;
      best = i;
      bestDistance = distance;
    }
    return best;
  }

  void _commitOutline(List<Offset> points, {required bool closedRing}) {
    final closed = [
      for (var i = 0; i < _step.polygons.length; i++) _step.isRingClosed(i),
      closedRing,
    ];
    _replaceStep(
      _step.copyWith(
        polygons: [..._step.polygons, points],
        ringClosed: closed,
      ),
    );
    _draft = const [];
  }

  void _closeDraft() {
    if (_draft.length < 3) return;
    final click = applyDraftClick(_draft, _draft.first);
    final closed = click.closed;
    if (closed == null) return;
    setState(() => _commitOutline(closed, closedRing: true));
  }

  void _editLevel(Offset point) {
    if (_mark == _MarkMode.erase) {
      final zones = _step.permutation.noFold;
      var best = -1;
      var bestDistance = _step.gridSpacing * 0.75;
      for (var i = 0; i < zones.length; i++) {
        for (final corner in zones[i]) {
          final distance = (corner - point).distance;
          if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
          }
        }
      }
      if (best < 0) return;
      final next = [...zones]..removeAt(best);
      setState(() {
        _replaceStep(
          _step.copyWith(
            permutation: _step.permutation.copyWith(noFold: next),
          ),
        );
      });
      return;
    }
    final anchor = _edgeAnchor;
    if (anchor == null) {
      setState(() => _edgeAnchor = point);
      return;
    }
    final zone = [
      anchor,
      Offset(point.dx, anchor.dy),
      point,
      Offset(anchor.dx, point.dy),
    ];
    setState(() {
      _edgeAnchor = null;
      _replaceStep(
        _step.copyWith(
          permutation: _step.permutation.copyWith(
            noFold: [..._step.permutation.noFold, zone],
          ),
        ),
      );
    });
  }

  int? _edgeIndex(int piece, Offset point) {
    final ring = _step.polygons[piece];
    var best = -1;
    var bestDistance = _step.gridSpacing * 0.45;
    final count = _step.edgeCountOf(piece);
    for (var i = 0; i < count; i++) {
      final distance = _segmentDistance(
        point,
        ring[i],
        ring[(i + 1) % ring.length],
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  void _toggleEdge(int piece, int edge) {
    final styles = [
      for (var i = 0; i < _step.polygons.length; i++)
        List<EdgeStyle>.of(_step.edgeStyleOf(i)),
    ];
    final row = styles[piece];
    row[edge] = row[edge] == EdgeStyle.penciled
        ? EdgeStyle.penned
        : EdgeStyle.penciled;
    setState(() => _replaceStep(_step.copyWith(edgeStyles: styles)));
  }

  void _nudgeCollision(int delta) {
    if (_selected.length != 1) return;
    final index = _selected.single;
    final collisions = [
      for (var i = 0; i < _step.polygons.length; i++) _step.collisionOf(i),
    ];
    final current = collisions[index];
    if (delta < 0 && (current == null || current <= 1)) {
      collisions[index] = null;
    } else {
      collisions[index] = (current ?? 0) + delta;
    }
    setState(() => _replaceStep(_step.copyWith(collisions: collisions)));
  }

  void _merge() {
    if (_selected.length < 2) return;
    final chosen = [for (final index in _selected) _step.polygons[index]];
    setState(() {
      final kept = _step.filterPieces((index) => !_selected.contains(index));
      _replaceStep(
        kept.copyWith(
          polygons: [...kept.polygons, ...mergeSelected(chosen)],
        ),
      );
      _selected = {};
    });
  }

  void _newPuzzle() {
    setState(() => _adopt(blankPuzzle()));
  }

  void _copyPuzzle() {
    setState(() => _adopt(copyPuzzle(_blueprint)));
  }

  Future<void> _save() async {
    await _levelsStore.save(_blueprint);
    if (!mounted) return;
    setState(() => _snapshot = cloneGridBlueprint(_blueprint));
    await _refreshLevels();
  }

  void _clear() {
    setState(() => _adopt(cloneGridBlueprint(_snapshot)));
  }

  void _play() {
    context.pushNamed('grid_puzzles', extra: cloneGridBlueprint(_blueprint));
  }

  void _nudgeLimit({required bool exits, required int delta}) {
    final rules = _step.rules;
    if (exits) {
      final current = rules.maxExits;
      if (delta < 0 && (current == null || current <= 1)) {
        setState(() => _setRules(rules.copyWith(clearExits: true)));
        return;
      }
      setState(
        () => _setRules(rules.copyWith(maxExits: (current ?? 0) + delta)),
      );
      return;
    }
    final current = rules.maxLength;
    if (delta < 0 && (current == null || current <= 1)) {
      setState(() => _setRules(rules.copyWith(clearLength: true)));
      return;
    }
    final next = (current ?? 0) + delta;
    setState(() => _setRules(rules.copyWith(maxLength: next.toDouble())));
  }

  List<GridBlueprint> get _menuLevels {
    if (!_levels.any((level) => level.id == _blueprint.id)) {
      return [_blueprint, ..._levels];
    }
    return [
      for (final level in _levels)
        if (level.id == _blueprint.id) _blueprint else level,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (_needsFrame && _viewport.width > 2) {
            _needsFrame = false;
            _frame();
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent ||
                        event.scrollDelta.dy == 0) {
                      return;
                    }
                    _camera.zoomByScale(
                      math.exp(-event.scrollDelta.dy * 0.002),
                    );
                  },
                  child: GestureDetector(
                    key: const Key('puzzle-editor-canvas'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: CustomPaint(
                      painter: GridPuzzlePainter(
                        camera: _camera,
                        step: _step,
                        sheet: PapercutSheet.empty(),
                        march: null,
                        flash: 0,
                        rulerX: null,
                        showRuler: false,
                        selected: _selected,
                        fillShapes: true,
                        draft: _shownDraft,
                        picked: _picked,
                        marquee: _marqueeRect,
                        marqueeCross: _marqueeCross,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              FmSafePositioned(top: 8, left: 8, right: 8, child: _topBar()),
              FmSafePositioned(left: 0, right: 0, bottom: 8, child: _toolbar()),
            ],
          );
        },
      ),
    );
  }

  Rect? get _marqueeRect {
    final start = _marqueeStart;
    final end = _marqueeEnd;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  bool get _marqueeCross {
    final start = _marqueeStart;
    final end = _marqueeEnd;
    if (start == null || end == null) return false;
    return end.dx < start.dx;
  }

  bool get _selecting =>
      _tool == _EditorTool.shapes && _shape == _ShapeTool.select;

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocal = details.localFocalPoint;
    _downScreen = details.localFocalPoint;
    _moved = 0;
    _gestureScale = 1;
    _zoomed = false;
    _dragDelta = Offset.zero;
    _downWorld = _worldAt(details.localFocalPoint);
    _dragShape = false;
    _dragBase = null;
    _dragRules = null;
    _marqueeStart = null;
    _marqueeEnd = null;
    _pressPolygon = null;
    _pressMark = null;
    final world = _downWorld;
    if (!_selecting || world == null) return;
    final polygon = _hit(world);
    final mark = polygon == null ? _hitMark(world) : null;
    _pressPolygon = polygon;
    _pressMark = mark;
    final onPolygon = polygon != null && _selected.contains(polygon);
    final onMark = mark != null && _picked.contains(mark);
    if (onPolygon || onMark) _armDrag();
  }

  void _armDrag() {
    final polygon = _pressPolygon;
    final mark = _pressMark;
    if (polygon != null && !_selected.contains(polygon)) {
      _selected = {polygon};
      _picked = {};
    } else if (mark != null && !_picked.contains(mark)) {
      _selected = {};
      _picked = {mark};
    }
    _dragShape = true;
    _dragBase = [for (final ring in _step.polygons) List<Offset>.from(ring)];
    _dragRules = _step.rules;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final local = details.localFocalPoint;
    final previous = _lastFocal ?? local;
    final delta = local - previous;
    _lastFocal = local;
    _moved += delta.distance;
    final world = _worldAt(local);
    if (world != null) _hover = _snapPoint(world);
    if (details.pointerCount >= 2 || (details.scale - 1).abs() > 0.02) {
      _zoomed = true;
      _dragShape = false;
      _marqueeStart = null;
      _marqueeEnd = null;
    }
    if (details.pointerCount >= 2) {
      if (_gestureScale > 0) {
        _camera.zoomByScale(details.scale / _gestureScale);
      }
      _gestureScale = details.scale;
      _camera.panByScreen(delta, _viewport);
      return;
    }
    if (_selecting && !_zoomed && !_dragShape && _moved >= 8) {
      if (_pressPolygon != null || _pressMark != null) {
        _armDrag();
      } else {
        _marqueeStart ??= _downScreen;
        _marqueeEnd = local;
        setState(() {});
        return;
      }
    }
    if (_marqueeStart != null) {
      _marqueeEnd = local;
      setState(() {});
      return;
    }
    if (_selecting && !_zoomed && !_dragShape) {
      setState(() {});
      return;
    }
    if (_dragShape &&
        _dragBase != null &&
        _dragRules != null &&
        _downWorld != null &&
        world != null) {
      final shift = _gridDelta(_downWorld!, world);
      if (shift == _dragDelta) {
        setState(() {});
        return;
      }
      _dragDelta = shift;
      setState(() {
        _replaceStep(
          _step.copyWith(
            polygons: translatePolygons(_dragBase!, _selected, shift),
            rules: translateRules(_dragRules!, _picked, shift),
          ),
        );
      });
      return;
    }
    _camera.panByScreen(delta, _viewport);
    setState(() {});
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final tapped = !_zoomed && _moved < 8 && _dragDelta == Offset.zero;
    final world = _downWorld;
    final start = _marqueeStart;
    final end = _marqueeEnd;
    _dragShape = false;
    _dragBase = null;
    _dragRules = null;
    _marqueeStart = null;
    _marqueeEnd = null;
    _pressPolygon = null;
    _pressMark = null;
    if (start != null && end != null && !_zoomed) {
      _applyMarquee(start, end);
      setState(() {});
      return;
    }
    if (tapped && world != null) _onTap(world);
  }

  void _applyMarquee(Offset start, Offset end) {
    final screen = Rect.fromPoints(start, end);
    final origin = _camera.planePoint(screen.topLeft, _viewport);
    final far = _camera.planePoint(screen.bottomRight, _viewport);
    if (origin == null || far == null) return;
    final hits = marqueeHits(
      _step,
      Rect.fromPoints(origin, far),
      marqueePick(start, end),
    );
    _selected = hits.polygons;
    _picked = hits.marks;
  }

  RulePick? _hitMark(Offset world) {
    final rules = _step.rules;
    final limit = _step.gridSpacing * 0.75;
    RulePick? best;
    var bestDistance = limit;
    void consider(RuleKind kind, int index, double distance) {
      if (distance > bestDistance) return;
      best = RulePick(kind, index);
      bestDistance = distance;
    }

    for (var i = 0; i < rules.forbidden.length; i++) {
      consider(RuleKind.forbidden, i, (rules.forbidden[i] - world).distance);
    }
    for (var i = 0; i < rules.colors.length; i++) {
      consider(RuleKind.color, i, (rules.colors[i].point - world).distance);
    }
    for (var i = 0; i < rules.numbers.length; i++) {
      consider(RuleKind.number, i, (rules.numbers[i].point - world).distance);
    }
    for (var i = 0; i < rules.docks.length; i++) {
      consider(RuleKind.dock, i, (rules.docks[i] - world).distance);
    }
    for (var i = 0; i < rules.links.length; i++) {
      consider(RuleKind.link, i, (rules.links[i].point - world).distance);
    }
    for (var i = 0; i < rules.arrows.length; i++) {
      consider(
        RuleKind.arrow,
        i,
        _segmentDistance(world, rules.arrows[i].a, rules.arrows[i].b),
      );
    }
    for (var i = 0; i < rules.seams.length; i++) {
      consider(
        RuleKind.seam,
        i,
        _segmentDistance(world, rules.seams[i].a, rules.seams[i].b),
      );
    }
    return best;
  }

  Offset _gridDelta(Offset from, Offset to) {
    final spacing = _step.gridSpacing;
    if (spacing <= 1e-9) return to - from;
    return Offset(
      ((to.dx - from.dx) / spacing).roundToDouble() * spacing,
      ((to.dy - from.dy) / spacing).roundToDouble() * spacing,
    );
  }

  Widget _topBar() {
    final levels = _menuLevels;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(84, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _dropdown(levels),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  key: const Key('puzzle-new'),
                  onPressed: _newPuzzle,
                  child: const Text('New'),
                ),
                TextButton(
                  key: const Key('puzzle-copy'),
                  onPressed: _copyPuzzle,
                  child: const Text('Copy'),
                ),
                TextButton(
                  key: const Key('puzzle-save'),
                  onPressed: _save,
                  child: const Text('Save'),
                ),
                TextButton(
                  key: const Key('puzzle-clear'),
                  onPressed: _clear,
                  child: const Text('Clear'),
                ),
                TextButton(
                  key: const Key('puzzle-play'),
                  onPressed: _play,
                  child: const Text('Play'),
                ),
                if (_selected.length >= 2)
                  TextButton(
                    key: const Key('puzzle-merge'),
                    onPressed: _merge,
                    child: const Text('Merge'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(List<GridBlueprint> levels) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _hud,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('puzzle-level-dropdown'),
            isDense: true,
            dropdownColor: _hud,
            value: _blueprint.id,
            items: [
              for (final level in levels)
                DropdownMenuItem(
                  value: level.id,
                  child: Text(
                    level.name,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null || id == _blueprint.id) return;
              final level = levels.where((item) => item.id == id).firstOrNull;
              if (level == null) return;
              setState(() => _adopt(cloneGridBlueprint(level)));
            },
          ),
        ),
      ),
    );
  }

  Widget _toolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: kGameToolCarouselDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: hudCarouselSubmenuTransition,
          child: KeyedSubtree(key: ValueKey(_tool), child: _subtoolbar()),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: HudToolCarousel<_EditorTool>(
            items: [
              for (final tool in _EditorTool.values)
                HudCarouselItem(
                  value: tool,
                  icon: _toolIcon(tool),
                  label: _toolLabel(tool),
                  fill: _editorToolFill(tool),
                ),
            ],
            selected: _tool,
            onSelect: (tool) => setState(() {
              _tool = tool;
              _mark = _MarkMode.place;
              _edgeAnchor = null;
              if (tool != _EditorTool.links) {
                _linkAnchor = null;
                _linkPair = null;
              }
              if (tool != _EditorTool.shapes) _draft = const [];
            }),
          ),
        ),
      ],
    );
  }

  Widget _subtoolbar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: switch (_tool) {
              _EditorTool.shapes => _shapeBar(),
              _EditorTool.level => _levelBar(),
              _EditorTool.exits => _stepper(
                label: _step.rules.maxExits?.toString() ?? '∞',
                onMinus: () => _nudgeLimit(exits: true, delta: -1),
                onPlus: () => _nudgeLimit(exits: true, delta: 1),
              ),
              _EditorTool.length => _stepper(
                label: _step.rules.maxLength?.toStringAsFixed(0) ?? '∞',
                onMinus: () => _nudgeLimit(exits: false, delta: -1),
                onPlus: () => _nudgeLimit(exits: false, delta: 1),
              ),
              _EditorTool.colors => _colorBar(),
              _EditorTool.arrows => _markBar(flip: true),
              _ => _markBar(flip: false),
            },
          ),
        ),
        const SizedBox(width: 8),
        _helpButton(),
      ],
    );
  }

  Widget _helpButton() {
    return KeyedSubtree(
      key: const Key('puzzle-tool-help'),
      child: HudToolButton(
        icon: Icons.help_outline,
        label: 'Help',
        fill: CraftPalette.warmGrey.fill,
        selected: false,
        iconSize: 20,
        buttonSize: 34,
        onTap: _showHelp,
      ),
    );
  }

  Future<void> _showHelp() {
    final help = _toolHelp(_tool);
    return showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          key: const Key('puzzle-tool-help-dialog'),
          backgroundColor: _hud,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_toolIcon(_tool), color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        help.title,
                        key: const Key('puzzle-tool-help-title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  help.body,
                  key: const Key('puzzle-tool-help-body'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('puzzle-tool-help-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shapeBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_draft.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _draft = _draft.sublist(0, _draft.length - 1);
                }),
                child: const Text('Undo point'),
              ),
              TextButton(
                onPressed: _draft.length >= 3 ? _closeDraft : null,
                child: const Text('Close'),
              ),
            ],
          ),
        HudToolCarousel<_ShapeTool>(
          compact: true,
          items: [
            for (final tool in _ShapeTool.values)
              HudCarouselItem(
                value: tool,
                icon: switch (tool) {
                  _ShapeTool.draw => Icons.timeline,
                  _ShapeTool.select => Icons.near_me,
                  _ShapeTool.delete => Icons.delete_outline,
                },
                label: switch (tool) {
                  _ShapeTool.draw => 'Draw',
                  _ShapeTool.select => 'Select',
                  _ShapeTool.delete => 'Delete',
                },
                fill: _shapeToolFill(tool),
              ),
          ],
          selected: _shape,
          onSelect: (shape) {
            if (shape == _ShapeTool.delete && _selected.isNotEmpty) {
              _removePolygons(_selected);
            }
            setState(() {
              _shape = shape;
              if (shape != _ShapeTool.draw) _draft = const [];
            });
          },
        ),
        if (_selected.length == 1) ...[
          const SizedBox(height: 8),
          _stepper(
            label: 'hits ${_step.collisionOf(_selected.single)?.toString() ?? '—'}',
            onMinus: () => _nudgeCollision(-1),
            onPlus: () => _nudgeCollision(1),
          ),
        ],
      ],
    );
  }

  Widget _levelBar() {
    final permutation = _step.permutation;
    final attachment = _step.attachment;
    final tools = _step.tools;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _flag('Dark', permutation.darkness, (value) {
            _replaceStep(
              _step.copyWith(
                permutation: permutation.copyWith(darkness: value),
              ),
            );
          }),
          _flag('Mirror X', permutation.mirrorX, (value) {
            _replaceStep(
              _step.copyWith(
                permutation: permutation.copyWith(mirrorX: value),
              ),
            );
          }),
          _flag('Mirror Y', permutation.mirrorY, (value) {
            _replaceStep(
              _step.copyWith(
                permutation: permutation.copyWith(mirrorY: value),
              ),
            );
          }),
          _flag('Light', attachment.flashlightThrow != null, (value) {
            _replaceStep(
              _step.copyWith(
                attachment: attachment.copyWith(
                  clearThrow: !value,
                  flashlightThrow: value
                      ? (attachment.flashlightThrow ?? 4)
                      : null,
                ),
              ),
            );
          }),
          _stepper(
            label: attachment.flashlightThrow?.toStringAsFixed(0) ?? '—',
            onMinus: () => _nudgeThrow(-1),
            onPlus: () => _nudgeThrow(1),
          ),
          _stepper(
            label: attachment.thickCut == 0
                ? '—'
                : attachment.thickCut.toStringAsFixed(2),
            onMinus: () => _nudgeThick(-0.25),
            onPlus: () => _nudgeThick(0.25),
          ),
          _flag('Limit', tools != null, (value) {
            _replaceStep(
              _step.copyWith(
                clearTools: !value,
                tools: value
                    ? const ToolFilter({
                        CraftTool.scissors: null,
                        CraftTool.folder: null,
                        CraftTool.holePunch: null,
                      })
                    : null,
              ),
            );
          }),
          if (tools != null) ...[
            for (final tool in CraftTool.values) ...[
              _flag(tool.name, tools.allows(tool), (value) {
                final next = value
                    ? tools.copyWithUse(tool, tools.budget(tool))
                    : tools.without(tool);
                _replaceStep(_step.copyWith(tools: next));
              }),
              if (tools.allows(tool))
                _stepper(
                  label: tools.budget(tool)?.toStringAsFixed(0) ?? '∞',
                  onMinus: () => _nudgeToolUse(tool, -1),
                  onPlus: () => _nudgeToolUse(tool, 1),
                ),
            ],
          ],
          _markBar(flip: false),
        ],
      ),
    );
  }

  void _nudgeToolUse(CraftTool tool, int delta) {
    final tools = _step.tools;
    if (tools == null || !tools.allows(tool)) return;
    final current = tools.budget(tool);
    final double? next;
    if (current == null) {
      next = delta > 0 ? 1 : null;
    } else if (current + delta < 1) {
      next = null;
    } else {
      next = current + delta;
    }
    setState(() {
      _replaceStep(_step.copyWith(tools: tools.copyWithUse(tool, next)));
    });
  }

  void _nudgeThrow(int delta) {
    final current = _step.attachment.flashlightThrow;
    if (current == null && delta < 0) return;
    final next = (current ?? 0) + delta;
    setState(() {
      _replaceStep(
        _step.copyWith(
          attachment: _step.attachment.copyWith(
            clearThrow: next <= 0,
            flashlightThrow: next <= 0 ? null : next,
          ),
        ),
      );
    });
  }

  void _nudgeThick(double delta) {
    final next = (_step.attachment.thickCut + delta).clamp(0, 4).toDouble();
    setState(() {
      _replaceStep(
        _step.copyWith(
          attachment: _step.attachment.copyWith(thickCut: next),
        ),
      );
    });
  }

  Widget _flag(String label, bool on, ValueChanged<bool> write) {
    return TextButton(
      onPressed: () => setState(() => write(!on)),
      child: Text(
        label,
        style: TextStyle(color: on ? Colors.white : Colors.white38),
      ),
    );
  }

  Widget _markBar({required bool flip}) {
    return HudToolCarousel<_MarkMode>(
      compact: true,
      items: [
        HudCarouselItem(
          value: _MarkMode.place,
          icon: Icons.add_location_alt_outlined,
          label: 'Place',
          fill: _markFill(_MarkMode.place),
        ),
        if (flip)
          HudCarouselItem(
            value: _MarkMode.flip,
            icon: Icons.swap_horiz,
            label: 'Flip',
            fill: _markFill(_MarkMode.flip),
          ),
        HudCarouselItem(
          value: _MarkMode.erase,
          icon: Icons.auto_fix_off,
          label: 'Erase',
          fill: _markFill(_MarkMode.erase),
        ),
      ],
      selected: _mark,
      onSelect: (mode) => setState(() {
        _mark = mode;
        _edgeAnchor = null;
      }),
    );
  }

  Widget _colorBar() {
    return HudToolCarousel<int>(
      compact: true,
      items: [
        for (var i = 0; i < kRulePalette.length; i++)
          HudCarouselItem(
            value: i,
            icon: Icons.circle,
            label: kRuleColorNames[i],
            fill: kRulePalette[i].withValues(alpha: 0.6),
          ),
        HudCarouselItem(
          value: -1,
          icon: Icons.auto_fix_off,
          label: 'Erase',
          fill: _markFill(_MarkMode.erase),
        ),
      ],
      selected: _mark == _MarkMode.erase ? -1 : _color,
      onSelect: (value) => setState(() {
        if (value < 0) {
          _mark = _MarkMode.erase;
          return;
        }
        _mark = _MarkMode.place;
        _color = value;
      }),
    );
  }

  Widget _stepper({
    required String label,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove, color: Colors.white),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

double _segmentDistance(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (point - a).distance;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final closest = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
  return (point - closest).distance;
}

IconData _toolIcon(_EditorTool tool) {
  return switch (tool) {
    _EditorTool.shapes => Icons.pentagon_outlined,
    _EditorTool.level => Icons.tune,
    _EditorTool.exits => Icons.logout,
    _EditorTool.length => Icons.straighten,
    _EditorTool.forbid => Icons.close,
    _EditorTool.colors => Icons.palette_outlined,
    _EditorTool.numbers => Icons.looks_one_outlined,
    _EditorTool.arrows => Icons.arrow_right_alt,
    _EditorTool.docks => Icons.diamond_outlined,
    _EditorTool.links => Icons.link,
    _EditorTool.seams => Icons.content_cut,
  };
}

String _toolLabel(_EditorTool tool) {
  return switch (tool) {
    _EditorTool.shapes => 'Shapes',
    _EditorTool.level => 'Level',
    _EditorTool.exits => 'Exits',
    _EditorTool.length => 'Length',
    _EditorTool.forbid => 'Forbid',
    _EditorTool.colors => 'Color gems',
    _EditorTool.numbers => 'Number gems',
    _EditorTool.arrows => 'Arrows',
    _EditorTool.docks => 'Docks',
    _EditorTool.links => 'Links',
    _EditorTool.seams => 'Seams',
  };
}

class _ToolHelp {
  const _ToolHelp(this.title, this.body);

  final String title;
  final String body;
}

_ToolHelp _toolHelp(_EditorTool tool) {
  final title = _toolLabel(tool);
  final body = switch (tool) {
    _EditorTool.shapes =>
      'Tap grid points to draw. A line can stay open: tap the last point a second time to finish it. Tap the first point again, or Close, to join a ring. Select drags a rectangle: left to right keeps what sits fully inside, and right to left also takes what the rectangle crosses. With one blueprint piece selected, tap an edge to pencil it in. The hits counter is how many times a tool may touch that piece. Its paper can be cut free only once hits reaches 0; cutting it free sooner fails the level. Drag any selected item to move the whole selection. Delete removes the blueprint piece you tap, or the pieces already selected.',
    _EditorTool.level =>
      'Level permutations and tool attachments. Dark covers the sheet except the scissor flashlight. Mirror X and Mirror Y reflect a committed cut across the paper center. Throw is the flashlight reach in grid units. Thick is the scissor half-width. Limit tools lists which tools play may use, and a use count. No-fold: place two corners of a region that cannot be folded. Erase removes the nearest no-fold zone.',
    _EditorTool.exits =>
      'How many times the blade may leave the paper. A cut that ends on the paper edge spends one exit. The counter shows ∞ when there is no limit. Minus from 1 clears the limit, and plus from unlimited starts it at 1.',
    _EditorTool.length =>
      'How far the blade may travel, measured in grid cells. A cut that would pass the budget is refused. The counter shows ∞ when there is no limit. Minus from 1 clears the limit, and plus from unlimited starts it at 1.',
    _EditorTool.forbid =>
      'An X on a grid point. The blade cannot travel through that point. Place drops an X, and Erase removes the nearest one.',
    _EditorTool.colors =>
      'Color gems are entry points on the paper. A new cut starts only at a gem, and the blade can come back onto the paper only at one. The gem disappears when the blade takes it. The first color opens that group. Taking another color before the group is finished fails the level: that gem flashes red, then the level restarts. Every gem must be taken before the level is cleared. Tap a swatch to place that color. Tap an existing gem to recolor it. Erase removes the nearest gem.',
    _EditorTool.numbers =>
      'Number gems are entry points, taken in order starting at 1. A new cut starts only at a gem, and the gem disappears once the blade takes it. Taking a number out of order fails the level: that gem flashes red, then the level restarts. Every gem must be taken before the level is cleared. Each new gem takes the next unused number.',
    _EditorTool.arrows =>
      'A one-way stretch of the cut. The blade may travel from the tail to the head, and the other direction is refused. Place two points to draw the arrow. Flip reverses the nearest arrow. Erase removes it.',
    _EditorTool.docks =>
      'Diamonds where the blade is allowed to leave the paper. When any docks are placed, a cut may leave only at a dock. Place drops a diamond, and Erase removes the nearest one.',
    _EditorTool.links =>
      'Paired circles that share a number. After one of a pair is collected, its partner must be collected before the blade leaves the paper. The first tap starts a pair, and the second tap places the partner.',
    _EditorTool.seams =>
      'Dashed edges the puzzle wants cut. The blade may cross a seam. Crossing one marks it cut, and the status line tracks how many remain. Place two points to draw a seam, and Erase removes the nearest one.',
  };
  return _ToolHelp(title, body);
}
