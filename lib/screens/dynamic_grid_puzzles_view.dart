import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../gridcraft/blueprint.dart';
import '../gridcraft/dynamic_grid.dart';
import '../gridcraft/dynamic_grid_painter.dart';
import '../gridcraft/dynamic_l.dart';
import '../gridcraft/dynamic_stroke.dart';
import '../gridcraft/fold.dart';
import '../gridcraft/painter.dart';
import '../gridcraft/rules.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import '../ui/craft_palette.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/game_tool_carousel.dart';

enum _Surface { grid, blueprint }

enum _PlayTool { scissors, folder }

enum _GridTool { tangram, select, tessellation }

/// Experimental play view. The finger draws along a dynamic grid, and a
/// left-hand rail switches between editing that grid and cutting or folding.
class DynamicGridPuzzlesView extends StatefulWidget {
  const DynamicGridPuzzlesView({super.key});

  @override
  State<DynamicGridPuzzlesView> createState() => _DynamicGridPuzzlesViewState();
}

class _DynamicGridPuzzlesViewState extends State<DynamicGridPuzzlesView>
    with TickerProviderStateMixin {
  final PapercutCamera _camera = PapercutCamera();
  final Map<int, Offset> _pointers = {};
  late final AnimationController _pulse;
  late final AnimationController _failAnim;
  late final GridBlueprint _blueprint;
  late GridStep _step;
  late PapercutSheet _sheet;
  late DynamicStrokeSession _session;

  final List<TangramPiece> _pieces = [];
  DynamicTessellation _tessellation = DynamicTessellation.bbox;
  _Surface _surface = _Surface.blueprint;
  _PlayTool _playTool = _PlayTool.scissors;
  _GridTool _gridTool = _GridTool.tangram;
  TangramKind _shape = TangramKind.square;

  Size _viewport = Size.zero;
  bool _framed = false;
  bool _panning = false;
  bool _multiTouch = false;
  bool _won = false;
  int _nextPiece = 1;
  String? _selectedId;
  Offset? _downScreen;
  Offset? _grabWorld;
  Offset? _grabAnchor;
  FailureCue? _failure;
  DynamicStrokeAssessment? _assessment;
  PapercutSheet? _foldPreview;
  List<List<Offset>> _flashRings = const [];

  @override
  void initState() {
    super.initState();
    _blueprint = dynamicLBlueprint();
    _step = _blueprint.steps.first;
    _sheet = dynamicPaperSheet(_step);
    _session = DynamicStrokeSession(
      graph: DynamicGridGraph(vertices: const [], links: const []),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _failAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..addStatusListener(_onFailStatus);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _failAnim.dispose();
    _camera.dispose();
    super.dispose();
  }

  bool get _failing => _failAnim.isAnimating;

  void _onFailStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _failure = null;
      _sheet = dynamicPaperSheet(_step);
      _foldPreview = null;
      _flashRings = const [];
      _assessment = null;
    });
  }

  void _syncGraph() {
    _session.graph = buildDynamicGrid(
      pieces: _pieces,
      tessellation: _tessellation,
      cover: _cover(),
    );
  }

  /// Period shown while a tessellation stroke is still down.
  DynamicTessellation get _shownTessellation {
    if (_surface == _Surface.grid &&
        _gridTool == _GridTool.tessellation &&
        _session.active &&
        _session.points.length >= 2) {
      final delta = _session.points.last - _session.points.first;
      if (delta.distance > 1e-3) return _tessellation.withDrawn(delta);
    }
    return _tessellation;
  }

  Rect _cover() {
    final view = _visible().inflate(2);
    final paper = _step.paper.inflate(2);
    return Rect.fromLTRB(
      math.min(view.left, paper.left),
      math.min(view.top, paper.top),
      math.max(view.right, paper.right),
      math.max(view.bottom, paper.bottom),
    );
  }

  Rect _visible() {
    final halfH = _camera.framedHalfHeightMm;
    final aspect = _viewport.height < 2
        ? 1.0
        : _viewport.width / _viewport.height;
    final halfW = halfH * aspect;
    return Rect.fromCenter(
      center: _camera.lookAt,
      width: halfW * 2,
      height: halfH * 2,
    );
  }

  void _frame() {
    if (_viewport.width < 2 || _viewport.height < 2) return;
    final paper = _step.paper;
    final fit = _camera.halfHeightForSheet(
      _viewport,
      sheetMm: math.max(paper.width, paper.height),
    );
    // Half the previous opening size: the 12-cell cap filled the screen.
    final opened = math.min(fit, _maxHalfHeight(_viewport));
    _camera.moveLook(lookAt: paper.center, halfHeight: opened * 2);
    _syncGraph();
  }

  double _maxHalfHeight(Size viewport) {
    if (viewport.width < 2 || viewport.height < 2) return 6;
    final aspect = viewport.width / viewport.height;
    return (kDynamicMaxCellsAcross / 2) / aspect;
  }

  /// Pinch and scroll zoom. The look-at point stays on the blueprint.
  ///
  /// [scale] > 1 zooms in, matching [PapercutCamera.zoomByScale]. The camera's
  /// own clamp is in millimeters, so this view sets the distance directly.
  void _zoom(double scale) {
    if (scale <= 0 || (scale - 1).abs() < 1e-6) return;
    final next = (_camera.framedHalfHeightMm / scale).clamp(1.5, 800.0);
    if ((next - _camera.framedHalfHeightMm).abs() < 1e-4) return;
    _camera.moveLook(lookAt: _camera.lookAt, halfHeight: next);
  }

  Offset? _world(Offset screen) => _camera.planePoint(screen, _viewport);

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _session.cancel();
      _assessment = null;
      _foldPreview = null;
      _flashRings = const [];
      _panning = true;
      _multiTouch = true;
      _panSpan = null;
      setState(() {});
      return;
    }
    if (_failing || _won) return;
    _panning = false;
    _downScreen = event.localPosition;
    final world = _world(event.localPosition);
    if (world == null) return;
    if (_surface == _Surface.blueprint) {
      _syncGraph();
      _session.begin(world, _sheet);
      _assessment = null;
      _foldPreview = null;
      _flashRings = const [];
    } else if (_gridTool == _GridTool.select) {
      _selectDown(world);
    } else if (_gridTool == _GridTool.tessellation) {
      _syncGraph();
      _session.begin(world, _sheet, rejectInsidePaper: false);
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _pinchZoom();
      return;
    }
    if (_multiTouch || _panning || _failing || _won) return;
    final world = _world(event.localPosition);
    if (world == null) return;
    if (_surface == _Surface.blueprint && _session.active) {
      _syncGraph();
      _session.move(world);
      _refreshPreview();
      setState(() {});
      return;
    }
    if (_surface == _Surface.grid &&
        _gridTool == _GridTool.tessellation &&
        _session.active) {
      _session.move(world);
      setState(() {});
      return;
    }
    if (_surface == _Surface.grid &&
        _gridTool == _GridTool.select &&
        _grabAnchor != null &&
        _grabWorld != null) {
      _dragSelection(world);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final position = _pointers[event.pointer] ?? event.localPosition;
    final alone = _pointers.length == 1;
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) {
      if (_pointers.length == 1) _panning = false;
      setState(() {});
      return;
    }
    final wasPan = _panning || _multiTouch;
    _panning = false;
    _multiTouch = false;
    _panSpan = null;
    if (!alone || wasPan || _failing || _won) {
      _session.cancel();
      _assessment = null;
      _foldPreview = null;
      _flashRings = const [];
      _grabAnchor = null;
      setState(() {});
      return;
    }
    if (_surface == _Surface.blueprint) {
      _releaseStroke();
    } else if (_gridTool == _GridTool.tessellation) {
      _commitTessellation();
    } else if (_gridTool == _GridTool.tangram) {
      final down = _downScreen;
      if (down != null && (down - position).distance < 18) {
        final world = _world(position);
        if (world != null) _place(world);
      }
    }
    _grabAnchor = null;
    _grabWorld = null;
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _panning = false;
      _session.cancel();
      _assessment = null;
      _foldPreview = null;
      _flashRings = const [];
    }
    setState(() {});
  }

  void _pinchZoom() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.toList();
    final span = (points[0] - points[1]).distance;
    final previousSpan = _panSpan;
    _panSpan = span;
    if (previousSpan != null && previousSpan > 12 && span > 12) {
      _zoom(span / previousSpan);
    }
    _syncGraph();
    setState(() {});
  }

  double? _panSpan;

  void _selectDown(Offset world) {
    final lattice = tangramLattice(_pieces, tessellation: _tessellation);
    TangramPiece? hit;
    if (lattice != null) {
      for (final piece in _pieces.reversed) {
        if (hitsTangram(piece, world, lattice)) {
          hit = piece;
          break;
        }
      }
    }
    _selectedId = hit?.id;
    _grabWorld = hit == null ? null : world;
    _grabAnchor = hit?.anchor;
  }

  void _dragSelection(Offset world) {
    final id = _selectedId;
    final grabWorld = _grabWorld;
    final grabAnchor = _grabAnchor;
    if (id == null || grabWorld == null || grabAnchor == null) return;
    final delta = world - grabWorld;
    final anchor = Offset(
      (grabAnchor.dx + delta.dx).roundToDouble(),
      (grabAnchor.dy + delta.dy).roundToDouble(),
    );
    final index = _pieces.indexWhere((piece) => piece.id == id);
    if (index < 0) return;
    setState(() {
      _pieces[index] = _pieces[index].copyWith(anchor: anchor);
      _syncGraph();
    });
  }

  void _place(Offset world) {
    final anchor = Offset(world.dx.roundToDouble(), world.dy.roundToDouble());
    _pieces.add(
      TangramPiece(
        id: 'tangram-$_nextPiece',
        kind: _shape,
        anchor: anchor,
        colorIndex: _pieces.length % kTangramPalette.length,
      ),
    );
    _selectedId = _pieces.last.id;
    _nextPiece++;
    _syncGraph();
  }

  void _deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _pieces.removeWhere((piece) => piece.id == id);
      _selectedId = null;
      _syncGraph();
    });
  }

  void _commitTessellation() {
    final points = List<Offset>.of(_session.points);
    _session.cancel();
    if (points.length < 2) return;
    final delta = points.last - points.first;
    if (delta.distance < 1e-3) return;
    _tessellation = _tessellation.withDrawn(delta);
    _syncGraph();
  }

  void _resetTessellation() {
    _session.cancel();
    _tessellation = DynamicTessellation.bbox;
    _syncGraph();
  }

  void _turnSelected() {
    final id = _selectedId;
    if (id == null) return;
    final index = _pieces.indexWhere((piece) => piece.id == id);
    if (index < 0) return;
    final piece = _pieces[index];
    setState(() {
      _pieces[index] = piece.copyWith(turns: (piece.turns + 1) % 4);
      _syncGraph();
    });
  }

  void _refreshPreview() {
    _foldPreview = null;
    _flashRings = const [];
    if (!_session.active || _session.points.length < 2) {
      _assessment = null;
      return;
    }
    final assessment = assessDynamicStroke(_session.points, _sheet, _step);
    _assessment = assessment;
    if (!assessment.complete || assessment.illegal) return;
    if (_playTool == _PlayTool.scissors) {
      final preview = applyPapercutCut(_sheet, _session.points);
      if (preview == null) return;
      final before = {for (final piece in _sheet.pieces) piece.id};
      _flashRings = [
        for (final piece in preview.pieces)
          if (!before.contains(piece.id)) piece.vertices,
      ];
      return;
    }
    final span = assessment.fold;
    if (span == null) return;
    _foldPreview = foldSheet(
      sheet: _sheet,
      spanA: span.a,
      spanB: span.b,
      flapPoint: span.flap,
      facing: FoldFacing.toward,
      blueprintPieces: _step.closedPolygons,
      pieceId: span.pieceId,
    );
  }

  void _releaseStroke() {
    final points = List<Offset>.of(_session.points);
    _session.cancel();
    _foldPreview = null;
    _flashRings = const [];
    _assessment = null;
    if (points.length < 2) return;
    final assessment = assessDynamicStroke(points, _sheet, _step);
    if (!assessment.complete) return;
    if (assessment.illegal) {
      _failure = FailureCue(FailureKind.piece, assessment.piercedIndex ?? 0);
      _failAnim.forward(from: 0);
      return;
    }
    final next = _playTool == _PlayTool.scissors
        ? commitDynamicCut(sheet: _sheet, points: points, step: _step)
        : commitDynamicFold(sheet: _sheet, points: points, step: _step);
    if (next == null) return;
    _sheet = next;
    if (piecesLiberated(_step, liberatedPieceIndexes(_step, _sheet))) {
      _won = true;
    }
  }

  void _setSurface(_Surface surface) {
    if (_surface == surface) return;
    setState(() {
      _session.cancel();
      _assessment = null;
      _foldPreview = null;
      _flashRings = const [];
      _surface = surface;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (!_framed && _viewport.width > 2) {
            _framed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _frame();
              setState(() {});
            });
          }
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
                    _syncGraph();
                    setState(() {});
                  },
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulse, _failAnim, _camera]),
                    builder: (context, _) {
                      final shown = _shownTessellation;
                      final graph = buildDynamicGrid(
                        pieces: _pieces,
                        tessellation: shown,
                        cover: _cover(),
                      );
                      final showStroke =
                          _session.active && _session.points.isNotEmpty;
                      final illegal = _assessment?.illegal ?? false;
                      return CustomPaint(
                        key: const Key('dynamic-grid-canvas'),
                        foregroundPainter: DynamicGridPainter(
                          camera: _camera,
                          lattice: tangramLattice(_pieces, tessellation: shown),
                          pieces: _pieces,
                          graph: graph,
                          view: _visible(),
                          editing: _surface == _Surface.grid,
                          selectedId: _surface == _Surface.grid
                              ? _selectedId
                              : null,
                          stroke: showStroke ? _session.points : const [],
                          flashRings: _flashRings,
                          blueprint: _step.polygons,
                          failingBlueprint: _failure?.kind == FailureKind.piece
                              ? _failure!.index
                              : null,
                          failureFlash: _failAnim.value,
                          illegal: illegal,
                          pulse: _pulse.value,
                          showCursor: showStroke,
                        ),
                        painter: GridPuzzlePainter(
                          camera: _camera,
                          step: _step,
                          sheet: _foldPreview ?? _sheet,
                          march: null,
                          flash: 0,
                          rulerX: null,
                          showRuler: false,
                          selected: const {},
                          drawGrid: false,
                          drawPaper: false,
                          drawBlueprint: false,
                          failure: _failure,
                          failureFlash: _failAnim.value,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
              FmSafePositioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(child: _modeRail()),
              ),
              FmSafePositioned(left: 0, right: 0, bottom: 8, child: _toolbar()),
              if (_won)
                const Center(
                  child: Text(
                    'victory',
                    key: Key('dynamic-grid-victory'),
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _modeRail() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HudToolButton(
          key: const Key('dynamic-mode-grid'),
          icon: Icons.grid_on,
          label: 'Grid',
          fill: CraftPalette.cerulean.fill,
          selected: _surface == _Surface.grid,
          onTap: () => _setSurface(_Surface.grid),
        ),
        const SizedBox(height: 10),
        HudToolButton(
          key: const Key('dynamic-mode-blueprint'),
          icon: Icons.crop_square,
          label: 'Blueprint',
          fill: CraftPalette.goldenTan.fill,
          selected: _surface == _Surface.blueprint,
          onTap: () => _setSurface(_Surface.blueprint),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_surface == _Surface.grid) _gridSubmenu(),
        if (_surface == _Surface.grid)
          HudToolCarousel<_GridTool>(
            items: [
              HudCarouselItem(
                value: _GridTool.tangram,
                icon: Icons.extension,
                label: 'Tangram',
                fill: CraftPalette.seaGreen.fill,
              ),
              HudCarouselItem(
                value: _GridTool.select,
                icon: Icons.near_me,
                label: 'Select',
                fill: CraftPalette.kentuckyBlue.fill,
              ),
              HudCarouselItem(
                value: _GridTool.tessellation,
                icon: Icons.copy,
                label: 'Tessellation',
                fill: CraftPalette.fuschia.fill,
              ),
            ],
            selected: _gridTool,
            onSelect: (tool) => setState(() {
              _session.cancel();
              _gridTool = tool;
            }),
          )
        else
          HudToolCarousel<_PlayTool>(
            items: [
              HudCarouselItem(
                value: _PlayTool.scissors,
                icon: Icons.content_cut,
                label: 'Scissors',
                fill: CraftPalette.scarlet.fill,
              ),
              HudCarouselItem(
                value: _PlayTool.folder,
                icon: Icons.flip,
                label: 'Folder',
                fill: CraftPalette.carmel.fill,
              ),
            ],
            selected: _playTool,
            onSelect: (tool) => setState(() {
              _session.cancel();
              _assessment = null;
              _foldPreview = null;
              _flashRings = const [];
              _playTool = tool;
            }),
          ),
      ],
    );
  }

  Widget _gridSubmenu() {
    if (_gridTool == _GridTool.tessellation) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HudToolButton(
              icon: Icons.restart_alt,
              label: 'Reset',
              fill: CraftPalette.raspberry.fill,
              selected: false,
              enabled: !_tessellation.isBbox,
              onTap: () => setState(_resetTessellation),
            ),
          ],
        ),
      );
    }
    if (_gridTool == _GridTool.select) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HudToolButton(
              icon: Icons.rotate_right,
              label: 'Turn',
              fill: CraftPalette.goldenTan.fill,
              selected: false,
              enabled: _selectedId != null,
              onTap: _turnSelected,
            ),
            HudToolButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              fill: CraftPalette.scarlet.fill,
              selected: false,
              enabled: _selectedId != null,
              onTap: _deleteSelected,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final shape in TangramKind.values)
            HudToolButton(
              icon: switch (shape) {
                TangramKind.square => Icons.crop_square,
                TangramKind.triangle => Icons.change_history,
                TangramKind.circle => Icons.circle_outlined,
              },
              label: switch (shape) {
                TangramKind.square => 'Square',
                TangramKind.triangle => 'Triangle',
                TangramKind.circle => 'Circle',
              },
              fill: switch (shape) {
                TangramKind.square => CraftPalette.cerulean.fill,
                TangramKind.triangle => CraftPalette.mango.fill,
                TangramKind.circle => CraftPalette.seaFoam.fill,
              },
              selected: _shape == shape,
              onTap: () => setState(() => _shape = shape),
            ),
        ],
      ),
    );
  }
}
