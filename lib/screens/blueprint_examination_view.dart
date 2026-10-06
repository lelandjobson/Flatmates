import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/blueprint.dart';
import '../gridcraft/blueprint_examination_painter.dart';
import '../gridcraft/dimension_measure.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/twin_ls.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../ui/dimension_chrome.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

/// Clears the dev back button so the left ruler does not run through it.
const double _kBackClearance = 44;

/// Closest and farthest half-heights, in plane units. The shared camera floor
/// is coarser than a blueprint cell, so examination zooms on its own.
const double _kZoomMinHalfHeight = 0.25;
const double _kZoomMaxHalfHeight = 800;

class _GrabDrag {
  const _GrabDrag(this.axis, this.index);

  final DimensionAxis axis;
  final int index;
}

/// One blueprint step the examination menu can open.
class _ExamChoice {
  const _ExamChoice({required this.blueprint, required this.stepIndex});

  final GridBlueprint blueprint;
  final int stepIndex;

  String get key => '${blueprint.id}/$stepIndex';

  String get label => blueprint.steps[stepIndex].label;
}

/// Blueprint outlines, a grid on the pieces, and two dimension rulers.
class BlueprintExaminationView extends StatefulWidget {
  const BlueprintExaminationView({super.key, this.blueprint, this.levels});

  final GridBlueprint? blueprint;

  /// Where saved blueprints are read. Defaults to the app's level store.
  final LevelStore? levels;

  @override
  State<BlueprintExaminationView> createState() =>
      BlueprintExaminationViewState();
}

class BlueprintExaminationViewState extends State<BlueprintExaminationView> {
  final PapercutCamera _camera = PapercutCamera();
  final DimensionRuler _horizontal = DimensionRuler(DimensionAxis.horizontal);
  final DimensionRuler _vertical = DimensionRuler(DimensionAxis.vertical);
  final List<LockedDimension> _locked = [];
  final Map<int, Offset> _pointers = {};

  late GridBlueprint _blueprint;
  late List<_ExamChoice> _choices;
  late String _choiceKey;

  Size _viewport = Size.zero;
  DimensionChrome? _chrome;
  int _stepIndex = 0;
  bool _framed = false;
  bool _multi = false;
  bool _moved = false;
  Offset? _down;
  double? _span;
  Offset? _pinchCentroid;
  _GrabDrag? _drag;

  DimensionRuler get horizontalRuler => _horizontal;

  DimensionRuler get verticalRuler => _vertical;

  List<LockedDimension> get lockedDimensions => List.unmodifiable(_locked);

  DimensionChrome? get dimensionChrome => _chrome;

  Offset? projectPlane(Offset world) => _project(world);

  GridStep? get _step {
    if (_blueprint.steps.isEmpty) return null;
    return _blueprint.steps[_stepIndex.clamp(0, _blueprint.steps.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    final opened = widget.blueprint ?? twinLsBlueprint();
    _blueprint = opened;
    _choices = _openingChoices(opened);
    _choiceKey = '${opened.id}/$_stepIndex';
    _camera.addListener(_onCamera);
    _loadChoices();
  }

  @override
  void dispose() {
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    if (!mounted) return;
    if (_drag == null) _follow();
    setState(() {});
  }

  void _frame() {
    final step = _step;
    if (step == null || _viewport.width < 2) return;
    _camera.setRoll(0);
    final paper = step.paper;
    final span = math.max(paper.width, paper.height);
    _camera.frameSheet(
      _viewport,
      sheetMm: math.max(span, step.gridSpacing),
      center: paper.center,
    );
  }

  void _selectChoice(String? key) {
    if (key == null || key == _choiceKey) return;
    final choice = _choices.where((item) => item.key == key).firstOrNull;
    if (choice == null) return;
    setState(() {
      _choiceKey = key;
      _blueprint = choice.blueprint;
      _stepIndex = choice.stepIndex;
      _framed = false;
      _horizontal.reset();
      _vertical.reset();
      _locked.clear();
      _drag = null;
    });
  }

  List<_ExamChoice> _openingChoices(GridBlueprint opened) {
    final choices = _choicesFor(twinLsBlueprint());
    final seen = {for (final choice in choices) choice.key};
    for (final choice in _choicesFor(opened)) {
      if (seen.add(choice.key)) choices.add(choice);
    }
    return choices;
  }

  List<_ExamChoice> _choicesFor(GridBlueprint blueprint) {
    return [
      for (var i = 0; i < blueprint.steps.length; i++)
        _ExamChoice(blueprint: blueprint, stepIndex: i),
    ];
  }

  Future<void> _loadChoices() async {
    final store = widget.levels ?? LevelStore(bundle: rootBundle);
    final collections = await store.loadCollections();
    final side = [
      for (final collection in collections)
        if (collection.id == 'side-table') ...collection.puzzles,
    ];
    if (!mounted) return;
    final choices = _choicesFor(twinLsBlueprint());
    final seen = {for (final choice in choices) choice.key};
    for (final puzzle in side) {
      for (final choice in _choicesFor(puzzle)) {
        if (seen.add(choice.key)) choices.add(choice);
      }
    }
    final opened = widget.blueprint;
    if (opened != null) {
      for (final choice in _choicesFor(opened)) {
        if (seen.add(choice.key)) choices.add(choice);
      }
    }
    setState(() {
      _choices = choices;
      if (!_choices.any((choice) => choice.key == _choiceKey)) {
        final first = _choices.first;
        _choiceKey = first.key;
        _blueprint = first.blueprint;
        _stepIndex = first.stepIndex;
        _framed = false;
      }
    });
  }

  void _zoom(double scale) {
    if (scale <= 0 || (scale - 1).abs() < 1e-6) return;
    final next = (_camera.framedHalfHeightMm / scale).clamp(
      _kZoomMinHalfHeight,
      _kZoomMaxHalfHeight,
    );
    if ((next - _camera.framedHalfHeightMm).abs() < 1e-4) return;
    _camera.moveLook(lookAt: _camera.lookAt, halfHeight: next);
  }

  void _pan(Offset delta) {
    _camera.panByScreen(delta, _viewport);
  }

  Offset? _project(Offset world) {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.camera.projectToScreen(
      Vector3(world.dx, world.dy, 0),
      _viewport,
    );
  }

  List<ProjectedVertex> _vertices() {
    final step = _step;
    if (step == null) return const [];
    final out = <ProjectedVertex>[];
    for (final world in step.vertices) {
      final screen = _project(world);
      if (screen == null) continue;
      out.add(ProjectedVertex(world: world, screen: screen));
    }
    return out;
  }

  double? _screenAlong(DimensionAxis axis, double world) {
    final cross = axis == DimensionAxis.horizontal
        ? _camera.lookAt.dy
        : _camera.lookAt.dx;
    final point = axis == DimensionAxis.horizontal
        ? Offset(world, cross)
        : Offset(cross, world);
    final screen = _project(point);
    if (screen == null) return null;
    return axis == DimensionAxis.horizontal ? screen.dx : screen.dy;
  }

  void _follow() {
    final chrome = _chrome;
    if (chrome == null || _viewport.width < 2) return;
    final vertices = _vertices();
    final view = Offset.zero & _viewport;
    _horizontal.followCamera(
      vertices: vertices,
      viewport: view,
      track: chrome.horizontal,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.horizontal, world),
    );
    _vertical.followCamera(
      vertices: vertices,
      viewport: view,
      track: chrome.vertical,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.vertical, world),
    );
  }

  void _moveDrag(_GrabDrag drag, Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    final horizontal = drag.axis == DimensionAxis.horizontal;
    final ruler = horizontal ? _horizontal : _vertical;
    final track = horizontal ? chrome.horizontal : chrome.vertical;
    ruler.moveGrab(
      index: drag.index,
      screenAlong: horizontal ? screen.dx : screen.dy,
      track: track,
      vertices: _vertices(),
    );
  }

  String _label(DimensionRuler ruler) {
    return dimensionReadout(ruler, _step?.gridSpacing ?? 1);
  }

  List<SnapGuide> _guides() {
    final out = <SnapGuide>[];
    void add(DimensionRuler ruler) {
      for (final grab in ruler.grabs) {
        final world = grab.world;
        if (world == null) continue;
        final duplicate = out.any(
          (guide) =>
              guide.axis == ruler.axis &&
              (guide.world - world).abs() <= kDimensionColinearEpsilon,
        );
        if (duplicate) continue;
        out.add(SnapGuide(axis: ruler.axis, world: world));
      }
    }

    add(_horizontal);
    add(_vertical);
    return out;
  }

  double? _crossWorld(DimensionTrack track) {
    if (_viewport.width < 2) return null;
    final world = _camera.planePoint(track.at(0.5), _viewport);
    if (world == null) return null;
    return track.axis == DimensionAxis.horizontal ? world.dy : world.dx;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _multi = true;
      _moved = true;
      _drag = null;
      _span = null;
      _pinchCentroid = null;
      setState(() {});
      return;
    }
    _moved = false;
    _down = event.localPosition;
    final chrome = _chrome;
    if (chrome != null) {
      final horizontal = hitGrab(
        chrome.horizontal,
        _horizontal,
        event.localPosition,
      );
      if (horizontal != null) {
        _drag = _GrabDrag(DimensionAxis.horizontal, horizontal);
        setState(() {});
        return;
      }
      final vertical = hitGrab(chrome.vertical, _vertical, event.localPosition);
      if (vertical != null) {
        _drag = _GrabDrag(DimensionAxis.vertical, vertical);
        setState(() {});
        return;
      }
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer] ?? event.localPosition;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _twoFinger();
      setState(() {});
      return;
    }
    if (_multi) return;
    final drag = _drag;
    if (drag != null) {
      _moveDrag(drag, event.localPosition);
      final down = _down;
      if (down != null && (event.localPosition - down).distance > 4) {
        _moved = true;
      }
      setState(() {});
      return;
    }
    final down = _down;
    if (down == null) return;
    if (!_moved) {
      if ((event.localPosition - down).distance <= 18) return;
      _moved = true;
      _pan(event.localPosition - down);
    } else {
      _pan(event.localPosition - previous);
    }
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) {
      _span = null;
      _pinchCentroid = null;
      setState(() {});
      return;
    }
    final multi = _multi;
    final drag = _drag;
    final moved = _moved;
    final down = _down;
    _multi = false;
    _drag = null;
    _moved = false;
    _span = null;
    _pinchCentroid = null;
    _down = null;
    if (multi) {
      _follow();
      setState(() {});
      return;
    }
    if (drag != null) {
      if (!moved && down != null) _lockArmedTap(drag, down);
      _follow();
      setState(() {});
      return;
    }
    if (!moved && down != null) _tap(down);
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    _drag = null;
    _multi = false;
    _moved = false;
    _span = null;
    _pinchCentroid = null;
    _down = null;
    _follow();
    setState(() {});
  }

  void _twoFinger() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.toList();
    final centroid = (points[0] + points[1]) / 2;
    final span = (points[0] - points[1]).distance;
    final previousCentroid = _pinchCentroid;
    final previousSpan = _span;
    _pinchCentroid = centroid;
    _span = span;
    if (previousCentroid != null) _pan(centroid - previousCentroid);
    if (previousSpan != null && previousSpan > 12 && span > 12) {
      _zoom(span / previousSpan);
    }
  }

  void _tap(Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    if (_ownsTrack(chrome.horizontal, screen)) {
      _lockTrack(chrome.horizontal, _horizontal, screen);
      return;
    }
    if (_ownsTrack(chrome.vertical, screen)) {
      _lockTrack(chrome.vertical, _vertical, screen);
      return;
    }
    final index = _hitLocked(screen);
    if (index != null) _locked.removeAt(index);
  }

  bool _ownsTrack(DimensionTrack track, Offset screen) {
    final dist = spanDistance(track.start, track.end, screen);
    return dist != null && dist <= kDimensionSpanSlop;
  }

  void _lockArmedTap(_GrabDrag drag, Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    final horizontal = drag.axis == DimensionAxis.horizontal;
    _lockTrack(
      horizontal ? chrome.horizontal : chrome.vertical,
      horizontal ? _horizontal : _vertical,
      screen,
    );
  }

  void _lockTrack(DimensionTrack track, DimensionRuler ruler, Offset screen) {
    final a = track.at(ruler.grabs[0].fraction);
    final b = track.at(ruler.grabs[1].fraction);
    if (!tapHitsMeasuredSpan(a, b, screen)) return;
    final cross = _crossWorld(track);
    if (cross == null) return;
    final placed = lockDimension(ruler, cross);
    if (placed != null) _locked.add(placed);
  }

  int? _hitLocked(Offset tap) {
    final spans = <({Offset a, Offset b})>[];
    final indexes = <int>[];
    for (var i = 0; i < _locked.length; i++) {
      final ends = dimensionEndpoints(_locked[i]);
      final a = _project(ends.$1);
      final b = _project(ends.$2);
      if (a == null || b == null) continue;
      spans.add((a: a, b: b));
      indexes.add(i);
    }
    final hit = nearestSpan(spans, tap);
    if (hit == null) return null;
    return indexes[hit];
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: [const FmDevBackButton(), _stepMenu()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final safe = fmSafeInsets(context, minimum: kFmScreenInset);
          final chrome = DimensionChrome.layout(
            viewport: _viewport,
            safe: safe.copyWith(top: safe.top + _kBackClearance),
          );
          _chrome = chrome;
          if (!_framed && _viewport.width > 2 && _step != null) {
            _framed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _frame();
            });
          }
          final step = _step;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent ||
                        event.scrollDelta.dy == 0) {
                      return;
                    }
                    _zoom(math.exp(-event.scrollDelta.dy * 0.002));
                  },
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: AnimatedBuilder(
                    animation: _camera,
                    builder: (context, _) {
                      return CustomPaint(
                        key: const Key('blueprint-examination-canvas'),
                        painter: step == null
                            ? null
                            : BlueprintExaminationPainter(
                                camera: _camera,
                                step: step,
                                locked: _locked,
                                guides: _guides(),
                              ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DimensionChromePainter(
                      chrome: chrome,
                      horizontal: _horizontal,
                      vertical: _vertical,
                      horizontalLabel: _label(_horizontal),
                      verticalLabel: _label(_vertical),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stepMenu() {
    return FmSafePositioned(
      top: 12,
      right: 12,
      minimum: kFmScreenInset,
      child: SizedBox(
        width: 220,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('blueprint-examination-steps'),
                isExpanded: true,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A1A),
                value: _choiceKey,
                items: [
                  for (final choice in _choices)
                    DropdownMenuItem(
                      value: choice.key,
                      child: Text(
                        choice.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
                onChanged: _selectChoice,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
